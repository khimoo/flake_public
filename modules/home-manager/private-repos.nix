# private repo を home-manager だけで宣言的に clone する。NixOS でも非 NixOS(WSL/macOS)でも
# 同じ経路で動くよう systemd ではなく home.activation を使う(nixos-rebuild switch でも
# home-manager switch でも走り、Darwin でも動く)。
#
# 認証に使う ~/.ssh/id_github は ssh-keys.nix が secrets.yaml から書き出す。このモジュールは
# 復号を知らず、鍵が既に置かれている前提で clone だけを担う。
# privateRepos が非空なら profile.nix は必ずGitHub鍵も配り、ssh-keys.nix は書き出せなければ
# activation を止める。よって鍵の存在確認はここでは行わない(到達しない分岐を作らない)。
#
# 対象 repo は config.local.profile.privateRepos = [{ url, dest }] で受ける。空リスト(既定)なら activation
# 自体が生えない。公開 flake をそのまま使う人・自前 repo を手動 clone したい人には無影響。
# 個々の (url, dest) は profile.nix 側で agentConfig* / vaultSkeletonRepo* 等の高レベル設定から
# 組み立てる (dest だけ指定・URL 未指定は手動 clone のまま = 抜き差し可能)。
#
# clone は初回だけなので、以降の更新は pull-repos コマンドで手動で走らせる
# (flake 自身 + private repo 群をまとめて git pull --ff-only)。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  repos = config.local.profile.privateRepos;
  enable = repos != [ ];

  home = config.home.homeDirectory;
  sshKey = "${home}/.ssh/id_github";

  # git/ssh を絶対パスで呼ぶのは、NixOS では activation が systemd unit として走り
  # PATH に coreutils 等しか入らないため(裸の ssh は対話シェル経由でしか解決できない)。
  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${sshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";

  # 完成したcloneだけをdestへ移す。失敗した一時cloneを次回の成功判定に使わない。
  cloneRepoSnippet =
    { url, dest }:
    ''
      repo=${lib.escapeShellArg url}
      dest=${lib.escapeShellArg dest}
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ ! -e "$dest/.git" ]; then
          echo "private-repos: $dest exists but is not a Git checkout; inspect it before retrying" >&2
          exit 1
        fi
      else
        parent=$(dirname "$dest")
        mkdir -p "$parent"
        clone_tmp=$(mktemp -d "$parent/.private-clone.XXXXXX")
        trap 'rm -rf -- "$clone_tmp"' EXIT
        GIT_SSH_COMMAND=${lib.escapeShellArg gitSshCommand} \
          ${pkgs.git}/bin/git clone "$repo" "$clone_tmp/repo"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
          echo "private-repos: $dest appeared during clone; refusing to overwrite" >&2
          exit 1
        fi
        mv "$clone_tmp/repo" "$dest"
      fi
    '';

  dryRunListSnippet =
    { url, dest }:
    "echo ${lib.escapeShellArg "private-repos: (dry-run) ${url} を ${dest} へ clone する予定"} >&2";

  # flake 自身も同じ GitHub 鍵で更新するので、clone 対象と一緒に並べる。
  pullTargets = lib.unique ([ config.local.profile.flakeRoot ] ++ map (r: r.dest) repos);

  # --ff-only なので、ローカルにコミットがあって分岐している repo は git が拒否して終わる。
  # 1 つ失敗しても残りは回し、最後にまとめて非ゼロを返す。
  pullRepos = pkgs.writeShellApplication {
    name = "pull-repos";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      ${lib.optionalString (builtins.any (k: k.name == "id_github") config.local.profile.sshKeys) ''
        export GIT_SSH_COMMAND=${lib.escapeShellArg gitSshCommand}
      ''}

      status=0
      for dest in ${lib.escapeShellArgs pullTargets}; do
        if [ ! -e "$dest/.git" ]; then
          echo "pull-repos: $dest は clone されていない (switch すれば clone される)" >&2
          status=1
          continue
        fi
        echo "==> $dest"
        git -C "$dest" pull --ff-only || status=1
      done
      exit "$status"
    '';
  };
in
{
  config = lib.mkMerge [
    { home.packages = [ pullRepos ]; }

    (lib.mkIf enable {
      home.activation.privateRepos = lib.hm.dag.entryAfter [ "sshKeys" ] ''
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          ${lib.concatMapStringsSep "\n          " dryRunListSnippet repos}
        else
          # 各 repo を dest 未存在時のみ clone(既存 working tree は触らない・pull もしない)。
          ${lib.concatMapStringsSep "\n\n          " (
            r: "(\n            ${cloneRepoSnippet r}\n          )"
          ) repos}
        fi
      '';
    })
  ];
}
