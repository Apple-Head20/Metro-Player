# Metro Player V2

A desktop music player built with **Python, PySide6, and QML**, combining local music library management with online music discovery and playback.

Metro Player V2 provides a unified interface for browsing locally stored audio files, managing playback queues, searching YouTube Music, and displaying song lyrics.

## Features

### Local Music Library
- Automatically scans the system's Music directory for supported audio files.
- Supports MP3, M4A, FLAC, WAV, OGG, OPUS, and AAC formats.
- Extracts track metadata, including title, artist, album, duration, and embedded artwork.
- Organizes tracks by artist.
- Uses SQLite to store library metadata for faster subsequent launches.
- Supports local music searching and artist-based filtering.

### Music Playback
- Audio playback using Qt Multimedia.
- Play, pause, next, previous, and seek controls.
- Adjustable playback volume.
- Playback queue management.
- Shuffle and repeat modes.
- Automatic playback progression.

### Online Music
- Search for tracks using YouTube Music.
- Retrieve audio streams through `yt-dlp`.
- Play online audio without requiring a YouTube account.
- Temporarily cache extracted stream URLs to reduce repeated requests.

### Lyrics
- Retrieve lyrics using the LRCLIB API.
- Support for timestamped lyrics.
- Synchronize lyric progression with playback when timed lyrics are available.
- Fall back to plain lyrics when synchronized lyrics are unavailable.

### Desktop Interface
- QML-based graphical user interface.
- Dedicated views for music collections, artists, online search, playback, and queues.
- Background workers for library scanning, online operations, and lyric retrieval.

## Technology Stack

| Technology | Purpose |
|---|---|
| Python | Application logic |
| PySide6 | Qt integration and multimedia |
| QML | Desktop user interface |
| SQLite | Local music library database |
| Mutagen | Audio metadata extraction |
| Pillow | Album artwork processing |
| ytmusicapi | YouTube Music search |
| yt-dlp | Audio stream extraction |
| LRCLIB | Lyrics retrieval |

## Project Structure

```text
Metro-Player/
├── metro.py
├── database.py
├── online_engine.py
├── requirements.txt
├── .gitignore
└── qml/
    ├── App.qml
    └── Views/
        ├── ArtistView.qml
        ├── CollectionView.qml
        ├── MiniPlayerBar.qml
        ├── NowPlaying.qml
        ├── OnlineView.qml
        └── QueueView.qml
```

### Core Components

**metro.py**

Main application entry point and controller. Manages audio playback, track queues, application state, and communication between Python and QML. Uses background workers for library scanning, online operations, and lyrics.

**database.py**

Handles SQLite database operations for local music library management.

**online_engine.py**

Provides YouTube Music search, audio stream extraction, temporary stream URL caching, and lyric retrieval.

**qml/**

Contains the graphical interface components responsible for displaying the library, artists, playback controls, online results, and queue.

## Installation

### Prerequisites

- Python 3.10 or later
- Git
- An internet connection for online music and lyrics features

### 1. Clone the Repository

```bash
git clone https://github.com/Apple-Head20/Metro-Player.git
cd Metro-Player
```

### 2. Create a Virtual Environment

```bash
python -m venv .venv
```

Activate it on Windows PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
```

### 3. Install Dependencies

```bash
python -m pip install -r requirements.txt
```

### 4. Launch Metro Player

```bash
python metro.py
```

The application will initialize its local database and scan the system's Music directory.

## How It Works

### Local Playback

1. Metro Player scans the system's Music directory.
2. Audio metadata and embedded album artwork are extracted.
3. Track information is stored in SQLite.
4. The library is presented through the QML interface.
5. Selecting a track starts playback through Qt Multimedia.

### Online Playback

1. The user searches for a song.
2. `ytmusicapi` retrieves matching YouTube Music results.
3. The selected track's audio stream is resolved using `yt-dlp`.
4. Qt Multimedia plays the resolved stream.
5. Stream URLs are temporarily cached to reduce repeated extraction requests.

### Lyrics

1. Track metadata is sent to LRCLIB.
2. Available synchronized lyrics are retrieved and parsed.
3. Lyric timestamps are compared against the current playback position.
4. The interface receives updates as playback progresses.

## Architecture

Metro Player separates its application logic from its user interface.

- **Frontend:** QML
- **Application controller:** Python QObject exposed to QML
- **Audio engine:** Qt Multimedia
- **Local storage:** SQLite
- **Online integration:** ytmusicapi and yt-dlp
- **Lyrics integration:** LRCLIB

Background operations use QThreads to reduce blocking of the main interface.

## Current Limitations

- Online playback depends on third-party services and may be affected by upstream changes.
- Internet connectivity is required for online search, streaming, and lyrics retrieval.
- The local music scanner currently uses the system's Music directory.
- Detection of modifications to previously indexed audio files is not yet implemented.
- Synchronized lyrics depend on availability from LRCLIB.

## Planned Improvements

Potential areas for future development include:

- Custom music folder selection.
- Detection of modified audio files during library scans.
- Improved handling of unavailable online streams.
- Additional library organization and filtering options.
- Packaging the application for easier desktop installation.

## Disclaimer

Metro Player V2 is an independent desktop music player project and is not affiliated with YouTube, YouTube Music, or Google.

Online functionality relies on third-party services and libraries. Users are responsible for complying with applicable service terms and copyright requirements.

## Author

**Mridul Mayank Jha**

GitHub: [@Apple-Head20](https://github.com/Apple-Head20)

---

*Metro Player V2 — Local music and online discovery in one desktop application.*
