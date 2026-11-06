"""
Metro Music Player V2 — metro.py
The QObject controller. Main thread only — all heavy work is delegated to QThreads.

Architecture:
  MetroController  — QObject exposed to QML as 'metro'
  ScanWorker       — QThread: disk walk + thumbnail generation + DB upsert
  OnlineWorker     — QThread: ytmusicapi search + yt-dlp stream extraction
  LyricsWorker     — QThread: LRCLIB fetch + LRC parse
"""

import sys
import os
import json
import random
import tempfile
import threading

from PySide6.QtCore import (
    QObject, Slot, Signal, Property, QUrl,
    QStandardPaths, QThread, Qt
)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput

from mutagen import File as MutagenFile
from mutagen.id3 import ID3NoHeaderError
from PIL import Image as PilImage
import io

import database as db
import online_engine


# ─────────────────────────────────────────────────────────────
# THUMBNAIL HELPER  (used by ScanWorker)
# ─────────────────────────────────────────────────────────────

_THUMB_DIR = os.path.join(os.path.expanduser("~"), ".metro", "thumbs")
os.makedirs(_THUMB_DIR, exist_ok=True)

_THUMB_SIZE = (300, 300)


def _extract_and_cache_thumb(audio, file_path: str) -> str:
    """
    Extract embedded album art, resize to 300×300, save to ~/.metro/thumbs/.
    Returns a QUrl file:// string, or "" if no artwork found.
    """
    try:
        raw = None

        # MP3 / ID3
        if hasattr(audio, "tags") and audio.tags:
            for key in audio.tags.keys():
                if key.startswith("APIC"):
                    raw = audio.tags[key].data
                    break

        # M4A / MP4
        if raw is None and "covr" in (audio or {}):
            raw = bytes(audio["covr"][0])

        # FLAC
        if raw is None and hasattr(audio, "pictures") and audio.pictures:
            raw = audio.pictures[0].data

        if not raw:
            return ""

        file_hash = format(abs(hash(file_path)), "x")
        thumb_path = os.path.join(_THUMB_DIR, f"{file_hash}.jpg")

        if not os.path.exists(thumb_path):
            img = PilImage.open(io.BytesIO(raw)).convert("RGB")
            img.thumbnail(_THUMB_SIZE, PilImage.LANCZOS)
            img.save(thumb_path, "JPEG", quality=85, optimize=True)

        return QUrl.fromLocalFile(thumb_path).toString()

    except Exception as e:
        print(f"[Thumb] {e}")
        return ""


def _parse_audio_meta(file_path: str) -> dict:
    """
    Read metadata from an audio file using mutagen.
    Returns a dict ready for db.upsert_song / QML consumption.
    """
    filename = os.path.basename(file_path)
    result = {
        "title":       os.path.splitext(filename)[0],
        "artist":      "Unknown Artist",
        "album":       "Unknown Album",
        "track_number": 0,
        "year":        0,
        "duration_ms": 0,
        "cover_path":  "",
        "path":        QUrl.fromLocalFile(file_path).toString(),
    }

    try:
        audio = MutagenFile(file_path, easy=False)
        if audio is None:
            return result

        # Duration
        if audio.info:
            result["duration_ms"] = int((audio.info.length or 0) * 1000)

        tags = audio.tags or {}

        def _tag(keys, fallback=""):
            for k in keys:
                v = tags.get(k)
                if v:
                    return str(v[0]) if hasattr(v, "__iter__") and not isinstance(v, str) else str(v)
            return fallback

        result["title"]  = _tag(["TIT2", "©nam", "\xa9nam", "title"],  result["title"])
        result["artist"] = _tag(["TPE1", "©ART", "\xa9ART", "artist"], "Unknown Artist")
        result["album"]  = _tag(["TALB", "©alb", "\xa9alb", "album"],  "Unknown Album")

        trck = _tag(["TRCK", "trkn"])
        if trck:
            result["track_number"] = int(trck.split("/")[0]) if "/" in trck else int(trck or 0)

        yr = _tag(["TDRC", "TYER", "©day", "\xa9day"])
        if yr:
            result["year"] = int(str(yr)[:4]) if str(yr)[:4].isdigit() else 0

        result["cover_path"] = _extract_and_cache_thumb(audio, file_path)

    except Exception as e:
        print(f"[Meta] {file_path}: {e}")

    return result


