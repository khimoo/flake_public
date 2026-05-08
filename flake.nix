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
        ./modules/home-manager/yazi.nix
        ./modules/home-manager/dev.nix
        ./modules/home-manager/gui/default.nix
        ./modules/home-manager/gui/gnome.nix
        ./modules/home-manager/gui/ime.nix
        ./modules/home-manager/gui/desktop-entry.nix
        ./modules/home-manager/audio.nix
      ];

      # features のデフォルト値（すべて無効）
      defaultFeatures = {
        gui = false;
        gnome = false;
        ime = false;
        audio = false;
        desktopEntry = false;
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
      mkSystem = { hostname, system, users, timezone, keymap ? "us", stateVersion, primaryUser ? (builtins.head users).username }:
        let
          settings = baseSettings // {
            inherit hostname system users timezone keymap stateVersion primaryUser;
            features = {
              gui = true;
              gnome = true;
              ime = true;
              audio = true;
              desktopEntry = true;
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
      mkHome = { username, system, homeFile ? null, stateVersion, allowUnfree ? false, features ? {}, extraSettings ? {} }:
        let
          pkgs = import nixpkgs { inherit system; inherit overlays; };
          skk-dict = mkSkkDict system;
          settings = baseSettings // {
            inherit system stateVersion;
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
        };

        # macOS (CLI のみ、GUI は homeFile で追加可能)
        "pomu-macos" = mkHome {
          username = "pomu";
          system = "aarch64-darwin";  # Intel Mac なら x86_64-darwin
          stateVersion = "25.05";
          allowUnfree = true;
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
        };
      };
    };
}
