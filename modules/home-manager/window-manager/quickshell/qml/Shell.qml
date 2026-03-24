//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick

ShellRoot {
    id: root

    signal clockClicked()
    signal popupRequested(string action, string widget)

    property string scriptsDir: Quickshell.env("HOME") + "/.config/quickshell/scripts"
    property string activePopup: ""

    // Socket IPC server — listens for commands from qs_manager.sh
    SocketServer {
        id: ipcServer
        active: true
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/quickshell.sock"

        handler: Socket {
            parser: SplitParser {
                onRead: message => {
                    var msg = message.trim();
                    if (msg === "close") {
                        root.activePopup = "";
                        root.popupRequested("close", "");
                    } else if (msg.startsWith("toggle:")) {
                        var widget = msg.substring(7);
                        if (root.activePopup === widget) {
                            root.activePopup = "";
                            root.popupRequested("close", "");
                        } else {
                            root.activePopup = widget;
                            root.popupRequested("open", widget);
                        }
                    } else if (msg.startsWith("open:")) {
                        var w = msg.substring(5);
                        root.activePopup = w;
                        root.popupRequested("open", w);
                    }
                }
            }
        }
    }

    // Clean up stale socket on startup
    Component.onCompleted: {
        // SocketServer handles cleanup automatically when binding
        console.log("IPC socket: " + ipcServer.path);
    }

    // System info state
    property string volume: "0"
    property bool volumeMuted: false
    property string batteryPercent: ""
    property string batteryStatus: ""
    property string cpuUsage: "0"
    property string cpuCores: ""
    property string memUsage: "0"
    property string diskUsage: "0"
    property bool micMuted: false
    property string weatherTemp: ""
    property string weatherIcon: ""
    property string cpuGovernor: ""
    property string platformProfile: ""

    // Fast poller — mem, disk, volume, mic, battery (no sleep)
    Process {
        id: fastPoller
        command: ["bash", root.scriptsDir + "/poll_fast.sh"]
        stdout: SplitParser {
            onRead: data => {
                var eq = data.indexOf("=");
                if (eq < 0) return;
                var k = data.substring(0, eq), v = data.substring(eq + 1).trim();
                if (k === "mem") root.memUsage = v;
                else if (k === "vol") root.volume = v;
                else if (k === "disk") root.diskUsage = v;
                else if (k === "muted") root.volumeMuted = (v === "true");
                else if (k === "micmuted") root.micMuted = (v === "true");
                else if (k === "bat") root.batteryPercent = v;
                else if (k === "batstatus") root.batteryStatus = v;
                else if (k === "governor") root.cpuGovernor = v;
                else if (k === "platform") root.platformProfile = v;
            }
        }
    }
    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!fastPoller.running) fastPoller.running = true; }
    }

    // CPU poller — 500ms delta, runs every 2s
    Process {
        id: cpuPoller
        command: ["bash", root.scriptsDir + "/poll_cpu.sh"]
        stdout: SplitParser {
            onRead: data => {
                var eq = data.indexOf("=");
                if (eq < 0) return;
                var k = data.substring(0, eq), v = data.substring(eq + 1).trim();
                if (k === "cpu") root.cpuUsage = v;
                else if (k === "cpucores") root.cpuCores = v;
            }
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!cpuPoller.running) cpuPoller.running = true; }
    }

    // Weather poller
    Process {
        id: weatherPoller
        command: ["bash", "-c", "curl -sf 'wttr.in/?format=%t+%C' 2>/dev/null || echo ''"]
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(" ");
                if (parts.length >= 1 && parts[0] !== "") {
                    root.weatherTemp = parts[0];
                    var cond = parts.slice(1).join(" ").toLowerCase();
                    if (cond.indexOf("sun") >= 0 || cond.indexOf("clear") >= 0) root.weatherIcon = "\uf185";
                    else if (cond.indexOf("cloud") >= 0 || cond.indexOf("overcast") >= 0) root.weatherIcon = "\uf0c2";
                    else if (cond.indexOf("rain") >= 0 || cond.indexOf("drizzle") >= 0) root.weatherIcon = "\uf043";
                    else if (cond.indexOf("snow") >= 0) root.weatherIcon = "\uf2dc";
                    else if (cond.indexOf("thunder") >= 0 || cond.indexOf("storm") >= 0) root.weatherIcon = "\uf0e7";
                    else if (cond.indexOf("fog") >= 0 || cond.indexOf("mist") >= 0) root.weatherIcon = "\uf75f";
                    else root.weatherIcon = "\uf185";
                }
            }
        }
    }
    Timer {
        interval: 150000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!weatherPoller.running) weatherPoller.running = true; }
    }

    // Active media player
    property var activePlayer: {
        for (var i = 0; i < Mpris.players.values.length; i++) {
            var p = Mpris.players.values[i];
            if (p.playbackState === MprisPlaybackState.Playing || p.playbackState === MprisPlaybackState.Paused)
                return p;
        }
        return null;
    }

    function workspaceState(wsId) {
        for (var i = 0; i < Hyprland.workspaces.values.length; i++) {
            var ws = Hyprland.workspaces.values[i];
            if (ws.id === wsId) {
                if (ws.focused) return "focused";
                if (ws.active) return "active";
                return "occupied";
            }
        }
        return "empty";
    }

    // === Reusable ===
    component Island: Rectangle {
        color: Qt.rgba(Style.background.r, Style.background.g, Style.background.b, 0.8)
        radius: Style.pillRadius
        height: Style.pillHeight
    }

    component Metric: Item {
        id: metricRoot
        property string icon: ""
        property string value: ""
        property color iconColor: Style.accent
        property color textColor: Style.text
        property bool clickable: false
        signal clicked()

        width: metricRow.implicitWidth
        height: Style.pillHeight

        Row {
            id: metricRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                text: metricRoot.icon
                font.family: Style.fontMono; font.pixelSize: Style.barIconSize
                color: metricRoot.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: metricRoot.value !== ""
                text: metricRoot.value
                font.family: Style.fontMono; font.pixelSize: Style.barFontSize
                color: metricRoot.textColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: metricRoot.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: metricRoot.clicked()
        }
    }

    // Popup sizes per widget
    property var popupSizes: ({
        "calendar": Qt.size(400, 350),
        "music": Qt.size(350, 300),
        "battery": Qt.size(300, 350),
        "network": Qt.size(400, 350),
        "wallpaper": Qt.size(600, 300),
        "monitors": Qt.size(450, 300),
        "focustime": Qt.size(400, 350),
        "stewart": Qt.size(400, 300),
        "power": Qt.size(240, 250)
    })

    // Close popup on any bar click (except popup toggles)
    function barClicked() {
        if (root.activePopup !== "") root.activePopup = "";
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: Style.barHeight
            exclusiveZone: Style.barHeight
            color: "transparent"

            Item {
                anchors.fill: parent

                // Click on empty bar area closes popup
                MouseArea {
                    anchors.fill: parent; z: -1
                    onClicked: root.barClicked()
                }

                // ========== LEFT ISLAND ==========
                Island {
                    id: leftIsland
                    anchors.left: parent.left; anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: leftContent.implicitWidth + 14

                    transform: Translate { id: leftSlide; x: -200 }
                    opacity: 0
                    Component.onCompleted: { leftSlideAnim.start(); leftFadeAnim.start(); }
                    NumberAnimation { id: leftSlideAnim; target: leftSlide; property: "x"; to: 0; duration: 600; easing.type: Easing.OutCubic }
                    NumberAnimation { id: leftFadeAnim; target: leftIsland; property: "opacity"; to: 1; duration: 600; easing.type: Easing.OutCubic }

                    Row {
                        id: leftContent
                        anchors.centerIn: parent; spacing: 3

                        Repeater {
                            model: [1,2,3,4,5,6,7,8,9,10,11,12]
                            Rectangle {
                                required property int modelData
                                property string wsState: root.workspaceState(modelData)
                                width: 18; height: 16; radius: 4
                                color: wsState === "focused" ? Style.special :
                                       wsState === "active" ? Style.accent :
                                       wsState === "occupied" ? Style.subtle : Qt.rgba(Style.dimText.r, Style.dimText.g, Style.dimText.b, 0.3)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent; text: modelData.toString()
                                    font.family: Style.fontMono; font.pixelSize: 8
                                    font.weight: wsState === "focused" ? Font.Bold : Font.Normal
                                    color: wsState === "focused" || wsState === "active" ? Style.background : Style.dimText
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Hyprland.dispatch("workspace " + modelData) }
                            }
                        }

                        Item {
                            visible: root.activePlayer !== null
                            width: visible ? mediaRow.implicitWidth + 10 : 0; height: 16
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Row {
                                id: mediaRow; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Image {
                                    width: 14; height: 14; source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.activePlayer ? root.activePlayer.trackTitle : ""
                                    font.family: Style.fontMono; font.pixelSize: Style.barFontSize; color: Style.text
                                    elide: Text.ElideRight; width: Math.min(implicitWidth, 140)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text { text: "\uf048"; font.family: Style.fontMono; font.pixelSize: 10; color: Style.dimText; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.previous() } } }
                                Text { text: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "\uf04c" : "\uf04b"; font.family: Style.fontMono; font.pixelSize: 11; color: Style.accent; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.togglePlaying() } } }
                                Text { text: "\uf051"; font.family: Style.fontMono; font.pixelSize: 10; color: Style.dimText; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.activePlayer) root.activePlayer.next() } } }
                            }
                        }
                    }
                }

                // ========== CENTER ISLAND ==========
                Island {
                    id: centerIsland
                    anchors.centerIn: parent
                    width: centerContent.implicitWidth + 18
                    opacity: 0
                    Component.onCompleted: centerFadeAnim.start()
                    NumberAnimation { id: centerFadeAnim; target: centerIsland; property: "opacity"; to: 1; duration: 600; easing.type: Easing.OutCubic }

                    Row {
                        id: centerContent; anchors.centerIn: parent; spacing: 8
                        Text {
                            visible: root.weatherTemp !== ""
                            text: root.weatherIcon + " " + root.weatherTemp
                            font.family: Style.fontMono; font.pixelSize: Style.barFontSize; color: Style.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: clockText; font.family: Style.fontMono; font.pixelSize: Style.barFontSize
                            font.weight: Font.Bold; color: Style.text; anchors.verticalCenter: parent.verticalCenter
                            Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: clockText.text = Qt.formatDateTime(new Date(), "dd/MM/yyyy - hh:mm") }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.activePopup === "calendar") root.activePopup = "";
                            else root.activePopup = "calendar";
                        }
                    }
                }

                // ========== RIGHT ISLAND ==========
                Island {
                    id: rightIsland
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: rightContent.implicitWidth + 14

                    transform: Translate { id: rightSlide; x: 200 }
                    opacity: 0
                    Component.onCompleted: { rightSlideAnim.start(); rightFadeAnim.start(); }
                    NumberAnimation { id: rightSlideAnim; target: rightSlide; property: "x"; to: 0; duration: 600; easing.type: Easing.OutCubic }
                    NumberAnimation { id: rightFadeAnim; target: rightIsland; property: "opacity"; to: 1; duration: 600; easing.type: Easing.OutCubic }

                    Row {
                        id: rightContent; anchors.centerIn: parent; spacing: 8

                        // CPU — tooltip shows per-core
                        Metric {
                            icon: "\uf4bc"; value: root.cpuUsage + "%"
                            iconColor: parseInt(root.cpuUsage) > 80 ? Style.error : Style.accent
                            textColor: parseInt(root.cpuUsage) > 80 ? Style.error : Style.text
                            clickable: true; onClicked: Quickshell.execDetached(["ghostty", "-e", "btop"])
                        }

                        // Memory
                        Metric {
                            icon: "\uefc5"; value: root.memUsage + "%"
                            iconColor: parseInt(root.memUsage) > 80 ? Style.error : Style.special
                            textColor: parseInt(root.memUsage) > 80 ? Style.error : Style.text
                            clickable: true; onClicked: Quickshell.execDetached(["ghostty", "-e", "btop"])
                        }

                        // Disk
                        Metric {
                            icon: "\uf0a0"; value: root.diskUsage + "%"
                            iconColor: parseInt(root.diskUsage) > 90 ? Style.error : Style.info
                            textColor: parseInt(root.diskUsage) > 90 ? Style.error : Style.text
                        }

                        Rectangle { width: 1; height: 14; color: Style.subtle }

                        // Battery
                        Metric {
                            visible: root.batteryPercent !== ""
                            icon: root.batteryStatus === "Charging" ? "\uf0e7" :
                                  parseInt(root.batteryPercent) > 80 ? "\uf240" :
                                  parseInt(root.batteryPercent) > 60 ? "\uf241" :
                                  parseInt(root.batteryPercent) > 40 ? "\uf242" :
                                  parseInt(root.batteryPercent) > 20 ? "\uf243" : "\uf244"
                            value: root.batteryPercent + "%"
                            iconColor: parseInt(root.batteryPercent) < 20 ? Style.error : Style.success
                            textColor: parseInt(root.batteryPercent) < 20 ? Style.error : Style.text
                        }

                        // Mic (icon only)
                        Metric {
                            icon: root.micMuted ? "\uf131" : "\uf130"; value: ""
                            iconColor: root.micMuted ? Style.error : Style.success
                            clickable: true; onClicked: Quickshell.execDetached(["pamixer", "--default-source", "-t"])
                        }

                        // Volume (icon only — click to mute/unmute)
                        Metric {
                            icon: root.volumeMuted ? "\uf6a9" : "\uf028"; value: ""
                            iconColor: root.volumeMuted ? Style.error : Style.warning
                            clickable: true
                            onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                        }

                        Rectangle { width: 1; height: 14; color: Style.subtle }

                        // Tray
                        Row {
                            spacing: 6
                            Repeater {
                                model: SystemTray.items
                                delegate: Item {
                                    id: trayItem
                                    required property SystemTrayItem modelData
                                    width: 16; height: 16

                                    Image {
                                        id: trayIcon
                                        anchors.fill: parent
                                        source: trayItem.modelData.icon || ""
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        opacity: trayMouse.containsMouse ? 1.0 : 0.75
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        id: trayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.MiddleButton) {
                                                trayItem.modelData.secondaryActivate();
                                            } else if (mouse.button === Qt.RightButton) {
                                                // Use display() with position relative to bar window
                                                var pos = trayItem.mapToItem(null, 0, trayItem.height);
                                                trayItem.modelData.display(bar, pos.x, pos.y);
                                            } else {
                                                trayItem.modelData.activate();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: 1; height: 14; color: Style.subtle }

                        // Power button
                        Metric {
                            icon: "\uf011"; value: ""
                            iconColor: Style.error
                            clickable: true
                            onClicked: {
                                if (root.activePopup === "power") root.activePopup = "";
                                else root.activePopup = "power";
                            }
                        }
                    }
                }
            }

            // ========== POPUP OVERLAY ==========
            // Fullscreen transparent overlay that catches outside clicks
            PanelWindow {
                id: popupOverlay
                property var modelData: bar.modelData
                screen: bar.modelData

                anchors { top: true; left: true; right: true; bottom: true }
                exclusiveZone: 0
                visible: root.activePopup !== ""
                color: "transparent"

                property int popupWidth: {
                    var s = root.popupSizes[root.activePopup];
                    return s ? s.width : 400;
                }
                property int popupHeight: {
                    var s = root.popupSizes[root.activePopup];
                    return s ? s.height : 300;
                }

                // Click anywhere on overlay = close popup
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.activePopup = ""
                }

                // Popup content centered horizontally, below bar
                Rectangle {
                    id: popupRect
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Style.barHeight + 4
                    width: popupOverlay.popupWidth
                    height: popupOverlay.popupHeight
                    color: Qt.rgba(Style.background.r, Style.background.g, Style.background.b, 0.9)
                    radius: 12
                    border.width: 1
                    border.color: Qt.rgba(Style.subtle.r, Style.subtle.g, Style.subtle.b, 0.5)

                    // Absorb clicks inside popup (don't close)
                    MouseArea { anchors.fill: parent }

                    // Dynamic popup content
                    Loader {
                        id: popupLoader
                        anchors.fill: parent
                        source: {
                            if (root.activePopup === "calendar") return "CalendarPopup.qml";
                            if (root.activePopup === "music") return "MusicPopup.qml";
                            if (root.activePopup === "battery") return "BatteryPopup.qml";
                            if (root.activePopup === "network") return "NetworkPopup.qml";
                            if (root.activePopup === "wallpaper") return "WallpaperPopup.qml";
                            if (root.activePopup === "monitors") return "MonitorPopup.qml";
                            if (root.activePopup === "focustime") return "FocusTimePopup.qml";
                            if (root.activePopup === "stewart") return "StewartPopup.qml";
                            if (root.activePopup === "power") return "PowerPopup.qml";
                            return "";
                        }
                    }

                    // Placeholder for unimplemented popups
                    Text {
                        anchors.centerIn: parent
                        visible: popupLoader.source === "" && root.activePopup !== ""
                        text: root.activePopup + "\n(coming soon)"
                        font.family: Style.fontMono; font.pixelSize: 14
                        color: Style.dimText; horizontalAlignment: Text.AlignHCenter
                    }

                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