# ─────────────────────────────────────────────────────────────
# WORKER: ScanWorker
# ─────────────────────────────────────────────────────────────

class ScanWorker(QThread):
    """
    Background thread: walks the Music folder, upserts metadata into SQLite,
    generates thumbnails, then emits the full song list when done.

    Emits:
      scanComplete(list)  — list of song dicts for QML
      scanProgress(int)   — 0-100 progress percentage
    """
    scanComplete = Signal(list)
    scanProgress = Signal(int)

    def run(self):
        music_path = QStandardPaths.writableLocation(QStandardPaths.MusicLocation)
        if not os.path.exists(music_path):
            self.scanComplete.emit([])
            return

        # Collect all audio files
        supported = (".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac")
        all_files = []
        for root, _, files in os.walk(music_path):
            for f in files:
                if f.lower().endswith(supported):
                    all_files.append(os.path.join(root, f))

        total = len(all_files)
        if total == 0:
            self.scanComplete.emit([])
            return

        # Diff against DB — only process new/changed files
        known_paths = db.get_paths_in_db()
        new_files   = [p for p in all_files if QUrl.fromLocalFile(p).toString() not in known_paths]
        # (For changed detection we'd check mtime — V2.1 feature)

        batch = []
        BATCH_SIZE = 50

        for i, file_path in enumerate(new_files):
            meta = _parse_audio_meta(file_path)
            batch.append({
                "title":        meta["title"],
                "artist":       meta["artist"],
                "album":        meta["album"],
                "path":         meta["path"],
                "cover_path":   meta["cover_path"],
                "duration_ms":  meta["duration_ms"],
                "track_number": meta["track_number"],
                "year":         meta["year"],
            })

            if len(batch) >= BATCH_SIZE:
                db.bulk_upsert_songs(batch)
                batch.clear()

            progress = int((i + 1) / len(new_files) * 100)
            self.scanProgress.emit(progress)

        if batch:
            db.bulk_upsert_songs(batch)

        # Purge files that no longer exist on disk
        db.purge_missing_files()

        # Emit the full library from DB (including previously scanned songs)
        songs = db.get_all_songs()
        self.scanComplete.emit(songs)


# ─────────────────────────────────────────────────────────────
# WORKER: OnlineWorker
# ─────────────────────────────────────────────────────────────

class OnlineWorker(QThread):
    """
    Background thread for all online operations.
    Emits signals that the controller re-emits on the main thread.
    """
    searchComplete  = Signal(list)   # list of result dicts
    streamReady     = Signal(str)    # direct audio URL
    errorOccurred   = Signal(str)    # human-readable error message

    def __init__(self):
        super().__init__()
        self._mode      = "search"
        self._query     = ""
        self._video_id  = ""

    def start_search(self, query: str):
        self._mode  = "search"
        self._query = query
        if not self.isRunning():
            self.start()

    def start_stream(self, video_id: str):
        self._mode     = "stream"
        self._video_id = video_id
        if not self.isRunning():
            self.start()

    def run(self):
        try:
            if self._mode == "search":
                results = online_engine.search(self._query)
                self.searchComplete.emit(results)
            elif self._mode == "stream":
                url = online_engine.get_stream_url(self._video_id)
                self.streamReady.emit(url)
        except RuntimeError as e:
            self.errorOccurred.emit(str(e))
        except Exception as e:
            self.errorOccurred.emit(f"Unexpected error: {e}")


# ─────────────────────────────────────────────────────────────
# WORKER: LyricsWorker
# ─────────────────────────────────────────────────────────────

