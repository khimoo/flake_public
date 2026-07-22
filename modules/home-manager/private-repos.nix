# private repo を home-manager だけで宣言的に clone する。NixOS でも非 NixOS(WSL/macOS)でも
# 同じ経路で動くよう systemd ではなく home.activation を使う(nixos-rebuild switch でも
# home-manager switch でも走り、Darwin でも動く)。
#
# 認証の流れ:
#   1) 復号の種 = 専用 age 秘密鍵。~/.config/sops/age/keys.txt に out-of-band で置く
#      (既存マシンから SSH 送信、または Bitwarden から取得)。マシンに縛られない小さな鍵。
#   2) 暗号文 = secrets/secrets.yaml(この repo にコミット・sops で暗号化済み)。中身は GitHub 登録
#      済みのユーザー SSH 鍵(既存のものを流用)。age 鍵で復号し ~/.ssh/id_ed25519 が無ければ書き出す。
#   3) その SSH 鍵で claudeConfigRepo を claudeConfigRoot へ clone(既に在れば何もしない)。
#
# claudeConfigRepo が null(既定)なら activation 自体が生えない。公開 flake をそのまま使う人・
# 自前 repo を手動 clone したい人に無影響(抜き差し可能)。dev/claude.nix の symlink は
# claudeConfigRoot さえ在れば clone の有無に関わらず効く。
{ config, lib, pkgs, settings, ... }:

let
  claudeRoot = settings.claudeConfigRoot or null;
  claudeRepo = settings.claudeConfigRepo or null;
  # clone 自動化を有効化するのは clone 先(root)と clone 元(repo)の両方が指定されたときだけ。
  enable = claudeRoot != null && claudeRepo != null;

  home = config.home.homeDirectory;
  ageKeyFile = "${home}/.config/sops/age/keys.txt";
  sshKey = "${home}/.ssh/id_ed25519";

  # コミット済みの暗号文。store path になる(暗号化済みなので world-readable でも安全)。
  secretsFile = ../../secrets/secrets.yaml;
in
{
  config = lib.mkIf enable {
    home.activation.privateRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      age_key=${lib.escapeShellArg ageKeyFile}
      ssh_key=${lib.escapeShellArg sshKey}
      repo=${lib.escapeShellArg claudeRepo}
      dest=${lib.escapeShellArg claudeRoot}
      secrets=${lib.escapeShellArg (toString secretsFile)}

      if [ ! -f "$age_key" ]; then
        # 復号の種が無ければ何も進められない。破壊はせず警告して抜ける(次の switch で再試行)。
        echo "private-repos: age 復号鍵 $age_key が無いのでスキップ(SSH 送信 or Bitwarden で設置)" >&2
      elif [ -n "''${DRY_RUN_CMD:-}" ]; then
        # dry-run 時は SSH 鍵ファイルを絶対に触らない(リダイレクトは DRY_RUN_CMD で包めないため)。
        echo "private-repos: (dry-run) $repo を $dest へ clone する予定" >&2
      else
        # ユーザー SSH 鍵が無ければ暗号文から復元(既存鍵は上書きしない=非破壊)。
        if [ ! -f "$ssh_key" ]; then
          mkdir -p "$(dirname "$ssh_key")"
          ( umask 077
            SOPS_AGE_KEY_FILE="$age_key" \
              ${pkgs.sops}/bin/sops --decrypt --extract '["git_ssh_key"]' "$secrets" > "$ssh_key" )
          chmod 600 "$ssh_key"
        fi

        # clone 先が無ければ初回 clone(既存 working tree は触らない・pull もしない)。
        if [ ! -e "$dest" ]; then
          mkdir -p "$(dirname "$dest")"
          GIT_SSH_COMMAND="ssh -i $ssh_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
            ${pkgs.git}/bin/git clone "$repo" "$dest"
        fi
      fi
    '';
  };
}
