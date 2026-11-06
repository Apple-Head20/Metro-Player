import QtQuick
import QtQuick.Controls

// QueueView.qml
// Shows the current playback queue. Click any track to jump to it.
// Displays shuffle and repeat status.

Item {
    id: root
    signal songSelected(string path)

    // ── QUEUE HEADER ──────────────────────────────────────────
    Row {
        id:     queueHeader
        x:      44
        y:      170
        spacing: 30

        Text {
            text:          metro.queueTotal + " tracks"
            color:         "#333"
            font.family:   "Segoe UI"
            font.pixelSize: 16
            anchors.verticalCenter: parent.verticalCenter
        }

        // Shuffle badge
        Rectangle {
            width:   90
            height:  26
            radius:  3
            color:   metro.isShuffled ? "#001020" : "transparent"
            border.color: metro.isShuffled ? "#00ADEF" : "#1a1a1a"
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text:           "\uE8B1"
                    font.family:    "Segoe MDL2 Assets"
                    font.pixelSize: 13
                    color:          metro.isShuffled ? "#00ADEF" : "#333"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text:           "Shuffle"
                    color:          metro.isShuffled ? "#00ADEF" : "#333"
                    font.family:    "Segoe UI"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    metro.toggleShuffle()
            }
        }

        // Repeat badge
        Rectangle {
            width:   86
            height:  26
            radius:  3
            color:   metro.repeatMode > 0 ? "#001020" : "transparent"
            border.color: metro.repeatMode > 0 ? "#00ADEF" : "#1a1a1a"
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text:           "\uE8EE"
                    font.family:    "Segoe MDL2 Assets"
                    font.pixelSize: 13
                    color:          metro.repeatMode > 0 ? "#00ADEF" : "#333"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text:           metro.repeatMode === 1 ? "One" : (metro.repeatMode === 2 ? "All" : "Off")
                    color:          metro.repeatMode > 0 ? "#00ADEF" : "#333"
                    font.family:    "Segoe UI"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    metro.cycleRepeat()
            }
        }
    }

    // ── QUEUE LIST ────────────────────────────────────────────
    ListView {
        anchors.top:          queueHeader.bottom
        anchors.topMargin:    18
        anchors.bottom:       miniBar.top
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.leftMargin:   44
        anchors.rightMargin:  44
        clip:                 true
        spacing:              1
        model:                metro.queueList

        delegate: Rectangle {
            required property var  modelData
            required property int  index

            property bool isCurrent: index === metro.queueIndex

            width:  ListView.view.width
            height: 56
            color:  isCurrent ? "#0a1520" : (rowMa.containsMouse ? "#0a0a0a" : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }

            // Active track highlight bar
            Rectangle {
                width:  2
                height: parent.height
                color:  "#00ADEF"
                visible: isCurrent
            }

            Row {
                anchors.fill:          parent
                anchors.leftMargin:    18
                anchors.rightMargin:   18
                spacing:               14

                // Index number
                Text {
                    width:                  28
                    text:                   isCurrent ? "\uE768" : (index + 1)
                    font.family:            isCurrent ? "Segoe MDL2 Assets" : "Segoe UI"
                    font.pixelSize:         isCurrent ? 14 : 12
                    color:                  isCurrent ? "#00ADEF" : "#2a2a2a"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Cover
                Rectangle {
                    width:  42
                    height: 42
                    color:  "#111"
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source:       modelData.cover_path || ""
                        fillMode:     Image.PreserveAspectCrop
                        asynchronous: true
                        cache:        true
                        sourceSize.width: 80
                    }
                }

                // Track info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width:                  parent.width - 130
                    spacing:                3

                    Text {
                        text:           modelData.title || ""
                        color:          isCurrent ? "white" : "#888"
                        font.family:    "Segoe UI" + (isCurrent ? " Semibold" : "")
                        font.pixelSize: 13
                        elide:          Text.ElideRight
                        width:          parent.width
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text:           modelData.artist || ""
                        color:          isCurrent ? "#555" : "#2a2a2a"
                        font.family:    "Segoe UI"
                        font.pixelSize: 11
                        elide:          Text.ElideRight
                        width:          parent.width
                    }
                }

                // Duration
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var s = Math.floor((modelData.duration_ms || 0) / 1000)
                        var m = Math.floor(s / 60)
                        s = s % 60
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    color:          isCurrent ? "#444" : "#1a1a1a"
                    font.family:    "Segoe UI"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width:  parent.width
                height: 1
                color:  "#080808"
            }

            MouseArea {
                id:          rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:   root.songSelected(modelData.path || "")
            }
        }

        Text {
            anchors.centerIn: parent
            visible:          metro.queueTotal === 0
            text:             "Queue is empty"
            color:            "#1a1a1a"
            font.family:      "Segoe UI Light"
            font.pixelSize:   20
        }
    }

    MiniPlayerBar {
        id:              miniBar
        anchors.bottom:  parent.bottom
        width:           parent.width
        arrowIcon:       "\uE70E"
        onExpandClicked: { /* open now playing from app level */ }
    }
}
