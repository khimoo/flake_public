{
  description = "NixOS configuration in spin713";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    my-secrets = {
       url = "git+ssh://git@github.com/khimoo/myflakes.git";
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
  };

  outputs = inputs@{ nixpkgs, home-manager, skk-jisyo, kiro, my-secrets, ... }:
    let
      private = my-secrets.settings;
      # 基本設定（共通部分）
      baseSettings = {
        gitUsername = private.gitUsername;
        gitUserEmail = private.gitUserEmail;
        locale = "ja_JP.UTF-8";
      };

      # ホストごとの設定を生成するヘルパー関数
      mkSystem = { hostname, system, username, timezone, keymap ? "us", stateVersion }:
        let
          # 基本設定をマージし、引数で渡された設定で上書き
          settings = baseSettings // {
            inherit hostname system username timezone keymap stateVersion;
          };

          pkgs = import nixpkgs { inherit system; };
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
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                backupFileExtension = "bak";
                extraSpecialArgs = { inherit skk-dict kiro; inherit settings; };
                users.${username} = import ./hosts/${hostname}/home.nix;
              };
            }
            {
              environment.systemPackages = [
                inputs.kiro.packages.${system}.default
              ];
            }
          ];
        };

    in {
      nixosConfigurations = {
        nixos-spin713 = mkSystem {
          hostname = "nixos-spin713";
          system = "x86_64-linux";
          username = "pomu";
          timezone = "Asia/Tokyo";
          keymap = "us";
          stateVersion = "25.05";
        };

        nixos-desktop = mkSystem {
          hostname = "nixos-desktop";
          system = "x86_64-linux";
          username = "pomu";
          timezone = "Asia/Tokyo";
          keymap = "us";
          stateVersion = "25.05";
        };
      };
    };
}
