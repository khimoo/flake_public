import QtQuick
import QtQuick.Controls.Basic as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower

Rectangle {
    id: rightCol

    required property var hubWindow
    required property bool hubOpen
    required property var workspaces

    signal requestClose()

    Layout.preferredWidth: 264
    Layout.fillHeight: true
    color: Theme.mantle

    property string timeText: ""
    property string dateText: ""
    property bool hasBacklight: false
    property int brightnessPct: 0
    property var displayProfiles: []
    property string currentDisplayProfile: ""
    property string defaultDisplayProfile: ""
    property string pendingPowerId: ""
    property string pendingPowerLabel: ""
    property var devModeItems: []
    property bool anyDevMode: false

    readonly property var powerItems: [
        { id: "lock", icon: "󰌾", label: "ロック", immediate: true, cmd: ["loginctl", "lock-session"] },
        { id: "suspend", icon: "󰤄", label: "スリープ", immediate: false, cmd: ["systemctl", "suspend"] },
        { id: "logout", icon: "󰍃", label: "ログアウト", immediate: false, cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"] },
        { id: "reboot", icon: "󰜉", label: "再起動", immediate: false, cmd: ["systemctl", "reboot"] },
        { id: "poweroff", icon: "󰐥", label: "終了", immediate: false, cmd: ["systemctl", "poweroff"] }
    ]

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property int volumePct: sinkAudio ? Math.round(Math.max(0, Math.min(1.0, sinkAudio.volume)) * 100) : 0
    readonly property bool isMuted: sinkAudio ? sinkAudio.muted : false

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int batteryPct: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool batteryCharging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

    function handleEscape(event) {
        if (event.key === Qt.Key_Escape) {
            requestClose();
            event.accepted = true;
            return true;
        }
        return false;
    }

    function updateClock() {
        var now = new Date();
        var days = ["日", "月", "火", "水", "木", "金", "土"];
        var hh = String(now.getHours()).padStart(2, "0");
        var mm = String(now.getMinutes()).padStart(2, "0");
        var mon = String(now.getMonth() + 1).padStart(2, "0");
        var dd = String(now.getDate()).padStart(2, "0");
        timeText = hh + ":" + mm;
        dateText = mon + "/" + dd + " (" + days[now.getDay()] + ")";
    }

    function refreshBrightness() {
        if (!brightnessReadProc.running) {
            brightnessReadProc.running = true;
        }
    }

    function refreshDisplayProfiles() {
        if (!displayReadProc.running) {
            displayReadProc.running = true;
        }
    }

    function refreshDevMode() {
        if (!devModeReadProc.running) {
            devModeReadProc.running = true;
        }
    }

    function hasQuickshellDev() {
        for (var i = 0; i < devModeItems.length; i++) {
            if (devModeItems[i].name === "quickshell" && devModeItems[i].dev) {
                return true;
            }
        }
        return false;
    }

    function runDevModeAction(args, restartsHub) {
        if (restartsHub) {
            requestClose();
            Quickshell.execDetached(["dotfiles-mode"].concat(args));
            return;
        }
        if (devModeActionProc.running) {
            return;
        }
        devModeActionProc.command = ["dotfiles-mode"].concat(args);
        devModeActionProc.running = true;
    }

    function setBrightness(pct) {
        var clamped = Math.max(1, Math.min(100, Math.round(pct)));
        brightnessPct = clamped;
        Quickshell.execDetached(["brightnessctl", "--class=backlight", "set", clamped + "%"]);
    }

    function clearPendingPower() {
        pendingPowerId = "";
        pendingPowerLabel = "";
        confirmResetTimer.stop();
    }

    function triggerPower(id, label, immediate, cmd) {
        if (immediate) {
            clearPendingPower();
            requestClose();
            Quickshell.execDetached(cmd);
            return;
        }
        if (pendingPowerId === id) {
            clearPendingPower();
            requestClose();
            Quickshell.execDetached(cmd);
        } else {
            pendingPowerId = id;
            pendingPowerLabel = label;
            confirmResetTimer.restart();
        }
    }

    onHubOpenChanged: {
        if (hubOpen) {
            updateClock();
            refreshBrightness();
            refreshDisplayProfiles();
            refreshDevMode();
            clearPendingPower();
        } else {
            clearPendingPower();
        }
    }

    Component.onCompleted: {
        updateClock();
        refreshBrightness();
        refreshDisplayProfiles();
        refreshDevMode();
    }

    Timer {
        interval: 1000
        running: rightCol.hubOpen
        repeat: true
        onTriggered: rightCol.updateClock()
    }

    // ハブを開いている間、物理の明るさキー操作をスライダーへ即座に反映する（操作中は停止）。
    Timer {
        interval: 200
        running: rightCol.hubOpen && rightCol.hasBacklight && !briSlider.pressed
        repeat: true
        onTriggered: rightCol.refreshBrightness()
    }

    Timer {
        id: confirmResetTimer
        interval: 4000
        repeat: false
        onTriggered: rightCol.clearPendingPower()
    }

    Process {
        id: displayReadProc
        command: ["kanshi-switch", "--status-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text || "{}");
                    rightCol.displayProfiles = Array.isArray(parsed.profiles) ? parsed.profiles : [];
                    rightCol.currentDisplayProfile = parsed.current || "";
                    rightCol.defaultDisplayProfile = parsed.default || "";
                } catch (e) {
                    rightCol.displayProfiles = [];
                    rightCol.currentDisplayProfile = "";
                    rightCol.defaultDisplayProfile = "";
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                rightCol.displayProfiles = [];
                rightCol.currentDisplayProfile = "";
                rightCol.defaultDisplayProfile = "";
            }
        }
    }

    Process {
        id: devModeReadProc
        command: ["dotfiles-mode", "--status-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text || "{}");
                    rightCol.devModeItems = Array.isArray(parsed.items) ? parsed.items : [];
                    rightCol.anyDevMode = Boolean(parsed.any_dev);
                } catch (e) {
                    rightCol.devModeItems = [];
                    rightCol.anyDevMode = false;
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                rightCol.devModeItems = [];
                rightCol.anyDevMode = false;
            }
        }
    }

    Process {
        id: devModeActionProc
        onExited: function() {
            rightCol.refreshDevMode();
            rightCol.refreshDisplayProfiles();
        }
    }

    Process {
        id: brightnessReadProc
        command: ["brightnessctl", "--class=backlight", "-m", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                var line = this.text.trim().split("\n")[0] || "";
                var parts = line.split(",");
                if (parts.length >= 4 && parts[3].indexOf("%") !== -1) {
                    var parsed = parseInt(parts[3].replace("%", ""), 10);
                    if (!isNaN(parsed)) {
                        rightCol.hasBacklight = true;
                        rightCol.brightnessPct = parsed;
                        return;
                    }
                }
                rightCol.hasBacklight = false;
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                rightCol.hasBacklight = false;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // 時計・日付・バッテリー
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: rightCol.timeText
                color: Theme.text
                font.family: Theme.monoFamily
                font.pixelSize: 28
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: rightCol.dateText
                    color: Theme.subtext
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: rightCol.hasBattery
                    implicitWidth: batText.implicitWidth + 14
                    implicitHeight: 22
                    radius: Theme.radiusSmall
                    color: rightCol.batteryPct <= 15 && !rightCol.batteryCharging ? Theme.redSoft : Theme.surface0

                    Text {
                        id: batText
                        anchors.centerIn: parent
                        text: (rightCol.batteryCharging ? "󰂄 " : "󰁹 ") + rightCol.batteryPct + "%"
                        color: rightCol.batteryPct <= 15 && !rightCol.batteryCharging ? Theme.red : (rightCol.batteryCharging ? Theme.green : Theme.text)
                        font.family: Theme.monoFamily
                        font.pixelSize: 11
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.surface0
        }

        // ワークスペース一覧（各ピルが標準 QQC.Button として Tab 巡回に参加）
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "ワークスペース"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    id: wsRepeater
                    model: rightCol.workspaces

                    QQC.Button {
                        id: wsBtn
                        required property var modelData
                        required property int index
                        readonly property bool isActiveWs: Boolean(modelData.is_active)

                        activeFocusOnTab: true
                        implicitWidth: Math.max(30, wsText.implicitWidth + 14)
                        implicitHeight: 26
                        padding: 0

                        onClicked: {
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(wsBtn.modelData.idx)]);
                            rightCol.requestClose();
                        }

                        Keys.onPressed: function(event) {
                            if (rightCol.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                wsBtn.clicked();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: wsBtn.isActiveWs ? Theme.accent : (wsBtn.hovered ? Theme.surface1 : Theme.surface0)
                            border.width: wsBtn.activeFocus ? 2 : 0
                            border.color: wsBtn.isActiveWs ? Theme.text : Theme.accent
                        }

                        contentItem: Text {
                            id: wsText
                            text: wsBtn.modelData.name ? wsBtn.modelData.name : String(wsBtn.modelData.idx)
                            color: wsBtn.isActiveWs ? "#11111b" : Theme.text
                            font.family: Theme.monoFamily
                            font.pixelSize: 11
                            font.bold: wsBtn.isActiveWs
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        // ディスプレイ配置（kanshi の名前付きプロファイル切替＋管理ランチャー起動）
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "ディスプレイ"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    Layout.fillWidth: true
                }

                QQC.Button {
                    id: displayManageBtn
                    activeFocusOnTab: true
                    padding: 4

                    onClicked: {
                        rightCol.requestClose();
                        Quickshell.execDetached(["kanshi-switch"]);
                    }

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            displayManageBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: displayManageBtn.hovered ? Theme.surface0 : "transparent"
                        border.width: displayManageBtn.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        text: "管理"
                        color: displayManageBtn.hovered || displayManageBtn.activeFocus ? Theme.accent : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: rightCol.displayProfiles

                    QQC.Button {
                        id: dispBtn
                        required property string modelData
                        readonly property bool isActiveDisp: modelData === rightCol.currentDisplayProfile
                        readonly property bool isDefaultDisp: rightCol.displayProfiles.length > 1 && modelData === rightCol.defaultDisplayProfile

                        activeFocusOnTab: true
                        implicitWidth: Math.max(44, dispText.implicitWidth + 16)
                        implicitHeight: 26
                        padding: 0

                        onClicked: {
                            Quickshell.execDetached(["kanshi-switch", dispBtn.modelData]);
                            rightCol.requestClose();
                        }

                        Keys.onPressed: function(event) {
                            if (rightCol.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                dispBtn.clicked();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: dispBtn.isActiveDisp ? Theme.accent : (dispBtn.hovered ? Theme.surface1 : Theme.surface0)
                            border.width: dispBtn.activeFocus ? 2 : 0
                            border.color: dispBtn.isActiveDisp ? Theme.text : Theme.accent
                        }

                        contentItem: Text {
                            id: dispText
                            text: (dispBtn.isDefaultDisp ? "★ " : "") + dispBtn.modelData
                            color: dispBtn.isActiveDisp ? "#11111b" : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: dispBtn.isActiveDisp
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                QQC.Button {
                    id: dispCreateBtn
                    visible: rightCol.displayProfiles.length === 0
                    activeFocusOnTab: rightCol.displayProfiles.length === 0
                    implicitWidth: dispCreateText.implicitWidth + 16
                    implicitHeight: 26
                    padding: 0

                    onClicked: {
                        rightCol.requestClose();
                        Quickshell.execDetached(["kanshi-switch", "--create"]);
                    }

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            dispCreateBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: dispCreateBtn.hovered ? Theme.surface1 : Theme.surface0
                        border.width: dispCreateBtn.activeFocus ? 2 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        id: dispCreateText
                        text: "+ プロファイルを作成"
                        color: Theme.subtext
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // 音量コントロール（ミュート Button・ミキサー Button・音量 Slider）
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                QQC.Button {
                    id: volMuteBtn
                    activeFocusOnTab: true
                    padding: 4
                    Layout.fillWidth: true

                    onClicked: {
                        if (rightCol.sinkAudio) {
                            rightCol.sinkAudio.muted = !rightCol.sinkAudio.muted;
                        }
                    }

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            volMuteBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: volMuteBtn.hovered ? Theme.surface0 : "transparent"
                        border.width: volMuteBtn.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        text: rightCol.isMuted ? "󰝟 ミュート" : ("󰕾 音量 " + rightCol.volumePct + "%")
                        color: rightCol.isMuted ? Theme.muted : Theme.subtext
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                QQC.Button {
                    id: mixerBtn
                    activeFocusOnTab: true
                    padding: 4

                    onClicked: {
                        rightCol.requestClose();
                        Quickshell.execDetached(["pwvucontrol"]);
                    }

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            mixerBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: mixerBtn.hovered ? Theme.surface0 : "transparent"
                        border.width: mixerBtn.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        text: "ミキサー"
                        color: mixerBtn.hovered || mixerBtn.activeFocus ? Theme.accent : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            QQC.Slider {
                id: volSlider
                Layout.fillWidth: true
                implicitHeight: 20
                activeFocusOnTab: true
                from: 0
                to: 100
                stepSize: 5
                value: rightCol.volumePct

                onMoved: {
                    if (rightCol.sinkAudio) {
                        rightCol.sinkAudio.muted = false;
                        rightCol.sinkAudio.volume = value / 100.0;
                    }
                }

                Keys.onPressed: function(event) {
                    rightCol.handleEscape(event);
                }

                background: Rectangle {
                    x: volSlider.leftPadding
                    y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                    width: volSlider.availableWidth
                    height: 6
                    radius: 3
                    color: Theme.surface0
                    border.width: volSlider.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    Rectangle {
                        width: volSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 3
                        color: rightCol.isMuted ? Theme.muted : Theme.accent
                    }
                }

                handle: Rectangle {
                    x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                    y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                    width: volSlider.activeFocus ? 14 : 10
                    height: width
                    radius: width / 2
                    color: volSlider.activeFocus ? Theme.text : Theme.accent
                    border.width: volSlider.activeFocus ? 2 : 0
                    border.color: Theme.accent
                }
            }
        }

        // 明るさスライダー（バックライトがある環境のみ表示）
        ColumnLayout {
            visible: rightCol.hasBacklight
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "󰃠 明るさ " + rightCol.brightnessPct + "%"
                color: briSlider.activeFocus ? Theme.accent : Theme.subtext
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            QQC.Slider {
                id: briSlider
                Layout.fillWidth: true
                implicitHeight: 20
                activeFocusOnTab: rightCol.hasBacklight
                from: 1
                to: 100
                stepSize: 5
                value: rightCol.brightnessPct

                onMoved: rightCol.setBrightness(value)

                Keys.onPressed: function(event) {
                    rightCol.handleEscape(event);
                }

                background: Rectangle {
                    x: briSlider.leftPadding
                    y: briSlider.topPadding + briSlider.availableHeight / 2 - height / 2
                    width: briSlider.availableWidth
                    height: 6
                    radius: 3
                    color: Theme.surface0
                    border.width: briSlider.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    Rectangle {
                        width: briSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 3
                        color: Theme.yellow
                    }
                }

                handle: Rectangle {
                    x: briSlider.leftPadding + briSlider.visualPosition * (briSlider.availableWidth - width)
                    y: briSlider.topPadding + briSlider.availableHeight / 2 - height / 2
                    width: briSlider.activeFocus ? 14 : 10
                    height: width
                    radius: width / 2
                    color: briSlider.activeFocus ? Theme.text : Theme.yellow
                    border.width: briSlider.activeFocus ? 2 : 0
                    border.color: Theme.accent
                }
            }
        }

        // システムトレイ（各アイコンが標準 QQC.Button として Tab 巡回に参加）
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "システムトレイ"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: SystemTray.items.values

                    QQC.Button {
                        id: trayBtn
                        required property var modelData

                        activeFocusOnTab: true
                        implicitWidth: 30
                        implicitHeight: 30
                        padding: 0

                        function openMenu() {
                            var pos = trayBtn.mapToItem(null, trayBtn.width / 2, trayBtn.height / 2);
                            trayBtn.modelData.display(rightCol.hubWindow, Math.round(pos.x), Math.round(pos.y));
                        }

                        onClicked: {
                            if (trayBtn.modelData.onlyMenu) openMenu();
                            else trayBtn.modelData.activate();
                        }

                        Keys.onPressed: function(event) {
                            if (rightCol.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                trayBtn.clicked();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Menu) {
                                trayBtn.openMenu();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: trayBtn.hovered ? Theme.surface1 : Theme.surface0
                            border.width: trayBtn.activeFocus ? 2 : 0
                            border.color: Theme.accent
                        }

                        contentItem: Item {
                            Image {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: trayBtn.modelData.icon
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                        }

                        // 右クリックでトレイメニューを開く
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: trayBtn.openMenu()
                        }
                    }
                }

                Text {
                    visible: SystemTray.items.values.length === 0
                    text: "アイコンなし"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        // Dev モード（Nix store とローカル checkout の個別切替。dotfiles-mode が無い環境では非表示）
        ColumnLayout {
            visible: rightCol.devModeItems.length > 0
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Dev モード"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    Layout.fillWidth: true
                }

                QQC.Button {
                    id: devResetBtn
                    visible: rightCol.anyDevMode
                    activeFocusOnTab: rightCol.anyDevMode
                    padding: 4

                    onClicked: rightCol.runDevModeAction(["reset"], rightCol.hasQuickshellDev())

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            devResetBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: devResetBtn.hovered ? Theme.surface0 : "transparent"
                        border.width: devResetBtn.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        text: "全て戻す"
                        color: devResetBtn.hovered || devResetBtn.activeFocus ? Theme.yellow : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: rightCol.devModeItems

                    QQC.Button {
                        id: devBtn
                        required property var modelData
                        readonly property bool isDev: Boolean(modelData.dev)

                        activeFocusOnTab: rightCol.devModeItems.length > 0
                        implicitWidth: Math.max(44, devText.implicitWidth + 14)
                        implicitHeight: 26
                        padding: 0

                        onClicked: rightCol.runDevModeAction(
                            ["toggle", String(devBtn.modelData.name)],
                            devBtn.modelData.name === "quickshell"
                        )

                        Keys.onPressed: function(event) {
                            if (rightCol.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                devBtn.clicked();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: devBtn.isDev ? Theme.yellow : (devBtn.hovered ? Theme.surface1 : Theme.surface0)
                            border.width: devBtn.activeFocus ? 2 : 0
                            border.color: devBtn.isDev ? Theme.text : Theme.accent
                        }

                        contentItem: Text {
                            id: devText
                            text: (devBtn.isDev ? "● " : "") + devBtn.modelData.label
                            color: devBtn.isDev ? "#11111b" : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: devBtn.isDev
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // 電源ボタン確認メッセージ（2回押し確認時のみ表示）
        Rectangle {
            visible: rightCol.pendingPowerId.length > 0
            Layout.fillWidth: true
            implicitHeight: confirmText.implicitHeight + 10
            radius: Theme.radiusSmall
            color: Theme.redSoft
            border.width: 1
            border.color: Theme.red

            Text {
                id: confirmText
                anchors.centerIn: parent
                text: "もう一度押して「" + rightCol.pendingPowerLabel + "」"
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.surface0
        }

        // 電源ボタン群（すべて標準 QQC.Button で Tab 巡回に参加）
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: rightCol.powerItems

                QQC.Button {
                    id: pwrBtn
                    required property var modelData
                    readonly property bool isPending: rightCol.pendingPowerId === modelData.id

                    activeFocusOnTab: true
                    Layout.fillWidth: true
                    implicitHeight: 34
                    padding: 0

                    onClicked: rightCol.triggerPower(
                        pwrBtn.modelData.id,
                        pwrBtn.modelData.label,
                        pwrBtn.modelData.immediate,
                        pwrBtn.modelData.cmd
                    )

                    Keys.onPressed: function(event) {
                        if (rightCol.handleEscape(event)) return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            pwrBtn.clicked();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: pwrBtn.isPending ? Theme.red : (pwrBtn.hovered ? Theme.surface1 : Theme.surface0)
                        border.width: pwrBtn.activeFocus ? 2 : 0
                        border.color: pwrBtn.isPending ? Theme.text : Theme.accent
                    }

                    contentItem: Text {
                        text: pwrBtn.modelData.icon
                        color: pwrBtn.isPending ? "#11111b" : (pwrBtn.modelData.id === "poweroff" ? Theme.red : Theme.text)
                        font.family: Theme.monoFamily
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
