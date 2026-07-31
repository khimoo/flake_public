# private repo を home-manager だけで宣言的に clone する。NixOS でも非 NixOS(WSL/macOS)でも
# 同じ経路で動くよう systemd ではなく home.activation を使う(nixos-rebuild switch でも
# home-manager switch でも走り、Darwin でも動く)。
#
# 認証に使う ~/.ssh/id_github は ssh-keys.nix が secrets.yaml から書き出す。このモジュールは
# 復号を知らず、鍵が既に置かれている前提で clone だけを担う(activation の順序で保証する)。
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
  sshKey = "${home}/.ssh/id_github";

  # 1 repo 分の clone スニペット。dest が既にあれば触らない(冪等・非破壊)。
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
    home.activation.privateRepos = lib.hm.dag.entryAfter [ "sshKeys" ] ''
      ssh_key=${lib.escapeShellArg sshKey}

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        ${lib.concatMapStringsSep "\n        " dryRunListSnippet repos}
      elif [ ! -f "$ssh_key" ]; then
        # ssh-keys.nix が書き出せていない(age 鍵が無い)。破壊はせず警告して抜ける。
        echo "private-repos: $ssh_key が無いので clone をスキップ(age 鍵を置いて switch し直す)" >&2
      else
        # 各 repo を dest 未存在時のみ clone(既存 working tree は触らない・pull もしない)。
        ${lib.concatMapStringsSep "\n\n        " (r: "(\n          ${cloneRepoSnippet r}\n        )") repos}
      fi
    '';
  };
}