class LyricsWorker(QThread):
    """
    Fetches and parses synced lyrics from LRCLIB in the background.
    """
    lyricsReady = Signal(str)   # JSON string: [{time_ms, text}, ...]

    def __init__(self):
        super().__init__()
        self._title      = ""
        self._artist     = ""
        self._duration   = 0

    def fetch(self, title: str, artist: str, duration_ms: int = 0):
        self._title    = title
        self._artist   = artist
        self._duration = duration_ms
        if not self.isRunning():
            self.start()

    def run(self):
        lines = online_engine.fetch_lyrics(self._title, self._artist, self._duration)
        self.lyricsReady.emit(json.dumps(lines))


# ─────────────────────────────────────────────────────────────
# QUEUE
# ─────────────────────────────────────────────────────────────

class PlayQueue:
    """
    Simple playback queue. Tracks a list of song dicts and a cursor.
    Supports shuffle (Fisher-Yates on a copy) and repeat modes.
    """

    REPEAT_NONE = 0
    REPEAT_ONE  = 1
    REPEAT_ALL  = 2

    def __init__(self):
        self._items:         list[dict] = []
        self._original:      list[dict] = []  # pre-shuffle order
        self._index:         int        = -1
        self._shuffled:      bool       = False
        self._repeat_mode:   int        = self.REPEAT_NONE

    # ── mutation ──

    def set(self, songs: list[dict], start_index: int = 0):
        self._original = list(songs)
        self._items    = list(songs)
        self._index    = start_index
        if self._shuffled:
            self._apply_shuffle(preserve_current=True)

    def clear(self):
        self._items   = []
        self._original = []
        self._index   = -1

    def add(self, song: dict):
        self._items.append(song)
        self._original.append(song)

    def remove(self, index: int):
        if 0 <= index < len(self._items):
            self._items.pop(index)
            if index < self._index:
                self._index -= 1
            elif index == self._index:
                self._index = min(self._index, len(self._items) - 1)

    # ── navigation ──

    def current(self) -> dict | None:
        if 0 <= self._index < len(self._items):
            return self._items[self._index]
        return None

    def advance(self) -> dict | None:
        """Move to next track. Respects repeat modes."""
        if not self._items:
            return None

        if self._repeat_mode == self.REPEAT_ONE:
            return self.current()

        next_idx = self._index + 1

        if next_idx >= len(self._items):
            if self._repeat_mode == self.REPEAT_ALL:
                next_idx = 0
            else:
                return None  # end of queue

        self._index = next_idx
        return self.current()

    def back(self) -> dict | None:
        """Move to previous track."""
        if not self._items:
            return None
        self._index = max(0, self._index - 1)
        return self.current()

    def jump_to(self, index: int) -> dict | None:
        if 0 <= index < len(self._items):
            self._index = index
        return self.current()

    # ── shuffle ──

    def toggle_shuffle(self) -> bool:
        self._shuffled = not self._shuffled
        if self._shuffled:
            self._apply_shuffle(preserve_current=True)
        else:
            # Restore original order, keep same song playing
            current = self.current()
            self._items = list(self._original)
            if current:
                try:
                    self._index = self._items.index(current)
                except ValueError:
                    self._index = 0
        return self._shuffled

    def _apply_shuffle(self, preserve_current: bool = True):
        current = self.current() if preserve_current else None
        pool = list(self._items)
        if current and current in pool:
            pool.remove(current)
        random.shuffle(pool)
        self._items = ([current] + pool) if current else pool
        self._index = 0

    # ── repeat ──

    def cycle_repeat(self) -> int:
        self._repeat_mode = (self._repeat_mode + 1) % 3
        return self._repeat_mode

    # ── properties ──

    @property
    def items(self) -> list[dict]:
        return list(self._items)

    @property
    def index(self) -> int:
        return self._index

    @property
    def total(self) -> int:
        return len(self._items)

    @property
    def is_shuffled(self) -> bool:
        return self._shuffled

    @property
    def repeat_mode(self) -> int:
        return self._repeat_mode


# ─────────────────────────────────────────────────────────────
# MAIN CONTROLLER
# ─────────────────────────────────────────────────────────────

