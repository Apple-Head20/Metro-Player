"""
Metro Music Player V2 — online_engine.py
Streaming bridge: anonymous YouTube Music search + yt-dlp audio extraction.

Design:
  - No login, no OAuth, no cookies required.
  - Search returns structured metadata dicts (same shape as local songs).
  - Stream extraction returns a direct HTTPS audio URL that QMediaPlayer can consume.
  - URL results are cached for 30 minutes to avoid redundant yt-dlp calls.
  - All public functions are called from OnlineWorker (QThread) — never the main thread.
"""

import time
import threading
from typing import Optional


# ─────────────────────────────────────────────────────────────
# LAZY IMPORTS
# These are only imported when the online engine is first used.
# This keeps startup time fast even if yt-dlp takes a moment to load.
# ─────────────────────────────────────────────────────────────

_ytmusic = None
_ytmusic_lock = threading.Lock()


def _get_ytmusic():
    global _ytmusic
    if _ytmusic is None:
        with _ytmusic_lock:
            if _ytmusic is None:
                try:
                    from ytmusicapi import YTMusic
                    _ytmusic = YTMusic()
                except ImportError:
                    raise RuntimeError(
                        "ytmusicapi is not installed. Run: pip install ytmusicapi"
                    )
    return _ytmusic


# ─────────────────────────────────────────────────────────────
# URL CACHE — TTL 30 minutes
# Maps videoId → (url, expiry_timestamp)
# ─────────────────────────────────────────────────────────────

_url_cache: dict[str, tuple[str, float]] = {}
_cache_lock = threading.Lock()
_TTL = 1800  # 30 minutes in seconds


def _cache_get(video_id: str) -> Optional[str]:
    with _cache_lock:
        entry = _url_cache.get(video_id)
        if entry and time.time() < entry[1]:
            return entry[0]
        if entry:
            del _url_cache[video_id]
        return None


def _cache_set(video_id: str, url: str):
    with _cache_lock:
        _url_cache[video_id] = (url, time.time() + _TTL)


def _cache_purge_expired():
    """Remove stale entries. Call periodically to avoid unbounded growth."""
    now = time.time()
    with _cache_lock:
        expired = [k for k, (_, exp) in _url_cache.items() if now >= exp]
        for k in expired:
            del _url_cache[k]


# ─────────────────────────────────────────────────────────────
# SEARCH
# ─────────────────────────────────────────────────────────────

def search(query: str, limit: int = 20) -> list[dict]:
    """
    Search YouTube Music for songs matching `query`.

    Returns a list of dicts with keys:
      title, artist, album, duration_ms, video_id, cover, source='online'

    Raises RuntimeError if ytmusicapi is unavailable.
    """
    if not query.strip():
        return []

    yt = _get_ytmusic()

    try:
        raw = yt.search(query, filter="songs", limit=limit)
    except Exception as e:
        raise RuntimeError(f"YouTube Music search failed: {e}") from e

    results = []
    for item in raw:
        try:
            video_id = item.get("videoId", "")
            if not video_id:
                continue

            # Title
            title = item.get("title", "Unknown Title")

            # Artist — ytmusicapi returns a list of artist dicts
            artists = item.get("artists") or []
            artist = ", ".join(a.get("name", "") for a in artists) or "Unknown Artist"

            # Album
            album_obj = item.get("album") or {}
            album = album_obj.get("name", "")

            # Duration — ytmusicapi returns "3:45" string
            duration_str = item.get("duration", "0:00")
            duration_ms = _parse_duration(duration_str)

            # Thumbnail — pick the highest resolution available
            thumbnails = item.get("thumbnails") or []
            cover = thumbnails[-1].get("url", "") if thumbnails else ""
            # Force 300×300 thumbnail by rewriting the URL size param
            if cover:
                cover = cover.split("=w")[0] + "=w300-h300-l90-rj"

            results.append({
                "title":       title,
                "artist":      artist,
                "album":       album,
                "duration_ms": duration_ms,
                "video_id":    video_id,
                "cover":       cover,
                "source":      "online",
                # path is filled in when the stream URL is resolved
                "path":        f"ytmusic://{video_id}",
            })

        except Exception:
            # Skip malformed results silently
            continue

    return results


def _parse_duration(s: str) -> int:
    """Convert 'H:MM:SS' or 'M:SS' to milliseconds."""
    try:
        parts = [int(p) for p in s.split(":")]
        if len(parts) == 3:
            return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000
        if len(parts) == 2:
            return (parts[0] * 60 + parts[1]) * 1000
    except Exception:
        pass
    return 0


# ─────────────────────────────────────────────────────────────
# STREAM EXTRACTION
# ─────────────────────────────────────────────────────────────

