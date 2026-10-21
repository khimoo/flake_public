# 全マシン共通の秘密を secrets/secrets.yaml に揃える。
# sshKeys は ~/.ssh へ 600 で置く短い入口で、ここで一般の secrets と同じ items へ変換する。
# switch のたびに復号し、手で置いた・書き換えた通常のファイルも暗号文の内容へ戻す。
# 配置したパスだけを記録し、宣言から外した秘密は消す。symlink などは警告して触らない。
# 宣言が空でも記録の削除を行うが、この場合は age 鍵を必要としない。
{ config, lib, pkgs, ... }:

let
  home = config.home.homeDirectory;
  fromSshKeys = map (k: {
    inherit (k) secret;
    path = "${home}/.ssh/${k.name}";
    mode = "600";
  }) config.local.profile.sshKeys;
  items = fromSshKeys ++ config.local.profile.secrets;
  ageKeyFile = "${home}/.config/sops/age/keys.txt";
  secretsFile = ../../secrets/secrets.yaml;
  stateDir = "${config.xdg.stateHome}/flake-secrets";

  ageKeyMissing = ''
    echo "secrets: age 復号鍵 $age_key が無い。" >&2
    echo "  既存マシンから送る: ( umask 077; ssh <既存機> 'cat ~/.config/sops/age/keys.txt' > $age_key )" >&2
    echo "  または Bitwarden から取り出して同じパスに 600 で置く。" >&2
  '';

  extractSnippet = { secret, path, mode }: ''
    dest=${lib.escapeShellArg path}
    if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
      echo "secrets: $dest: 通常のファイルでないので触らない" >&2
    else
      mkdir -p "$(dirname "$dest")"
      pending_tmp=$(umask 077; mktemp "$dest.XXXXXX")
      if ! ( umask 077
             SOPS_AGE_KEY_FILE="$age_key" \
               ${pkgs.sops}/bin/sops --decrypt --extract ${lib.escapeShellArg (builtins.toJSON [ secret ])} "$secrets" < /dev/null > "$pending_tmp" ); then
        echo "secrets: ${secret} の復号に失敗した。$age_key がこの暗号文の受信者か確認する" >&2
        exit 1
      fi
      if [ -f "$dest" ] && cmp -s -- "$pending_tmp" "$dest"; then
        chmod ${lib.escapeShellArg mode} "$dest"
      else
        chmod ${lib.escapeShellArg mode} "$pending_tmp"
        mv -f -- "$pending_tmp" "$dest"
      fi
      rm -f -- "$pending_tmp"
      pending_tmp=
      printf '%s\n' "$dest" >> "$state_tmp"
    fi
  '';
in
{
  home.activation.secrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      state_file=${lib.escapeShellArg "${stateDir}/placed"}
      declared=(${lib.concatMapStringsSep " " (i: lib.escapeShellArg i.path) items})
      dry_run=''${DRY_RUN_CMD:-}
      ${lib.optionalString (items != [ ]) ''
        age_key=${lib.escapeShellArg ageKeyFile}
        # 暗号文を単独で store にコピーし、世代の closure に入れる。起動時の activation も毎回復号するので、
        # GC で flake のソースが消えても読めるようにする。
        secrets=${lib.escapeShellArg "${secretsFile}"}
        if [ -z "$dry_run" ] && [ ! -f "$age_key" ]; then
          ${ageKeyMissing}
          exit 1
        fi
      ''}
      # 空の宣言で記録も無い場合は、ディレクトリすら作らない。
      if [ "''${#declared[@]}" = 0 ] && [ ! -f "$state_file" ]; then
        exit 0
      fi
      pending_tmp=
      state_tmp=
      trap 'rm -f -- "$pending_tmp" "$state_tmp"' EXIT
      trap 'exit 1' HUP INT TERM
      if [ -n "$dry_run" ]; then
        for dest in "''${declared[@]}"; do
          echo "secrets: (dry-run) $dest を暗号文に揃える予定" >&2
        done
      else
        mkdir -p "$(dirname "$state_file")"
        state_tmp=$(umask 077; mktemp "$state_file.XXXXXX")
        ${lib.concatMapStringsSep "\n" extractSnippet items}
      fi
      if [ -f "$state_file" ]; then
        while IFS= read -r dest; do
          is_declared=
          for path in "''${declared[@]}"; do
            if [ "$dest" = "$path" ]; then
              is_declared=1
              break
            fi
          done
          [ -z "$is_declared" ] || continue
          if [ -n "$dry_run" ]; then
            echo "secrets: (dry-run) $dest: 宣言から外れたので削除予定" >&2
          elif [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
            echo "secrets: $dest: 通常のファイルでないので削除せず記録から外す" >&2
          else
            rm -f -- "$dest"
          fi
        done < "$state_file"
      fi
      if [ -z "$dry_run" ]; then
        mv -f -- "$state_tmp" "$state_file"
        state_tmp=
      fi
    )
  '';
}
