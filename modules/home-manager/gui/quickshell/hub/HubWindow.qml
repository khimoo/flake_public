import QtQuick
import QtQuick.Controls.Basic as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Calc.js" as Calc

PanelWindow {
    id: hubWin

    required property var store

    property bool hubOpen: false
    property int currentTab: 0 // 0:All, 1:Windows, 2:Files, 3:Clipboard, 4:Vault, 5:Notify
    property string query: ""
    property int selectedIndex: 0

    property var workspaces: []
    property var niriWindows: []
    property var fileResults: []
    property var clipEntries: []
    property var vaultEntries: []
    property string vaultStatus: "" // "", "loading", or error/status message
    property bool vaultLoaded: false

    readonly property var tabDefs: [
        { id: "all", label: "All" },
        { id: "windows", label: "Windows" },
        { id: "files", label: "Files" },
        { id: "clipboard", label: "Clipboard" },
        { id: "vault", label: "Vault" },
        { id: "notify", label: "Notify" }
    ]

    // プレフィックス解析（どのタブでも = ? を解釈、All タブでは @ / ~ : も自動ルーティング）
    readonly property var parsedQuery: {
        var q = query;
        if (q.startsWith("=")) {
            return { mode: "calc", term: q.slice(1).trim(), raw: q };
        }
        if (q.startsWith("?")) {
            return { mode: "web", term: q.slice(1).trim(), raw: q };
        }
        if (currentTab === 0) {
            if (q.startsWith("@")) return { mode: "vault", term: q.slice(1).trim(), raw: q };
            if (q.startsWith("/") || q.startsWith("~")) return { mode: "files", term: q.slice(1).trim(), raw: q };
            if (q.startsWith(":")) return { mode: "clipboard", term: q.slice(1).trim(), raw: q };
            return { mode: "all", term: q.trim(), raw: q };
        }
        var tabMode = tabDefs[currentTab].id;
        return { mode: tabMode, term: q.trim(), raw: q };
    }

    readonly property string effectiveMode: parsedQuery.mode
    readonly property string searchTerm: parsedQuery.term

    readonly property var itemsModel: computeItems()

    visible: hubOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-hub"
    WlrLayershell.keyboardFocus: hubOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function openHub() {
        query = "";
        currentTab = 0;
        selectedIndex = 0;
        vaultLoaded = false;
        vaultStatus = "";
        hubOpen = true;
        refreshNiriState();
        refreshClipboard();
        focusTimer.restart();
    }

    function closeHub() {
        hubOpen = false;
        query = "";
        selectedIndex = 0;
    }

    function toggleHub() {
        if (hubOpen) closeHub();
        else openHub();
    }

    function focusSearch() {
        searchInput.forceActiveFocus(Qt.OtherFocusReason);
    }

    function switchTab(idx, keepTabBarFocus) {
        var next = (idx + tabDefs.length) % tabDefs.length;
        currentTab = next;
        selectedIndex = 0;
        if (tabDefs[next].id === "notify") {
            store.markAllRead();
        }
        ensureModeDataLoaded();
        if (keepTabBarFocus) {
            tabBarFocus.forceActiveFocus(Qt.TabFocusReason);
        } else {
            focusSearch();
        }
    }

    function handleEscape(event) {
        if (event.key === Qt.Key_Escape) {
            closeHub();
            event.accepted = true;
            return true;
        }
        return false;
    }

    function ensureModeDataLoaded() {
        var mode = effectiveMode;
        if (mode === "vault" && !vaultLoaded && vaultStatus !== "loading") {
            refreshVault();
        } else if (mode === "clipboard") {
            refreshClipboard();
        } else if (mode === "files") {
            fileSearchDebounce.restart();
        }
    }

    onEffectiveModeChanged: {
        selectedIndex = 0;
        if (hubOpen) {
            if (effectiveMode === "notify") {
                store.markAllRead();
            }
            ensureModeDataLoaded();
        }
    }

    onSearchTermChanged: {
        selectedIndex = 0;
        if (hubOpen && effectiveMode === "files") {
            fileSearchDebounce.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: hubWin.focusSearch()
    }

    Timer {
        id: fileSearchDebounce
        interval: 160
        repeat: false
        onTriggered: refreshFiles()
    }

    function refreshNiriState() {
        if (!wsProc.running) wsProc.running = true;
        if (!winProc.running) winProc.running = true;
    }

    function refreshClipboard() {
        if (!clipListProc.running) clipListProc.running = true;
    }

    function refreshFiles() {
        if (fileProc.running) fileProc.running = false;
        var term = searchTerm;
        var home = Quickshell.env("HOME") || "/";
        if (term.length === 0) {
            fileProc.command = ["fd", "--max-depth", "2", "--max-results", "40", "--exclude", ".git", ".", home];
        } else {
            fileProc.command = ["fd", "--max-results", "40", "--hidden", "--exclude", ".git", "--ignore-case", "--fixed-strings", "--", term, home];
        }
        fileProc.running = true;
    }

    function refreshVault() {
        vaultStatus = "loading";
        if (vaultListProc.running) vaultListProc.running = false;
        vaultListProc.running = true;
    }

    Process {
        id: wsProc
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    parsed.sort(function(a, b) { return (a.idx || 0) - (b.idx || 0); });
                    hubWin.workspaces = parsed;
                } catch (e) {}
            }
        }
    }

    Process {
        id: winProc
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    hubWin.niriWindows = parsed;
                } catch (e) {}
            }
        }
    }

    Process {
        id: clipListProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var out = [];
                for (var i = 0; i < lines.length && out.length < 100; i++) {
                    var line = lines[i];
                    if (!line) continue;
                    var tabIdx = line.indexOf("\t");
                    if (tabIdx <= 0) continue;
                    out.push({
                        clipId: line.slice(0, tabIdx),
                        preview: line.slice(tabIdx + 1).trim()
                    });
                }
                hubWin.clipEntries = out;
            }
        }
    }

    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: {
                var home = Quickshell.env("HOME") || "";
                var lines = this.text.split("\n");
                var out = [];
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].trim();
                    if (!p) continue;
                    var display = (home && p.startsWith(home + "/")) ? ("~/" + p.slice(home.length + 1)) : p;
                    var parts = display.split("/");
                    var base = parts[parts.length - 1] || display;
                    out.push({ fullPath: p, display: display, basename: base });
                }
                hubWin.fileResults = out;
            }
        }
    }

    Process {
        id: vaultListProc
        command: ["qs-hub-vault", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    if (parsed.ok) {
                        hubWin.vaultEntries = parsed.items || [];
                        hubWin.vaultStatus = "";
                        hubWin.vaultLoaded = true;
                    } else {
                        hubWin.vaultEntries = [];
                        hubWin.vaultStatus = parsed.error || "rbw のロック解除または設定が必要です";
                        hubWin.vaultLoaded = true;
                    }
                } catch (e) {
                    hubWin.vaultEntries = [];
                    hubWin.vaultStatus = "rbw の出力を読み取れませんでした";
                    hubWin.vaultLoaded = true;
                }
            }
        }
    }

    function wsIndexMap() {
        var map = {};
        for (var i = 0; i < workspaces.length; i++) {
            map[workspaces[i].id] = workspaces[i].idx;
        }
        return map;
    }

    function computeItems() {
        var mode = effectiveMode;
        var term = searchTerm;
        var lower = term.toLowerCase();
        var list = [];

        if (mode === "calc") {
            var val = Calc.evaluate(term);
            if (val !== null) {
                list.push({
                    kind: "calc",
                    title: "= " + val,
                    subtitle: term + "  （Enter でコピー）",
                    badge: "Calc",
                    payload: val
                });
            }
            return list;
        }

        if (mode === "web") {
            if (term.length > 0) {
                list.push({
                    kind: "web",
                    title: "Web 検索: " + term,
                    subtitle: "Zen Browser の新しいタブで検索",
                    badge: "Web",
                    payload: term
                });
            }
            return list;
        }

        if (mode === "all" || mode === "windows") {
            var wsMap = wsIndexMap();
            var wins = [];
            for (var wi = 0; wi < niriWindows.length; wi++) {
                var w = niriWindows[wi];
                var wTitle = w.title || "";
                var wApp = w.app_id || "";
                var hay = (wTitle + " " + wApp).toLowerCase();
                if (lower.length === 0 || hay.indexOf(lower) !== -1) {
                    var wsIdx = wsMap[w.workspace_id] || 0;
                    wins.push({
                        kind: "window",
                        title: wTitle || wApp,
                        subtitle: wApp,
                        badge: "WS " + wsIdx,
                        wsIdx: wsIdx,
                        payload: w.id
                    });
                }
            }
            wins.sort(function(a, b) { return a.wsIdx - b.wsIdx; });
            if (mode === "windows") {
                return wins;
            }
            if (lower.length > 0) {
                for (var k = 0; k < wins.length && k < 6; k++) {
                    list.push(wins[k]);
                }
            }
        }

        if (mode === "all") {
            var apps = DesktopEntries.applications.values;
            var prefixMatches = [];
            var subMatches = [];
            for (var ai = 0; ai < apps.length; ai++) {
                var app = apps[ai];
                if (app.noDisplay) continue;
                var name = app.name || "";
                var comment = app.comment || app.genericName || "";
                var kws = app.keywords ? app.keywords.join(" ") : "";
                var nameL = name.toLowerCase();
                var allL = (name + " " + comment + " " + kws).toLowerCase();
                if (lower.length === 0 || allL.indexOf(lower) !== -1) {
                    var item = {
                        kind: "app",
                        title: name,
                        subtitle: comment,
                        badge: "App",
                        icon: app.icon ? Quickshell.iconPath(app.icon, true) : "",
                        payload: app
                    };
                    if (lower.length > 0 && nameL.startsWith(lower)) prefixMatches.push(item);
                    else subMatches.push(item);
                }
            }
            prefixMatches.sort(function(a, b) { return a.title.localeCompare(b.title); });
            subMatches.sort(function(a, b) { return a.title.localeCompare(b.title); });
            list = list.concat(prefixMatches, subMatches);
            if (term.length > 0) {
                list.push({
                    kind: "web",
                    title: "Web 検索: " + term,
                    subtitle: "Zen Browser の新しいタブで検索",
                    badge: "Web",
                    payload: term
                });
            }
            return list;
        }

        if (mode === "files") {
            for (var fi = 0; fi < fileResults.length; fi++) {
                var f = fileResults[fi];
                list.push({
                    kind: "file",
                    title: f.basename,
                    subtitle: f.display,
                    badge: "File",
                    payload: f.fullPath
                });
            }
            return list;
        }

        if (mode === "clipboard") {
            for (var ci = 0; ci < clipEntries.length; ci++) {
                var c = clipEntries[ci];
                if (lower.length === 0 || c.preview.toLowerCase().indexOf(lower) !== -1) {
                    list.push({
                        kind: "clip",
                        title: c.preview,
                        subtitle: "Enter でクリップボードへコピー",
                        badge: "Clip",
                        payload: c.clipId
                    });
                }
            }
            return list;
        }

        if (mode === "vault") {
            for (var vi = 0; vi < vaultEntries.length; vi++) {
                var v = vaultEntries[vi];
                var vHay = ((v.name || "") + " " + (v.user || "") + " " + (v.folder || "")).toLowerCase();
                if (lower.length === 0 || vHay.indexOf(lower) !== -1) {
                    list.push({
                        kind: "vault",
                        title: v.name || "(無題)",
                        subtitle: (v.user || "") + (v.folder ? ("  [" + v.folder + "]") : ""),
                        badge: "Vault",
                        payload: v
                    });
                }
            }
            return list;
        }

        if (mode === "notify") {
            var hist = store.history;
            for (var ni = 0; ni < hist.length; ni++) {
                var n = hist[ni];
                var nHay = ((n.appName || "") + " " + (n.summary || "") + " " + (n.body || "")).toLowerCase();
                if (lower.length === 0 || nHay.indexOf(lower) !== -1) {
                    list.push({
                        kind: "notify",
                        title: (n.summary || n.appName),
                        subtitle: n.appName + " · " + n.timeText + (n.body ? (" — " + n.body) : ""),
                        badge: n.isCritical ? "重要" : "通知",
                        isCritical: n.isCritical,
                        payload: n
                    });
                }
            }
            return list;
        }

        return list;
    }

    function activateItem(item) {
        if (!item) return;
        if (item.kind === "app") {
            try { item.payload.execute(); } catch (e) {}
            closeHub();
        } else if (item.kind === "window") {
            Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(item.payload)]);
            closeHub();
        } else if (item.kind === "file") {
            Quickshell.execDetached(["xdg-open", item.payload]);
            closeHub();
        } else if (item.kind === "clip") {
            Quickshell.execDetached(["qs-hub-cliphist-copy", String(item.payload)]);
            closeHub();
        } else if (item.kind === "vault") {
            Quickshell.execDetached(["qs-hub-vault", "copy-pass", String(item.payload.id)]);
            closeHub();
        } else if (item.kind === "calc") {
            Quickshell.execDetached(["wl-copy", String(item.payload)]);
            closeHub();
        } else if (item.kind === "web") {
            Quickshell.execDetached(["qs-hub-web-search", String(item.payload)]);
            closeHub();
        } else if (item.kind === "notify") {
            store.invokeDefault(item.payload);
            closeHub();
        }
    }

    // 外クリックで閉じるための透明バックドロップ
    MouseArea {
        anchors.fill: parent
        onClicked: hubWin.closeHub()
    }

    // 中央フローティングカード（モデル B: 左右 2 カラム）
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(880, parent.width - 48)
        height: Math.min(540, parent.height - 48)
        radius: Theme.radiusLarge
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1
        clip: true

        // カード内クリックがバックドロップへ抜けないよう吸収する
        MouseArea {
            anchors.fill: parent
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // 左カラム: タブ・検索・操作メモ・アクションボタン・一覧
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 14
                spacing: 8

                // タブバー（Tab / Shift+Tab でここにフォーカスが当たった状態で ← / → により切替）
                FocusScope {
                    id: tabBarFocus
                    Layout.fillWidth: true
                    implicitHeight: 32
                    activeFocusOnTab: true

                    Keys.onPressed: function(event) {
                        if (hubWin.handleEscape(event)) return;
                        if (event.key === Qt.Key_Left) {
                            hubWin.switchTab(hubWin.currentTab - 1, true);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right) {
                            hubWin.switchTab(hubWin.currentTab + 1, true);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            hubWin.focusSearch();
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: "transparent"
                        border.width: tabBarFocus.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 4

                        Repeater {
                            model: hubWin.tabDefs

                            Rectangle {
                                id: tabBtn
                                required property var modelData
                                required property int index
                                readonly property bool active: hubWin.currentTab === index || (hubWin.currentTab === 0 && hubWin.effectiveMode === modelData.id && modelData.id !== "all")

                                implicitWidth: tabLabel.implicitWidth + 18
                                height: 28
                                radius: Theme.radiusSmall
                                color: active ? Theme.accentSoft : (tabMouse.containsMouse ? Theme.surface0 : "transparent")
                                border.width: active ? (tabBarFocus.activeFocus ? 2 : 1) : 0
                                border.color: Theme.accent

                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: {
                                        if (tabBtn.modelData.id === "notify" && hubWin.store.unreadCount > 0) {
                                            return tabBtn.modelData.label + " (" + hubWin.store.unreadCount + ")";
                                        }
                                        return tabBtn.modelData.label;
                                    }
                                    color: tabBtn.active ? Theme.accent : Theme.subtext
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: tabBtn.active
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: hubWin.switchTab(tabBtn.index, false)
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // 検索窓（Tab / Shift+Tab は標準のフォーカス移動に譲る）
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: Theme.radiusMedium
                    color: Theme.mantle
                    border.width: searchInput.activeFocus ? 2 : 1
                    border.color: searchInput.activeFocus ? Theme.accent : Theme.surface1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "󰍉"
                            color: Theme.accent
                            font.family: Theme.monoFamily
                            font.pixelSize: 15
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            activeFocusOnTab: true
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            selectionColor: Theme.accentSoft
                            selectedTextColor: Theme.text
                            clip: true
                            text: hubWin.query

                            onTextChanged: hubWin.query = text

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.text.length === 0
                                text: "検索...（アプリ・ウィンドウ・ファイル・履歴・Vault）"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }

                            Keys.onPressed: function(event) {
                                var ctrl = Boolean(event.modifiers & Qt.ControlModifier);
                                if (event.key === Qt.Key_Escape) {
                                    hubWin.closeHub();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (hubWin.itemsModel.length > 0) {
                                        hubWin.selectedIndex = (hubWin.selectedIndex + 1) % hubWin.itemsModel.length;
                                        resultList.positionViewAtIndex(hubWin.selectedIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    if (hubWin.itemsModel.length > 0) {
                                        hubWin.selectedIndex = (hubWin.selectedIndex - 1 + hubWin.itemsModel.length) % hubWin.itemsModel.length;
                                        resultList.positionViewAtIndex(hubWin.selectedIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (hubWin.itemsModel.length > 0 && hubWin.selectedIndex < hubWin.itemsModel.length) {
                                        hubWin.activateItem(hubWin.itemsModel[hubWin.selectedIndex]);
                                    }
                                    event.accepted = true;
                                } else if (hubWin.effectiveMode === "vault" && ctrl && event.key === Qt.Key_U) {
                                    var itU = hubWin.itemsModel[hubWin.selectedIndex];
                                    if (itU && itU.kind === "vault") {
                                        Quickshell.execDetached(["qs-hub-vault", "copy-user", String(itU.payload.id)]);
                                        hubWin.closeHub();
                                    }
                                    event.accepted = true;
                                } else if (hubWin.effectiveMode === "vault" && ctrl && event.key === Qt.Key_T) {
                                    var itT = hubWin.itemsModel[hubWin.selectedIndex];
                                    if (itT && itT.kind === "vault") {
                                        Quickshell.execDetached(["qs-hub-vault", "copy-totp", String(itT.payload.id)]);
                                        hubWin.closeHub();
                                    }
                                    event.accepted = true;
                                } else if (hubWin.effectiveMode === "notify" && event.key === Qt.Key_Delete) {
                                    var itN = hubWin.itemsModel[hubWin.selectedIndex];
                                    if (itN && itN.kind === "notify") {
                                        hubWin.store.removeEntry(itN.payload.entryId);
                                        if (hubWin.selectedIndex >= hubWin.itemsModel.length) {
                                            hubWin.selectedIndex = Math.max(0, hubWin.itemsModel.length - 1);
                                        }
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // プレフィックス・フォーカス操作メモ
                Text {
                    Layout.fillWidth: true
                    text: "@ Vault  / Files  : Clip  ? Web  = 電卓  Tab フォーカス移動  ←→ タブ/スライダー"
                    color: Theme.muted
                    font.family: Theme.monoFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                // Notify タブの標準コントロール（Tab でそのままフォーカス到達）
                RowLayout {
                    visible: hubWin.effectiveMode === "notify"
                    Layout.fillWidth: true
                    spacing: 8

                    QQC.Button {
                        id: dndBtn
                        activeFocusOnTab: hubWin.effectiveMode === "notify"
                        implicitHeight: 28
                        leftPadding: 10
                        rightPadding: 10

                        onClicked: hubWin.store.dnd = !hubWin.store.dnd

                        Keys.onPressed: function(event) {
                            if (hubWin.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                dndBtn.clicked();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: hubWin.store.dnd ? Theme.accentSoft : (dndBtn.hovered ? Theme.surface1 : Theme.surface0)
                            border.width: dndBtn.activeFocus ? 2 : (hubWin.store.dnd ? 1 : 0)
                            border.color: Theme.accent
                        }

                        contentItem: Text {
                            text: hubWin.store.dnd ? "󰂛 おやすみ中（ON）" : "󰂚 おやすみモード（OFF）"
                            color: hubWin.store.dnd ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Item { Layout.fillWidth: true }

                    QQC.Button {
                        id: clearNotifBtn
                        visible: hubWin.store.history.length > 0
                        activeFocusOnTab: visible && hubWin.effectiveMode === "notify"
                        implicitHeight: 28
                        leftPadding: 10
                        rightPadding: 10

                        onClicked: hubWin.store.clearAll()

                        Keys.onPressed: function(event) {
                            if (hubWin.handleEscape(event)) return;
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                clearNotifBtn.clicked();
                                event.accepted = true;
                            }
                        }

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: clearNotifBtn.hovered ? Theme.redSoft : Theme.surface0
                            border.width: clearNotifBtn.activeFocus ? 2 : 0
                            border.color: Theme.red
                        }

                        contentItem: Text {
                            text: "すべて消去"
                            color: Theme.red
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // Vault 未解錠／状態バナー（解錠ボタンも標準 QQC.Button で Tab 到達）
                Rectangle {
                    visible: hubWin.effectiveMode === "vault" && hubWin.vaultStatus.length > 0
                    Layout.fillWidth: true
                    implicitHeight: vaultBannerRow.implicitHeight + 14
                    radius: Theme.radiusSmall
                    color: Theme.surface0

                    RowLayout {
                        id: vaultBannerRow
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 8

                        Text {
                            text: hubWin.vaultStatus === "loading" ? "Bitwarden（rbw）を読み込み中..." : hubWin.vaultStatus
                            color: Theme.subtext
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        QQC.Button {
                            id: unlockBtn
                            visible: hubWin.vaultStatus !== "loading" && hubWin.vaultStatus.indexOf("未設定") === -1
                            activeFocusOnTab: visible && hubWin.effectiveMode === "vault"
                            implicitHeight: 26
                            leftPadding: 10
                            rightPadding: 10

                            onClicked: {
                                hubWin.vaultLoaded = false;
                                hubWin.closeHub();
                                Quickshell.execDetached(["qs-hub-vault", "unlock"]);
                            }

                            Keys.onPressed: function(event) {
                                if (hubWin.handleEscape(event)) return;
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    unlockBtn.clicked();
                                    event.accepted = true;
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.accent
                                border.width: unlockBtn.activeFocus ? 2 : 0
                                border.color: Theme.text
                            }

                            contentItem: Text {
                                text: "解錠 (rbw)"
                                color: "#11111b"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                // メイン一覧
                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: hubWin.itemsModel
                    currentIndex: hubWin.selectedIndex

                    delegate: Rectangle {
                        id: rowItem
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === hubWin.selectedIndex

                        width: resultList.width
                        height: 46
                        radius: Theme.radiusMedium
                        color: selected ? Theme.accentSoft : (rowMouse.containsMouse ? Theme.surface0 : "transparent")
                        border.width: selected ? 1 : 0
                        border.color: Theme.accent

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Image {
                                visible: Boolean(rowItem.modelData.icon && rowItem.modelData.icon.length > 0)
                                source: rowItem.modelData.icon || ""
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: rowItem.modelData.title
                                    color: rowItem.modelData.isCritical ? Theme.red : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: rowItem.selected
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: text.length > 0
                                    text: rowItem.modelData.subtitle || ""
                                    color: Theme.subtext
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Vault 用の ID / TOTP コピーボタン
                            RowLayout {
                                visible: rowItem.modelData.kind === "vault"
                                spacing: 4

                                Rectangle {
                                    implicitWidth: 32
                                    height: 22
                                    radius: 4
                                    color: Theme.surface1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "ID"
                                        color: Theme.text
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 10
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.execDetached(["qs-hub-vault", "copy-user", String(rowItem.modelData.payload.id)]);
                                            hubWin.closeHub();
                                        }
                                    }
                                }

                                Rectangle {
                                    implicitWidth: 42
                                    height: 22
                                    radius: 4
                                    color: Theme.surface1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "TOTP"
                                        color: Theme.text
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 10
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.execDetached(["qs-hub-vault", "copy-totp", String(rowItem.modelData.payload.id)]);
                                            hubWin.closeHub();
                                        }
                                    }
                                }
                            }

                            // Notify 用の削除ボタン
                            Rectangle {
                                visible: rowItem.modelData.kind === "notify"
                                width: 22
                                height: 22
                                radius: 4
                                color: delNotifMouse.containsMouse ? Theme.redSoft : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.subtext
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: delNotifMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: hubWin.store.removeEntry(rowItem.modelData.payload.entryId)
                                }
                            }

                            // カテゴリバッジ
                            Rectangle {
                                visible: Boolean(rowItem.modelData.badge)
                                implicitWidth: badgeText.implicitWidth + 10
                                height: 20
                                radius: 4
                                color: rowItem.modelData.isCritical ? Theme.redSoft : Theme.surface0

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: rowItem.modelData.badge || ""
                                    color: rowItem.modelData.isCritical ? Theme.red : Theme.muted
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 10
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onEntered: hubWin.selectedIndex = rowItem.index
                            onClicked: hubWin.activateItem(rowItem.modelData)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: resultList.count === 0 && !(hubWin.effectiveMode === "vault" && hubWin.vaultStatus.length > 0)
                        text: {
                            if (hubWin.effectiveMode === "notify") return "通知履歴はありません";
                            if (hubWin.effectiveMode === "clipboard") return "クリップボード履歴はありません";
                            if (hubWin.effectiveMode === "calc") return "数式を入力してください（例: =1280*1.2）";
                            if (hubWin.effectiveMode === "web") return "検索語を入力してください（例: ?nix quickshell）";
                            return "一致する項目がありません";
                        }
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }

            // 縦の仕切り線
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Theme.surface0
            }

            // 右カラム: 時計・電池・WS・音量・明るさ・トレイ・電源（全要素が標準コントロール）
            RightColumn {
                id: rightCol
                hubWindow: hubWin
                hubOpen: hubWin.hubOpen
                workspaces: hubWin.workspaces
                onRequestClose: hubWin.closeHub()
            }
        }
    }
}
