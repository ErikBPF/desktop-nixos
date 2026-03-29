import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: monRoot
    property var monitors: []

    Process {
        id: monPoller
        command: ["bash", "-c", "hyprctl monitors -j | jq -r '.[] | \"\\(.name)|\\(.width)x\\(.height)|\\(.refreshRate)|\\(.x),\\(.y)\"'"]
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split("|");
                if (parts.length >= 4)
                    monRoot.monitors = monRoot.monitors.concat([{name: parts[0], res: parts[1], hz: parts[2], pos: parts[3]}]);
            }
        }
        onRunningChanged: { if (running) monRoot.monitors = []; }
    }
    Component.onCompleted: monPoller.running = true

    Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 12

        Text {
            text: "Monitors"
            font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold; color: Style.text
        }

        ListView {
            width: parent.width; height: parent.height - 40
            clip: true; spacing: 8
            model: monRoot.monitors

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width; height: 64; radius: 8; color: Style.surface

                Column {
                    anchors.fill: parent; anchors.margins: 12; spacing: 4

                    Row {
                        spacing: 8
                        Text { text: "\uf108"; font.family: Style.fontMono; font.pixelSize: 16; color: Style.accent }
                        Text { text: modelData.name; font.family: Style.fontMono; font.pixelSize: 13; font.weight: Font.Bold; color: Style.text }
                    }

                    Row {
                        spacing: 16
                        Text { text: modelData.res; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText }
                        Text { text: Math.round(parseFloat(modelData.hz)) + "Hz"; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText }
                        Text { text: "pos: " + modelData.pos; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText }
                    }
                }
            }
        }
    }
}
