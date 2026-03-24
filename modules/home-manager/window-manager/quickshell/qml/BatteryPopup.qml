import QtQuick
import Quickshell

Item {
    id: batRoot

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Battery icon + percentage
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.batteryStatus === "Charging" ? "\uf0e7" :
                      parseInt(root.batteryPercent) > 80 ? "\uf240" :
                      parseInt(root.batteryPercent) > 60 ? "\uf241" :
                      parseInt(root.batteryPercent) > 40 ? "\uf242" :
                      parseInt(root.batteryPercent) > 20 ? "\uf243" : "\uf244"
                font.family: Style.fontMono; font.pixelSize: 48
                color: parseInt(root.batteryPercent) < 20 ? Style.error : Style.success
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.batteryPercent || "??") + "%"
                font.family: Style.fontMono; font.pixelSize: 24; font.weight: Font.Bold
                color: Style.text
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.batteryStatus || "Unknown"
                font.family: Style.fontMono; font.pixelSize: 12
                color: Style.dimText
            }
        }

        // Battery bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32; height: 8; radius: 4
            color: Style.surface

            Rectangle {
                width: parent.width * (parseInt(root.batteryPercent || "0") / 100)
                height: parent.height; radius: 4
                color: parseInt(root.batteryPercent) < 20 ? Style.error :
                       parseInt(root.batteryPercent) < 50 ? Style.warning : Style.success
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }

        // Power profile (TLP-managed)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Power Profile (TLP)"
            font.family: Style.fontMono; font.pixelSize: 11; font.weight: Font.Bold
            color: Style.dimText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { governor: "powersave", platform: "low-power", label: "\uf06c Save", color: Style.success },
                    { governor: "", platform: "balanced", label: "\uf24e Balanced", color: Style.accent },
                    { governor: "performance", platform: "performance", label: "\uf0e7 Perf", color: Style.warning }
                ]

                Rectangle {
                    required property var modelData
                    property bool active: root.platformProfile === modelData.platform ||
                                         (modelData.platform !== "balanced" && root.cpuGovernor === modelData.governor)
                    width: profileText.implicitWidth + 16; height: 28; radius: 6
                    color: active ? Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.2) : Style.surface
                    border.width: active ? 2 : 1
                    border.color: active ? modelData.color : Style.dimText

                    Text {
                        id: profileText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: Style.fontMono; font.pixelSize: 10
                        font.weight: active ? Font.Bold : Font.Normal
                        color: active ? modelData.color : Style.dimText
                    }

                    Accessible.role: Accessible.StaticText; Accessible.name: modelData.label
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Governor: " + (root.cpuGovernor || "—")
            font.family: Style.fontMono; font.pixelSize: 9
            color: Style.dimText
        }

        // Volume slider
        Column {
            width: parent.width; spacing: 4

            Row {
                spacing: 8
                Text { text: root.volumeMuted ? "\uf6a9" : "\uf028"; font.family: Style.fontMono; font.pixelSize: 14; color: Style.warning; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Volume"; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText; anchors.verticalCenter: parent.verticalCenter }
            }

            Rectangle {
                width: parent.width; height: 6; radius: 3; color: Style.surface
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        var pct = Math.round(mouse.x / parent.width * 100);
                        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"]);
                    }
                }
                Rectangle {
                    width: parent.width * (parseInt(root.volume || "0") / 100)
                    height: parent.height; radius: 3; color: Style.warning
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }
        }

        // Brightness slider
        Column {
            width: parent.width; spacing: 4

            Row {
                spacing: 8
                Text { text: "\uf185"; font.family: Style.fontMono; font.pixelSize: 14; color: Style.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Brightness"; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText; anchors.verticalCenter: parent.verticalCenter }
            }

            Rectangle {
                width: parent.width; height: 6; radius: 3; color: Style.surface
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        var pct = Math.round(mouse.x / parent.width * 100);
                        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
                    }
                }
            }
        }
    }
}
