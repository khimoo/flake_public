{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # 更新の速いツールだけをここから取る。用途は overlays/unstable-packages.nix を参照。
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # RustOwl公式のインストール案内で紹介されているNix community flake。
    # 上流のnixpkgs/toolchain固定をそのまま使い、専用sysrootをstoreに閉じる。
    rustowl.url = "github:nix-community/rustowl-flake";
    skk-jisyo = {
      url = "https://skk-dev.github.io/dict/SKK-JISYO.L.gz";
      flake = false;
    };
    musnix.url = "github:musnix/musnix"; # https://github.com/musnix/musnix
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
    # Claude Code。新しいモデルはクライアントのリリースと同時に選べるようになるので、
    # nixos-unstable チャンネルが進むまでの数日はそのモデルを指定できない。この flake は
    # 上流リリースのネイティブバイナリを hash 固定で取り、時間単位で追従する。
    # 経緯と除外条件は docs/architecture/unstable-packages.md に置いた。
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
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
    # comma と command-not-found が引く nix-index のデータベース。週次で生成済みのものを
    # 取り、手元で nixpkgs 全体を索引しない。判断は docs/howtouse/cli-tools/comma.md に置いた。
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # WSL ホストの OS 側（wsl.conf、既定ユーザー、ブートローダーの代わり）。ブランチは nixpkgs の
    # リリースに合わせる（docs/architecture/wsl.md）。
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rnote.url = "github:khimoo/rnote";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      configurations = import ./lib/configurations.nix { inherit inputs; };
      inherit (configurations) mkSystem mkHome overlays;
    in
    {
      packages.x86_64-linux = {
        inherit (inputs.rustowl.packages.x86_64-linux) rustowl rustowl-nvim;
      };

      nixosConfigurations = nixpkgs.lib.mapAttrs
        (hostname: m: mkSystem ({ inherit hostname; inherit (m) system; } // m.nixos))
        (nixpkgs.lib.filterAttrs (_: m: m ? nixos) (import ./hosts/machines.nix).machines);

      homeConfigurations = {
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
