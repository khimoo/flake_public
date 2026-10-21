# private repo の初回 clone（clone-repos）と、その後の更新（pull-repos）のコマンド。
# 環境の適用（switch）にはネットワークの取得を含めない。新しいマシンでは switch で鍵が置かれた後に
# clone-repos を一度実行する。NixOS でも macOS の Home Manager でも同じコマンドを使う。
#
# 認証に使う ~/.ssh/id_github は secrets.nix が secrets.yaml から書き出す。このモジュールは
# 復号を知らず、鍵が置かれているかを clone の前に確かめるだけにする。
#
# 対象 repo は config.local.profile.privateRepos = [{ url, dest }] で受ける。空リスト(既定)なら
# clone-repos は入らない。個々の (url, dest) は profile.nix 側で agentConfig* / vaultSkeletonRepo* 等の
# 高レベル設定から組み立てる (dest だけ指定・URL 未指定は手動 clone のまま = 抜き差し可能)。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  repos = config.local.profile.privateRepos;

  home = config.home.homeDirectory;
  sshKey = "${home}/.ssh/id_github";

  # git/ssh を絶対パスで呼ぶのは、GIT_SSH_COMMAND が PATH と無関係に解釈されるため。
  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${sshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";

  # 完成したcloneだけをdestへ移す。失敗した一時cloneを次回の成功判定に使わない。
  # 1 つ失敗しても残りは回し、最後にまとめて非ゼロを返す。
  cloneText = ''
    dry_run=0
    if [ "''${1:-}" = "--dry-run" ]; then
      dry_run=1
    fi

    clone() {
      local repo=$1 dest=$2 parent clone_tmp
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ ! -e "$dest/.git" ]; then
          echo "clone-repos: $dest exists but is not a Git checkout; inspect it before retrying" >&2
          return 1
        fi
        return 0
      fi
      if [ "$dry_run" = 1 ]; then
        echo "clone-repos: (dry-run) $repo を $dest へ clone する予定" >&2
        return 0
      fi
      parent=$(dirname "$dest")
      if ! mkdir -p "$parent"; then
        return 1
      fi
      if ! clone_tmp=$(mktemp -d "$parent/.private-clone.XXXXXX"); then
        return 1
      fi
      if ! GIT_SSH_COMMAND=${lib.escapeShellArg gitSshCommand} git clone "$repo" "$clone_tmp/repo"; then
        rm -rf -- "$clone_tmp"
        return 1
      fi
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        rm -rf -- "$clone_tmp"
        echo "clone-repos: $dest appeared during clone; refusing to overwrite" >&2
        return 1
      fi
      if ! mv "$clone_tmp/repo" "$dest"; then
        echo "clone-repos: failed to move checkout to $dest" >&2
        rm -rf -- "$clone_tmp"
        return 1
      fi
      rm -rf -- "$clone_tmp"
    }

    if [ "$dry_run" = 0 ] && [ ! -f ${lib.escapeShellArg sshKey} ]; then
      echo "clone-repos: ${sshKey} がない。switch で secrets が配置されたか確認する" >&2
      exit 1
    fi

    status=0
    ${lib.concatMapStringsSep "\n" (
      r: "clone ${lib.escapeShellArg r.url} ${lib.escapeShellArg r.dest} || status=1"
    ) repos}
    exit "$status"
  '';

  cloneRepos = pkgs.writeShellApplication {
    name = "clone-repos";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = cloneText;
    # tests/default.nix が偽の git で本文を実行する。
    passthru.text = cloneText;
  };

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
      # 配列にしておくと、private repo がなく対象が flake 自身だけのときも shellcheck の SC2043 にならない。
      targets=(${lib.escapeShellArgs pullTargets})
      for dest in "''${targets[@]}"; do
        if [ ! -e "$dest/.git" ]; then
          echo "pull-repos: $dest は clone されていない (clone-repos で clone する)" >&2
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
  home.packages = [ pullRepos ] ++ lib.optional (repos != [ ]) cloneRepos;
}
