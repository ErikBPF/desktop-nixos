import QtQuick

Item {
    id: focusRoot

    Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 16

        Text {
            text: "Focus Time"
            font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold; color: Style.text
        }

        Text {
            text: "Focus tracking daemon not yet configured.\nThis will show daily, weekly, and monthly\nproductivity statistics."
            font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText
            horizontalAlignment: Text.AlignHCenter; width: parent.width
        }

        // Placeholder: current uptime as proxy
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 4

            Text { text: "Session Uptime"; font.family: Style.fontMono; font.pixelSize: 11; color: Style.dimText; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                id: uptimeText
                font.family: Style.fontMono; font.pixelSize: 20; font.weight: Font.Bold; color: Style.accent
                anchors.horizontalCenter: parent.horizontalCenter

                property int startTime: Math.floor(Date.now() / 1000)
                Timer {
                    interval: 1000; running: true; repeat: true; triggeredOnStart: true
                    onTriggered: {
                        var elapsed = Math.floor(Date.now() / 1000) - uptimeText.startTime;
                        var h = Math.floor(elapsed / 3600);
                        var m = Math.floor((elapsed % 3600) / 60);
                        var s = elapsed % 60;
                        uptimeText.text = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }
                }
            }
        }
    }
}
