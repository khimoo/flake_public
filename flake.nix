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
    # RustOwl公式のインストール案内で紹介されているNix community flake。
    # 上流のnixpkgs/toolchain固定をそのまま使い、専用sysrootをstoreに閉じる。
    rustowl.url = "github:nix-community/rustowl-flake";
    skk-jisyo = {
      url = "https://skk-dev.github.io/dict/SKK-JISYO.L.gz";
      flake = false;
    };
    kiro.url = "github:johnkferguson/kiro-linux-flake";
    musnix.url = "github:musnix/musnix"; # https://github.com/musnix/musnix
    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-history = {
      url = "github:raine/claude-history";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Codex CLI。nixpkgs は unstable でも追従が数週間遅れ、その間 OpenAI 側が
    # 新しいデフォルトモデルに切り替えると CLI が model 名を解決できず 400 になる。
    # この flake は上流リリースの musl バイナリを hash 固定で取り、時間単位で追従する。
    # nixpkgs が追いついたら overlays/unstable-packages.nix 経由に戻してここを消す。
    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      configurations = import ./lib/configurations.nix { inherit inputs; };
      inherit (configurations) mkSystem mkHome overlays;
    in
    {
      packages =
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]
          (system: {
            happy = nixpkgs.legacyPackages.${system}.callPackage ./packages/happy { };
          } // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
            rustowl = inputs.rustowl.packages.${system}.rustowl;
          });

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
          stateVersion = "25.05";
        };
        nixos-desktop = mkSystem {
          hostname = "nixos-desktop";
          system = "x86_64-linux";
          users =
            map
              (
                u:
                u
                // {
                  homeFile = ./hosts/nixos-desktop + "/home-manager-${u.username}.nix";
                }
              )
              [
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
          stateVersion = "25.05";
        };
      };

      homeConfigurations = {
        "pomu-wsl" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          stateVersion = "25.05";
          homeFile = ./profiles/home/pomu.nix;
        };
        "pomu-macos" = mkHome {
          username = "pomu";
          system = "aarch64-darwin";
          stateVersion = "25.05";
          homeFile = ./profiles/home/pomu.nix;
        };
        "pomu-nixos" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          stateVersion = "25.05";
          homeFile = ./profiles/home/pomu.nix;
          modules = [
            {
              local.profile.features = {
                gui = true;
                gnome = true;
                ime = true;
                audio = true;
              };
            }
          ];
        };
      };

      checks = import ./tests { inherit inputs configurations; };

      devShells.x86_64-linux = import ./devShells {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          inherit overlays;
          config.allowUnfree = true;
        };
      };
    };
}
