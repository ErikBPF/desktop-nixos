import QtQuick
import Quickshell

Item {
    id: powerRoot

    Column {
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Power Options"
            font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold
            color: Style.text
        }

        Repeater {
            model: [
                { icon: "\uf023", label: "Lock", cmd: ["hyprlock"], color: Style.accent },
                { icon: "\uf2f5", label: "Logout", cmd: ["hyprctl", "dispatch", "exit"], color: Style.warning },
                { icon: "\uf021", label: "Reboot", cmd: ["systemctl", "reboot"], color: Style.special },
                { icon: "\uf011", label: "Shutdown", cmd: ["systemctl", "poweroff"], color: Style.error }
            ]

            Rectangle {
                required property var modelData
                required property int index
                width: 200; height: 40; radius: 8
                color: powerBtnMouse.containsMouse ? Style.surface : "transparent"
                border.width: 1; border.color: powerBtnMouse.containsMouse ? modelData.color : Style.subtle

                Row {
                    anchors.centerIn: parent; spacing: 12

                    Text {
                        text: modelData.icon
                        font.family: Style.fontMono; font.pixelSize: 16
                        color: modelData.color
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.label
                        font.family: Style.fontMono; font.pixelSize: 13
                        color: Style.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: powerBtnMouse
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activePopup = "";
                        Quickshell.execDetached(modelData.cmd);
                    }
                }

                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
            }
        }
    }
}
