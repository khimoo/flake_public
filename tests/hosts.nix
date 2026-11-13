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
    configDir
    configurations
    activationDepsExist
    hasLauncher
    systemAssertionsHold
    ;
  # 会社 PC の制限は、架空のホストではなく実際の nixos-work-wsl で確かめる（docs/architecture/wsl.md）。
  wsl = inputs.self.nixosConfigurations.nixos-work-wsl.config;
  wslUser = wsl.home-manager.users.nixos;
  wslSshConfig = wsl.environment.etc."ssh/ssh_config".text;
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  desktopKeyd =
    inputs.self.nixosConfigurations.nixos-desktop.config.services.keyd.keyboards.default.settings;
  desktopPkgs = inputs.self.nixosConfigurations.nixos-desktop.pkgs;
  desktopWindowsVm = lib.findFirst (
    p: (p.name or "") == "windows-vm"
  ) (throw "windows-vm is not installed") desktopUser.home.packages;
  desktopGenerated =
    (import ../lib/confgen.nix {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      inherit configDir;
    }).read
      "nixos-desktop"
      "x86_64-linux"
      "pomu";
  generatedPackages =
    element:
    (lib.findFirst (
      s:
      s.path == [
        "home"
        "packages"
      ]
    ) null element.home).value;
  desktopXsavedEnv =
    builtins.elemAt (builtins.head (generatedPackages desktopGenerated.elements.serve_xsaved))."$repoPkgWith"
      1;
  desktopXsavedBackupEnv =
    builtins.elemAt
      (builtins.head (generatedPackages desktopGenerated.elements.xsaved_backup))."$shellAppEnv"
      2;
  desktopVmEnv =
    builtins.elemAt
      (builtins.head (generatedPackages desktopGenerated.elements.windows_vm_gui))."$shellAppEnv"
      2;
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
    assert !(wslUser.dconf.settings ? "org/gnome/shell");
    assert !wslUser.i18n.inputMethod.enable;
    assert builtins.any (p: (p.pname or "") == "kitty") wslUser.home.packages;
    assert wsl.wsl.startMenuLaunchers;
    assert !(hasLauncher wslUser "agent-sync");
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
    assert desktopVmEnv.WINDOWS_VM_DOMAIN == "win11";
    assert hasLauncher desktopUser "mimikopi-env";
    # @mimikopi は手で作る subvol なので、作る前の switch や再起動で起動を止めないよう nofail を外さない。
    assert builtins.elem "nofail"
      inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems."/home/pomu/.local/share/mimikopi".options;
    assert hasLauncher desktopUser "xsaved";
    assert hasLauncher desktopUser "xsaved-restore-check";
    assert builtins.elem "nofail"
      inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems.${desktopXsavedEnv.dataDir}.options;
    # xsaved が接続するデータベースを、OS 側の Postgres が作る。
    assert builtins.elem desktopXsavedEnv.database
      inputs.self.nixosConfigurations.nixos-desktop.config.services.postgresql.ensureDatabases;
    # ログイン画面のまま放置されても、ユーザーの timer を起動時から動かす。
    assert inputs.self.nixosConfigurations.nixos-desktop.config.users.users.pomu.linger == true;
    # 何時間も続く定期実行を、switch で止めて起動し直さない。
    assert builtins.all (n: desktopUser.systemd.user.services.${n}.Unit.X-SwitchMethod == "keep-old") [
      "xsaved-sync"
      "xsaved-process"
      "xsaved-backup"
    ];
    # Web UI は常駐させず、ブラウザで開いたときにソケットから起動する。
    assert desktopUser.systemd.user.sockets.xsaved-web.Install.WantedBy == [ "sockets.target" ];
    assert !(desktopUser.systemd.user.services.xsaved-web-server ? Install);
    # X で消えたツイートは取り直せないので、保存先と別の場所へ毎日写す。
    assert desktopUser.systemd.user.timers ? xsaved-backup;
    assert lib.hasInfix desktopXsavedBackupEnv.RESTIC_PASSWORD_FILE
      desktopUser.home.activation.secrets.data;
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
    assert lib.hasInfix "('xkb','us+altgr-intl')" (
      toString desktopUser.dconf.settings."org/gnome/desktop/input-sources".sources
    );
    assert !(desktopKeyd.main or { } ? rightalt);
    "nixos-desktop contracts passed";
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
  # GNOME は metadata.json の shell-version に自分のメジャー版がない拡張を読み込まない（OUT OF DATE）。
  # nixpkgs を上げて GNOME と拡張の版がずれても評価とビルドは通るので、ここで止める。
  # 対応版は拡張のパッケージの中にしかないので、評価ではなくビルドの段階で読む。
  gnome-extensions =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "gnome-extensions-skipped" { } "touch $out"
        else
          let
            checkHost =
              hostname:
              let
                host = inputs.self.nixosConfigurations.${hostname};
                shellMajor = lib.versions.major host.pkgs.gnome-shell.version;
                extensions = builtins.filter (
                  p: p ? extensionUuid
                ) host.config.home-manager.users.pomu.home.packages;
              in
              lib.concatMapStrings (p: ''
                check ${hostname} ${shellMajor} ${lib.escapeShellArg p.extensionUuid} ${p}
              '') extensions;
          in
          pkgs.runCommand "gnome-extensions" { nativeBuildInputs = [ pkgs.jq ]; } ''
            fail=0
            check() {
              metadata="$4/share/gnome-shell/extensions/$3/metadata.json"
              if ! jq -e --arg v "$2" '.["shell-version"] | index($v) != null' "$metadata" > /dev/null; then
                echo "$1: $3 does not support GNOME $2 (shell-version: $(jq -c '.["shell-version"]' "$metadata"))" >&2
                fail=1
              fi
            }
            ${checkHost "nixos-desktop"}
            ${checkHost "nixos-spin713"}
            [ "$fail" = 0 ]
            touch "$out"
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
  # 起動順序の循環は評価でもビルドでも見つからず、起動のたびに systemd が循環の中のジョブを一つ取り消すだけで
  # 起動が続く（docs/architecture/disk-tiering.md）。
  # fileSystems のマウントはユニットのディレクトリになく、起動時に fstab から generator が作るので、ここでも作る。
  # SYSTEMD_PROC_CMDLINE を空にして、ビルドするマシンのカーネルのコマンドラインを generator に読ませない。
  # systemd-analyze verify は循環を見つけても 0 で終わるので、出力で判定する。
  # ビルドのサンドボックスには /run がなく、verify は /run/systemd を作れずに止まるので、bwrap で /run を用意する。
  systemd-ordering =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "systemd-ordering-skipped" { } "touch $out"
        else
          pkgs.runCommand "systemd-ordering" { nativeBuildInputs = [ pkgs.bubblewrap ]; } (
            lib.concatMapStrings (
              name:
              let
                host = inputs.self.nixosConfigurations.${name}.config;
                systemd = host.systemd.package;
              in
              ''
                gen=$PWD/${name}
                mkdir -p "$gen"/normal "$gen"/early "$gen"/late
                SYSTEMD_FSTAB=${pkgs.writeText "${name}-fstab" host.environment.etc.fstab.text} \
                  SYSTEMD_PROC_CMDLINE= SYSTEMD_IN_INITRD=0 \
                  ${systemd}/lib/systemd/system-generators/systemd-fstab-generator "$gen"/normal "$gen"/early "$gen"/late
                SYSTEMD_UNIT_PATH="$gen/early:${
                  host.environment.etc."systemd/system".source
                }:$gen/normal:$gen/late" \
                  bwrap --bind /nix /nix --bind "$PWD" "$PWD" --proc /proc --dev /dev --tmpfs /run --tmpfs /tmp \
                  ${systemd}/bin/systemd-analyze verify --man=no --generators=no default.target 2>&1 | tee "$gen.log"
                if grep -q 'ordering cycle' "$gen.log"; then
                  echo "${name}: 起動順序が循環している" >&2
                  exit 1
                fi
              ''
            ) (builtins.attrNames inputs.self.nixosConfigurations)
            + ''
              touch "$out"
            ''
          )
      );
    })
    // {
      hosts = builtins.attrNames inputs.self.nixosConfigurations;
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
}
