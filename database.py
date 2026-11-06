"""
Metro Music Player V2 — database.py
Persistence layer: SQLite + FTS5 for instant startup and sub-millisecond search.

Tables:
  songs          — full song metadata + cover cache path
  songs_fts      — FTS5 virtual table (title, artist, album) for instant search
  playlists      — user-created playlists
  playlist_songs — junction table (playlist ↔ song)
  play_history   — scrobble log + stats
"""

import os
import sqlite3
import threading
from contextlib import contextmanager


DB_PATH = os.path.join(os.path.expanduser("~"), ".metro", "library.db")


def _ensure_dir():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)


@contextmanager
def _conn():
    """Thread-safe connection context manager. Each call gets its own connection."""
    con = sqlite3.connect(DB_PATH, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")   # concurrent read/write
    con.execute("PRAGMA synchronous=NORMAL") # fast writes, safe enough
    con.execute("PRAGMA foreign_keys=ON")
    try:
        yield con
        con.commit()
    except Exception:
        con.rollback()
        raise
    finally:
        con.close()


# ─────────────────────────────────────────────────────────────
# SCHEMA
# ─────────────────────────────────────────────────────────────

SCHEMA = """
CREATE TABLE IF NOT EXISTS songs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    title           TEXT    NOT NULL DEFAULT 'Unknown Title',
    artist          TEXT    NOT NULL DEFAULT 'Unknown Artist',
    album           TEXT    NOT NULL DEFAULT 'Unknown Album',
    path            TEXT    NOT NULL UNIQUE,
    cover_path      TEXT    NOT NULL DEFAULT '',
    duration_ms     INTEGER NOT NULL DEFAULT 0,
    track_number    INTEGER NOT NULL DEFAULT 0,
    year            INTEGER NOT NULL DEFAULT 0,
    date_added      INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts USING fts5(
    title, artist, album,
    content='songs',
    content_rowid='id'
);

CREATE TRIGGER IF NOT EXISTS songs_ai AFTER INSERT ON songs BEGIN
    INSERT INTO songs_fts(rowid, title, artist, album)
    VALUES (new.id, new.title, new.artist, new.album);
END;

CREATE TRIGGER IF NOT EXISTS songs_ad AFTER DELETE ON songs BEGIN
    INSERT INTO songs_fts(songs_fts, rowid, title, artist, album)
    VALUES ('delete', old.id, old.title, old.artist, old.album);
END;

CREATE TRIGGER IF NOT EXISTS songs_au AFTER UPDATE ON songs BEGIN
    INSERT INTO songs_fts(songs_fts, rowid, title, artist, album)
    VALUES ('delete', old.id, old.title, old.artist, old.album);
    INSERT INTO songs_fts(rowid, title, artist, album)
    VALUES (new.id, new.title, new.artist, new.album);
END;

CREATE TABLE IF NOT EXISTS playlists (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    created_at  INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);

CREATE TABLE IF NOT EXISTS playlist_songs (
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    song_id     INTEGER NOT NULL REFERENCES songs(id)     ON DELETE CASCADE,
    position    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (playlist_id, song_id)
);

CREATE TABLE IF NOT EXISTS play_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    song_id     INTEGER REFERENCES songs(id) ON DELETE SET NULL,
    played_at   INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    source      TEXT    NOT NULL DEFAULT 'local'  -- 'local' | 'online'
);

CREATE INDEX IF NOT EXISTS idx_songs_artist  ON songs(artist);
CREATE INDEX IF NOT EXISTS idx_songs_album   ON songs(album);
CREATE INDEX IF NOT EXISTS idx_history_song  ON play_history(song_id);
"""


def init_db():
    """Create all tables and triggers if they don't exist. Safe to call every launch."""
    _ensure_dir()
    with _conn() as con:
        con.executescript(SCHEMA)


# ─────────────────────────────────────────────────────────────
# WRITE — called from ScanWorker thread
# ─────────────────────────────────────────────────────────────

def upsert_song(title: str, artist: str, album: str, path: str,
                cover_path: str, duration_ms: int,
                track_number: int = 0, year: int = 0) -> int:
    """
    Insert or update a song by its file path.
    Returns the row id.
    """
    with _conn() as con:
        cur = con.execute("""
            INSERT INTO songs (title, artist, album, path, cover_path, duration_ms,
                               track_number, year)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                title        = excluded.title,
                artist       = excluded.artist,
                album        = excluded.album,
                cover_path   = excluded.cover_path,
                duration_ms  = excluded.duration_ms,
                track_number = excluded.track_number,
                year         = excluded.year
        """, (title, artist, album, path, cover_path, duration_ms, track_number, year))
        return cur.lastrowid


def delete_song_by_path(path: str):
    """Remove a song that no longer exists on disk."""
    with _conn() as con:
        con.execute("DELETE FROM songs WHERE path = ?", (path,))


def bulk_upsert_songs(rows: list[dict]):
    """
    High-performance batch insert. Accepts a list of dicts with keys:
    title, artist, album, path, cover_path, duration_ms, track_number, year.
    Uses a single transaction for the entire batch.
    """
    with _conn() as con:
        con.executemany("""
            INSERT INTO songs (title, artist, album, path, cover_path, duration_ms,
                               track_number, year)
            VALUES (:title, :artist, :album, :path, :cover_path, :duration_ms,
                    :track_number, :year)
            ON CONFLICT(path) DO UPDATE SET
                title        = excluded.title,
                artist       = excluded.artist,
                album        = excluded.album,
                cover_path   = excluded.cover_path,
                duration_ms  = excluded.duration_ms,
                track_number = excluded.track_number,
                year         = excluded.year
        """, rows)


def record_play(song_id: int, source: str = "local"):
    """Log a play event."""
    with _conn() as con:
        con.execute(
            "INSERT INTO play_history (song_id, source) VALUES (?, ?)",
            (song_id, source)
        )


# ─────────────────────────────────────────────────────────────
# READ — called from main thread / QML bindings
# ─────────────────────────────────────────────────────────────

def get_all_songs() -> list[dict]:
    """
    Returns every song as a list of plain dicts.
    This is the cold-start payload — delivered to QML instantly from DB.
    """
    with _conn() as con:
        rows = con.execute("""
            SELECT id, title, artist, album, path, cover_path, duration_ms
            FROM   songs
            ORDER  BY artist COLLATE NOCASE, album COLLATE NOCASE, track_number
        """).fetchall()
        return [dict(r) for r in rows]


def search_songs(query: str, limit: int = 200) -> list[dict]:
    """
    FTS5 full-text search over title + artist + album.
    Returns results ranked by relevance (BM25). Sub-millisecond on 50k songs.

    The query is auto-prefixed so partial words match:
      'tay swi' → matches 'Taylor Swift'
    """
    if not query.strip():
        return get_all_songs()

    # Build a safe FTS5 prefix query — escape special chars, add * for prefix match
    safe = query.replace('"', '').strip()
    fts_query = " ".join(f'"{w}"*' for w in safe.split())

    with _conn() as con:
        rows = con.execute("""
            SELECT s.id, s.title, s.artist, s.album, s.path,
                   s.cover_path, s.duration_ms
            FROM   songs_fts
            JOIN   songs s ON songs_fts.rowid = s.id
            WHERE  songs_fts MATCH ?
            ORDER  BY rank
            LIMIT  ?
        """, (fts_query, limit)).fetchall()
        return [dict(r) for r in rows]


def get_all_artists() -> list[dict]:
    """
    Returns unique artists with their song count and a representative cover.
    Used to populate the Artists grid.
    """
    with _conn() as con:
        rows = con.execute("""
            SELECT   artist AS name,
                     COUNT(*) AS song_count,
                     (SELECT cover_path FROM songs s2
                      WHERE  s2.artist = s.artist AND cover_path != ''
                      LIMIT  1) AS cover
            FROM     songs s
            GROUP BY artist COLLATE NOCASE
            ORDER BY artist COLLATE NOCASE
        """).fetchall()
        return [dict(r) for r in rows]


def get_songs_by_artist(artist: str) -> list[dict]:
    """All songs for a given artist, sorted by album then track number."""
    with _conn() as con:
        rows = con.execute("""
            SELECT id, title, artist, album, path, cover_path, duration_ms, track_number
            FROM   songs
            WHERE  artist = ? COLLATE NOCASE
            ORDER  BY album COLLATE NOCASE, track_number, title COLLATE NOCASE
        """, (artist,)).fetchall()
        return [dict(r) for r in rows]


def get_paths_in_db() -> set[str]:
    """Returns a set of all file paths currently stored. Used for diff-sync."""
    with _conn() as con:
        rows = con.execute("SELECT path FROM songs").fetchall()
        return {r["path"] for r in rows}


def get_song_id_by_path(path: str) -> int | None:
    """Lookup a song's DB id by its file path."""
    with _conn() as con:
        row = con.execute("SELECT id FROM songs WHERE path = ?", (path,)).fetchone()
        return row["id"] if row else None


def get_play_stats(limit: int = 20) -> list[dict]:
    """Most-played songs. Used for a 'Top Tracks' playlist."""
    with _conn() as con:
        rows = con.execute("""
            SELECT   s.id, s.title, s.artist, s.cover_path,
                     COUNT(h.id) AS play_count
            FROM     play_history h
            JOIN     songs s ON h.song_id = s.id
            WHERE    h.source = 'local'
            GROUP BY h.song_id
            ORDER BY play_count DESC
            LIMIT    ?
        """, (limit,)).fetchall()
        return [dict(r) for r in rows]


# ─────────────────────────────────────────────────────────────
# PLAYLIST MANAGEMENT
# ─────────────────────────────────────────────────────────────

def create_playlist(name: str) -> int:
    with _conn() as con:
        cur = con.execute("INSERT INTO playlists (name) VALUES (?)", (name,))
        return cur.lastrowid


def get_playlists() -> list[dict]:
    with _conn() as con:
        rows = con.execute(
            "SELECT id, name, created_at FROM playlists ORDER BY created_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]


def add_song_to_playlist(playlist_id: int, song_id: int, position: int = 0):
    with _conn() as con:
        con.execute("""
            INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position)
            VALUES (?, ?, ?)
        """, (playlist_id, song_id, position))


def get_playlist_songs(playlist_id: int) -> list[dict]:
    with _conn() as con:
        rows = con.execute("""
            SELECT   s.id, s.title, s.artist, s.album,
                     s.path, s.cover_path, s.duration_ms,
                     ps.position
            FROM     playlist_songs ps
            JOIN     songs s ON ps.song_id = s.id
            WHERE    ps.playlist_id = ?
            ORDER BY ps.position
        """, (playlist_id,)).fetchall()
        return [dict(r) for r in rows]


# ─────────────────────────────────────────────────────────────
# MAINTENANCE — called from ScanWorker after diff-sync
# ─────────────────────────────────────────────────────────────

def rebuild_fts():
    """Force-rebuild the FTS5 index. Call after a bulk import if triggers misfired."""
    with _conn() as con:
        con.execute("INSERT INTO songs_fts(songs_fts) VALUES('rebuild')")


def purge_missing_files():
    """
    Remove DB entries whose file no longer exists on disk.
    Runs in ScanWorker after the scan loop finishes.
    """
    paths_in_db = get_paths_in_db()
    to_delete = [p for p in paths_in_db if not os.path.isfile(p)]
    if to_delete:
        with _conn() as con:
            con.executemany(
                "DELETE FROM songs WHERE path = ?",
                [(p,) for p in to_delete]
            )
    return len(to_delete)