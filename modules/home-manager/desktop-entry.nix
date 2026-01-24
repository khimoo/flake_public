{ settings, config, pkgs, kiro, lib, ... }:

let
  createWaylandDesktopEntry = { pkg, desktopName, execArgs, binName ? null }:
    let
      originalDesktop = "${pkg}/share/applications/${desktopName}";
      originalContent = builtins.readFile originalDesktop;
      execCmd = if binName != null then binName else pkg.pname;
      newContent = pkgs.runCommand "modified-${desktopName}" {} ''
        echo "${originalContent}" > $out
        sed -i 's|^Exec=.*|Exec=${execCmd} ${execArgs} %U|' $out
      '';
    in
      newContent;

  waylandApps = [
    {
      pkg = pkgs.discord;
      desktopName = "discord.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
    }
    {
      pkg = kiro.packages.${settings.system}.default;
      desktopName = "kiro.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      binName = "kiro";
    }
    {
      pkg = pkgs.spotify;
      desktopName = "spotify.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
    }
    {
      pkg = pkgs.steam;
      desktopName = "steam.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      binName = "steam";
    }
  ];

  cursorConfig = {
    appImage = "${config.home.homeDirectory}/.local/bin/cursor.AppImage";
    icon = "${config.home.homeDirectory}/.local/share/icons/cursor.png";
    url = "https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/latest";
    iconUrl = "https://framerusercontent.com/images/lfSBU4EhKcMg3iGg98L2F1ESfA.jpg";
  };

  desktopEntries = builtins.listToAttrs (
    (map
      (app: {
        name = ".local/share/applications/${app.desktopName}";
        value = {
          source = createWaylandDesktopEntry {
            pkg = app.pkg;
            desktopName = app.desktopName;
            execArgs = app.execArgs;
            binName = app.binName or null;
          };
        };
      })
    waylandApps)
    ++
    [
      {
        name = ".local/share/applications/cursor.desktop";
        value = {
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
      }
    ]
  );

in {
  home.packages = map (app: app.pkg) waylandApps;

  home.file = desktopEntries;

  home.activation.installCursor = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Checking for Cursor AI updates..."

    $DRY_RUN_CMD mkdir -p "$(dirname ${cursorConfig.appImage})"
    $DRY_RUN_CMD mkdir -p "$(dirname ${cursorConfig.icon})"

    if [ ! -f "${cursorConfig.icon}" ]; then
      echo "Downloading Cursor icon..."
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -L "${cursorConfig.iconUrl}" -o "${cursorConfig.icon}"
    fi

    if [ -f "${cursorConfig.appImage}" ]; then
      echo "Existing Cursor found. Checking for updates..."
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -z "${cursorConfig.appImage}" -L "${cursorConfig.url}" -o "${cursorConfig.appImage}"
    else
      echo "Installing Cursor for the first time..."
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -L "${cursorConfig.url}" -o "${cursorConfig.appImage}"
    fi

    $DRY_RUN_CMD chmod +x "${cursorConfig.appImage}"
  '';
}
