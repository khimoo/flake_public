{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    my-secrets = {
       url = "git+ssh://git@github.com/khimoo/flake_private.git";
    };
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
    nix-openclaw.url = "github:openclaw/nix-openclaw";
  };

  outputs = inputs@{ nixpkgs, home-manager, skk-jisyo, kiro, my-secrets, nix-openclaw, ... }:
    let
      private = my-secrets.settings;
      # 基本設定（共通部分）
      baseSettings = {
        gitUsername = private.gitUsername;
        gitUserEmail = private.gitUserEmail;
        locale = "ja_JP.UTF-8";
      };

      # OpenClaw シークレット: どの Git リポジトリにも置かず、ローカルファイルのみ参照する。
      # OPENCLAW_SECRETS_NIX で Nix ファイルの絶対パスを指定し、--impure でビルドする。
      openclawSecretsPathStr = builtins.getEnv "OPENCLAW_SECRETS_NIX";
      openclawSecretsPath = if openclawSecretsPathStr != "" then (/. + openclawSecretsPathStr) else null;
      openclawSecrets = if openclawSecretsPath != null && builtins.pathExists openclawSecretsPath
        then import openclawSecretsPath
        else { };

      # ホストごとの設定を生成するヘルパー関数
      mkSystem = { hostname, system, users, timezone, keymap ? "us", stateVersion }:
        let
          # 基本設定をマージ。openclaw はリポジトリ外のファイル（OPENCLAW_SECRETS_NIX）からのみ取得
          settings = baseSettings // {
            inherit hostname system users timezone keymap stateVersion;
            openclaw = openclawSecrets;
          };

          pkgs = import nixpkgs {
            inherit system;
            overlays = [ nix-openclaw.overlays.default ];
          };
          skk-dict = pkgs.stdenv.mkDerivation {
            name = "skk-jisyo-dict";
            src = skk-jisyo;
            nativeBuildInputs = [ pkgs.gzip ];
            unpackPhase = "gzip -d < $src > $out";
            dontInstall = true;
          };
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; inherit skk-dict kiro; inherit settings; };
          inherit system;
          modules = [
            inputs.musnix.nixosModules.musnix
            (./hosts/${hostname}/default.nix)
            # nix-openclaw overlay (home-manager の pkgs にも反映するため NixOS 側にも設定)
            ({ specialArgs, ... }: {
              nixpkgs.overlays = [ specialArgs.inputs.nix-openclaw.overlays.default ];
            })
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                backupFileExtension = "bak";
                extraSpecialArgs = {
                  inherit skk-dict kiro;
                  inherit settings;
                  nix-openclaw = inputs.nix-openclaw;
                  openclawDocumentsPath = ./hosts/nixos-desktop/openclaw-documents;
                };
                users = builtins.listToAttrs (map (user: {
                  name = user.username;
                  value = import (user.homeFile or ./hosts/${hostname}/home.nix);
                }) (builtins.filter (user: user.manageHome or true) users));
              };
            }
          ];
        };

    in {
      nixosConfigurations = {
        nixos-spin713 = mkSystem {
          hostname = "nixos-spin713";
          system = "x86_64-linux";
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
          }) private.nixos-desktopUsers;
          timezone = "Asia/Tokyo";
          keymap = "us";
          stateVersion = "25.05";
        };
      };
    };
}
