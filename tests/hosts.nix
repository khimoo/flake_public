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
    configurations
    activationDepsExist
    hasLauncher
    systemAssertionsHold
    ;
  # 会社 PC の制限は、架空のホストではなく実際の nixos-work-wsl で確かめる（docs/architecture/wsl.md）。
  wsl = inputs.self.nixosConfigurations.nixos-work-wsl.config;
  wslUser = wsl.home-manager.users.nixos;
  wslSshConfig = wsl.environment.etc."ssh/ssh_config".text;
  gce = inputs.self.nixosConfigurations.nixos-gce.config;
  gceUser = gce.home-manager.users.pomu;
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  desktopKeyd =
    inputs.self.nixosConfigurations.nixos-desktop.config.services.keyd.keyboards.default.settings;
  desktopPkgs = inputs.self.nixosConfigurations.nixos-desktop.pkgs;
  desktopWindowsVm = lib.findFirst (
    p: (p.name or "") == "windows-vm"
  ) (throw "windows-vm is not installed") desktopUser.home.packages;
  wslContracts =
    # /etc/nixos を checkout へのリンクにして、--flake なしの nixos-rebuild がこの flake を使うようにする。
    assert builtins.elem "L+ /etc/nixos - - - - /home/nixos/sagyo/flake_public"
      wsl.systemd.tmpfiles.rules;
    assert systemAssertionsHold wsl;
    assert wsl.wsl.enable && wsl.wsl.defaultUser == "nixos";
    # 社用の AI アカウントがない会社の PC なので、自分用のエージェントの設定（agents-private）を置かない。
    assert !(wslUser.home.file ? ".claude/CLAUDE.md");
    assert !(wsl.environment.etc ? "claude-code/managed-settings.json");
    assert !(lib.hasInfix "IdentityFile" wslSshConfig);
    assert wslUser.home.activation ? secrets;
    assert !(lib.hasInfix "SOPS_AGE_KEY_FILE" wslUser.home.activation.secrets.data);
    assert !(lib.hasInfix "age_key=" wslUser.home.activation.secrets.data);
    assert !(hasLauncher wslUser "clone-repos");
    # 会社 PC でも kitty を使うため、GUI アプリは WSLg で表示する（docs/architecture/wsl.md）。
    assert !(wslUser.xdg.configFile ? "niri/config.kdl");
    assert !wsl.programs.niri.enable;
    assert !wslUser.i18n.inputMethod.enable;
    assert builtins.any (p: (p.pname or "") == "kitty") wslUser.home.packages;
    assert wsl.wsl.startMenuLaunchers;
    assert !(hasLauncher wslUser "agent-sync");
    assert !(hasLauncher wslUser "flake-deploy");
    # uv が取得した Python だけを使わせる設定は、nix-ld と一緒に use_uv が入れる。
    assert wsl.programs.nix-ld.enable;
    assert wslUser.programs.uv.settings.python-preference == "only-managed";
    "nixos-work-wsl contracts passed";
  # デスクトップ（nixos-desktop）の実際の構成に固有の確認。
  desktopContracts =
    assert activationDepsExist desktopUser.home.activation;
    assert builtins.elem "L+ /etc/nixos - - - - /home/pomu/sagyo/flake_public"
      inputs.self.nixosConfigurations.nixos-desktop.config.systemd.tmpfiles.rules;
    assert !desktopUser.programs.uv.enable;
    # Windows VM のランチャーはデスクトップだけで有効にする。
    assert hasLauncher desktopUser "windows-vm";
    assert lib.hasInfix "WINDOWS_VM_DOMAIN=win11" desktopWindowsVm.text;
    assert hasLauncher desktopUser "mimikopi-env";
    # @mimikopi は手で作る subvol なので、作る前の switch や再起動で起動を止めないよう nofail を外さない。
    assert builtins.elem "nofail"
      inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems."/home/pomu/.local/share/mimikopi".options;
    assert hasLauncher desktopUser "xsaved-web";
    assert hasLauncher desktopUser "xsaved-remote";
    assert hasLauncher desktopUser "cargo-remote-run";
    assert hasLauncher desktopUser "flake-deploy";
    assert !(desktopUser.systemd.user.services ? xsaved-sync);
    # GCE オフロード中は nixos-desktop からも gce-ts へリモートビルドを送る。
    assert builtins.any (
      m: m.hostName == "gce-ts"
    ) inputs.self.nixosConfigurations.nixos-desktop.config.nix.buildMachines;
    # 個人フォルダの bind mount の元は、ユーザーごとのサービスがマウントの前に作る。元がないと起動が緊急モードで止まる。
    assert builtins.all
      (
        user:
        builtins.elem "x-systemd.requires=personal-folders-${user}.service"
          inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems."/home/${user}/ダウンロード".options
      )
      [
        "pomu"
        "mase"
      ];
    # ログイン画面のまま放置されても、ユーザーの timer を起動時から動かす。
    assert inputs.self.nixosConfigurations.nixos-desktop.config.users.users.pomu.linger == true;
    # 定期実行が失敗したら気づけるよう、どの timer のサービスにも失敗の通知を付ける。
    assert lib.all (
      name:
      desktopUser.systemd.user.services.${name}.Unit.OnFailure or [ ] == [ "notify-failure@%n.service" ]
    ) (lib.attrNames desktopUser.systemd.user.timers);
    # sdl-freerdp は右 Alt（AltGr）の単独押しで、次のショートカット一回だけキーボードを掴む。右 Alt が AltGr に
    # なる配列を既定にし、keyd は普段の右 Alt を書き換えず、ターボの連打は ◇ + 右 Alt で入れるレイヤーに置く
    # （docs/architecture/windows-vm.md）。
    # 一回だけ掴む動作はパッチを当てた FreeRDP にしかないので、ランチャーがそれを使っていることを確かめる。
    assert lib.hasInfix (builtins.unsafeDiscardStringContext "${
      desktopPkgs.callPackage ../packages/freerdp-grab-once { }
    }/bin") desktopWindowsVm.text;
    assert
      builtins.fromJSON desktopUser.xdg.configFile."freerdp/sdl-freerdp.json".text == {
        SDL_KeyModMask = [ "KMOD_MODE" ];
        SDL_Grab = "SDL_SCANCODE_RALT";
      };
    assert lib.hasInfix "layout \"us\"; variant \"altgr-intl\""
      desktopUser.xdg.configFile."niri/generated.kdl".text;
    assert !(desktopKeyd.main or { } ? rightalt);
    "nixos-desktop contracts passed";
  gceContracts =
    assert systemAssertionsHold gce;
    assert gce.users.users.pomu.linger == true;
    assert gce.users.users.pomu.openssh.authorizedKeys.keys != [ ];
    # クラウド VM には個人の全秘密や private repo の clone（personal_files）を配らない。
    assert !(hasLauncher gceUser "clone-repos");
    assert !(hasLauncher gceUser "flake-deploy");
    assert gceUser.home.activation ? secrets;
    assert !(lib.hasInfix "SOPS_AGE_KEY_FILE" gceUser.home.activation.secrets.data);
    assert !(lib.hasInfix "age_key=" gceUser.home.activation.secrets.data);
    assert gce.system.build ? diskoScript;
    assert gce.networking.firewall.enable;
    assert !gce.security.googleOsLogin.enable;
    # serve_xsaved と serve_builds と serve_workspace を引き受けていること。
    assert hasLauncher gceUser "xsaved";
    assert builtins.any (p: (p.pname or "") == "rsync") gceUser.home.packages;
    assert builtins.elem "xsaved" gce.services.postgresql.ensureDatabases;
    assert builtins.all (n: gceUser.systemd.user.services.${n}.Unit.X-SwitchMethod == "keep-old") [
      "xsaved-sync"
      "xsaved-process"
      "xsaved-frames"
    ];
    assert gceUser.systemd.user.services.xsaved-web-server.Install.WantedBy == [ "default.target" ];
    assert !(gceUser.systemd.user.sockets ? xsaved-web);
    assert builtins.elem "pomu" gce.nix.settings.trusted-users;
    "nixos-gce contracts passed";
