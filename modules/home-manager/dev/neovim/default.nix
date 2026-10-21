{ config, pkgs, lib, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.local.neovim;
  enabled = lib.filterAttrs (_: f: f.enable) cfg.features;
  enabledList = lib.attrValues enabled;

  # 機能の Lua spec は lua/features/<名前>.lua に置き、lua/plugins/ の一括 import には含めない。
  # 定義と spec が片方だけ残ると、機能を消したときに依存か読み込みのどちらかが取り残される。
  specNames = map (lib.removeSuffix ".lua") (
    lib.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".lua" name) (
        builtins.readDir ./config/lua/features
      )
    )
  );
  definedNames = lib.attrNames cfg.features;

  # nvim 実行ファイルのフルパス。home.shellAliases から参照することで
  # 「programs.neovim が有効でないと eval エラー」という形で依存を強制する。
  nvimExe = lib.getExe config.programs.neovim.finalPackage;
in
{
  imports = [ ./features.nix ];

  options.local.neovim.features = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Load lua/features/<name>.lua and provide the tools it needs.";
          };
          packages = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = "Commands the feature runs. They are added to Neovim's PATH only.";
          };
          luaPackages = mkOption {
            type = types.functionTo (types.listOf types.package);
            default = _: [ ];
            description = "Lua modules the feature needs, chosen from Neovim's Lua package set.";
          };
          data = mkOption {
            type = types.attrsOf types.anything;
            default = { };
            description = ''Values the feature's spec reads as require("config.nix").data.<name>.'';
          };
        };
      }
    );
    default = { };
    description = "Neovim features. Removing one drops its spec, its tools and its data together.";
  };

  config = {
    assertions = [
      {
        assertion = lib.sort lib.lessThan definedNames == lib.sort lib.lessThan specNames;
        message = "local.neovim.features must match lua/features/*.lua. Only defined: ${
          toString (lib.subtractLists specNames definedNames)
        }; only a spec: ${toString (lib.subtractLists definedNames specNames)}.";
      }
    ];

    programs.neovim = {
      enable = true;
      vimAlias = true;
      defaultEditor = true;
      withNodeJs = true;
      # home.stateVersion が 26.05 未満のあいだ、Home Manager は従来の既定（true）を使うので明示する。
      # Python と Ruby の provider を使うプラグインはない。全ユーザーの home.stateVersion が 26.05 以上に
      # なったら既定と同じになるので、この 2 行を消す。
      withRuby = false;
      withPython3 = false;
      # Home Manager 26.05 は Lua のパスや provider の設定を ~/.config/nvim/init.lua に書き出すが、
      # ~/.config/nvim は checkout への symlink なのでその中に置けない。ラッパーの引数で読み込ませる。
      sideloadInitLua = true;
      extraPackages = lib.unique (lib.concatMap (f: f.packages) enabledList);
      # luarocks をユーザー環境に出さず、nixpkgs の Lua モジュールを渡す。
      extraLuaPackages = ps: lib.unique (lib.concatMap (f: f.luaPackages ps) enabledList);
      plugins = with pkgs.vimPlugins; [
        lazy-nvim
      ];
    };

    # Neovim の設定ディレクトリを out-of-store symlink で配置する。
    # ~/.config/nvim → ${flakeRoot}/modules/home-manager/dev/neovim/config への symlink。
    # これにより lua の編集が rebuild なしで反映され、lazy-lock.json もリポジトリ内に
    # 書き戻されるため git で追跡できる。
    xdg.configFile."nvim".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.local.profile.flakeRoot}/modules/home-manager/dev/neovim/config";

    # 有効な機能の一覧と値。lua/config/lazy.lua と各機能の spec が lua/config/nix.lua 経由で読む。
    # ~/.config/nvim は checkout への symlink なので、生成物は stdpath("data") に置く。
    xdg.dataFile."nvim/nix/features.lua".text = "return " + lib.generators.toLua { } {
      features = lib.attrNames enabled;
      data = lib.mapAttrs (_: f: f.data) enabled;
    };

    # 一時 markdown draft を nvim で開く。Claude への返信下書きなどに使う。
    # /tmp は systemd-tmpfiles が 10 日経過で自動削除するためメンテ不要。
    home.shellAliases.draft = ''${nvimExe} "$(mktemp --suffix=.md)"'';
  };
}
