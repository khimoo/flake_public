{
  settings,
  config,
  pkgs,
  kiro,
  lib,
  ...
}:

let
  waylandFlags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";

  cursorConfig = {
    appImage = "${config.home.homeDirectory}/.local/bin/cursor.AppImage";
    icon = "${config.home.homeDirectory}/.local/share/icons/cursor.png";
    url = "https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/latest";
    iconUrl = "https://framerusercontent.com/images/lfSBU4EhKcMg3iGg98L2F1ESfA.jpg";
  };

  # ---- アプリ定義（追加・削除はここだけ） ----

  guiApps = [
    # -- 常駐系（自動起動） --
    {
      pkg = pkgs.slack;
      wayland = true;
      autostart = true;
      startFlags = "--silent";
    }
    {
      pkg = pkgs.discord;
      wayland = true;
      autostart = true;
      startFlags = "--start-minimized";
      binName = "Discord";
      desktopName = "discord.desktop";
    }
    {
      pkg = pkgs.thunderbird;
      autostart = true;
    }
    {
      pkg = pkgs.sticky-notes;
      autostart = true;
      binName = "com.vixalien.sticky";
      desktopName = "com.vixalien.sticky.desktop";
    }

    # -- オフィス・ドキュメント --
    { pkg = pkgs.libreoffice; }
    { pkg = pkgs.pdfarranger; }
    { pkg = pkgs.obsidian; }
    { pkg = pkgs.bitwarden-desktop; }
    { pkg = pkgs.teams-for-linux; }

    # -- メディア・クリエイティブ --
    { pkg = pkgs.krita; }
    { pkg = pkgs.mypaint; }
    { pkg = pkgs.vlc; }
    { pkg = pkgs.xournalpp; }

    # -- ブラウザ --
    { pkg = pkgs.google-chrome; }
    { pkg = pkgs.brave; }
    {
      pkg = pkgs.spotify;
      wayland = true;
    }

    # -- ユーティリティ --
    { pkg = pkgs.typst; }
    { pkg = pkgs.yt-dlp; }
    { pkg = pkgs.transcribe; }
    { pkg = pkgs.appimage-run; }
    { pkg = pkgs.tdf; }
    { pkg = pkgs.vmpk; }
    { pkg = pkgs.showmethekey; }
    { pkg = pkgs.zoom-us; }
  ];

  # -- 特殊アプリ（外部 flake / AppImage） --
  # guiApps のリストには収まらないが、同じファイルで管理する

  kiroApp = {
    pkg = kiro.packages.${settings.system}.default;
    desktopName = "kiro.desktop";
    binName = "kiro";
    wayland = true;
  };

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

  kiroDesktopEntry = {
    ".local/share/applications/${kiroApp.desktopName}" = {
      source = createWaylandDesktopEntry {
        pkg = kiroApp.pkg;
        desktopName = kiroApp.desktopName;
        execArgs = waylandFlags;
        binName = kiroApp.binName;
      };
    };
  };

  cursorDesktopEntry = {
    ".local/share/applications/cursor.desktop" = {
      text = ''
        [Desktop Entry]
        Name=Cursor AI
        Comment=AI-first code editor
        Exec=${pkgs.appimage-run}/bin/appimage-run ${cursorConfig.appImage} --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime %U
        Icon=${cursorConfig.icon}
        Type=Application
        Categories=Development;IDE;
        Terminal=false
        StartupWMClass=Cursor
      '';
    };
  };

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
lib.mkIf settings.features.gui {
  home.packages = map (a: a.pkg) guiApps ++ [ kiroApp.pkg ];

  home.file = waylandDesktopEntries // kiroDesktopEntry // cursorDesktopEntry;

  systemd.user.services = autostartServices;

  home.activation.installCursor = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "Checking for Cursor AI updates..."

    $DRY_RUN_CMD mkdir -p "$(dirname ${cursorConfig.appImage})"
    $DRY_RUN_CMD mkdir -p "$(dirname ${cursorConfig.icon})"

    if [ ! -f "${cursorConfig.icon}" ]; then
      echo "Downloading Cursor icon..."
      if ! $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fL "${cursorConfig.iconUrl}" -o "${cursorConfig.icon}"; then
        echo "WARNING: Failed to download Cursor icon from ${cursorConfig.iconUrl}" >&2
      fi
    fi

    if [ -f "${cursorConfig.appImage}" ]; then
      echo "Existing Cursor found. Checking for updates..."
      if ! $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fz "${cursorConfig.appImage}" -L "${cursorConfig.url}" -o "${cursorConfig.appImage}"; then
        echo "WARNING: Failed to check for Cursor updates. Keeping existing version." >&2
      fi
    else
      echo "Installing Cursor for the first time..."
      if ! $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fL "${cursorConfig.url}" -o "${cursorConfig.appImage}"; then
        echo "ERROR: Failed to download Cursor AppImage from ${cursorConfig.url}" >&2
        exit 1
      fi
    fi

    $DRY_RUN_CMD chmod +x "${cursorConfig.appImage}"
  '';
}
