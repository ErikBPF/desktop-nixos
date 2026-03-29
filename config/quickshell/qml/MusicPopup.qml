import QtQuick
import Quickshell.Services.Mpris

Item {
    id: musicRoot

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Album art
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 160; height: 160; radius: 12
            color: Style.surface
            clip: true

            Image {
                anchors.fill: parent
                source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !root.activePlayer
                text: "\uf001"
                font.family: Style.fontMono; font.pixelSize: 48
                color: Style.dimText
            }
        }

        // Track info
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.activePlayer ? root.activePlayer.trackTitle : "No media playing"
                font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold
                color: Style.text
                elide: Text.ElideRight
                width: Math.min(implicitWidth, musicRoot.width - 40)
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.activePlayer ? root.activePlayer.trackArtist : ""
                font.family: Style.fontMono; font.pixelSize: 11
                color: Style.dimText
                elide: Text.ElideRight
                width: Math.min(implicitWidth, musicRoot.width - 40)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Seek bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32; height: 4; radius: 2
            color: Style.surface
            visible: root.activePlayer !== null

            Rectangle {
                width: root.activePlayer && root.activePlayer.length > 0
                    ? parent.width * (root.activePlayer.position / root.activePlayer.length)
                    : 0
                height: parent.height; radius: 2
                color: Style.accent
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }

        // Playback controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            Text {
                text: "\uf048"
                font.family: Style.fontMono; font.pixelSize: 18
                color: mouseP.containsMouse ? Style.text : Style.dimText
                MouseArea { id: mouseP; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.previous() } }
                Accessible.role: Accessible.Button; Accessible.name: "Previous"
            }
            Text {
                text: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "\uf04c" : "\uf04b"
                font.family: Style.fontMono; font.pixelSize: 24
                color: mousePlay.containsMouse ? Style.text : Style.accent
                MouseArea { id: mousePlay; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.togglePlaying() } }
                Accessible.role: Accessible.Button; Accessible.name: "Play/Pause"
            }
            Text {
                text: "\uf051"
                font.family: Style.fontMono; font.pixelSize: 18
                color: mouseN.containsMouse ? Style.text : Style.dimText
                MouseArea { id: mouseN; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.next() } }
                Accessible.role: Accessible.Button; Accessible.name: "Next"
            }
        }
    }
}
