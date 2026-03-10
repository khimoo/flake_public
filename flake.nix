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
          # 基本設定をマージし、引数で渡された設定で上書き
          settings = baseSettings // {
            inherit hostname system users timezone keymap stateVersion primaryUser;
          };

          skk-dict = mkSkkDict system;
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; inherit skk-dict kiro; inherit settings; };
          inherit system;
          modules = [
            inputs.musnix.nixosModules.musnix
            (./hosts/${hostname}/default.nix)
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                backupFileExtension = "bak";
                extraSpecialArgs = { inherit skk-dict kiro; inherit settings; };
                users = builtins.listToAttrs (map (user: {
                  name = user.username;
                  value = import (user.homeFile or ./hosts/${hostname}/home.nix);
                }) (builtins.filter (user: user.manageHome or true) users));
              };
            }
          ];
        };

      # スタンドアロンhome-manager設定を生成するヘルパー関数
      mkHome = { username, system, homeFile, stateVersion, allowUnfree ? false, extraSettings ? {} }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          skk-dict = mkSkkDict system;
          settings = baseSettings // {
            inherit system stateVersion;
          } // extraSettings;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit skk-dict kiro; inherit settings; };
          modules = [
            homeFile
            {
              # NixOSモジュールとして使う場合はmodules/nixos/nix-settings.nixで別途設定される
              nixpkgs.config.allowUnfree = allowUnfree;
              home.username = username;
              home.homeDirectory = "/home/${username}";
            }
          ];
        };

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

      # スタンドアロンhome-manager設定（NixOS以外の環境用）
      # 使い方: home-manager switch --flake .#pomu-spin713
      homeConfigurations = {
        "pomu-spin713" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          homeFile = ./hosts/nixos-spin713/home.nix;
          stateVersion = "25.05";
          allowUnfree = true;
        };

        "pomu-desktop" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          homeFile = ./hosts/nixos-desktop/home-manager-pomu.nix;
          stateVersion = "25.05";
          allowUnfree = true;
        };
      };
    };
}
