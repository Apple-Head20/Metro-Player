import QtQuick
import QtQuick.Controls

// ArtistView.qml
// Two-state view: artist grid → artist song list (drill-down).

Item {
    id: root
    signal songSelected(string path, int index)

    property bool folderOpen: false
    property string activeArtist: ""
    property var    activeArtistSongs: []

    // ── ARTIST GRID ───────────────────────────────────────────
    GridView {
        id:           artistGrid
        anchors.fill: parent
        anchors.topMargin:    185
        anchors.bottomMargin: 92
        anchors.margins:      44
        cellWidth:  220
        cellHeight: 235
        clip:       true
        visible:    !root.folderOpen
        opacity:    root.folderOpen ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 180 } }

        model: metro.artistList

        delegate: Item {
            width:  210
            height: 225

            Rectangle {
                anchors.fill:    parent
                anchors.margins: 5
                color:           "#0d0d0d"
                clip:            true

                Image {
                    anchors.fill:  parent
                    source:        modelData.cover || ""
                    fillMode:      Image.PreserveAspectCrop
                    asynchronous:  true
                    cache:         true
                    sourceSize.width: 300
                    opacity:       0.75
                }

                // Bottom gradient
                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: 70
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#f0000000" }
                    }
                }

                // Artist name
                Text {
                    anchors.bottom:       parent.bottom
                    anchors.bottomMargin: 22
                    anchors.left:         parent.left
                    anchors.leftMargin:   12
                    anchors.right:        parent.right
                    anchors.rightMargin:  12
                    text:           modelData.name || ""
                    color:          "white"
                    font.family:    "Segoe UI Semibold"
                    font.pixelSize: 14
                    elide:          Text.ElideRight
                }

                // Song count
                Text {
                    anchors.bottom:       parent.bottom
                    anchors.bottomMargin: 8
                    anchors.left:         parent.left
                    anchors.leftMargin:   12
                    text:           (modelData.songs ? modelData.songs.length : 0) + " songs"
                    color:          "#555"
                    font.family:    "Segoe UI"
                    font.pixelSize: 11
                }

                // Hover overlay
                Rectangle {
                    anchors.fill: parent
                    color:        gridHover.containsMouse ? "#14ffffff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id:          gridHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        root.activeArtist      = modelData.name
                        root.activeArtistSongs = modelData.songs
                        root.folderOpen        = true
                    }
                }
            }
        }
    }

    // ── ARTIST SONG LIST ──────────────────────────────────────
    Item {
        anchors.fill: parent
        visible:      root.folderOpen
        opacity:      root.folderOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Back button
        Row {
            id:             artistHeader
            x:              44
            y:              46
            spacing:        16
            z:              10

            Text {
                text:           "\uE76B"
                font.family:    "Segoe MDL2 Assets"
                font.pixelSize: 18
                color:          backArtistMa.containsMouse ? "white" : "#444"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea {
                    id:          backArtistMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    root.folderOpen = false
                }
            }

            Text {
                text:           root.activeArtist
                font.family:    "Segoe UI Light"
                font.pixelSize: 52
                color:          "white"
            }
        }

        // Song list
        ListView {
            anchors.top:          artistHeader.bottom
            anchors.topMargin:    18
            anchors.bottom:       miniBarArtist.top
            anchors.left:         parent.left
            anchors.right:        parent.right
            anchors.leftMargin:   44
            anchors.rightMargin:  44
            clip:                 true
            spacing:              1
            model:                root.activeArtistSongs

            delegate: Rectangle {
                required property var  modelData
                required property int  index

                width:  ListView.view.width
                height: 54
                color:  rowHover.containsMouse ? "#0d0d0d" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                // Currently playing indicator
                Rectangle {
                    width:  2
                    height: parent.height
                    color:  "#00ADEF"
                    visible: metro.currentTitle  === modelData.title
                             && metro.currentArtist === modelData.artist
                }

                Row {
                    anchors.fill:          parent
                    anchors.leftMargin:    18
                    anchors.rightMargin:   18
                    spacing:               16

                    // Track number
                    Text {
                        width:                  24
                        text:                   modelData.track_number > 0 ? modelData.track_number : ""
                        color:                  "#333"
                        font.family:            "Segoe UI"
                        font.pixelSize:         12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Thumbnail
                    Rectangle {
                        width:  40
                        height: 40
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

                    // Title + album
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width:                  parent.width - 120
                        spacing:                3
                        Text {
                            text:           modelData.title || ""
                            color:          "white"
                            font.family:    "Segoe UI"
                            font.pixelSize: 13
                            elide:          Text.ElideRight
                            width:          parent.width
                        }
                        Text {
                            text:           modelData.album || ""
                            color:          "#3a3a3a"
                            font.family:    "Segoe UI"
                            font.pixelSize: 11
                            elide:          Text.ElideRight
                            width:          parent.width
                            visible:        modelData.album && modelData.album !== "Unknown Album"
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
                        color:          "#333"
                        font.family:    "Segoe UI"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id:          rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:   root.songSelected(modelData.path || "", index)
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: 1
                    color:  "#0d0d0d"
                }
            }
        }

        MiniPlayerBar {
            id:             miniBarArtist
            anchors.bottom: parent.bottom
            width:          parent.width
            arrowIcon:      "\uE70E"
            onExpandClicked: root.songSelected("", -1)
        }
    }

    // Mini bar for grid state
    MiniPlayerBar {
        anchors.bottom: parent.bottom
        width:          parent.width
        visible:        !root.folderOpen
        arrowIcon:      "\uE70E"
        onExpandClicked: root.songSelected("", -1)
    }
}
