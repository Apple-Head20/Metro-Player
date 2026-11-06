import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// NowPlaying.qml
// Full-screen player. Blurred album art background, large type, synced lyrics panel.

Item {
    id: root
    signal backClicked()

    // ── BLURRED BACKGROUND ────────────────────────────────────
    // Large blurred/dimmed version of the album art fills the whole screen.
    Image {
        id:          bgArt
        anchors.fill: parent
        source:      metro.currentCover
        fillMode:    Image.PreserveAspectCrop
        asynchronous: true
        opacity:     0.18
        cache:       true
        sourceSize.width: 600

        Behavior on source { NumberAnimation { target: bgArt; property: "opacity"; from: 0; to: 0.18; duration: 600 } }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled:   true
            blur:          1.0
            blurMax:       32
            blurMultiplier: 2.0
        }
    }

    // Dark scrim on top of blur
    Rectangle {
        anchors.fill: parent
        color:        "#c0050505"
    }

    // ── BACK BUTTON ───────────────────────────────────────────
    Text {
        id:              backBtn
        text:            "\uE76B"
        font.family:     "Segoe MDL2 Assets"
        font.pixelSize:  20
        color:           backMa.containsMouse ? "white" : "#444"
        x:               44
        y:               46
        z:               10
        Behavior on color { ColorAnimation { duration: 150 } }
        MouseArea {
            id:          backMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    root.backClicked()
        }
    }

    // ── MAIN CONTENT ROW ──────────────────────────────────────
    Row {
        id:                  mainRow
        anchors.left:        parent.left
        anchors.leftMargin:  80
        anchors.right:       parent.right
        anchors.rightMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -46     // shift up to make room for mini bar
        spacing:             60

        // ── Album Art ──
        Rectangle {
            id:     artBox
            width:  420
            height: 420
            color:  "#111"

            // Subtle drop shadow frame
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: "transparent"
                border.color: "#ffffff08"
                border.width: 1
            }

            Image {
                id:          artImg
                anchors.fill: parent
                source:      metro.currentCover
                fillMode:    Image.PreserveAspectCrop
                asynchronous: true
                cache:       true
                sourceSize.width: 500

                // Slight scale-in when track changes
                NumberAnimation on scale {
                    id:    artScale
                    from:  0.94
                    to:    1.0
                    duration: 400
                    easing.type: Easing.OutCubic
                }
                onSourceChanged: artScale.restart()
            }

            Text {
                anchors.centerIn: parent
                text:         "\uE8D6"
                font.family:  "Segoe MDL2 Assets"
                font.pixelSize: 64
                color:        "#1a1a1a"
                visible:      metro.currentCover === ""
            }
        }

        // ── Info + Controls column ──
        Column {
            width:    root.width - artBox.width - 80 - 40 - 60 - lyricsPanel.width
            spacing:  16
            anchors.verticalCenter: artBox ? undefined : parent.verticalCenter

            // "NOW PLAYING" label
            Text {
                text:            "NOW PLAYING"
                color:           "#00ADEF"
                font.family:     "Segoe UI"
                font.pixelSize:  13
                font.letterSpacing: 3
            }

            // Title
            Text {
                text:          metro.currentTitle.length > 0 ? metro.currentTitle : "—"
                color:         "white"
                font.family:   "Segoe UI Light"
                font.pixelSize: 58
                width:         parent.width
                wrapMode:      Text.WordWrap
                lineHeight:    0.95
                maximumLineCount: 3
                elide:         Text.ElideRight
            }

            // Artist
            Text {
                text:          metro.currentArtist
                color:         "#666"
                font.family:   "Segoe UI"
                font.pixelSize: 22
                width:         parent.width
                elide:         Text.ElideRight
            }

            // Album
            Text {
                text:          metro.currentAlbum
                color:         "#3a3a3a"
                font.family:   "Segoe UI"
                font.pixelSize: 16
                width:         parent.width
                elide:         Text.ElideRight
                visible:       metro.currentAlbum.length > 0 && metro.currentAlbum !== "Unknown Album"
            }
        }

        // ── Lyrics panel ──────────────────────────────────────
        Item {
            id:     lyricsPanel
            width:  300
            height: 420
            clip:   true

            // Fetch indicator
            Text {
                anchors.centerIn: parent
                text:         "No lyrics"
                color:        "#1a1a1a"
                font.family:  "Segoe UI Light"
                font.pixelSize: 14
                visible:      lyricsView.count === 0
            }

            ListView {
                id:           lyricsView
                anchors.fill: parent
                clip:         true
                spacing:      4

                model:        {
                    try { return JSON.parse(metro.lyricsJson) } catch(e) { return [] }
                }

                // Auto-scroll to current line
                onCountChanged: {
                    if (metro.lyricsIndex >= 0)
                        positionViewAtIndex(metro.lyricsIndex, ListView.Center)
                }

                Connections {
                    target: metro
                    function onLyricsChanged() {
                        if (metro.lyricsIndex >= 0)
                            lyricsView.positionViewAtIndex(metro.lyricsIndex, ListView.Center)
                    }
                }

                delegate: Text {
                    required property var   modelData
                    required property int   index

                    property bool isActive: index === metro.lyricsIndex

                    width:          lyricsView.width
                    text:           modelData.text || ""
                    color:          isActive ? "white" : "#2a2a2a"
                    font.family:    "Segoe UI"
                    font.pixelSize: isActive ? 16 : 13
                    font.bold:      isActive
                    wrapMode:       Text.WordWrap
                    topPadding:     6
                    bottomPadding:  6
                    leftPadding:    4

                    Behavior on color          { ColorAnimation  { duration: 200 } }
                    Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
                }

                // Fade edges
                Rectangle {
                    anchors.top: parent.top
                    width:  parent.width
                    height: 50
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#ff050505" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    z: 2
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: 50
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#ff050505" }
                    }
                    z: 2
                }
            }
        }
    }

    // ── MINI PLAYER (anchored to bottom) ─────────────────────
    MiniPlayerBar {
        anchors.bottom: parent.bottom
        width:          parent.width
        arrowIcon:      "\uE70D"
        onExpandClicked: root.backClicked()
    }
}
