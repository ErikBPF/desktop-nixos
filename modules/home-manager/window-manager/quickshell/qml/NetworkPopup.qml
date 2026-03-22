import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: netRoot

    property string mode: "wifi"
    property string connectedSsid: ""
    property var networks: []
    property var btDevices: []

    Process {
        id: netPoller
        command: ["bash", root.scriptsDir + "/poll_network.sh", netRoot.mode]
        stdout: SplitParser {
            onRead: data => {
                var eq = data.indexOf("=");
                if (eq < 0) return;
                var k = data.substring(0, eq), v = data.substring(eq + 1).trim();
                if (k === "connected") netRoot.connectedSsid = v;
                else if (k === "net") {
                    var parts = v.split("|");
                    netRoot.networks = netRoot.networks.concat([{name: parts[0], signal: parts[1], security: parts[2]}]);
                } else if (k === "btconn" || k === "btpaired") {
                    var bp = v.split("|");
                    netRoot.btDevices = netRoot.btDevices.concat([{name: bp[0], mac: bp[1], connected: k === "btconn"}]);
                }
            }
        }
        onRunningChanged: {
            if (running) { netRoot.networks = []; netRoot.btDevices = []; }
        }
    }

    Component.onCompleted: netPoller.running = true
    Timer { interval: 5000; running: true; repeat: true; onTriggered: { if (!netPoller.running) netPoller.running = true; } }

    Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 12

        // Mode tabs
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 8

            Rectangle {
                width: 80; height: 28; radius: 6
                color: netRoot.mode === "wifi" ? Style.accent : Style.surface
                Text { anchors.centerIn: parent; text: "\uf1eb WiFi"; font.family: Style.fontMono; font.pixelSize: 11; color: netRoot.mode === "wifi" ? Style.background : Style.text }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { netRoot.mode = "wifi"; netPoller.running = true; } }
            }
            Rectangle {
                width: 100; height: 28; radius: 6
                color: netRoot.mode === "bt" ? Style.special : Style.surface
                Text { anchors.centerIn: parent; text: "\uf293 Bluetooth"; font.family: Style.fontMono; font.pixelSize: 11; color: netRoot.mode === "bt" ? Style.background : Style.text }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { netRoot.mode = "bt"; netPoller.running = true; } }
            }
        }

        // Connected info
        Text {
            visible: netRoot.mode === "wifi" && netRoot.connectedSsid !== ""
            text: "\uf058 Connected: " + netRoot.connectedSsid
            font.family: Style.fontMono; font.pixelSize: 11; color: Style.success
        }

        // Network/device list
        ListView {
            width: parent.width; height: parent.height - 80
            clip: true; spacing: 4
            model: netRoot.mode === "wifi" ? netRoot.networks : netRoot.btDevices

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width; height: 32; radius: 6
                color: Style.surface

                Row {
                    anchors.fill: parent; anchors.margins: 8; spacing: 8

                    Text {
                        text: netRoot.mode === "wifi"
                            ? (modelData.name === netRoot.connectedSsid ? "\uf058" : "\uf1eb")
                            : (modelData.connected ? "\uf293" : "\uf294")
                        font.family: Style.fontMono; font.pixelSize: 12
                        color: netRoot.mode === "wifi"
                            ? (modelData.name === netRoot.connectedSsid ? Style.success : Style.accent)
                            : (modelData.connected ? Style.special : Style.dimText)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: modelData.name
                        font.family: Style.fontMono; font.pixelSize: 11; color: Style.text
                        elide: Text.ElideRight; width: parent.width - 80
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: netRoot.mode === "wifi"
                        text: (modelData.signal || "") + "%"
                        font.family: Style.fontMono; font.pixelSize: 10; color: Style.dimText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (netRoot.mode === "wifi")
                            Quickshell.execDetached(["nmcli", "device", "wifi", "connect", modelData.name]);
                        else
                            Quickshell.execDetached(["bluetoothctl", "connect", modelData.mac]);
                    }
                }
            }
        }
    }
}
