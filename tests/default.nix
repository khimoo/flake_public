{ inputs, configurations }:
let
  inherit (inputs.nixpkgs) lib;
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
  fixture = configurations.mkSystem {
    hostname = "example";
    system = "x86_64-linux";
    timezone = "Asia/Tokyo";
    stateVersion = "25.11";
    hostModule = ../examples/new-host.nix;
    users = [
      {
        username = "alice";
        homeModules = [
          {
            local.profile = {
              gitUsername = "Alice";
              gitUserEmail = "alice@example.org";
              agentConfigRoot = "/home/alice/claude-config";
              agentConfigRepo = "git@example.org:alice/config.git";
              lanSsh = true;
            };
          }
        ];
      }
      { username = "bob"; }
      {
        username = "unmanaged";
        manageHome = false;
      }
    ];
  };
  users = fixture.config.home-manager.users;
  # 会社 PC の制限は、架空のホストではなく実際の nixos-work-wsl で確かめる（docs/architecture/wsl.md）。
  wsl = inputs.self.nixosConfigurations.nixos-work-wsl.config;
  wslUser = wsl.home-manager.users.nixos;
  wslSshConfig = wsl.environment.etc."ssh/ssh_config".text;
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  desktopKeyd = inputs.self.nixosConfigurations.nixos-desktop.config.services.keyd.keyboards.default.settings;
  desktopPkgs = inputs.self.nixosConfigurations.nixos-desktop.pkgs;
  desktopWindowsVm = lib.findFirst (
    p: (p.name or "") == "windows-vm"
  ) (throw "windows-vm is not installed") desktopUser.home.packages;
  windowsVm = {
    imports = [ ../modules/home-manager/windows-vm.nix ];
    local.windowsVm = {
      enable = true;
      domain = "win11";
    };
  };
  nixosHost =
    hostname: module:
    (configurations.mkSystem {
      inherit hostname;
      system = "x86_64-linux";
      timezone = "Asia/Tokyo";
      stateVersion = "25.11";
      hostModule.imports = [
        ../examples/new-host.nix
        module
      ];
      users = [
        {
          username = "alice";
          manageHome = false;
        }
      ];
    }).config;
  remoteBuildHost =
    hostname:
    nixosHost hostname {
      imports = [
        ../modules/nixos/ssh.nix
        ../modules/nixos/tailscale.nix
        ../modules/nixos/remote-builders.nix
      ];
      local.remoteBuilders.enable = true;
    };
  laptop = remoteBuildHost "nixos-spin713";
  agentHost =
    instructions:
    nixosHost "example" {
      imports = [
        ../modules/nixos/codex.nix
        ../modules/nixos/agent-instructions.nix
      ];
      local.agentInstructions = instructions;
    };
  # 会社 PC 向けの制限（modules/nixos/restricted-host.nix）を立てた架空のホスト。
  restrictedHost =
    hostModule: homeModules:
    (configurations.mkSystem {
      hostname = "example";
      system = "x86_64-linux";
      timezone = "Asia/Tokyo";
      stateVersion = "25.11";
      hostModule.imports = [
        ../examples/new-host.nix
        ../modules/nixos/restricted-host.nix
        hostModule
      ];
      users = [
        {
          username = "alice";
          inherit homeModules;
        }
      ];
    }).config;
  # 制限を破った構成では、落ちる assertion がすべて restrictedHost のものでなければならない。
  # ほかの assertion が落ちただけでも「止まった」とみなすと、制限が壊れても気づけない。
  stoppedByRestriction =
    config:
    let
      failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
    in
    failed != [ ] && builtins.all (lib.hasPrefix "local.restrictedHost:") failed;
  # 二人のユーザーが X のいいねの保存を使う架空のホスト。どちらにもデータ用のマウントはない。
  xLikesHost =
    (configurations.mkSystem {
      hostname = "example";
      system = "x86_64-linux";
      timezone = "Asia/Tokyo";
      stateVersion = "25.11";
      hostModule.imports = [
        ../examples/new-host.nix
        ../modules/nixos/x-likes.nix
      ];
      users = map (username: {
        inherit username;
        homeModules = [
          {
            local.xLikes = {
              enable = true;
              dataDir = "/home/${username}/.local/share/x-likes";
              projectDir = "/home/${username}/x-likes-archive";
              database = "xlikes_${username}";
            };
          }
        ];
      }) [ "alice" "bob" ];
    }).config;
  codexConfig = host: builtins.fromTOML host.environment.etc."codex/config.toml".text;
  systemAssertionsHold = config: builtins.all (a: a.assertion) config.assertions;
  mkTestHome =
    system: modules:
    configurations.mkHome {
      username = "test";
      inherit system modules;
      stateVersion = "25.11";
    };
  allAssertions = home: builtins.all (a: a.assertion) home.config.assertions;
  tagged = set: lib.mapAttrs (_: check: check // { checkSet = set; });
  # activation の after / before が存在しないノードを指しても、Home Manager はエラーにせず順序も保証しない。
  activationDepsExist =
    activation:
    builtins.all (
      entry: builtins.all (dep: activation ? ${dep}) (entry.after ++ entry.before)
    ) (builtins.attrValues activation);
  # Launchers are writeShellScriptBin outputs whose name is the executable name.
  hasLauncher = user: name: builtins.any (p: (p.name or "") == name) user.home.packages;
in
lib.genAttrs systems (
  system:
  let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    home = mkTestHome system [ ];
    activationHome = mkTestHome "x86_64-linux" [
      {
        local.profile = {
          agentConfigRoot = "/home/test/config";
          agentConfigRepo = "git@example.org:test/config.git";
        };
      }
    ];
    # These are shell-source tests using fake tools, not builds of the target
    # platform packages. Discard context only for these mocked script strings.
    mockPaths =
      text:
      builtins.unsafeDiscardStringContext (
        builtins.replaceStrings
          [
            "/home/test"
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.git)
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.sops)
          ]
          [ "@test-home@" "@tools@" "@tools@" ]
          text
      );
    snippet = name: mockPaths activationHome.config.home.activation.${name}.data;
    # コマンドの本文。道具は PATH から呼ぶので、テストが偽の道具を PATH の先頭に置く。
    commandText =
      name:
      mockPaths
        (lib.findFirst (p: (p.name or "") == name) (throw "${name} is not installed")
          activationHome.config.home.packages
        ).text;
    rejects =
      module:
      let
        result = builtins.tryEval (allAssertions (mkTestHome system [ module ]));
      in
      !result.success || !result.value;
    # Force the typed option directly: an invalid option value must fail evaluation.
    badType =
      builtins.tryEval
        (mkTestHome system [ { local.profile.features.gui = "yes"; } ]).config.local.profile.features.gui;
    unknownFeature =
      builtins.tryEval
        (mkTestHome system [ { local.profile.features.typo = true; } ]).config.local.profile.features.gui;
    # 架空のホストと Home Manager の構成で確かめる、ホストに依らない契約。
    contracts =
      assert allAssertions home;
      assert activationDepsExist activationHome.config.home.activation;
      assert systemAssertionsHold (restrictedHost { local.restrictedHost.enable = true; } [ ]);
      assert stoppedByRestriction (restrictedHost {
        local.restrictedHost.enable = true;
        services.openssh.enable = true;
      } [ ]);
      assert stoppedByRestriction (restrictedHost { local.restrictedHost.enable = true; } [
        { local.profile.lanSsh = true; }
      ]);
      # local.profile を通さず Home Manager の git の設定に直接書いた identity も止める。
      assert stoppedByRestriction (restrictedHost { local.restrictedHost.enable = true; } [
        { programs.git.settings.user.email = "someone@example.com"; }
      ]);
      assert users.alice.local.profile.gitUsername == "Alice";
      assert users.bob.local.profile.gitUsername == null;
      assert users.bob.local.profile.gitUserEmail == null;
      assert users.bob.local.profile.privateRepos == [ ];
      assert users.bob.local.profile.sshKeys == [ ];
      assert users.bob.local.profile.agentConfigRoot == null;
      assert users.bob.local.profile.flakeRoot == "/home/bob/sagyo/flake_public";
      assert !(hasLauncher users.bob "clone-repos");
      assert hasLauncher users.alice "clone-repos";
      assert !(users.alice.home.file ? ".claude/settings.json");
      assert !(users ? unmanaged);
      assert builtins.length users.alice.local.profile.sshKeys == 2;
      assert users.bob.local.profile.secrets == [ ];
      assert users.bob.home.activation ? secrets;
      assert !(lib.hasInfix "SOPS_AGE_KEY_FILE" users.bob.home.activation.secrets.data);
      assert !(lib.hasInfix "age_key=" users.bob.home.activation.secrets.data);
      assert users.alice.home.activation ? secrets;
      # 暗号文が世代の closure に入る（GC 後の起動時の activation でも復号できる）。
      assert lib.any (lib.hasSuffix "-secrets.yaml") (
        lib.attrNames (builtins.getContext users.alice.home.activation.secrets.data)
      );
      assert rejects {
        local.profile.secrets = [
          {
            secret = "a";
            path = "/home/test/.config/x";
          }
          {
            secret = "b";
            path = "/home/test/.config/x";
          }
        ];
      };
      assert rejects {
        local.profile.secrets = [
          {
            secret = "a";
            path = "/home/another-user/x";
          }
        ];
      };
      assert !(home.config.home.activation ? rustowl);
      assert !(builtins.any (p: (p.pname or "") == "rustowl") home.config.home.packages);
      assert home.config.local.neovim.features.rustowl.enable == (system == "x86_64-linux");
      assert (hasLauncher home.config "uv-mode") == (lib.hasSuffix "-linux" system);
      assert !(mkTestHome system [{ local.rustowl.enable = false; }]).config.local.neovim.features.rustowl.enable;
      assert !(hasLauncher home.config "cargo-remote-run");
      assert hasLauncher (mkTestHome system [
        {
          local.cargoRemoteRun = {
            enable = true;
            host = "builder";
          };
        }
      ]).config "cargo-remote-run";
      assert !(builtins.any (p: (p.pname or "") == "vscode") home.config.home.packages);
      # ~/.config/nvim は checkout への live symlink なので、その下に置くファイルは home-manager-files の
      # ビルドで "outside $HOME" になる。評価だけでは見つからないので、ここで止める。
      assert !(builtins.any (f: f.enable && lib.hasPrefix ".config/nvim/" f.target) (builtins.attrValues home.config.home.file));
      # プロファイルの起動コマンドは agent-sync が実行時に作る。設定 repo のないユーザーには入れない。
      assert hasLauncher users.alice "agent-sync";
      assert users.alice.home.activation ? agentSync;
      assert !(hasLauncher users.bob "agent-sync");
      assert !(users.bob.home.activation ? agentSync);
      assert !(users.alice.home.file ? ".codex/astra.config.toml");
      assert rejects { local.profile.agentConfigRepo = "git@example.org:test/config.git"; };
      assert rejects { local.profile.agentConfigRoot = "/home/another-user/config"; };
      assert rejects { local.profile.features.zettelkastenSync = true; };
      assert rejects { local.profile.features.gnome = true; };
      assert rejects {
        local.profile.privateRepos = [
          {
            url = "one";
            dest = "/home/test/repo";
          }
          {
            url = "two";
            dest = "/home/test/repo";
          }
        ];
      };
      assert system == "x86_64-linux" || rejects { local.rustowl.enable = true; };
      assert !(home.config.systemd.user.timers ? quaderno-pull);
      assert
        system != "x86_64-linux"
        || ((mkTestHome system [
          {
            local.quaderno = {
              enable = true;
              archiveDir = "/home/test/quaderno";
            };
          }
        ]).config.systemd.user.timers ? quaderno-pull);
      assert
        system != "x86_64-linux"
        || (mkTestHome system [
          {
            local.quaderno = {
              enable = true;
              archiveDir = "/home/test/quaderno";
            };
          }
        ]).config.local.quaderno.serial
        == null;
      assert rejects {
        local.quaderno = {
          enable = true;
          archiveDir = "/home/another-user/quaderno";
        };
      };
      # home の外は許す。別ディスクへ置く構成を弾かないこと。
      assert
        system != "x86_64-linux"
        || allAssertions (mkTestHome system [
          {
            local.quaderno = {
              enable = true;
              archiveDir = "/mnt/backup/quaderno";
            };
          }
        ]);
      # GUI のないユーザーでは Windows VM のランチャーの評価を止める。
      assert rejects windowsVm;
      assert
        system != "x86_64-linux"
        || allAssertions (mkTestHome system [
          windowsVm
          { local.profile.features.gui = true; }
        ]);
      assert rejects { local.quaderno.enable = true; };
      assert
        system == "x86_64-linux"
        || rejects {
          local.quaderno = {
            enable = true;
            archiveDir = "/home/test/quaderno";
          };
        };
      assert !badType.success;
      assert !unknownFeature.success;
      assert systemAssertionsHold laptop;
      assert laptop.nix.buildMachines != [ ];
      # nix-daemon の ssh は、ssh.nix が生成する Host ブロックで接続先と accept-new を得る。
      assert builtins.all (
        m: lib.hasInfix "Host ${m.hostName}\n" laptop.programs.ssh.extraConfig
      ) laptop.nix.buildMachines;
      assert builtins.all (m: m.sshKey == "/home/alice/.ssh/id_lan") laptop.nix.buildMachines;
      # builders に自分しかいないホストでは回す先がない。黙って何もしない設定にしない。
      assert !systemAssertionsHold (remoteBuildHost "nixos-desktop");
      # developer_instructions が codex.nix のテーブルに入らず、エスケープも崩れないこと。
      assert
        let
          instructions = "一行目 \"quoted\" back\\slash\n二行目\n";
          host = agentHost instructions;
        in
        (codexConfig host).developer_instructions == instructions
        && (codexConfig host).agents.enabled == false
        && host.environment.etc."claude-code/CLAUDE.md".text == instructions;
      assert !((agentHost "").environment.etc ? "claude-code/CLAUDE.md");
      # 複数のユーザーとマウントのないホストでも使える。GPU は共有のロックファイルで順番にする。
      assert systemAssertionsHold xLikesHost;
      assert xLikesHost.services.postgresql.ensureDatabases == [ "xlikes_alice" "xlikes_bob" ];
      assert builtins.elem "f ${xLikesHost.local.xLikes.gpuLock} 0644 root root -" xLikesHost.systemd.tmpfiles.rules;
      # データベースは NixOS 側が作るので、Home Manager 単独では有効にできない。
      assert rejects {
        local.xLikes = {
          enable = true;
          dataDir = "/home/test/.local/share/x-likes";
          projectDir = "/home/test/x-likes-archive";
        };
      };
      assert !(codexConfig (agentHost "") ? developer_instructions);
      "module contracts passed";
    # 会社 PC（nixos-work-wsl）の実際の構成に固有の確認（docs/architecture/wsl.md）。
    wslContracts =
      # /etc/nixos を checkout へのリンクにして、--flake なしの nixos-rebuild がこの flake を使うようにする。
      assert builtins.elem "L+ /etc/nixos - - - - /home/nixos/sagyo/flake_public" wsl.systemd.tmpfiles.rules;
      assert wsl.local.restrictedHost.enable;
      assert systemAssertionsHold wsl;
      assert wsl.wsl.enable && wsl.wsl.defaultUser == "nixos";
      # 社用の AI アカウントがない会社の PC なので、自分用のエージェントの設定（agents-private）を置かない。
      assert wslUser.local.profile.agentConfigRoot == null;
      assert !(wsl.environment.etc ? "claude-code/managed-settings.json");
      assert !(lib.hasInfix "IdentityFile" wslSshConfig);
      assert wslUser.home.activation ? secrets;
      assert !(lib.hasInfix "SOPS_AGE_KEY_FILE" wslUser.home.activation.secrets.data);
      assert !(lib.hasInfix "age_key=" wslUser.home.activation.secrets.data);
      assert !(hasLauncher wslUser "clone-repos");
      # 会社 PC でも kitty を使うため、GUI アプリは WSLg で表示する（docs/architecture/wsl.md）。
      assert lib.attrNames (lib.filterAttrs (_: enabled: enabled) wslUser.local.profile.features) == [ "gui" ];
      assert builtins.any (p: (p.pname or "") == "kitty") wslUser.home.packages;
      assert wsl.wsl.startMenuLaunchers;
      assert !(hasLauncher wslUser "agent-sync");
      assert hasLauncher wslUser "uv-mode";
      "nixos-work-wsl contracts passed";
    # デスクトップ（nixos-desktop）の実際の構成に固有の確認。
    desktopContracts =
      assert activationDepsExist desktopUser.home.activation;
      assert builtins.elem "L+ /etc/nixos - - - - /home/pomu/sagyo/flake_public"
        inputs.self.nixosConfigurations.nixos-desktop.config.systemd.tmpfiles.rules;
      # Windows VM のランチャーはデスクトップだけで有効にする。
      assert hasLauncher desktopUser "windows-vm";
      assert desktopUser.local.windowsVm.domain == "win11";
      assert hasLauncher desktopUser "mimikopi-env";
      # @mimikopi は手で作る subvol なので、作る前の switch や再起動で起動を止めないよう nofail を外さない。
      assert builtins.elem "nofail"
        inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems."/home/pomu/.local/share/mimikopi".options;
      assert hasLauncher desktopUser "xlikes";
      assert builtins.elem "nofail"
        inputs.self.nixosConfigurations.nixos-desktop.config.fileSystems.${desktopUser.local.xLikes.dataDir}.options;
      # xlikes が接続するデータベースを、OS 側の Postgres が作る。
      assert builtins.elem desktopUser.local.xLikes.database
        inputs.self.nixosConfigurations.nixos-desktop.config.services.postgresql.ensureDatabases;
      # ログイン画面のまま放置されても、ユーザーの timer を起動時から動かす。
      assert inputs.self.nixosConfigurations.nixos-desktop.config.users.users.pomu.linger == true;
      # X で消えたツイートは取り直せないので、保存先と別の場所へ毎日写す。
      assert desktopUser.systemd.user.timers ? xlikes-backup;
      assert builtins.any (s: s.path == desktopUser.local.xLikes.backup.passwordFile) desktopUser.local.profile.secrets;
      # 定期実行が失敗したら気づけるよう、どの timer のサービスにも失敗の通知を付ける。
      assert lib.all
        (name: desktopUser.systemd.user.services.${name}.Unit.OnFailure or [ ] == desktopUser.local.failureNotify.onFailure)
        (lib.attrNames desktopUser.systemd.user.timers);
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
  # どの変更でも確かめる共通の契約（common）と、ホストや機能に固有の確認（feature）に分ける。
  # scripts/check.sh は checkSet を見て build する集合を選ぶ。
  tagged "common" {
    module-contracts = pkgs.runCommand "module-contracts" { } ''
      echo ${lib.escapeShellArg contracts} > "$out"
    '';
    docs = pkgs.runCommand "documentation-links" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python ${../scripts/check-docs.py} ${../.}
      touch "$out"
    '';
    activation =
      pkgs.runCommand "activation-contracts"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.bash
          ];
          cloneScript = commandText "clone-repos";
          secretsScript = snippet "secrets";
          emptySecretsScript = mockPaths (mkTestHome "x86_64-linux" [ ]).config.home.activation.secrets.data;
          passAsFile = [
            "cloneScript"
            "secretsScript"
            "emptySecretsScript"
          ];
        }
        ''
          python ${./activation.py}
          touch "$out"
        '';
    # 設定 repo のファイルから起動コマンドと Claude Code の設定を作る agent-sync の動作。
    agent-sync =
      pkgs.runCommand "agent-sync"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.bash
            pkgs.jq
          ];
        }
        ''
          python ${./agent-sync.py} ${pkgs.writeText "agent-sync.sh" (commandText "agent-sync")}
          touch "$out"
        '';
    # agent-sync の shellcheck。
    agent-sync-package = lib.findFirst (p: (p.name or "") == "agent-sync") (throw "agent-sync is not installed") activationHome.config.home.packages;
    # private repo を持たないユーザーでも pull-repos のビルド（shellcheck）が通ること。
    # standalone の Home Manager は評価しかしないので、ここでビルドしないと見つからない。
    pull-repos = lib.findFirst (p: (p.name or "") == "pull-repos") (throw "pull-repos is not installed") home.config.home.packages;
    # clone-repos の shellcheck。本文の動作は activation の check が偽の git で確かめる。
    clone-repos = lib.findFirst (p: (p.name or "") == "clone-repos") (throw "clone-repos is not installed") activationHome.config.home.packages;
    # 非対話の bash（エージェントのシェル）が、見つからないコマンドに入手方法を添え、127 のまま終わる。
    # 実際の nix-locate と同梱の DB を使う。ビルド環境に node が無いことを前提にする。
    command-not-found-hint =
      if system != "x86_64-linux" then
        pkgs.runCommand "command-not-found-hint-skipped" { } "touch $out"
      else
        pkgs.runCommand "command-not-found-hint" { hint = home.config.home.sessionVariables.BASH_ENV; } ''
          status=0
          BASH_ENV=$hint ${pkgs.bash}/bin/bash -euo pipefail -c 'node --version' 2> err || status=$?
          cat err
          [ "$status" = 127 ]
          grep -q 'nix shell nixpkgs#nodejs' err
          # This pinned small database has exactly one executable candidate for figlet.
          candidates=$(${home.config.programs.nix-index.package}/bin/nix-locate \
            --minimal --no-group --type x --type s --whole-name --at-root /bin/figlet)
          [ "$candidates" = figlet.out ]
          status=0
          BASH_ENV=$hint ${pkgs.bash}/bin/bash -euo pipefail -c 'figlet --version' 2> err || status=$?
          cat err
          [ "$status" = 127 ]
          grep -q 'nix shell nixpkgs#figlet' err
          touch "$out"
        '';
  }
  // tagged "feature" {
    # clone 済みの両PCへ、配布元の骨格を補充しない。古い workflow の pin も検出する。
    vault-seed-isolation =
      assert lib.all (user:
        user.services.zettelkasten.enable
        && !user.services.zettelkasten.initializeVault
        && !(user.home.activation ? seedVault)
        && user.local.profile.zettelkastenRepoUrl != null
      ) [
        desktopUser
        inputs.self.nixosConfigurations.nixos-spin713.config.home-manager.users.pomu
      ];
      pkgs.runCommand "vault-seed-isolation" { } ''
        echo "Cloned vaults have no seed activation on either host" > "$out"
      '';
    # GNOME は metadata.json の shell-version に自分のメジャー版がない拡張を読み込まない（OUT OF DATE）。
    # nixpkgs を上げて GNOME と拡張の版がずれても評価とビルドは通るので、ここで止める。
    # 対応版は拡張のパッケージの中にしかないので、評価ではなくビルドの段階で読む。
    gnome-extensions =
      if system != "x86_64-linux" then
        pkgs.runCommand "gnome-extensions-skipped" { } "touch $out"
      else
        let
          checkHost =
            hostname:
            let
              host = inputs.self.nixosConfigurations.${hostname};
              shellMajor = lib.versions.major host.pkgs.gnome-shell.version;
              extensions = builtins.filter (p: p ? extensionUuid) host.config.home-manager.users.pomu.home.packages;
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
        '';
    graphify-smoke = pkgs.runCommand "graphify-smoke" {
      nativeBuildInputs = [ pkgs.python3 inputs.nixpkgs-unstable.legacyPackages.${system}.graphify ];
    } ''
      export HOME="$TMPDIR"
      python ${./graphify-smoke.py}
      touch "$out"
    '';
    cargo-remote-run =
      pkgs.runCommandCC "cargo-remote-run"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.cargo
            pkgs.rustc
            pkgs.rsync
          ];
        }
        ''
          python ${./cargo-remote-run.py} ${../modules/home-manager/dev/cargo-remote-run.sh}
          touch "$out"
        '';
    quaderno-plan = pkgs.runCommand "quaderno-plan" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      cp ${../modules/home-manager/quaderno_plan.py} quaderno_plan.py
      cp ${./quaderno-plan.py} test_quaderno_plan.py
      python test_quaderno_plan.py
      touch "$out"
    '';
    # mc-setup-hooks が prismlauncher.cfg の [General] だけを書き換え、起動中は触らないこと。
    minecraft-setup-hooks = pkgs.runCommand "minecraft-setup-hooks" { nativeBuildInputs = [ pkgs.python3 pkgs.gawk ]; } ''
      python ${./minecraft-setup-hooks.py} ${../modules/home-manager/minecraft-setup-hooks.sh}
      touch "$out"
    '';
    # windows-vm の起動、待機、ロック、止め忘れの通知を、偽の virsh と FreeRDP で確かめる。
    # flock は util-linux にしかなく、ランチャー自体も Linux 専用なので、Darwin では省く。
    windows-vm =
      if system != "x86_64-linux" then
        pkgs.runCommand "windows-vm-skipped" { } "touch $out"
      else
        pkgs.runCommand "windows-vm" { nativeBuildInputs = [ pkgs.python3 pkgs.util-linux ]; } ''
          python ${./windows-vm.py} ${../modules/home-manager/windows-vm.sh}
          touch "$out"
        '';
    # デスクトップの keyd の設定を keyd 自身で検証する。存在しないレイヤーへの toggle などは評価では
    # 見つからず、switch したあとで keyd が設定を読めずにキーボードの変換が止まる。
    keyd-config =
      if system != "x86_64-linux" then
        pkgs.runCommand "keyd-config-skipped" { } "touch $out"
      else
        pkgs.runCommand "keyd-config" { nativeBuildInputs = [ pkgs.keyd ]; } ''
          keyd check ${pkgs.writeText "default.conf" inputs.self.nixosConfigurations.nixos-desktop.config.environment.etc."keyd/default.conf".text}
          touch "$out"
        '';
    # windows-vm のビルド（writeShellApplication の shellcheck）を CI で通す。
    # デスクトップの構成は評価しかしないので、ここでビルドしないと見つからない。
    windows-vm-package =
      if system != "x86_64-linux" then
        pkgs.runCommand "windows-vm-package-skipped" { } "touch $out"
      else
        lib.findFirst (p: (p.name or "") == "windows-vm") (throw "windows-vm is not installed")
          (mkTestHome system [
            windowsVm
            { local.profile.features.gui = true; }
          ]).config.home.packages;
    wsl-contracts = pkgs.runCommand "wsl-contracts" { } ''
      echo ${lib.escapeShellArg wslContracts} > "$out"
    '';
    desktop-contracts = pkgs.runCommand "desktop-contracts" { } ''
      echo ${lib.escapeShellArg desktopContracts} > "$out"
    '';
  }
)
