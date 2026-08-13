{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # 更新の速いツールだけをここから取る。用途は overlays/unstable-packages.nix を参照。
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    skk-jisyo = {
      url = "https://skk-dev.github.io/dict/SKK-JISYO.L.gz";
      flake = false;
    };
    kiro.url = "github:johnkferguson/kiro-linux-flake";
    musnix.url = "github:musnix/musnix";  # https://github.com/musnix/musnix
    winapps = {
       url = "github:winapps-org/winapps";
       inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-history = {
      url = "github:raine/claude-history";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Zettelkasten(Obsidian vault)同期の mechanism(添付/papis の Drive 同期 + secret 暗号文の
    # 実行時復号)。flake_public は modules/home-manager/zettelkasten.nix で clone 位置だけ注入する。
    # mechanism は public repo に切り出したので github:(https 取得)で引く。ノート本文は別の
    # private repo。git+ssh をやめたことで、この flake の eval に SSH 鍵が要らなくなる。
    zettelkasten = {
      url = "github:khimoo/zettelkasten-workflow";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, skk-jisyo, kiro, ... }:
    let
      # 基本設定（共通部分）
      baseSettings = {
        gitUsername = "khimoo";
        gitUserEmail = "dailysentence1111@gmail.com";
        locale = "ja_JP.UTF-8";
      };

      # 全 home-manager モジュール（mkSystem / mkHome 共通）
      homeModules = [
        ./modules/home-manager/core.nix
        ./modules/home-manager/git.nix
        ./modules/home-manager/ssh-keys.nix
        ./modules/home-manager/private-repos.nix
        ./modules/home-manager/rclone.nix
        ./modules/home-manager/zettelkasten.nix
        ./modules/home-manager/yazi.nix
        ./modules/home-manager/dev
        ./modules/home-manager/gui/default.nix
        ./modules/home-manager/gui/gnome.nix
        ./modules/home-manager/gui/ime.nix
        ./modules/home-manager/gui/apps.nix
        ./modules/home-manager/gui/firefox.nix
        ./modules/home-manager/gui/teams-dispatcher.nix
        ./modules/home-manager/gui/xdg-scheme-workaround.nix
        ./modules/home-manager/audio
      ];

      # features のデフォルト値（すべて無効）
      defaultFeatures = {
        gui = false;
        gnome = false;
        ime = false;
        audio = false;
        referenceSync = false;
        zettelkastenSync = false;
        obsidian = false;
      };

      # SKK辞書の生成（system別にキャッシュ）
      mkSkkDict = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.stdenv.mkDerivation {
          name = "skk-jisyo-dict";
          src = skk-jisyo;
          nativeBuildInputs = [ pkgs.gzip ];
          unpackPhase = "gzip -d < $src > $out";
          dontInstall = true;
        };

      # ホストごとの設定を生成するヘルパー関数
      # flakeRoot: flake チェックアウト先の絶対パス。
      # modules/home-manager/dev/neovim が mkOutOfStoreSymlink でこのパスを参照する。
      # ホストごとの clone 位置に依存するため、各ホストの呼び出し側で指定する。
      # zettelkastenRoot: Obsidian vault(zettelkasten)の clone 先絶対パス。
      # modules/home-manager/zettelkasten.nix が添付フォルダの同期対象として参照する。
      # flakeRoot と同様に環境ごとの clone 位置に依存するため、呼び出し側で指定する。
      # zettelkastenRepoUrl: 上記を宣言的に自動 clone する場合の clone 元 URL (null で自動 clone 無効)。
      # ノート本文は private repo なので、claudeConfigRepo と同じ経路 (private-repos.nix + age 鍵)
      # で取得する。vault フォルダの用意はこの clone が担い、workflow 側の initializeVault は使わない。
      # claudeConfigRoot: Claude Code のユーザー設定 repo の clone 先絶対パス (null で無効)。
      # modules/home-manager/dev/claude.nix が ~/.claude 配下への symlink 元として参照する。
      # private repo なので clone がある環境だけ指定する（抜き差し可能）。
      # claudeConfigRepo: 上記を宣言的に自動 clone する場合の clone 元 URL (null で自動 clone 無効)。
      # modules/home-manager/private-repos.nix が age 鍵で復号した SSH 鍵で clone する。
      # root だけ指定して repo=null なら symlink のみ効き、clone は手動運用のまま。
      # vaultSkeletonRepo: vault の骨格(分類フォルダ・運用ドキュメント・.obsidian)をミラーする
      # workflow repo の local checkout 絶対パス (null で mirror-vault を PATH に載せない)。
      # modules/home-manager/zettelkasten.nix が services.zettelkasten.mirrorRepo に注入する。
      # 環境固有の checkout 位置なので flakeRoot 同様に呼び出し側で指定する。
      # vaultSkeletonRepoUrl: 上記を宣言的に自動 clone する場合の clone 元 URL (null で自動 clone 無効)。
      # claudeConfigRepo と同じ経路 (private-repos.nix + age 鍵) で clone される。
      # vaultSkeletonRepo だけ指定して Url=null なら手動 clone 運用のまま。
      # llmWikisRoot: LLM 向けナレッジベース(LLM Wiki)群の clone 先絶対パス (null で無効)。
      # flake 側にこれを読むモジュールは無く、private-repos.nix の clone 対象として渡すためだけに
      # 存在する。運用は該当ドメインのディレクトリで Claude Code を起動し、そこの CLAUDE.md を
      # スキーマとして使うので、~/.claude への配線は要らない (docs/architecture/llm-wikis.md 参照)。
      # llmWikisRepoUrl: 上記を宣言的に自動 clone する場合の clone 元 URL (null で自動 clone 無効)。
      # claudeConfigRepo と同じ経路 (private-repos.nix + age 鍵) で clone される。
      # buildPrivateRepos: {root, repo} 対のリストから、URL も指定されている項目だけを
      # private-repos.nix が食う {url, dest} リストに畳む。
      buildPrivateRepos = pairs:
        map (p: { url = p.repo; dest = p.root; })
          (builtins.filter (p: p.root != null && p.repo != null) pairs);

      # ssh-keys.nix が secrets/secrets.yaml から書き出す共通鍵。鍵は用途で名付ける
      # (アルゴリズム名の id_ed25519 だと 1 ファイルに複数の役割が同居しても気づけない)。
      githubSshKey = { secret = "git_ssh_key"; name = "id_github"; };  # GitHub 認証
      lanSshKey    = { secret = "lan_ssh_key"; name = "id_lan"; };     # LAN 内 machine-to-machine

      mkSystem = { hostname, system, users, timezone, keymap ? "us", stateVersion, primaryUser ? (builtins.head users).username, flakeRoot, zettelkastenRoot, zettelkastenRepoUrl ? null, claudeConfigRoot ? null, claudeConfigRepo ? null, vaultSkeletonRepo ? null, vaultSkeletonRepoUrl ? null, llmWikisRoot ? null, llmWikisRepoUrl ? null }:
        let
          privateRepos = buildPrivateRepos [
            { root = zettelkastenRoot;  repo = zettelkastenRepoUrl; }
            { root = claudeConfigRoot;  repo = claudeConfigRepo; }
            { root = vaultSkeletonRepo; repo = vaultSkeletonRepoUrl; }
            { root = llmWikisRoot;      repo = llmWikisRepoUrl; }
          ];
          settings = baseSettings // {
            inherit hostname system users timezone keymap stateVersion primaryUser flakeRoot zettelkastenRoot claudeConfigRoot claudeConfigRepo vaultSkeletonRepo privateRepos;
            # NixOS ホストは LAN の一員でもあるので id_lan も要る(modules/nixos/ssh.nix が使う)。
            sshKeys = [ githubSshKey lanSshKey ];
            standalone = false;
            features = {
              gui = true;
              gnome = true;
              ime = true;
              audio = true;
              referenceSync = true;
              zettelkastenSync = true;
              obsidian = true;
            };
          };

          skk-dict = mkSkkDict system;
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; inherit skk-dict kiro; inherit settings; };
          modules = [
            { nixpkgs = { hostPlatform = system; overlays = overlays; }; }
            inputs.musnix.nixosModules.musnix
            (./hosts/${hostname}/default.nix)
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                backupFileExtension = "bak";
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs skk-dict kiro; inherit settings; };
                users = builtins.listToAttrs (map (user: {
                  name = user.username;
                  value = {
                    imports = homeModules ++ [ (user.homeFile or ./hosts/${hostname}/home.nix) ];
                  };
                }) (builtins.filter (user: user.manageHome or true) users));
              };
            }
          ];
        };

      # スタンドアロンhome-manager設定を生成するヘルパー関数
      # mkSystem と同じく flakeRoot は呼び出し側で指定 (環境ごとに clone 位置が違うため)。
      # zettelkastenRoot は zettelkastenSync を有効化する standalone 環境のみ必要（既定 null）。
      mkHome = { username, system, homeFile ? null, stateVersion, allowUnfree ? false, features ? {}, flakeRoot, zettelkastenRoot ? null, zettelkastenRepoUrl ? null, claudeConfigRoot ? null, claudeConfigRepo ? null, vaultSkeletonRepo ? null, vaultSkeletonRepoUrl ? null, llmWikisRoot ? null, llmWikisRepoUrl ? null, extraSettings ? {} }:
        let
          pkgs = import nixpkgs { inherit system; inherit overlays; };
          skk-dict = mkSkkDict system;
          privateRepos = buildPrivateRepos [
            { root = zettelkastenRoot;  repo = zettelkastenRepoUrl; }
            { root = claudeConfigRoot;  repo = claudeConfigRepo; }
            { root = vaultSkeletonRepo; repo = vaultSkeletonRepoUrl; }
            { root = llmWikisRoot;      repo = llmWikisRepoUrl; }
          ];
          settings = baseSettings // {
            inherit system stateVersion flakeRoot zettelkastenRoot claudeConfigRoot claudeConfigRepo vaultSkeletonRepo privateRepos;
            # standalone(WSL/macOS)は LAN の一員ではないので id_lan は配らない。
            # clone 対象が無ければ id_github も不要 = activation 自体が生えない。
            sshKeys = nixpkgs.lib.optionals (privateRepos != []) [ githubSshKey ];
            standalone = true;
            features = defaultFeatures // features;
          } // extraSettings;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs skk-dict kiro; inherit settings; };
          modules = homeModules ++ [
            {
              nixpkgs.config.allowUnfree = allowUnfree;
              home.username = username;
              home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
            }
          ] ++ (if homeFile != null then [ homeFile ] else []);
        };

      # 一時的なパッチ等の overlay（overlays/default.nix）と、
      # unstable から取るパッケージの overlay（overlays/unstable-packages.nix）
      overlays = import ./overlays ++ [ (import ./overlays/unstable-packages.nix inputs) ];

    in {
      nixosConfigurations = {
        nixos-spin713 = mkSystem {
          hostname = "nixos-spin713";
          system = "x86_64-linux";
          primaryUser = "pomu";
          users = [
            {
              username = "pomu";
              isAdmin = true;
              homeFile = ./hosts/nixos-spin713/home.nix;
            }
          ];
          timezone = "Asia/Tokyo";
          keymap = "us";
          stateVersion = "25.05";
          flakeRoot = "/home/pomu/sagyo/flake_public";
          zettelkastenRoot = "/home/pomu/sagyo/zettelkasten";
          zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";
          claudeConfigRoot = "/home/pomu/sagyo/claude-private";
          claudeConfigRepo = "git@github.com:khimoo/claude-private.git";
          vaultSkeletonRepo = "/home/pomu/sagyo/zettelkasten-workflow";
          vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
          llmWikisRoot = "/home/pomu/sagyo/llm-wikis";
          llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
        };

        nixos-desktop = mkSystem {
          hostname = "nixos-desktop";
          system = "x86_64-linux";
          users = map (u: u // {
            homeFile = ./hosts/nixos-desktop + "/home-manager-${u.username}.nix";
          }) [
            {
              username = "pomu";
              isAdmin = true;
            }
            {
              username = "mase";
              isAdmin = false;
              manageHome = false;
              initialHashedPassword = "$6$jQHubQo9MXPX15.x$LSWMJBiOQT75T/HOeMyKlFmWZjl.wTi7CA.m02uFPPJqssvKCMq1..6fGYdjm7HMJhhBAIl1Vbpkuq92gaVbH/";
            }
          ];
          timezone = "Asia/Tokyo";
          keymap = "us";
          stateVersion = "25.05";
          flakeRoot = "/home/pomu/sagyo/flake_public";
          zettelkastenRoot = "/home/pomu/sagyo/zettelkasten";
          zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";
          claudeConfigRoot = "/home/pomu/sagyo/claude-private";
          claudeConfigRepo = "git@github.com:khimoo/claude-private.git";
          vaultSkeletonRepo = "/home/pomu/sagyo/zettelkasten-workflow";
          vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
          llmWikisRoot = "/home/pomu/sagyo/llm-wikis";
          llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
        };
      };

      # スタンドアロンhome-manager設定
      # 使い方: home-manager switch --flake .#<name>
      homeConfigurations = {
        # WSL (CLI のみ)
        "pomu-wsl" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          stateVersion = "25.05";
          allowUnfree = true;
          flakeRoot = "/home/pomu/sagyo/flake_public";
        };

        # macOS (CLI のみ、GUI は homeFile で追加可能)
        "pomu-macos" = mkHome {
          username = "pomu";
          system = "aarch64-darwin";  # Intel Mac なら x86_64-darwin
          stateVersion = "25.05";
          allowUnfree = true;
          flakeRoot = "/Users/pomu/sagyo/flake_public";
        };

        # NixOS スタンドアロン (フル機能)
        "pomu-nixos" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          stateVersion = "25.05";
          allowUnfree = true;
          features = {
            gui = true;
            gnome = true;
            ime = true;
            audio = true;
            desktopEntry = true;
          };
          flakeRoot = "/home/pomu/sagyo/flake_public";
        };
      };

      # コードリーディング/小さな実験用に ~/sagyo 配下の各プロジェクトから
      # `.envrc` 経由で参照する共通 devShell 群。
      # 使い方:
      #   echo 'use flake "/home/pomu/sagyo/flake_public#rust-bevy"' > .envrc
      #   direnv allow
      # 詳細: docs/howtouse/devshells.md / docs/architecture/devshells.md
      devShells.x86_64-linux =
        let
          devPkgs = import nixpkgs {
            system = "x86_64-linux";
            inherit overlays;
            config.allowUnfree = true;
          };
        in
          import ./devShells { pkgs = devPkgs; };
    };
}