class MetroController(QObject):

    # ── signals ──
    metadataChanged   = Signal()
    songsChanged      = Signal()
    positionChanged   = Signal()
    queueChanged      = Signal()
    lyricsChanged     = Signal()
    onlineResults     = Signal()
    onlineLoading     = Signal(bool)
    onlineError       = Signal(str)
    scanProgress      = Signal(int)    # 0-100

    def __init__(self):
        super().__init__()

        # ── multimedia ──
        self._player       = QMediaPlayer()
        self._audio_output = QAudioOutput()
        self._player.setAudioOutput(self._audio_output)
        self._audio_output.setVolume(1.0)

        # ── state ──
        self._title         = ""
        self._artist        = ""
        self._album         = ""
        self._current_cover = ""
        self._duration_ms   = 0
        self._current_song_id: int | None = None

        self._all_songs:    list[dict] = []   # full local library from DB
        self._artists_data: list[dict] = []   # for ArtistView
        self._online_results: list[dict] = []

        self._lyrics_data:  list[dict] = []   # [{time_ms, text}]
        self._current_lyrics_index: int = -1

        self._queue = PlayQueue()

        # ── workers ──
        self._scan_worker   = ScanWorker()
        self._online_worker = OnlineWorker()
        self._lyrics_worker = LyricsWorker()

        # ── wire workers ──
        self._scan_worker.scanComplete.connect(self._on_scan_complete)
        self._scan_worker.scanProgress.connect(self.scanProgress)

        self._online_worker.searchComplete.connect(self._on_search_complete)
        self._online_worker.streamReady.connect(self._on_stream_ready)
        self._online_worker.errorOccurred.connect(self._on_online_error)

        self._lyrics_worker.lyricsReady.connect(self._on_lyrics_ready)

        # ── player ──
        self._player.positionChanged.connect(self._on_position_changed)
        self._player.playbackStateChanged.connect(lambda _: self.metadataChanged.emit())
        self._player.mediaStatusChanged.connect(self._on_media_status)

        # ── boot ──
        db.init_db()
        self._load_library_from_db()
        self._scan_worker.start()   # background diff-sync

    # ─────────────────────────────────────────────────────────
    # BOOT HELPERS
    # ─────────────────────────────────────────────────────────

    def _load_library_from_db(self):
        """Instant startup: read cached metadata from SQLite before disk scan finishes."""
        self._all_songs    = db.get_all_songs()
        self._artists_data = self._build_artists(self._all_songs)
        self.songsChanged.emit()

    def _build_artists(self, songs: list[dict]) -> list[dict]:
        """Group songs by artist. Returns sorted list of artist dicts for ArtistView."""
        artists: dict[str, dict] = {}
        for s in songs:
            name = s.get("artist", "Unknown Artist")
            if name not in artists:
                artists[name] = {
                    "name":  name,
                    "cover": s.get("cover_path", ""),
                    "songs": [],
                }
            if not artists[name]["cover"] and s.get("cover_path"):
                artists[name]["cover"] = s["cover_path"]
            artists[name]["songs"].append(s)

        return sorted(artists.values(), key=lambda a: a["name"].lower())

    # ─────────────────────────────────────────────────────────
    # WORKER CALLBACKS  (called on main thread via queued signals)
    # ─────────────────────────────────────────────────────────

    def _on_scan_complete(self, songs: list[dict]):
        self._all_songs    = songs
        self._artists_data = self._build_artists(songs)
        self.songsChanged.emit()

    def _on_search_complete(self, results: list[dict]):
        self._online_results = results
        self.onlineResults.emit()
        self.onlineLoading.emit(False)

    def _on_stream_ready(self, url: str):
        self._player.setSource(QUrl(url))
        self._player.play()
        self.onlineLoading.emit(False)
        self.metadataChanged.emit()

    def _on_online_error(self, msg: str):
        self.onlineLoading.emit(False)
        self.onlineError.emit(msg)

    def _on_lyrics_ready(self, json_str: str):
        self._lyrics_data          = json.loads(json_str)
        self._current_lyrics_index = -1
        self.lyricsChanged.emit()

    def _on_position_changed(self):
        self.positionChanged.emit()
        self._update_lyrics_index()

    def _on_media_status(self, status):
        if status == QMediaPlayer.MediaStatus.EndOfMedia:
            self._auto_advance()

    def _auto_advance(self):
        next_song = self._queue.advance()
        if next_song:
            self._play_song_dict(next_song)
        self.queueChanged.emit()

    def _update_lyrics_index(self):
        """Find which lyric line corresponds to the current playback position."""
        if not self._lyrics_data:
            return
        pos = self._player.position()
        new_idx = -1
        for i, line in enumerate(self._lyrics_data):
            if line["time_ms"] <= pos:
                new_idx = i
            else:
                break
        if new_idx != self._current_lyrics_index:
            self._current_lyrics_index = new_idx
            self.lyricsChanged.emit()

    # ─────────────────────────────────────────────────────────
    # QML PROPERTIES
    # ─────────────────────────────────────────────────────────

    @Property(list, notify=songsChanged)
    def songList(self): return self._all_songs

    @Property(list, notify=songsChanged)
    def artistList(self): return self._artists_data

    @Property(list, notify=onlineResults)
    def onlineList(self): return self._online_results

    @Property(str, notify=metadataChanged)
    def currentTitle(self): return self._title

    @Property(str, notify=metadataChanged)
    def currentArtist(self): return self._artist

    @Property(str, notify=metadataChanged)
    def currentAlbum(self): return self._album

    @Property(str, notify=metadataChanged)
    def currentCover(self): return self._current_cover

    @Property(float, notify=positionChanged)
    def progress(self):
        if self._player.duration() > 0:
            return self._player.position() / self._player.duration()
        return 0.0

    @Property(int, notify=positionChanged)
    def positionMs(self): return self._player.position()

    @Property(int, notify=metadataChanged)
    def durationMs(self): return self._player.duration() or self._duration_ms

    @Property(bool, notify=metadataChanged)
    def isPlaying(self):
        return self._player.playbackState() == QMediaPlayer.PlaybackState.PlayingState

    @Property(int, notify=metadataChanged)
    def volume(self): return int(self._audio_output.volume() * 100)

    # Queue properties
    @Property(list, notify=queueChanged)
    def queueList(self): return self._queue.items

    @Property(int, notify=queueChanged)
    def queueIndex(self): return self._queue.index

    @Property(int, notify=queueChanged)
    def queueTotal(self): return self._queue.total

    @Property(bool, notify=queueChanged)
    def isShuffled(self): return self._queue.is_shuffled

    @Property(int, notify=queueChanged)
    def repeatMode(self): return self._queue.repeat_mode

    # Lyrics properties
    @Property(str, notify=lyricsChanged)
    def lyricsJson(self): return json.dumps(self._lyrics_data)

    @Property(int, notify=lyricsChanged)
    def lyricsIndex(self): return self._current_lyrics_index

    # ─────────────────────────────────────────────────────────
    # SLOTS — called by QML
    # ─────────────────────────────────────────────────────────

    @Slot(str)
    def playTrack(self, file_url: str):
        """Play a local track by its QUrl file:// path. Sets the queue to just this song."""
        if not file_url:
            return
        # Find the song dict in our list
        song = next((s for s in self._all_songs if s.get("path") == file_url), None)
        if song:
            self._queue.set(self._all_songs, self._all_songs.index(song))
            self._play_song_dict(song)
        else:
            # Fallback: play directly without queue metadata
            self._play_url_directly(file_url)

    @Slot(str, int)
    def playFromList(self, file_url: str, list_index: int):
        """
        Play song at list_index from the current visible song list.
        Sets the full visible list as the queue so next/prev work.
        """
        self._queue.set(self._all_songs, list_index)
        song = self._queue.current()
        if song:
            self._play_song_dict(song)

    @Slot(list, int)
    def playFromArtist(self, artist_songs: list, index: int):
        """Play from an artist's song list."""
        self._queue.set(artist_songs, index)
        song = self._queue.current()
        if song:
            self._play_song_dict(song)

    @Slot(str, str)
    def playOnline(self, video_id: str, title: str):
        """Start streaming an online track by its YouTube videoId."""
        self._title  = title
        self._artist = ""
        self.metadataChanged.emit()
        self.onlineLoading.emit(True)
        self._online_worker.start_stream(video_id)

    @Slot()
    def togglePlayback(self):
        if self.isPlaying:
            self._player.pause()
        else:
            self._player.play()
        self.metadataChanged.emit()

    @Slot()
    def nextTrack(self):
        song = self._queue.advance()
        if song:
            self._play_song_dict(song)
        self.queueChanged.emit()

    @Slot()
    def prevTrack(self):
        # If >3 seconds in, restart current track instead of going back
        if self._player.position() > 3000:
            self._player.setPosition(0)
        else:
            song = self._queue.back()
            if song:
                self._play_song_dict(song)
        self.queueChanged.emit()

    @Slot(float)
    def seek(self, ratio: float):
        if self._player.duration() > 0:
            self._player.setPosition(int(ratio * self._player.duration()))

    @Slot(int)
    def setVolume(self, percent: int):
        self._audio_output.setVolume(max(0, min(100, percent)) / 100.0)
        self.metadataChanged.emit()

    @Slot()
    def toggleShuffle(self):
        self._queue.toggle_shuffle()
        self.queueChanged.emit()

    @Slot()
    def cycleRepeat(self):
        self._queue.cycle_repeat()
        self.queueChanged.emit()

    @Slot(str)
    def searchOnline(self, query: str):
        if not query.strip():
            return
        self.onlineLoading.emit(True)
        self._online_worker.start_search(query)

    @Slot(str)
    def searchLocal(self, query: str) -> list:
        """FTS5 search — returns results directly (called synchronously from QML)."""
        results = db.search_songs(query)
        self._all_songs = results
        self.songsChanged.emit()

    @Slot()
    def clearSearch(self):
        self._all_songs = db.get_all_songs()
        self.songsChanged.emit()

    @Slot(str)
    def filterByArtist(self, artist: str):
        songs = db.get_songs_by_artist(artist)
        self._all_songs = songs
        self.songsChanged.emit()

    # ─────────────────────────────────────────────────────────
    # PRIVATE HELPERS
    # ─────────────────────────────────────────────────────────

    def _play_song_dict(self, song: dict):
        self._title         = song.get("title",      "")
        self._artist        = song.get("artist",     "")
        self._album         = song.get("album",      "")
        self._current_cover = song.get("cover_path", "")
        self._duration_ms   = song.get("duration_ms", 0)

        path = song.get("path", "")
        if path.startswith("ytmusic://"):
            # Online track — stream URL already in cache or needs extraction
            video_id = path.replace("ytmusic://", "")
            self.onlineLoading.emit(True)
            self._online_worker.start_stream(video_id)
        else:
            self._play_url_directly(path)

        # Fetch lyrics in background
        self._lyrics_data = []
        self.lyricsChanged.emit()
        self._lyrics_worker.fetch(self._title, self._artist, self._duration_ms)

        # Log play
        song_id = song.get("id")
        if song_id:
            db.record_play(song_id, source="local")

        self.metadataChanged.emit()
        self.queueChanged.emit()

    def _play_url_directly(self, path: str):
        """Convert a QUrl string to a local path and begin playback."""
        if sys.platform == "win32":
            local_path = path.replace("file:///", "")
        else:
            local_path = path.replace("file://", "")

        self._player.setSource(QUrl.fromLocalFile(local_path))
        self._player.play()


# ─────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)

    if hasattr(sys, "_MEIPASS"):
        bundle_dir = sys._MEIPASS
    else:
        bundle_dir = os.path.abspath(os.path.dirname(__file__))

    qml_path = os.path.join(bundle_dir, "qml", "App.qml")

    ctrl   = MetroController()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("metro", ctrl)
    engine.load(QUrl.fromLocalFile(qml_path))

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())