in
{
  cargo-remote-run-contracts =
    (lib.lazyDerivation {
      derivation = (
        # 目的 cargo_remote_run を選ぶ spin713 には入る（config/hosts/nixos-spin713.toml）。
        assert hasLauncher inputs.self.nixosConfigurations.nixos-spin713.config.home-manager.users.pomu
          "cargo-remote-run";
        pkgs.runCommand "cargo-remote-run-contracts" { } ''touch "$out"''
      );
    })
    // {
      hosts = [ "nixos-spin713" ];
    };
  # clone 済みの両PCへ、配布元の骨格を補充しない。古い workflow の pin も検出する。
  vault-seed-isolation =
    (lib.lazyDerivation {
      derivation = (
        assert lib.all
          (
            user:
            user.services.memex.enable
            && !user.services.memex.initializeVault
            && !(user.home.activation ? seedVault)
            &&
              lib.hasInfix user.services.memex.vaultDir
                (lib.findFirst (
                  p: (p.name or "") == "clone-repos"
                ) (throw "clone-repos is not installed") user.home.packages).text
          )
          [
            desktopUser
            inputs.self.nixosConfigurations.nixos-spin713.config.home-manager.users.pomu
          ];
        pkgs.runCommand "vault-seed-isolation" { } ''
          echo "Cloned vaults have no seed activation on either host" > "$out"
        ''
      );
    })
    // {
      hosts = [
        "nixos-desktop"
        "nixos-spin713"
      ];
    };

  alook-open =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "alook-open-skipped" { } "touch $out"
        else
          let
            alookOpen =
              lib.findFirst (p: (p.name or "") == "alook-open") (throw "alook-open is not installed")
                inputs.self.nixosConfigurations.nixos-spin713.config.home-manager.users.pomu.home.packages;
          in
          pkgs.runCommand "alook-open"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.coreutils
                pkgs.util-linux
              ];
              buildInputs = [ alookOpen ];
            }
            ''
              python ${./alook-open.py} ${../modules/home-manager/dev/alook-open.sh}
              touch "$out"
            ''
      );
    })
    // {
      hosts = [ "nixos-spin713" ];
    };
  # デスクトップの keyd の設定を keyd 自身で検証する。存在しないレイヤーへの toggle などは評価では
  # 見つからず、switch したあとで keyd が設定を読めずにキーボードの変換が止まる。
  keyd-config =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "keyd-config-skipped" { } "touch $out"
        else
          pkgs.runCommand "keyd-config" { nativeBuildInputs = [ pkgs.keyd ]; } ''
            keyd check ${
              pkgs.writeText "default.conf"
                inputs.self.nixosConfigurations.nixos-desktop.config.environment.etc."keyd/default.conf".text
            }
            touch "$out"
          ''
      );
    })
    // {
      hosts = [ "nixos-desktop" ];
    };

  wsl-contracts =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "wsl-contracts" { } ''
          echo ${lib.escapeShellArg wslContracts} > "$out"
        ''
      );
    })
    // {
      hosts = [ "nixos-work-wsl" ];
    };

  desktop-contracts =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "desktop-contracts" { } ''
          echo ${lib.escapeShellArg desktopContracts} > "$out"
        ''
      );
    })
    // {
      hosts = [ "nixos-desktop" ];
    };

  gce-contracts =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "gce-contracts" { } ''
          echo ${lib.escapeShellArg gceContracts} > "$out"
        ''
      );
    })
    // {
      hosts = [ "nixos-gce" ];
    };
}
