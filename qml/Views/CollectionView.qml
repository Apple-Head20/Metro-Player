import QtQuick
import QtQuick.Controls

// CollectionView.qml
// Local library — virtual ListView (low RAM), FTS5 search, horizontal tile scroll.

Item {
    id: root
    signal songSelected(string path, int listIndex)

    // ── Focus stopper ──────────────────────────────────────────
    Item { id: focusStopper; focus: true }

    // ── SEARCH BAR ────────────────────────────────────────────
    Rectangle {
        id:              searchBox
        anchors.right:   parent.right
        anchors.rightMargin: 56
        anchors.top:     parent.top
        anchors.topMargin: 48
        width:           searchField.activeFocus ? 480 : 380
        height:          44
        color:           searchField.activeFocus ? "#0f0f0f" : "transparent"
        radius:          3
        z:               50
        Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation   { duration: 180 } }

        // Search icon
        Text {
            text:                "\uE71E"
            font.family:         "Segoe MDL2 Assets"
            font.pixelSize:      16
            color:               searchField.activeFocus ? "#00ADEF" : "#383838"
            anchors.left:        parent.left
            anchors.leftMargin:  14
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        TextField {
            id:                searchField
            anchors.fill:      parent
            anchors.leftMargin: 42
            anchors.rightMargin: 36
            placeholderText:   "SEARCH"
            color:             "white"
            font.family:       "Segoe UI Semilight"
            font.pixelSize:    14
            font.letterSpacing: 1
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse:     true

            background: Item {
                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: searchField.activeFocus ? 2 : 1
                    color:  searchField.activeFocus ? "#00ADEF" : "#222"
                    Behavior on color  { ColorAnimation  { duration: 180 } }
                    Behavior on height { NumberAnimation { duration: 120 } }
                }
            }

            onTextChanged: {
                searchTimer.restart()
            }
        }

        // Clear button
        Text {
            text:            "\uE8BB"
            font.family:     "Segoe MDL2 Assets"
            font.pixelSize:  13
            color:           "#555"
            visible:         searchField.text.length > 0
            anchors.right:   parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    searchField.text = ""
                    focusStopper.forceActiveFocus()
                    metro.clearSearch()
                }
            }
        }
    }

    // Debounce timer — search fires 250ms after the user stops typing
    Timer {
        id:        searchTimer
        interval:  250
        onTriggered: {
            if (searchField.text.length >= 2)
                metro.searchLocal(searchField.text)
            else if (searchField.text.length === 0)
                metro.clearSearch()
        }
    }

    // ── SONG GRID ─────────────────────────────────────────────
    // Horizontal-flowing GridView: songs arranged top-to-bottom per column,
    // user scrolls left-right. Virtual (only visible cells rendered).
    GridView {
        id:               grid
        anchors.top:      parent.top
        anchors.topMargin: 185
        anchors.bottom:   miniBar.top
        anchors.left:     parent.left
        anchors.right:    parent.right
        anchors.margins:  44

        cellWidth:         230
        cellHeight:        215
        flow:              GridView.FlowTopToBottom
        layoutDirection:   Qt.LeftToRight
        flickableDirection: Flickable.HorizontalFlick
        snapMode:          GridView.SnapToRow
        clip:              true
        cacheBuffer:       460      // one column each side pre-rendered

        model: metro.songList

        MouseArea {
            anchors.fill: parent
            z:            -1
            onClicked:    focusStopper.forceActiveFocus()
        }

        delegate: Item {
            id:      tile
            width:   220
            height:  205

            // ── Tile card ──
            Rectangle {
                id:           card
                anchors.fill: parent
                anchors.margins: 4
                color:        "#0e0e0e"
                clip:         true

                // Album art — lazy, decoded at 300px max
                Image {
                    anchors.fill: parent
                    source:       modelData.cover_path || ""
                    fillMode:     Image.PreserveAspectCrop
                    asynchronous: true
                    cache:        true
                    sourceSize.width: 300   // ← RAM budget: never decode bigger than this
                    opacity:      0.82

                    onStatusChanged: {
                        if (status === Image.Ready) fadeIn.start()
                    }

                    NumberAnimation on opacity { id: fadeIn; from: 0; to: 0.82; duration: 300 }
                }

                // Fallback icon
                Text {
                    anchors.centerIn: parent
                    text:         "\uE8D6"
                    font.family:  "Segoe MDL2 Assets"
                    font.pixelSize: 32
                    color:        "#1f1f1f"
                    visible:      !modelData.cover_path
                }

                // Gradient footer
                Rectangle {
                    anchors.bottom: parent.bottom
                    width:          parent.width
                    height:         56
                    color:          "transparent"
                    // dark gradient
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#e0000000" }
                    }
                }

                // Title label
                Text {
                    anchors.bottom:       parent.bottom
                    anchors.bottomMargin: 14
                    anchors.left:         parent.left
                    anchors.leftMargin:   10
                    anchors.right:        parent.right
                    anchors.rightMargin:  10
                    text:             modelData.title || ""
                    color:            "white"
                    font.family:      "Segoe UI Semibold"
                    font.pixelSize:   12
                    elide:            Text.ElideRight
                }

                // Hover overlay
                Rectangle {
                    anchors.fill: parent
                    color:        hoverMa.containsMouse ? "#18ffffff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Playing indicator
                Rectangle {
                    anchors.top:         parent.top
                    anchors.left:        parent.left
                    width:               3
                    height:              parent.height
                    color:               "#00ADEF"
                    visible:             metro.currentTitle === modelData.title
                                         && metro.currentArtist === modelData.artist
                }

                MouseArea {
                    id:          hoverMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        focusStopper.forceActiveFocus()
                        root.songSelected(modelData.path || "", index)
                    }
                }
            }
        }
    }

    // ── EMPTY STATE ───────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing:          12
        visible:          metro.songList.length === 0
        opacity:          0.3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:         "\uE8D6"
            font.family:  "Segoe MDL2 Assets"
            font.pixelSize: 48
            color:        "white"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:         "No music found"
            font.family:  "Segoe UI Light"
            font.pixelSize: 22
            color:        "white"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:         QStandardPaths.writableLocation(QStandardPaths.MusicLocation)
            font.family:  "Segoe UI"
            font.pixelSize: 13
            color:        "white"
        }
    }

    // ── MINI PLAYER ───────────────────────────────────────────
    MiniPlayerBar {
        id:              miniBar
        anchors.bottom:  parent.bottom
        width:           parent.width
        arrowIcon:       "\uE70E"
        onExpandClicked: {
            focusStopper.forceActiveFocus()
            root.songSelected("", -1)
        }
    }
}
