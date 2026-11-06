# sshfs で別の PC のファイルを編集するための導入と、sshfs 上で起きる問題の対策。
# 使い方と設計判断: docs/howtouse/sshfs.md
{ config, lib, pkgs, ... }:

let
  cfg = config.local.sshfs;
  relations = config.local.relations;
  direnvCache = relations.measures.direnvCacheOnSshfs;
  direnvCondition = relations.conditions.${direnvCache.condition}.mountType;
in
{
  options.local.sshfs = {
    enable = lib.mkEnableOption "sshfs and its workarounds for editing another machine's files";
  };

  config = lib.mkMerge [
    # 用途と条件は sshfs を入れていない環境でも宣言する。Neovim の PDF 対策はマウント種別だけを見て働く。
    (lib.mkIf pkgs.stdenv.isLinux {
      local.relations.purposes.sshfsEditing.description = "sshfs で別の PC のファイルを編集する";
      local.relations.conditions.onSshfs = {
        description = "対象のパスが sshfs 上にある";
        mountType = {
          fsType = "fuse.sshfs";
          package = pkgs.util-linux;
        };
      };
    })

    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.sshfs ];

      local.relations.measures.direnvCacheOnSshfs = {
        description = "direnv のキャッシュを手元に置く";
        source = "modules/home-manager/sshfs.nix";
        purpose = "sshfsEditing";
        condition = "onSshfs";
      };

      programs.direnv.stdlib = ''
        direnv_layout_dir() {
          if [[ -n ''${direnv_layout_dir:-} ]]; then
            echo "$direnv_layout_dir"
          elif [[ $(${direnvCondition.findmnt} -n -o FSTYPE -T "$PWD") == ${direnvCondition.fsType} ]]; then
            local hash
            hash=$(printf '%s' "$PWD" | sha1sum | cut -c1-40)
            echo "''${XDG_CACHE_HOME:-$HOME/.cache}/direnv/layouts/$hash''${PWD//[^a-zA-Z0-9]/-}"
          else
            echo "$PWD/.direnv"
          fi
        }
      '';
    })
  ];
}
