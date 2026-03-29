import QtQuick

Item {
    id: calRoot

    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()
    property int todayDay: new Date().getDate()
    property int todayMonth: new Date().getMonth()
    property int todayYear: new Date().getFullYear()

    function daysInMonth(month, year) {
        return new Date(year, month + 1, 0).getDate();
    }

    function firstDayOfWeek(month, year) {
        var d = new Date(year, month, 1).getDay();
        return d === 0 ? 6 : d - 1; // Monday = 0
    }

    function monthName(month) {
        var names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"];
        return names[month];
    }

    function prevMonth() {
        if (displayMonth === 0) { displayMonth = 11; displayYear--; }
        else displayMonth--;
    }

    function nextMonth() {
        if (displayMonth === 11) { displayMonth = 0; displayYear++; }
        else displayMonth++;
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Header: month navigation
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Text {
                text: "\uf053"
                font.family: Style.fontMono; font.pixelSize: 14; color: Style.dimText
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calRoot.prevMonth() }
                Accessible.role: Accessible.Button; Accessible.name: "Previous month"
            }

            Text {
                text: calRoot.monthName(calRoot.displayMonth) + " " + calRoot.displayYear
                font.family: Style.fontMono; font.pixelSize: 14; font.weight: Font.Bold
                color: Style.text
                width: 160; horizontalAlignment: Text.AlignHCenter
            }

            Text {
                text: "\uf054"
                font.family: Style.fontMono; font.pixelSize: 14; color: Style.dimText
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calRoot.nextMonth() }
                Accessible.role: Accessible.Button; Accessible.name: "Next month"
            }
        }

        // Day of week headers
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                Text {
                    text: modelData
                    font.family: Style.fontMono; font.pixelSize: 10; font.weight: Font.Bold
                    color: Style.dimText
                    width: 36; horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Calendar grid (6 rows x 7 cols)
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7; spacing: 4

            Repeater {
                model: 42

                Rectangle {
                    property int dayNum: {
                        var offset = calRoot.firstDayOfWeek(calRoot.displayMonth, calRoot.displayYear);
                        var d = index - offset + 1;
                        if (d < 1 || d > calRoot.daysInMonth(calRoot.displayMonth, calRoot.displayYear))
                            return 0;
                        return d;
                    }
                    property bool isToday: dayNum > 0 &&
                        calRoot.displayMonth === calRoot.todayMonth &&
                        calRoot.displayYear === calRoot.todayYear &&
                        dayNum === calRoot.todayDay

                    width: 36; height: 28; radius: 6
                    color: isToday ? Style.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: dayNum > 0 ? dayNum.toString() : ""
                        font.family: Style.fontMono; font.pixelSize: 11
                        font.weight: isToday ? Font.Bold : Font.Normal
                        color: isToday ? Style.background : Style.text
                    }

                    Accessible.role: Accessible.StaticText
                    Accessible.name: dayNum > 0 ? dayNum + " " + calRoot.monthName(calRoot.displayMonth) : ""
                }
            }
        }

        // Weather section (uses root.weatherTemp/weatherIcon from Shell)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            visible: root.weatherTemp !== ""

            Text {
                text: root.weatherIcon + " " + root.weatherTemp
                font.family: Style.fontMono; font.pixelSize: 13
                color: Style.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
