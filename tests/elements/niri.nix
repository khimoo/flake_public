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
  # Niri のデスクトップ一式。Niri の設定は Home Manager 側へ集約し、XKB と keyd の正本を揃えることを確かめる。
  niri-contracts =
    (lib.lazyDerivation {
      derivation = (
        let
          host = nixosHost "test-niri";
          alice = host.home-manager.users.alice;
          generated = alice.xdg.configFile."niri/generated.kdl".text;
          personal = builtins.readFile ../../modules/home-manager/gui/niri/config.kdl;
        in
        assert systemAssertionsHold host;
        assert host.programs.niri.enable;
        assert host.services.displayManager.gdm.enable;
        assert host.services.displayManager.defaultSession == "niri";
        assert host.services.xserver.xkb.layout == "us";
        assert host.services.xserver.xkb.variant == "altgr-intl";
        assert host.services.keyd.enable;
        assert host.services.keyd.keyboards.default.settings.main.leftmeta == "overload(meta, f24)";
        assert host.services.keyd.keyboards.default.settings.main.rightmeta == "overload(meta, f24)";
        assert !host.services.desktopManager.gnome.enable;
        assert !(host.home-manager.users ? bob);
        assert !(host.environment.etc ? "niri/config.kdl");
        assert !(host.environment.etc ? "niri/generated.kdl");
        assert lib.hasInfix ''include "generated.kdl"'' personal;
        # 節は1つずつ。同じ節が2つあると Niri は設定を読まない。
        assert count "input {\n" generated == 1;
        assert count "binds {\n" generated == 1;
        assert count "environment {\n" generated == 1;
        assert lib.hasInfix ''layout "us"; variant "altgr-intl"'' generated;
        assert lib.hasInfix ''xcursor-theme "Adwaita"'' generated;
        assert lib.hasInfix "honor-xdg-activation-with-invalid-serial" generated;
        assert lib.hasInfix ''NIXOS_OZONE_WL "1"'' generated;
        assert lib.hasInfix "Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }"
          personal;
        assert lib.hasInfix ''F24 { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }'' generated;
        assert lib.hasInfix ''Mod+D { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }'' generated;
        # 端末は terminal_exec が決め、Mod+Return とハブは xdg-terminal-exec を通して開く。
        assert lib.hasInfix ''Mod+Return { spawn "xdg-terminal-exec"; }'' personal;
        assert host.environment.etc."xdg/xdg-terminals.list".text == "kitty.desktop\n";
        assert builtins.any (p: (p.pname or "") == "xdg-terminal-exec") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "kitty") host.environment.systemPackages;
        assert lib.hasInfix ''match namespace="^quickshell-hub$"'' generated;
        assert lib.hasInfix ''match namespace="^quickshell-hub-notifications$"'' generated;
        assert lib.hasInfix ''block-out-from "screencast"'' generated;
        assert !(lib.hasInfix ''workspace "main"'' generated);
        assert !(lib.hasInfix ''workspace "background"'' generated);
        # 生成設定に個人のホームパスを埋め込まない。
        assert !(lib.hasInfix "/home/" generated);
        assert host.environment.etc ? "xdg/quickshell/hub/shell.qml";
        assert host.environment.etc ? "xdg/quickshell/hub/HubWindow.qml";
        assert host.environment.etc ? "xdg/quickshell/hub/RightColumn.qml";
        assert host.environment.etc ? "xdg/quickshell/hub/NotificationStore.qml";
        assert host.services.upower.enable;
        assert host.systemd.user.services.quickshell-hub.wantedBy == [ "graphical-session.target" ];
        assert !host.systemd.user.services.quickshell-hub.enableDefaultPath;
        assert host.systemd.user.services.cliphist-watch.wantedBy == [ "graphical-session.target" ];
        assert !host.systemd.user.services.cliphist-watch.enableDefaultPath;
        assert host.systemd.user.services.kanshi.wantedBy == [ "graphical-session.target" ];
        assert !host.systemd.user.services.kanshi.enableDefaultPath;
        assert lib.hasInfix "kanshictl" host.systemd.user.services.kanshi.serviceConfig.ExecReload;
        assert !(lib.hasInfix "kanshi" generated);
        assert
          etc host "kanshi/config" == builtins.readFile ../../modules/home-manager/gui/kanshi/config;
        assert !(lib.hasInfix "/home/" (etc host "kanshi/config"));
        assert builtins.any (p: (p.pname or "") == "kanshi") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "wdisplays") host.environment.systemPackages;
        assert builtins.any (p: (p.name or "") == "kanshi-switch") host.environment.systemPackages;
        assert builtins.any (p: (p.name or "") == "kanshi-switch-desktop") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "quickshell") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "hhkb-bt-audio") host.services.udev.packages;
        assert builtins.any (p: (p.pname or "") == "cliphist") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "rbw") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "pinentry-qt") host.environment.systemPackages;
        assert builtins.any (p: (p.pname or "") == "fd") host.environment.systemPackages;
        assert host.systemd.user.services ? polkit-gnome-authentication-agent-1;
        assert host.services.gnome.gnome-keyring.enable;
        # stay_awake があるので、swayidle は自動 suspend を持たず、ロックと消灯だけを行う。
        assert
          !(lib.hasInfix "systemctl suspend" host.systemd.user.services.swayidle.serviceConfig.ExecStart);
        assert lib.hasInfix "before-sleep" host.systemd.user.services.swayidle.serviceConfig.ExecStart;
        assert lib.hasInfix " lock '" host.systemd.user.services.swayidle.serviceConfig.ExecStart;
        assert !host.services.displayManager.gdm.autoSuspend;
        assert !(host.systemd.user.services ? vicinae);
        assert lib.hasInfix ''Mod+Ctrl+V { spawn "niri-toggle-floating"; }'' generated;
        assert builtins.any (p: (p.name or "") == "niri-toggle-floating") host.environment.systemPackages;
        assert alice.xdg.configFile ? "niri/config.kdl";
        assert alice.xdg.configFile."niri/generated.kdl".text == generated;
        assert alice.xdg.configFile ? "quickshell/hub";
        assert alice.xdg.configFile ? "kanshi";
        assert alice.dconf.settings."network/cycles/wdisplays".save-kanshi-config;
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
        "dotfiles_mode"
        "gdm"
        "gui"
        "keyd"
        "kitty"
        "niri"
        "niri_config"
        "niri_floating_toggle"
        "nm_applet"
        "quickshell_hub"
        "stay_awake"
        "swaybg"
        "swayidle"
        "swaylock"
        "terminal_exec"
        "xkb"
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
        assert !(desktop.home-manager.users ? mase);
        assert !(desktop.environment.etc ? "niri/config.kdl");
        assert !(desktop.environment.etc ? "niri/generated.kdl");
        assert desktop.environment.etc ? "xdg/quickshell/hub/shell.qml";
        assert desktop.environment.etc ? "kanshi/config";
        assert desktopUser.xdg.configFile ? "kanshi";
        assert spin713User.xdg.configFile ? "kanshi";
        assert lib.hasInfix ''F24 { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }''
          desktopUser.xdg.configFile."niri/generated.kdl".text;
        assert lib.hasInfix ''F24 { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }''
          spin713User.xdg.configFile."niri/generated.kdl".text;
        assert !(lib.hasInfix "/home/" desktopUser.xdg.configFile."niri/generated.kdl".text);
        assert desktopUser.xdg.configFile ? "autostart/sticky-notes.desktop";
        assert desktopUser.xdg.configFile ? "autostart/thunderbird.desktop";
        assert lib.hasInfix " --startup\n" desktopUser.xdg.configFile."autostart/slack.desktop".text;
        assert desktop.services.xserver.xkb.layout == "us" && desktop.services.xserver.xkb.variant == "altgr-intl";
        assert spin713.services.xserver.xkb.layout == "us" && spin713.services.xserver.xkb.variant == "altgr-intl";
        assert spin713.services.keyd.keyboards.default.settings.main.rightmeta == "overload(meta, f24)";
        # desktop は眠らない。spin713 は放置すると suspend する。
        assert
          !(lib.hasInfix "systemctl suspend" desktop.systemd.user.services.swayidle.serviceConfig.ExecStart);
        assert lib.hasInfix "systemctl suspend"
          spin713.systemd.user.services.swayidle.serviceConfig.ExecStart;
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
          generated = host.home-manager.users.alice.xdg.configFile."niri/generated.kdl".text;
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
                generated = pkgs.writeText "generated.kdl"
                  host.home-manager.users.alice.xdg.configFile."niri/generated.kdl".text;
                personalConfig = pkgs.writeText "personal.kdl" (
                  builtins.replaceStrings [ ''include "generated.kdl"'' ] [ ''include "${generated}"'' ] (
                    builtins.readFile ../../modules/home-manager/gui/niri/config.kdl
                  )
                );
              in
              ''
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
        "keyd"
        "xkb"
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

  quickshell-hub =
    (lib.lazyDerivation {
      derivation =
        pkgs.runCommand "quickshell-hub"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            HUB_VAULT_SCRIPT=${../../modules/home-manager/gui/quickshell/hub-vault.py} python ${../quickshell-hub.py}
            touch "$out"
          '';
    })
    // {
      elements = [ "quickshell_hub" ];
    };

  kanshi-switch =
    (lib.lazyDerivation {
      derivation =
        pkgs.runCommand "kanshi-switch"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            KANSHI_SWITCH_SCRIPT=${../../modules/home-manager/gui/kanshi-switch.py} python ${../kanshi-switch.py}
            touch "$out"
          '';
    })
    // {
      elements = [ "display_layout" ];
    };

  niri-brightness-step =
    (lib.lazyDerivation {
      derivation =
        let
          host = nixosHost "test-niri";
          generated = host.home-manager.users.alice.xdg.configFile."niri/generated.kdl".text;
          helper = lib.findFirst (p: (p.name or "") == "niri-brightness-step") null host.environment.systemPackages;
        in
        assert lib.hasInfix ''XF86MonBrightnessUp allow-when-locked=true { spawn "niri-brightness-step" "up"; }'' generated;
        assert lib.hasInfix ''XF86MonBrightnessDown allow-when-locked=true { spawn "niri-brightness-step" "down"; }'' generated;
        assert helper != null;
        pkgs.runCommand "niri-brightness-step-test" { } ''
          export XDG_RUNTIME_DIR="$PWD/runtime"
          mkdir "$XDG_RUNTIME_DIR"
          brightnessctl() {
            if [[ "$*" == "--class=backlight --machine-readable info" ]]; then
              local value=$current
              if [[ -n "''${test_state:-}" ]]; then
                value=$(<"$test_state")
                # 連打で、書き込み前にもう一方の読み取りが走る時間を作る。
                sleep 0.5
              fi
              printf 'test-backlight,backlight,%s,0%%,%s\n' "$value" "$maximum"
            elif [[ "$*" == "--class=backlight --device=test-backlight --quiet set $5" ]]; then
              if [[ -n "''${test_state:-}" ]]; then
                printf '%s\n' "$5" > "$test_state"
              else
                printf '%s\n' "$5"
              fi
            else
              return 1
            fi
          }
          export -f brightnessctl
          check() {
            local actual
            actual=$(current="$1" maximum="$2" ${helper}/bin/niri-brightness-step "$3")
            if [[ "$actual" != "$4" ]]; then
              printf 'current=%s max=%s direction=%s: expected [%s], got [%s]\n' "$1" "$2" "$3" "$4" "$actual" >&2
              return 1
            fi
          }
          # spin713 と同じ最大値。境界と、スライダーで中間値にした場合を確かめる。
          check 0 1500 up 45
          check 45 1500 up 75
          check 75 1500 up 150
          check 150 1500 up 225
          check 225 1500 down 150
          check 150 1500 down 75
          check 75 1500 down 45
          check 45 1500 down 0
          check 44 1500 up 45
          check 46 1500 down 45
          check 0 1500 down ""
          check 1500 1500 up ""
          # 複数の % が同じ実輝度に丸められても、次の実輝度へ進める。
          check 0 10 up 1
          check 1 10 down 0

          # 上げるキーを連打しても、3% から 5% を経て 10% まで進む。
          export test_state="$PWD/brightness" current=45 maximum=1500
          printf '%s\n' 45 > "$test_state"
          ${helper}/bin/niri-brightness-step up &
          first=$!
          ${helper}/bin/niri-brightness-step up &
          second=$!
          wait "$first"
          wait "$second"
          actual=$(<"$test_state")
          if [[ "$actual" != 150 ]]; then
            printf 'Two overlapping up requests: expected 150, got %s\n' "$actual" >&2
            exit 1
          fi
          touch "$out"
        '';
    })
    // {
      elements = [ "audio_controls" ];
    };

  hhkb-bt-audio =
    (lib.lazyDerivation {
      derivation =
        if pkgs.stdenv.hostPlatform.isLinux then
          pkgs.callPackage ../../packages/hhkb-bt-audio { }
        else
          pkgs.runCommand "hhkb-bt-audio-skipped" { } "touch $out";
    })
    // {
      elements = [ "audio_controls" ];
    };
}
