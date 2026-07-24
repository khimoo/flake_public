# private repo を home-manager だけで宣言的に clone する。NixOS でも非 NixOS(WSL/macOS)でも
# 同じ経路で動くよう systemd ではなく home.activation を使う(nixos-rebuild switch でも
# home-manager switch でも走り、Darwin でも動く)。
#
# 認証の流れ:
#   1) 復号の種 = 専用 age 秘密鍵。~/.config/sops/age/keys.txt に out-of-band で置く
#      (既存マシンから SSH 送信、または Bitwarden から取得)。マシンに縛られない小さな鍵。
#   2) 暗号文 = secrets/secrets.yaml(この repo にコミット・sops で暗号化済み)。中身は GitHub 登録
#      済みのユーザー SSH 鍵(既存のものを流用)。age 鍵で復号し ~/.ssh/id_ed25519 が無ければ書き出す。
#   3) その SSH 鍵で 各 { url, dest } を dest 未存在時のみ clone(冪等・非破壊)。
#
# 対象 repo は settings.privateRepos = [{ url, dest }] で受ける。空リスト(既定)なら activation
# 自体が生えない。公開 flake をそのまま使う人・自前 repo を手動 clone したい人には無影響。
# 個々の (url, dest) は flake.nix 側で claudeConfig* / obsidianConfig* 等の高レベル設定から
# 組み立てる (dest だけ指定・URL 未指定は手動 clone のまま = 抜き差し可能)。
{ config, lib, pkgs, settings, ... }:

let
  repos = settings.privateRepos or [];
  enable = repos != [];

  home = config.home.homeDirectory;
  ageKeyFile = "${home}/.config/sops/age/keys.txt";
  sshKey = "${home}/.ssh/id_ed25519";

  # コミット済みの暗号文。store path になる(暗号化済みなので world-readable でも安全)。
  secretsFile = ../../secrets/secrets.yaml;

  # 1 repo 分の clone スニペット。SSH 鍵と age 鍵の下準備は外側で 1 度だけ行う前提。
  cloneRepoSnippet = { url, dest }: ''
    repo=${lib.escapeShellArg url}
    dest=${lib.escapeShellArg dest}
    if [ ! -e "$dest" ]; then
      mkdir -p "$(dirname "$dest")"
      GIT_SSH_COMMAND="ssh -i $ssh_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
        ${pkgs.git}/bin/git clone "$repo" "$dest"
    fi
  '';

  dryRunListSnippet = { url, dest }:
    "echo 'private-repos: (dry-run) ${url} を ${dest} へ clone する予定' >&2";
in
{
  config = lib.mkIf enable {
    home.activation.privateRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      age_key=${lib.escapeShellArg ageKeyFile}
      ssh_key=${lib.escapeShellArg sshKey}
      secrets=${lib.escapeShellArg (toString secretsFile)}

      if [ ! -f "$age_key" ]; then
        # 復号の種が無ければ何も進められない。破壊はせず警告して抜ける(次の switch で再試行)。
        echo "private-repos: age 復号鍵 $age_key が無いのでスキップ(SSH 送信 or Bitwarden で設置)" >&2
      elif [ -n "''${DRY_RUN_CMD:-}" ]; then
        # dry-run 時は SSH 鍵ファイルを絶対に触らない(リダイレクトは DRY_RUN_CMD で包めないため)。
        ${lib.concatMapStringsSep "\n        " dryRunListSnippet repos}
      else
        # ユーザー SSH 鍵が無ければ暗号文から復元(既存鍵は上書きしない=非破壊)。
        if [ ! -f "$ssh_key" ]; then
          mkdir -p "$(dirname "$ssh_key")"
          ( umask 077
            SOPS_AGE_KEY_FILE="$age_key" \
              ${pkgs.sops}/bin/sops --decrypt --extract '["git_ssh_key"]' "$secrets" > "$ssh_key" )
          chmod 600 "$ssh_key"
        fi

        # 各 repo を dest 未存在時のみ clone(既存 working tree は触らない・pull もしない)。
        ${lib.concatMapStringsSep "\n\n        " (r: "(\n          ${cloneRepoSnippet r}\n        )") repos}
      fi
    '';
  };
}