def get_stream_url(video_id: str) -> str:
    """
    Extract a direct audio stream URL for the given YouTube video ID.

    Uses yt-dlp with audio-only format selection:
      bestaudio[ext=m4a]  — AAC/M4A preferred (QMediaPlayer native)
      bestaudio           — fallback to best audio container

    Results are cached for 30 minutes. Subsequent calls for the same
    video_id within the TTL window return instantly.

    Raises RuntimeError if yt-dlp is unavailable or extraction fails.
    """
    # Check cache first
    cached = _cache_get(video_id)
    if cached:
        return cached

    try:
        import yt_dlp
    except ImportError:
        raise RuntimeError("yt-dlp is not installed. Run: pip install yt-dlp")

    ydl_opts = {
        "format":          "bestaudio[ext=m4a]/bestaudio",
        "quiet":           True,
        "no_warnings":     True,
        "noplaylist":      True,
        "skip_download":   True,          # extract only — do NOT download
        "extract_flat":    False,
        "socket_timeout":  10,
        # Throttle workaround: request slightly lower quality if 403 received
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            )
        },
    }

    url = f"https://music.youtube.com/watch?v={video_id}"

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:
        raise RuntimeError(f"yt-dlp extraction failed for {video_id}: {e}") from e

    # Walk the format list to find the best audio URL
    stream_url = _pick_best_audio_url(info)

    if not stream_url:
        raise RuntimeError(f"No audio stream found for video_id={video_id}")

    _cache_set(video_id, stream_url)
    _cache_purge_expired()  # housekeeping
    return stream_url


def _pick_best_audio_url(info: dict) -> str:
    """
    From a yt-dlp info dict, return the direct URL of the best audio format.
    Prefers M4A (AAC) for widest QMediaPlayer compatibility.
    Falls back to the highest-bitrate audio-only format.
    """
    formats = info.get("formats") or []

    # Filter to audio-only streams (no video)
    audio_formats = [
        f for f in formats
        if f.get("vcodec") == "none" and f.get("url")
    ]

    if not audio_formats:
        # Last resort: direct URL on the info dict (single-format responses)
        return info.get("url", "")

    # Prefer M4A/AAC
    m4a = [f for f in audio_formats if f.get("ext") == "m4a"]
    pool = m4a if m4a else audio_formats

    # Pick highest bitrate
    pool.sort(key=lambda f: f.get("abr") or f.get("tbr") or 0, reverse=True)
    return pool[0]["url"]


# ─────────────────────────────────────────────────────────────
# LYRICS — LRCLIB
# ─────────────────────────────────────────────────────────────

def fetch_lyrics(title: str, artist: str, duration_ms: int = 0) -> list[dict]:
    """
    Fetch synced (timed) lyrics from LRCLIB — a free, open, no-auth API.
    https://lrclib.net

    Returns a list of dicts sorted by time:
      [{"time_ms": 1200, "text": "Hello, is it me you're looking for?"}, ...]

    Returns an empty list if no synced lyrics are found.
    """
    try:
        import urllib.request
        import urllib.parse
        import json

        params = urllib.parse.urlencode({
            "track_name":  title,
            "artist_name": artist,
            "duration":    duration_ms // 1000 if duration_ms else 0,
        })
        req = urllib.request.Request(
            f"https://lrclib.net/api/get?{params}",
            headers={"User-Agent": "Metro Music Player V2 (github placeholder)"},
        )

        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode())

        synced_lrc = data.get("syncedLyrics") or ""
        if not synced_lrc:
            # Fall back to plain lyrics if synced isn't available
            plain = data.get("plainLyrics") or ""
            if plain:
                return [{"time_ms": 0, "text": line}
                        for line in plain.splitlines() if line.strip()]
            return []

        return _parse_lrc(synced_lrc)

    except Exception as e:
        print(f"[LyricsWorker] LRCLIB fetch failed: {e}")
        return []


def _parse_lrc(lrc: str) -> list[dict]:
    """
    Parse an LRC format string into a sorted list of timed lines.

    LRC format:
      [MM:SS.xx] Line of lyrics
      [01:23.45] Another line
    """
    import re
    pattern = re.compile(r"\[(\d+):(\d+)\.(\d+)\](.*)")
    lines = []

    for raw_line in lrc.splitlines():
        m = pattern.match(raw_line.strip())
        if not m:
            continue
        minutes = int(m.group(1))
        seconds = int(m.group(2))
        centis  = int(m.group(3))
        text    = m.group(4).strip()

        time_ms = (minutes * 60 + seconds) * 1000 + centis * 10
        lines.append({"time_ms": time_ms, "text": text})

    return sorted(lines, key=lambda x: x["time_ms"])