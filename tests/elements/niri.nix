{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    inputs
    nixosHost
    hasLauncher
    systemAssertionsHold
    ;
  count = needle: text: builtins.length (lib.splitString needle text) - 1;
  etc = host: name: host.environment.etc.${name}.text;
  desktop = inputs.self.nixosConfigurations.nixos-desktop.config;
  desktopUser = desktop.home-manager.users.pomu;
  spin713 = inputs.self.nixosConfigurations.nixos-spin713.config;
  spin713User = spin713.home-manager.users.pomu;
in
{
  # Home Manager を使わないユーザー（bob）にも、システムの設定だけで Niri のセッションが動くことを確かめる。
  niri-contracts =
    (lib.lazyDerivation {
      derivation = (
        let
          host = nixosHost "test-niri";
          generated = etc host "niri/generated.kdl";
          alice = host.home-manager.users.alice;
        in
        assert systemAssertionsHold host;
        assert host.programs.niri.enable;
        assert host.services.displayManager.gdm.enable;
        assert host.services.displayManager.defaultSession == "niri";
        assert !host.services.desktopManager.gnome.enable;
        assert !(host.home-manager.users ? bob);
        assert lib.hasInfix ''include "/etc/niri/generated.kdl"'' (etc host "niri/config.kdl");
        # 節は1つずつ。同じ節が2つあると Niri は設定を読まない。
        assert count "input {\n" generated == 1;
        assert count "binds {\n" generated == 1;
        assert count "environment {\n" generated == 1;
        assert lib.hasInfix ''layout "us"; variant "altgr-intl"'' generated;
        assert lib.hasInfix ''xcursor-theme "Adwaita"'' generated;
        assert lib.hasInfix "honor-xdg-activation-with-invalid-serial" generated;
        assert lib.hasInfix ''NIXOS_OZONE_WL "1"'' generated;
        assert lib.hasInfix "Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }"
          generated;
        assert lib.hasInfix ''spawn-at-startup "waybar"'' generated;
        assert lib.hasInfix ''spawn-at-startup "swaync" "--config" "/etc/xdg/swaync/config.json"'' generated;
        assert lib.hasInfix ''match namespace="^swaync-notification-window$"'' generated;
        assert lib.hasInfix ''match namespace="^swaync-control-center$"'' generated;
        assert lib.hasInfix ''workspace "background"'' generated;
        assert lib.hasInfix "open-focused false" generated;
        # システムの設定は、どのユーザーの checkout や home も指さない。
        assert !(lib.hasInfix "/home/" (etc host "niri/config.kdl"));
        assert !(lib.hasInfix "/home/" generated);
        assert host.environment.etc ? "xdg/waybar/config.jsonc";
        assert lib.hasInfix "swaync-client -t -sw" (etc host "xdg/waybar/config.jsonc");
        assert host.environment.etc ? "xdg/swaync/config.json";
        assert lib.hasInfix ''"timeout-critical": 0'' (etc host "xdg/swaync/config.json");
        assert lib.hasInfix ''"hide-on-action": true'' (etc host "xdg/swaync/config.json");
        assert host.systemd.user.services ? polkit-gnome-authentication-agent-1;
        assert host.services.gnome.gnome-keyring.enable;
        # stay_awake があるので、swayidle は自動 suspend を持たず、ロックと消灯だけを行う。
        assert
          !(lib.hasInfix "systemctl suspend" host.systemd.user.services.swayidle.serviceConfig.ExecStart);
        assert lib.hasInfix "before-sleep" host.systemd.user.services.swayidle.serviceConfig.ExecStart;
        assert lib.hasInfix " lock '" host.systemd.user.services.swayidle.serviceConfig.ExecStart;
        assert !host.services.displayManager.gdm.autoSuspend;
        assert lib.hasInfix ''match namespace="^vicinae$"'' generated;
        assert lib.hasInfix ''block-out-from "screencast"'' generated;
        assert lib.hasInfix ''Mod+Ctrl+V { spawn "niri-toggle-floating"; }'' generated;
        assert builtins.any (p: (p.name or "") == "niri-toggle-floating") host.environment.systemPackages;
        assert alice.xdg.configFile ? "niri/config.kdl";
        assert alice.xdg.configFile."niri/generated.kdl".text == generated;
        assert alice.xdg.configFile ? "vicinae/nix.json";
        assert lib.hasInfix ''"close_on_focus_loss": true'' alice.xdg.configFile."vicinae/nix.json".text;
        assert lib.hasInfix ''"enabled": false'' alice.xdg.configFile."vicinae/nix.json".text;
        assert lib.hasInfix "niri msg action quit --skip-confirmation"
          alice.xdg.configFile."vicinae/nix.json".text;
        assert host.systemd.user.services.vicinae.wantedBy == [ "graphical-session.target" ];
        assert host.systemd.user.services.vicinae.partOf == [ "graphical-session.target" ];
        assert !host.systemd.user.services.vicinae.enableDefaultPath;
        assert lib.hasSuffix " server" host.systemd.user.services.vicinae.serviceConfig.ExecStart;
        assert !alice.programs.vicinae.systemd.enable;
        assert !(alice.systemd.user.services ? vicinae);
        assert alice.gtk.enable && alice.gtk.colorScheme == "dark";
        assert alice.home.pointerCursor.name == "Adwaita";
        assert host.fonts.fontconfig.defaultFonts.sansSerif == [
          "IBM Plex Sans JP"
          "Noto Sans CJK JP"
        ];
        assert alice.fonts.fontconfig.defaultFonts.sansSerif == [
          "IBM Plex Sans JP"
          "Noto Sans CJK JP"
        ];
        pkgs.runCommand "niri-contracts" { } ''
          echo "niri contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "audio_controls"
        "blueman_applet"
        "checkout"
        "desktop"
        "desktop_appearance"
        "display_layout"
        "gdm"
        "gui"
        "kitty"
        "niri"
        "niri_background_apps"
        "niri_config"
        "niri_floating_toggle"
        "nm_applet"
        "stay_awake"
        "swaybg"
        "swayidle"
        "swaylock"
        "swaync"
        "vicinae"
        "waybar"
      ];
    };

  # 実機の構成で、GNOME の画面の仕組みが残っていないことと、遠隔配信のポートの範囲を確かめる。
  niri-hosts =
    (lib.lazyDerivation {
      derivation = (
        let
          sunshine = desktop.services.sunshine;
          tailnet = desktop.networking.firewall.interfaces.tailscale0;
        in
        assert !desktop.services.desktopManager.gnome.enable;
        assert !spin713.services.desktopManager.gnome.enable;
        assert !(desktop.systemd.services ? gnome-remote-desktop);
        assert !(builtins.any (r: r.from == 1714) desktop.networking.firewall.allowedTCPPortRanges);
        assert !(builtins.any (r: r.from == 1714) spin713.networking.firewall.allowedUDPPortRanges);
        assert !(builtins.any (r: r.from == 3389) desktop.networking.firewall.allowedTCPPortRanges);
        # Sunshine のポートは tailnet のインターフェースにだけ開ける。NixOS のモジュールの全体への許可と自動起動は使わない。
        assert sunshine.enable && !sunshine.openFirewall && !sunshine.autoStart && !sunshine.capSysAdmin;
        assert desktop.systemd.user.services.sunshine.wantedBy == [ ];
        assert sunshine.settings.capture == "wlr";
        assert sunshine.settings.output_name == "sunshine-extend";
        assert builtins.all (p: builtins.elem p tailnet.allowedTCPPorts) [
          47984
          47989
          48010
        ];
        assert builtins.all (p: builtins.elem p tailnet.allowedUDPPorts) [
          47998
          47999
          48000
          48002
          48010
        ];
        assert !(builtins.elem 47984 desktop.networking.firewall.allowedTCPPorts);
        assert !(builtins.elem 47990 tailnet.allowedTCPPorts);
        assert (builtins.head sunshine.applications.apps).name == "Extend (Virtual Display)";
        assert desktop.systemd.user.services.niri-headless.environment.NIRI_BACKEND == "headless";
        # 配信を始めるのは serve_remote_desktop を選んだアカウントだけ。
        assert desktopUser.xdg.configFile ? "systemd/user/graphical-session.target.wants/sunshine.service";
        assert
          !(spin713User.xdg.configFile ? "systemd/user/graphical-session.target.wants/sunshine.service");
        assert hasLauncher spin713User "remote-desktop";
        assert !(hasLauncher desktopUser "remote-desktop");
        # mase は Home Manager を使わないので、システムの設定だけで足りる。
        assert !(desktop.home-manager.users ? mase);
        assert lib.hasInfix ''spawn-at-startup "waybar"'' (etc desktop "niri/generated.kdl");
        assert !(lib.hasInfix "/home/" (etc desktop "niri/generated.kdl"));
        # desktop は眠らない。spin713 は放置すると suspend する。
        assert
          !(lib.hasInfix "systemctl suspend" desktop.systemd.user.services.swayidle.serviceConfig.ExecStart);
        assert lib.hasInfix "systemctl suspend"
          spin713.systemd.user.services.swayidle.serviceConfig.ExecStart;
        assert desktopUser.xdg.configFile."niri/generated.kdl".text == etc desktop "niri/generated.kdl";
        pkgs.runCommand "niri-hosts" { } ''
          echo "niri hosts passed" > "$out"
        ''
      );
    })
    // {
      hosts = [
        "nixos-desktop"
        "nixos-spin713"
      ];
    };

  niri-convertible-contracts =
    (lib.lazyDerivation {
      derivation = (
        let
          host = nixosHost "test-niri-convertible";
          generated = etc host "niri/generated.kdl";
        in
        assert systemAssertionsHold host;
        assert host.services.iio-niri.enable;
        assert host.hardware.sensor.iio.enable;
        assert builtins.any (p: (p.pname or "") == "brightnessctl") host.environment.systemPackages;
        assert builtins.any (p: (p.name or "") == "niri-rotate") host.environment.systemPackages;
        assert lib.hasInfix ''map-to-output "eDP-1"'' generated;
        assert lib.hasInfix "XF86ScreenSaver" generated;
        assert lib.hasInfix "XF86KbdBrightnessUp" generated;
        assert lib.hasInfix ''Alt+XF86Reload { spawn "niri-rotate" "cw"; }'' generated;
        assert host.home-manager.users.alice.xdg.desktopEntries ? niri-auto-rotate;
        assert spin713.services.iio-niri.enable;
        pkgs.runCommand "niri-convertible-contracts" { } ''
          echo "niri convertible contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "has_orientation_sensor"
        "iio_niri"
        "niri_config"
      ];
    };

  niri-remote-contracts =
    (lib.lazyDerivation {
      derivation = (
        let
          host = nixosHost "test-niri-remote";
          sunshine = host.services.sunshine;
          apps = sunshine.applications.apps;
        in
        assert systemAssertionsHold host;
        assert builtins.length apps == 1;
        assert (builtins.head apps).name == "Extend (Virtual Display)";
        assert lib.hasInfix "sunshine-extend" (builtins.head (builtins.head apps).prep-cmd).do;
        assert sunshine.settings.capture == "wlr";
        assert sunshine.settings.output_name == "sunshine-extend";
        assert !sunshine.openFirewall && !sunshine.autoStart;
        assert host.systemd.user.services.niri-headless.environment.NIRI_BACKEND == "headless";
        assert !host.systemd.user.services.niri-headless.enableDefaultPath;
        assert builtins.elem "xdg-desktop-autostart.target" host.systemd.user.services.niri-headless.wants;
        assert lib.hasInfix "niri-shutdown.target" host.systemd.user.services.niri-headless.postStop;
        # ポートを開けるのは serve_remote_desktop。部品だけのホストは何も開けない。
        assert !(host.networking.firewall.interfaces ? tailscale0);
        pkgs.runCommand "niri-remote-contracts" { } ''
          echo "niri remote contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "niri"
        "niri_remote_session"
        "sunshine"
        "sunshine_virtual_output"
      ];
    };

  niri-config-syntax =
    (lib.lazyDerivation {
      derivation =
        if system != "x86_64-linux" then
          pkgs.runCommand "niri-config-syntax-skipped" { } "touch $out"
        else
          let
            hosts = map nixosHost [
              "test-niri-config"
              "test-niri"
              "test-niri-convertible"
            ];
            validate =
              host:
              let
                generated = pkgs.writeText "generated.kdl" (etc host "niri/generated.kdl");
                systemConfig = pkgs.writeText "system.kdl" (
                  builtins.replaceStrings [ "/etc/niri/generated.kdl" ] [ (toString generated) ] (
                    etc host "niri/config.kdl"
                  )
                );
                personalConfig = pkgs.writeText "personal.kdl" (
                  builtins.replaceStrings [ ''include "generated.kdl"'' ] [ ''include "${generated}"'' ] (
                    builtins.readFile ../../modules/home-manager/gui/niri/config.kdl
                  )
                );
              in
              ''
                ${lib.getExe host.programs.niri.package} validate -c ${systemConfig}
                ${lib.getExe host.programs.niri.package} validate -c ${personalConfig}
              '';
          in
          pkgs.runCommand "niri-config-syntax" { } ''
            ${lib.concatMapStrings validate hosts}
            touch "$out"
          '';
    })
    // {
      elements = [
        "niri"
        "niri_config"
        "desktop"
        "iio_niri"
      ];
    };

  niri-remote-lifecycle =
    (lib.lazyDerivation {
      derivation =
        if system != "x86_64-linux" then
          pkgs.runCommand "niri-remote-lifecycle-skipped" { } "touch $out"
        else
          let
            host = nixosHost "test-niri-remote";
            helper = lib.findFirst (
              p: (p.name or "") == "remote-niri"
            ) (throw "remote-niri is not installed") host.environment.systemPackages;
            source = pkgs.writeText "remote-niri.sh" helper.text;
          in
          pkgs.runCommand "niri-remote-lifecycle"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
              ];
            }
            ''
              python ${../niri-remote.py} ${source}
              touch "$out"
            '';
    })
    // {
      elements = [ "niri_remote_session" ];
    };

  niri-floating-toggle =
    (lib.lazyDerivation {
      derivation =
        pkgs.runCommand "niri-floating-toggle"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            TOGGLE_FLOATING_SCRIPT=${../../modules/home-manager/gui/niri/toggle-floating.py} python ${../niri-floating-toggle.py}
            touch "$out"
          '';
    })
    // {
      elements = [ "niri_floating_toggle" ];
    };

  niri-rotate =
    (lib.lazyDerivation {
      derivation =
        pkgs.runCommand "niri-rotate"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            NIRI_ROTATE_SCRIPT=${../../modules/home-manager/gui/niri/rotate.py} python ${../niri-rotate.py}
            touch "$out"
          '';
    })
    // {
      elements = [ "iio_niri" ];
    };
}
