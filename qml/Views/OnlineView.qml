import QtQuick
import QtQuick.Controls

// OnlineView.qml
// YouTube Music search: type a query, see results, click to stream.

Item {
    id: root
    signal songSelected(string videoId, string title)

    Item { id: focusStopper; focus: true }

    // ── SEARCH BAR ────────────────────────────────────────────
    Row {
        id:             searchRow
        x:              44
        y:              170
        width:          parent.width - 88
        spacing:        16

        Rectangle {
            width:   searchRow.width - goBtn.width - 16
            height:  50
            color:   onlineField.activeFocus ? "#0f0f0f" : "#080808"
            border.color: onlineField.activeFocus ? "#00ADEF" : "#1a1a1a"
            border.width: 1
            radius:  3
            Behavior on border.color { ColorAnimation { duration: 180 } }

            Text {
                text:                "\uE721"
                font.family:         "Segoe MDL2 Assets"
                font.pixelSize:      16
                color:               onlineField.activeFocus ? "#00ADEF" : "#333"
                anchors.left:        parent.left
                anchors.leftMargin:  16
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            TextField {
                id:               onlineField
                anchors.fill:     parent
                anchors.leftMargin: 46
                anchors.rightMargin: 12
                placeholderText:  "Search YouTube Music…"
                color:            "white"
                font.family:      "Segoe UI"
                font.pixelSize:   15
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse:    true
                background:       Item {}

                Keys.onReturnPressed: {
                    focusStopper.forceActiveFocus()
                    metro.searchOnline(text)
                }
            }
        }

        Rectangle {
            id:      goBtn
            width:   100
            height:  50
            color:   goBtnMa.containsMouse ? "#00ADEF" : "#0a1a25"
            radius:  3
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text:         "SEARCH"
                color:        "white"
                font.family:  "Segoe UI"
                font.pixelSize: 13
                font.letterSpacing: 1
            }
            MouseArea {
                id:          goBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    focusStopper.forceActiveFocus()
                    metro.searchOnline(onlineField.text)
                }
            }
        }
    }

    // Loading indicator
    Row {
        anchors.top:        searchRow.bottom
        anchors.topMargin:  12
        anchors.left:       parent.left
        anchors.leftMargin: 44
        spacing:            8
        visible:            false    // bound via Connections below
        id:                 loadingRow

        Repeater {
            model: 3
            Rectangle {
                width:  6
                height: 6
                radius: 3
                color:  "#00ADEF"

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation    { duration: index * 200 }
                    NumberAnimation   { from: 0.2; to: 1.0; duration: 300 }
                    NumberAnimation   { from: 1.0; to: 0.2; duration: 300 }
                }
            }
        }

        Text {
            text:           "Searching…"
            color:          "#444"
            font.family:    "Segoe UI"
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Connections {
        target: metro
        function onOnlineLoading(loading) { loadingRow.visible = loading }
        function onOnlineError(msg) {
            errorText.text = msg
            errorText.visible = true
        }
        function onOnlineResults() { errorText.visible = false }
    }

    Text {
        id:             errorText
        anchors.top:    searchRow.bottom
        anchors.topMargin: 14
        anchors.left:   parent.left
        anchors.leftMargin: 44
        color:          "#883333"
        font.family:    "Segoe UI"
        font.pixelSize: 13
        visible:        false
    }

    // ── RESULTS LIST ──────────────────────────────────────────
    ListView {
        anchors.top:          loadingRow.bottom
        anchors.topMargin:    24
        anchors.bottom:       miniBar.top
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.leftMargin:   44
        anchors.rightMargin:  44
        clip:                 true
        spacing:              1
        model:                metro.onlineList

        delegate: Rectangle {
            required property var  modelData
            required property int  index

            width:  ListView.view.width
            height: 64
            color:  rowMa.containsMouse ? "#0d0d0d" : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
                anchors.fill:          parent
                anchors.leftMargin:    10
                anchors.rightMargin:   10
                spacing:               14

                // Thumbnail from YouTube
                Rectangle {
                    width:  50
                    height: 50
                    color:  "#111"
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source:       modelData.cover || ""
                        fillMode:     Image.PreserveAspectCrop
                        asynchronous: true
                        cache:        true
                        sourceSize.width: 120
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width:                  parent.width - 200
                    spacing:                4

                    Text {
                        text:           modelData.title || ""
                        color:          "white"
                        font.family:    "Segoe UI Semibold"
                        font.pixelSize: 13
                        elide:          Text.ElideRight
                        width:          parent.width
                    }
                    Text {
                        text:           (modelData.artist || "") + (modelData.album ? "  ·  " + modelData.album : "")
                        color:          "#444"
                        font.family:    "Segoe UI"
                        font.pixelSize: 11
                        elide:          Text.ElideRight
                        width:          parent.width
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var ms = modelData.duration_ms || 0
                        var s  = Math.floor(ms / 1000)
                        var m  = Math.floor(s / 60)
                        s = s % 60
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    color:          "#333"
                    font.family:    "Segoe UI"
                    font.pixelSize: 12
                }

                // Stream button
                Rectangle {
                    width:  80
                    height: 30
                    color:  streamMa.containsMouse ? "#00ADEF" : "#0a1825"
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text:         "\uE768  Play"
                        font.family:  "Segoe MDL2 Assets, Segoe UI"
                        font.pixelSize: 12
                        color:        "white"
                    }
                    MouseArea {
                        id:          streamMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:   root.songSelected(modelData.video_id || "", modelData.title || "")
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width:  parent.width
                height: 1
                color:  "#0d0d0d"
            }

            MouseArea {
                id:          rowMa
                anchors.fill: parent
                hoverEnabled: true
                z:            -1
            }
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible:  metro.onlineList.length === 0
            text:     "Search YouTube Music above"
            color:    "#1a1a1a"
            font.family: "Segoe UI Light"
            font.pixelSize: 20
        }
    }

    MiniPlayerBar {
        id:              miniBar
        anchors.bottom:  parent.bottom
        width:           parent.width
        arrowIcon:       "\uE70E"
        onExpandClicked: { /* no-op from online view */ }
    }
}
