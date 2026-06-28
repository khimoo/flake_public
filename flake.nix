{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
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
        ./modules/home-manager/rclone.nix
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
      mkSystem = { hostname, system, users, timezone, keymap ? "us", stateVersion, primaryUser ? (builtins.head users).username, flakeRoot }:
        let
          settings = baseSettings // {
            inherit hostname system users timezone keymap stateVersion primaryUser flakeRoot;
            standalone = false;
            features = {
              gui = true;
              gnome = true;
              ime = true;
              audio = true;
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
                extraSpecialArgs = { inherit skk-dict kiro; inherit settings; };
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
      mkHome = { username, system, homeFile ? null, stateVersion, allowUnfree ? false, features ? {}, flakeRoot, extraSettings ? {} }:
        let
          pkgs = import nixpkgs { inherit system; inherit overlays; };
          skk-dict = mkSkkDict system;
          settings = baseSettings // {
            inherit system stateVersion flakeRoot;
            standalone = true;
            features = defaultFeatures // features;
          } // extraSettings;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit skk-dict kiro; inherit settings; };
          modules = homeModules ++ [
            {
              nixpkgs.config.allowUnfree = allowUnfree;
              home.username = username;
              home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
            }
          ] ++ (if homeFile != null then [ homeFile ] else []);
        };

      # 一時的なパッチ等の overlay（overlays/default.nix）
      overlays = import ./overlays;

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
