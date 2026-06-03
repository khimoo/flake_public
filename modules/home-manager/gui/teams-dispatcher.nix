{ pkgs, lib, settings, ... }:

# Teams の URL だけ Junction (アプリ選択ダイアログ) を表示し、
# それ以外は Firefox に直接渡すディスパッチャ。
#
# 背景:
#   teams-for-linux はマルチアカウントに対応しておらず、アカウント切り替えに
#   毎回ログアウトが必要。複数インスタンスを --partition で起動し、Junction で
#   開き先を選択することで擬似的にマルチアカウントを実現する。
#   Junction 自体に URL フィルタリング機能がないため、このスクリプトで補う。
#
# 注意:
#   x-scheme-handler/https をディスパッチャに向けると、Firefox が mimeapps.list を
#   参照して無限ループする。firefox.nix の network.protocol-handler.expose.{http,https}
#   で Firefox 自身に HTTP/HTTPS を内部処理させることで回避している。

let
  # id はファイル名 teams-${id}.desktop に展開される。
  # - "for-linux" を選んだ理由: パッケージ同梱の teams-for-linux.desktop と
  #   同名にすることで XDG の探索順により自前のエントリでパッケージ版を shadow し、
  #   アプリメニューに「Microsoft Teams for Linux」と「Teams」が両方並ぶ重複を防ぐ。
  # - partition = null は --partition フラグを付けず teams-for-linux の
  #   デフォルトプロファイルで起動する＝「通常の Teams」を意味する。
  #   それ以外の値は擬似マルチアカウント用の独立パーティションを示す。
  teamsAccounts = [
    { id = "for-linux"; label = "Teams";       partition = null;  }
    { id = "uni";       label = "Teams (Uni)"; partition = "uni"; }
  ];

  teamsBin = lib.getExe pkgs.teams-for-linux;

  teamsDesktopEntries = builtins.listToAttrs (map (account: {
    name = ".local/share/applications/teams-${account.id}.desktop";
    value = {
      # MimeType に x-scheme-handler/https,http を宣言しているのは Junction の
      # URL ハンドラ候補に列挙させるため。mimeapps.list のデフォルトは
      # teams-url-dispatcher.desktop のままなので、ブラウザ等の通常フローには影響しない。
      text = ''
        [Desktop Entry]
        Name=${account.label}
        Comment=Microsoft Teams - ${account.label}
        Exec=${teamsBin}${lib.optionalString (account.partition != null) " --partition=${account.partition}"} %U
        Icon=teams-for-linux
        Type=Application
        Categories=Network;Chat;
        Terminal=false
        StartupWMClass=teams-for-linux
        MimeType=x-scheme-handler/https;x-scheme-handler/http;
      '';
    };
  }) teamsAccounts);

  dispatcher = pkgs.writeShellScriptBin "teams-url-dispatcher" ''
    case "$1" in
      *teams.microsoft.com*|*teams.live.com*)
        exec ${lib.getExe pkgs.junction} "$1" ;;
      *)
        exec ${lib.getExe pkgs.firefox} "$1" ;;
    esac
  '';

  dispatcherDesktopEntry = {
    ".local/share/applications/teams-url-dispatcher.desktop" = {
      text = ''
        [Desktop Entry]
        Name=Teams URL Dispatcher
        Comment=Route Teams URLs to Junction, others to Firefox
        Exec=${dispatcher}/bin/teams-url-dispatcher %U
        Type=Application
        NoDisplay=true
        MimeType=x-scheme-handler/http;x-scheme-handler/https;
      '';
    };
  };

in
lib.mkIf settings.features.gui {
  home.packages = [
    pkgs.junction
    pkgs.teams-for-linux
  ];

  home.file = teamsDesktopEntries // dispatcherDesktopEntry;

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/http" = "teams-url-dispatcher.desktop";
    "x-scheme-handler/https" = "teams-url-dispatcher.desktop";
  };

  # Junction の候補ウィンドウでアイコン下にアプリ名を表示する。
  # 同じ teams-for-linux アイコンを使う複数エントリ（Teams / Teams (Uni) など）を
  # 視覚的に区別するために必須。Junction 組み込みの "Show App Names" 設定。
  dconf.settings."re/sonny/Junction" = {
    show-app-names = true;
  };
}
