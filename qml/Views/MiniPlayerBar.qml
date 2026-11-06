import QtQuick
import QtQuick.Controls

// MiniPlayerBar.qml
// Persistent bottom playback bar. Used in both content views and NowPlaying.
// Set arrowIcon + connect expandClicked to integrate into any parent.

Rectangle {
    id:     bar
    height: 92
    color:  "#050505"

    property string arrowIcon: ""
    signal expandClicked()

    // ── top separator ──────────────────────────────────────────
    Rectangle {
        width:  parent.width
        height: 1
        color:  "#181818"
        anchors.top: parent.top
    }

    // ── SCRUB BAR ─────────────────────────────────────────────
    Item {
        id: scrubArea
        anchors.top:    parent.top
        width:          parent.width
        height:         6

        // Track background
        Rectangle {
            anchors.fill: parent
            color: "#1c1c1c"
        }

        // Filled portion
        Rectangle {
            width:  parent.width * metro.progress
            height: parent.height
            color:  scrubMouseArea.containsMouse ? "#00ADEF" : "#555"
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Scrub thumb (appears on hover)
        Rectangle {
            x:       (parent.width * metro.progress) - width / 2
            y:       (parent.height - height) / 2
            width:   12
            height:  12
            radius:  6
            color:   "white"
            visible: scrubMouseArea.containsMouse
        }

        // Time tooltip on hover
        Rectangle {
            id: timeTip
            x:      Math.max(0, Math.min(scrubMouseArea.mouseX - width / 2, scrubArea.width - width))
            y:      -28
            width:  52
            height: 22
            radius: 4
            color:  "#222"
            visible: scrubMouseArea.containsMouse

            Text {
                anchors.centerIn: parent
                text: {
                    if (metro.durationMs <= 0) return "0:00"
                    var ms  = scrubMouseArea.mouseX / scrubArea.width * metro.durationMs
                    var sec = Math.floor(ms / 1000)
                    var m   = Math.floor(sec / 60)
                    var s   = sec % 60
                    return m + ":" + (s < 10 ? "0" : "") + s
                }
                font.pixelSize: 11
                font.family:    "Segoe UI"
                color:          "#aaa"
            }
        }

        MouseArea {
            id:          scrubMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: (mouse) => metro.seek(mouse.x / scrubArea.width)
        }
    }

    // ── MAIN ROW ──────────────────────────────────────────────
    Row {
        anchors.top:        scrubArea.bottom
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        spacing: 22

        // Album art thumbnail
        Rectangle {
            width:  58
            height: 58
            color:  "#111"
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source:       metro.currentCover
                fillMode:     Image.PreserveAspectCrop
                asynchronous: true

                Behavior on source { NumberAnimation { target: albumArtFade; property: "opacity"; from: 0; to: 1; duration: 300 } }
            }

            // Fallback music icon
            Text {
                id:               albumArtFade
                anchors.centerIn: parent
                text:             "\uE8D6"
                font.family:      "Segoe MDL2 Assets"
                font.pixelSize:   20
                color:            "#333"
                visible:          metro.currentCover === ""
            }
        }

        // Track info
        Column {
            width:                  260
            anchors.verticalCenter: parent.verticalCenter
            spacing:                3

            Text {
                text:          metro.currentTitle.length > 0 ? metro.currentTitle : "No Track"
                color:         "white"
                font.family:   "Segoe UI Semibold"
                font.pixelSize: 14
                elide:         Text.ElideRight
                width:         parent.width
            }
            Text {
                text:           metro.currentArtist
                color:          "#555"
                font.family:    "Segoe UI"
                font.pixelSize: 12
                elide:          Text.ElideRight
                width:          parent.width
            }
        }

        // Playback controls
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing:                36

            // Shuffle
            Text {
                text:            "\uE8B1"
                font.family:     "Segoe MDL2 Assets"
                font.pixelSize:  16
                color:           metro.isShuffled ? "#00ADEF" : "#444"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 180 } }
                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    metro.toggleShuffle()
                }
            }

            // Previous
            Text {
                text:            "\uE892"
                font.family:     "Segoe MDL2 Assets"
                font.pixelSize:  18
                color:           "white"
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    metro.prevTrack()
                }
            }

            // Play / Pause
            Rectangle {
                width:  44
                height: 44
                radius: 22
                color:  playPauseHover.containsMouse ? "#1a1a1a" : "transparent"
                border.color: "#222"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text:             metro.isPlaying ? "\uE769" : "\uE768"
                    font.family:      "Segoe MDL2 Assets"
                    font.pixelSize:   22
                    color:            "white"
                }
                MouseArea {
                    id:           playPauseHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    metro.togglePlayback()
                }
            }

            // Next
            Text {
                text:            "\uE893"
                font.family:     "Segoe MDL2 Assets"
                font.pixelSize:  18
                color:           "white"
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    metro.nextTrack()
                }
            }

            // Repeat
            Text {
                text: metro.repeatMode === 1 ? "\uE8EE" : "\uE8EE"
                font.family:    "Segoe MDL2 Assets"
                font.pixelSize: 16
                color: {
                    if (metro.repeatMode === 0) return "#444"
                    if (metro.repeatMode === 2) return "#00ADEF"
                    return "#0080CC"
                }
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 180 } }
                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    metro.cycleRepeat()
                }
            }
        }

        // Time display
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                function fmt(ms) {
                    var s = Math.floor(ms / 1000)
                    var m = Math.floor(s / 60)
                    s = s % 60
                    return m + ":" + (s < 10 ? "0" : "") + s
                }
                return fmt(metro.positionMs) + " / " + fmt(metro.durationMs)
            }
            font.family:    "Segoe UI"
            font.pixelSize: 12
            color:          "#444"
        }

        // Volume
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text:            "\uE767"
                font.family:     "Segoe MDL2 Assets"
                font.pixelSize:  16
                color:           "#444"
                anchors.verticalCenter: parent.verticalCenter
            }

            Slider {
                id:     volSlider
                from:   0
                to:     100
                value:  metro.volume
                width:  80
                anchors.verticalCenter: parent.verticalCenter
                onMoved: metro.setVolume(value)

                background: Rectangle {
                    x:      volSlider.leftPadding
                    y:      volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                    width:  volSlider.availableWidth
                    height: 3
                    color:  "#1c1c1c"

                    Rectangle {
                        width:  volSlider.visualPosition * parent.width
                        height: parent.height
                        color:  "#444"
                    }
                }
                handle: Rectangle {
                    x:      volSlider.leftPadding + volSlider.visualPosition * volSlider.availableWidth - width / 2
                    y:      volSlider.topPadding  + volSlider.availableHeight / 2 - height / 2
                    width:  10
                    height: 10
                    radius: 5
                    color:  "white"
                }
            }
        }

        // Queue position
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           metro.queueTotal > 0 ? (metro.queueIndex + 1) + " / " + metro.queueTotal : ""
            font.family:    "Segoe UI"
            font.pixelSize: 11
            color:          "#333"
        }

        // Expand / collapse arrow
        Text {
            text:                   arrowIcon
            font.family:            "Segoe MDL2 Assets"
            font.pixelSize:         18
            color:                  "#555"
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    bar.expandClicked()
            }
        }
    }
}
