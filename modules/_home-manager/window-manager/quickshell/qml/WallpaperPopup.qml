import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: wpRoot
    property var wallpapers: []
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    Process {
        id: wpScanner
        command: ["bash", "-c", "find '" + wpRoot.wallpaperDir + "' -maxdepth 1 -type f \\( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \\) | sort"]
        stdout: SplitParser {
            onRead: data => {
                var path = data.trim();
                if (path !== "") wpRoot.wallpapers = wpRoot.wallpapers.concat([path]);
            }
        }
        onRunningChanged: { if (running) wpRoot.wallpapers = []; }
    }
    Component.onCompleted: wpScanner.running = true

    Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 12

        Text {
            text: "Wallpapers"
            font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold; color: Style.text
        }

        Text {
            visible: wpRoot.wallpapers.length === 0
            text: "No wallpapers found in\n" + wpRoot.wallpaperDir
            font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText
            horizontalAlignment: Text.AlignHCenter; width: parent.width
        }

        GridView {
            width: parent.width; height: parent.height - 40
            cellWidth: 140; cellHeight: 100
            clip: true
            model: wpRoot.wallpapers

            delegate: Rectangle {
                required property string modelData
                required property int index
                width: 132; height: 92; radius: 8
                color: Style.surface; clip: true

                Image {
                    anchors.fill: parent; anchors.margins: 2
                    source: "file://" + modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    anchors.fill: parent; radius: 8
                    color: "transparent"; border.width: wpMouse.containsMouse ? 2 : 0
                    border.color: Style.accent
                }

                MouseArea {
                    id: wpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["swww", "img", modelData, "--transition-type", "fade", "--transition-duration", "1"])
                }
            }
        }
    }
}
