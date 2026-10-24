{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

let
  waylandFlags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";

  # ---- 一般アプリの定義（導入・Wayland・自動起動・MIME をまとめる） ----
  # 専用モジュールやスキーム登録の変更箇所: docs/howtouse/gui-apps.md

  # GNOME のスキーム解決には mimeapps.list の明示的な既定が必要なため、
  # mimeTypes からアプリと一緒に登録する（nixpkgs#301893、未マージの修正 PR #494847）。
  guiApps = [
    # -- 常駐系（自動起動） --
    {
      pkg = pkgs.slack;
      mimeTypes."x-scheme-handler/slack" = true;
      wayland = true;
      autostart = true;
      startFlags = "--silent";
    }
    {
      pkg = pkgs.discord;
      mimeTypes."x-scheme-handler/discord" = true;
      wayland = true;
      autostart = true;
      startFlags = "--start-minimized";
      binName = "Discord";
      desktopName = "discord.desktop";
    }
    {
      pkg = pkgs.thunderbird;
      autostart = true;
      mimeTypes = {
        "x-scheme-handler/mailto" = true;
        "message/rfc822" = true;
      };
    }
    {
      pkg = pkgs.sticky-notes;
      autostart = true;
      binName = "com.vixalien.sticky";
      desktopName = "com.vixalien.sticky.desktop";
    }

    # -- オフィス・ドキュメント --
    { pkg = pkgs.libreoffice; }
    {
      pkg = pkgs.pdfarranger;
      mimeTypes = {
        "application/pdf" = true;
      };
    }
    # Obsidian はここに置かない。plugin が要求する git / claude ごと包んだラッパーを
    # services.memex(obsidian.installPackage)が入れるので、素の pkgs.obsidian を
    # 足すと同じ実行ファイルが二重に PATH へ載る。
    {
      pkg = pkgs.bitwarden-desktop;
    }

    # -- メディア・クリエイティブ --
    {
      pkg = pkgs.krita;
    }
    { pkg = inputs.rnote.packages.${pkgs.stdenv.hostPlatform.system}.default; }
    { pkg = pkgs.mypaint; }
    {
      pkg = pkgs.vlc;
    }
    { pkg = pkgs.xournalpp; }
    # Google Photos から引き上げた写真の仕分け用。年フォルダ・動画のサムネイル・重複検出が
    # 揃っているのがこれだけ。7z は Takeout の zip を開くのに要る（unzip は日本語の
    # フォルダ名を化けさせる）。
    { pkg = pkgs.digikam; }
    { pkg = pkgs.p7zip; }

    # -- ブラウザ --
    { pkg = pkgs.google-chrome; }
    { pkg = pkgs.brave; }
    {
      pkg = pkgs.spotify;
      mimeTypes."x-scheme-handler/spotify" = true;
      wayland = true;
    }

    # -- ユーティリティ --
    { pkg = pkgs.typst; }
    { pkg = pkgs.yt-dlp; }
    { pkg = pkgs.transcribe; }
    { pkg = pkgs.tdf; }
    { pkg = pkgs.vmpk; }
    { pkg = pkgs.showmethekey; }
    {
      pkg = pkgs.zoom-us;
      desktopName = "Zoom.desktop";
      mimeTypes = {
        "x-scheme-handler/zoommtg" = true;
        "x-scheme-handler/zoomus" = true;
      };
    }
  ];

  # ---- 導出ロジック ----

  # 優先順位: 1. 明示的な binName, 2. meta.mainProgram, 3. pname
  getBinName = app: app.binName or (app.pkg.meta.mainProgram or app.pkg.pname);

  # 優先順位: 1. 明示的な desktopName, 2. pname + .desktop
  getDesktopName = app: app.desktopName or "${app.pkg.pname}.desktop";

  createWaylandDesktopEntry =
    {
      pkg,
      desktopName,
      execArgs,
      binName,
    }:
    let
      originalDesktop = "${pkg}/share/applications/${desktopName}";
      newContent = pkgs.runCommand "modified-${desktopName}" { } ''
        cp ${originalDesktop} $out
        if ! grep -q '^Exec=' $out; then
          echo "ERROR: No Exec= line found in ${desktopName}" >&2
          exit 1
        fi
        sed -i 's|^Exec=.*|Exec=${binName} ${execArgs} %U|' $out
        if ! grep -q '^Exec=${binName}' $out; then
          echo "ERROR: sed replacement failed for ${desktopName}" >&2
          exit 1
        fi
      '';
    in
    newContent;

  defaultApplications = lib.foldl' (
    acc: app:
    if app ? mimeTypes then acc // (lib.mapAttrs (_: _: getDesktopName app) app.mimeTypes) else acc
  ) { } guiApps;

  withWayland = builtins.filter (a: a.wayland or false) guiApps;
  withAutostart = builtins.filter (a: a.autostart or false) guiApps;

  waylandDesktopEntries = builtins.listToAttrs (
    map (
      app:
      let
        desktopName = getDesktopName app;
        binName = getBinName app;
      in
      {
        name = ".local/share/applications/${desktopName}";
        value = {
          source = createWaylandDesktopEntry {
            inherit (app) pkg;
            desktopName = desktopName;
            execArgs = waylandFlags;
            binName = binName;
          };
        };
      }
    ) withWayland
  );

  autostartServices = builtins.listToAttrs (
    map (
      app:
      let
        binName = getBinName app;
        bin = "${app.pkg}/bin/${binName}";
        flags = lib.concatStringsSep " " (
          lib.optional (app.wayland or false) waylandFlags ++ lib.optional (app ? startFlags) app.startFlags
        );
        execStart = if flags != "" then "${bin} ${flags}" else bin;
      in
      {
        name = app.pkg.pname;
        value = {
          Unit = {
            Description = "${app.pkg.pname} (autostart)";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = execStart;
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      }
    ) withAutostart
  );

in
{
  config = lib.mkIf config.local.profile.features.gui {
    home.packages = map (a: a.pkg) guiApps;

    home.file = waylandDesktopEntries;

    xdg.mimeApps = {
      enable = true;
      defaultApplications = defaultApplications;
    };

    systemd.user.services = autostartServices;
  };
}
