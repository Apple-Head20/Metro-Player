import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Views"

ApplicationWindow {
    id: window
    width: 1280
    height: 860
    minimumWidth: 900
    minimumHeight: 620
    visible: true
    title: "Metro"
    background: Rectangle { color: "#080808" }

    // ── Global State ──────────────────────────────────────────
    property int currentSection: 0
    // 0 = Collection  1 = Artists  2 = Online  3 = Queue

    property bool nowPlayingOpen: false

    // ── HEADER ────────────────────────────────────────────────
    Row {
        id: navHeader
        x: 44
        y: 38
        spacing: 44
        z: 100
        visible: !nowPlayingOpen

        Repeater {
            model: ["Collection", "Artists", "Online", "Queue"]
            delegate: Text {
                required property int   index
                required property string modelData

                text:            modelData
                font.pixelSize:  52
                font.family:     "Segoe UI Light"
                color:           currentSection === index ? "white" : "#2a2a2a"
                opacity:         currentSection === index ? 1.0 : 0.7

                Behavior on color   { ColorAnimation  { duration: 180 } }
                Behavior on opacity { NumberAnimation  { duration: 180 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        currentSection = index
                        if (artView) artView.folderOpen = false
                    }
                }
            }
        }
    }

    // Scan progress bar — thin line at top, fades out when scan finishes
    Rectangle {
        id: scanBar
        anchors.top:    parent.top
        width:          parent.width * (scanPct / 100)
        height:         2
        color:          "#00ADEF"
        z:              999
        opacity:        scanPct > 0 && scanPct < 100 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
        Behavior on width   { NumberAnimation { duration: 80  } }
    }
    property real scanPct: 0
    Connections {
        target: metro
        function onScanProgress(pct) { scanPct = pct }
    }

    // ── MAIN CONTENT (StackLayout) ────────────────────────────
    StackLayout {
        id: mainLayout
        anchors.fill:   parent
        currentIndex:   currentSection
        visible:        !nowPlayingOpen

        CollectionView {
            id: colView
            opacity: mainLayout.currentIndex === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            onSongSelected: (path, idx) => {
                if (path !== "") metro.playFromList(path, idx)
                nowPlayingOpen = true
            }
        }

        ArtistView {
            id: artView
            opacity: mainLayout.currentIndex === 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            onSongSelected: (path, idx) => {
                if (path !== "") metro.playTrack(path)
                nowPlayingOpen = true
            }
        }

        OnlineView {
            id: onlineView
            opacity: mainLayout.currentIndex === 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            onSongSelected: (videoId, title) => {
                metro.playOnline(videoId, title)
                nowPlayingOpen = true
            }
        }

        QueueView {
            id: queueView
            opacity: mainLayout.currentIndex === 3 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            onSongSelected: (path) => {
                metro.playTrack(path)
                nowPlayingOpen = true
            }
        }
    }

    // ── NOW PLAYING OVERLAY ────────────────────────────────────
    NowPlaying {
        id: nowPlaying
        anchors.fill: parent
        visible:      nowPlayingOpen
        opacity:      nowPlayingOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        onBackClicked: { nowPlayingOpen = false }
    }
}
