import QtQuick

Item {
    id: stewRoot

    Rectangle {
        anchors.fill: parent; color: "transparent"

        // Animated orb
        Rectangle {
            id: orb
            anchors.centerIn: parent
            width: 120; height: 120; radius: 60

            property real breathPhase: 0
            property real colorPhase: 0

            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Style.special.r, Style.special.g, Style.special.b, 0.8 + 0.1 * Math.sin(orb.breathPhase)) }
                GradientStop { position: 1.0; color: Qt.rgba(Style.info.r, Style.info.g, Style.info.b, 0.6 + 0.1 * Math.sin(orb.colorPhase)) }
            }

            // Breathing animation
            NumberAnimation on breathPhase {
                from: 0; to: Math.PI * 2; duration: 4000; loops: Animation.Infinite
            }
            NumberAnimation on colorPhase {
                from: 0; to: Math.PI * 2; duration: 6000; loops: Animation.Infinite
            }

            // Scale breathing
            transform: Scale {
                origin.x: 60; origin.y: 60
                xScale: 1.0 + 0.03 * Math.sin(orb.breathPhase)
                yScale: 1.0 + 0.03 * Math.sin(orb.breathPhase)
            }

            // Glow
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 20; height: parent.height + 20; radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(Style.special.r, Style.special.g, Style.special.b, 0.2 + 0.1 * Math.sin(orb.breathPhase))
                z: -1
            }
        }

        // Label
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 20
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Stewart"
                font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold
                color: Style.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "AI helper coming soon"
                font.family: Style.fontMono; font.pixelSize: 10
                color: Style.dimText
            }
        }
    }
}
