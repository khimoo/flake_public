# 全マシン共通の秘密を secrets/secrets.yaml から復元する。
#
# 入口は 2 つ。SSH 鍵は用途で名付けて ~/.ssh へ 600 で置くので
# config.local.profile.sshKeys = [{ secret, name }] という短い入口を保つ。それ以外は
# config.local.profile.secrets = [{ secret, path, mode }] で置き先を明示する。
# 復号の実装はこのファイルに 1 つだけ持ち、前者はここで後者へ変換する。
#
# 鍵は用途で名付ける。アルゴリズム名(id_ed25519)だと 1 ファイルに複数の役割が同居しても
# 気づけず、片方を rotate したときにもう片方を巻き込む:
#   ~/.ssh/id_github … GitHub 認証(clone/push)。clone-repos と pull-repos が使う
#   ~/.ssh/id_lan    … LAN 内 machine-to-machine。hosts/machines.nix の lanPublicKey と対
#
# 復号の種は専用 age 鍵 1 本(~/.config/sops/age/keys.txt)。これを out-of-band で置くことだけが
# 新マシンの手作業で、秘密の実体は switch が書き出す。
#
# switch は無いファイルを置くだけで、既存のファイルを上書きしない。置いたファイルは内容の
# sha256 を記録し、暗号文の差し替えや宣言の削除は update-secrets で反映する。記録と内容が
# 一致するファイルだけを更新・削除するので、手で置いた・手で変えたファイルは触らない。
#
# どちらの入口も空(既定)なら activation も update-secrets も生えない。
{ config, lib, pkgs, ... }:

let
  home = config.home.homeDirectory;

  fromSshKeys = map (k: {
    inherit (k) secret;
    path = "${home}/.ssh/${k.name}";
    mode = "600";
  }) config.local.profile.sshKeys;

  items = fromSshKeys ++ config.local.profile.secrets;
  enable = items != [ ];

  ageKeyFile = "${home}/.config/sops/age/keys.txt";

  # コミット済みの暗号文。flake のソース内のパスを文字列で参照する。
  secretsFile = ../../secrets/secrets.yaml;

  # 記録は「sha256<TAB>path」の 1 行 1 ファイルで、path の順に並べる。秘密の中身は書かない。
  stateDir = "${config.xdg.stateHome}/flake-secrets";

  ageKeyMissing = ''
    echo "secrets: age 復号鍵 $age_key が無い。" >&2
    echo "  既存マシンから送る: ( umask 077; ssh <既存機> 'cat ~/.config/sops/age/keys.txt' > $age_key )" >&2
    echo "  または Bitwarden から取り出して同じパスに 600 で置く。" >&2
  '';

  # activation と update-secrets が共有する記録の読み書き。呼び出し側が lock を取ってから使う。
  # awk の -v はバックスラッシュを解釈するので、パスは環境変数で渡す。
  stateLib = ''
    age_key=${lib.escapeShellArg ageKeyFile}
    secrets=${lib.escapeShellArg (toString secretsFile)}
    state_dir=${lib.escapeShellArg stateDir}
    state_file="$state_dir/managed"

    hash_of() {
      sha256sum "$1" | cut -d ' ' -f 1
    }

    record_of() {
      [ -f "$state_file" ] || return 0
      P=$1 awk -F '\t' '$2 == ENVIRON["P"] { print $1 }' "$state_file"
    }

    # $1 のパスの行を除き、$2 が空でなければ「$2<TAB>$1」を足して書き直す。
    write_record() {
      local tmp
      mkdir -p "$state_dir"
      tmp=$(mktemp "$state_file.XXXXXX")
      {
        if [ -f "$state_file" ]; then
          P=$1 awk -F '\t' '$2 != ENVIRON["P"]' "$state_file"
        fi
        if [ -n "$2" ]; then
          printf '%s\t%s\n' "$2" "$1"
        fi
      } | sort -t "$(printf '\t')" -k 2,2 > "$tmp"
      mv "$tmp" "$state_file"
    }
  '';

  # 既存ファイルは上書きしない(非破壊)。置いたファイルだけ記録する。
  #
  # 復号は一時ファイル経由。dest へ直接リダイレクトすると、sops が失敗しても空の dest が
  # 残り、次の switch が「もうある」と判定して二度と復号し直さない(壊れた秘密が固定される)。
  extractSnippet =
    { secret, path, mode }:
    ''
      dest=${lib.escapeShellArg path}
      if [ ! -f "$dest" ]; then
        mkdir -p "$(dirname "$dest")"
        tmp="$dest.tmp.$$"
        if ! ( umask 077
               SOPS_AGE_KEY_FILE="$age_key" \
                 ${pkgs.sops}/bin/sops --decrypt --extract '["${secret}"]' "$secrets" > "$tmp" ); then
          rm -f "$tmp"
          echo "secrets: ${secret} の復号に失敗した。$age_key がこの暗号文の受信者か確認する" >&2
          exit 1
        fi
        chmod ${mode} "$tmp"
        mv "$tmp" "$dest"
        write_record "$dest" "$(hash_of "$dest")"
      fi
    '';

  dryRunSnippet =
    { secret, path, ... }: "echo 'secrets: (dry-run) ${secret} を ${path} へ書き出す予定' >&2";

  # 宣言を「secret<TAB>path<TAB>mode」の行にして渡す。secret 名と mode は型で記号を含まない。
  declarations = lib.concatMapStrings (i: "${i.secret}\t${i.path}\t${i.mode}\n") items;

  updateText = ''
    dry_run=0
    if [ "''${1:-}" = "--dry-run" ]; then
      dry_run=1
    fi
    ${stateLib}
    if [ ! -f "$age_key" ]; then
      ${ageKeyMissing}
      exit 1
    fi

    mkdir -p "$state_dir"
    exec 9> "$state_dir/lock"
    flock 9

    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    status=0
    declared=$work/declared
    : > "$declared"

    say() {
      echo "update-secrets: $*"
    }
    warn() {
      echo "update-secrets: $*" >&2
    }

    # dry-run では記録を作業用の写しに書き、最後に捨てる。
    if [ "$dry_run" = 1 ] && [ -f "$state_file" ]; then
      cp "$state_file" "$work/managed"
    fi
    if [ "$dry_run" = 1 ]; then
      state_file=$work/managed
    fi

    update() {
      local secret=$1 dest=$2 mode=$3 tmp new current recorded
      printf '%s\n' "$dest" >> "$declared"
      if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
        warn "$dest: 通常のファイルでないので触らない"
        return 0
      fi
      if [ "$dry_run" = 1 ]; then
        tmp=$work/plain
      else
        mkdir -p "$(dirname "$dest")"
        tmp=$(mktemp "$dest.XXXXXX")
      fi
      if ! ( umask 077
             SOPS_AGE_KEY_FILE="$age_key" sops --decrypt --extract "[\"$secret\"]" "$secrets" < /dev/null > "$tmp" ); then
        rm -f "$tmp"
        warn "$secret の復号に失敗した。$age_key がこの暗号文の受信者か確認する"
        status=1
        return 0
      fi
      new=$(hash_of "$tmp")
      recorded=$(record_of "$dest")

      if [ ! -e "$dest" ]; then
        say "$dest: 配置"
        if [ "$dry_run" = 0 ]; then
          chmod "$mode" "$tmp"
          mv "$tmp" "$dest"
        fi
        write_record "$dest" "$new"
        rm -f "$tmp"
        return 0
      fi

      current=$(hash_of "$dest")
      if [ -n "$recorded" ] && [ "$current" = "$recorded" ] && [ "$current" != "$new" ]; then
        say "$dest: 更新"
        if [ "$dry_run" = 0 ]; then
          chmod "$mode" "$tmp"
          mv -f "$tmp" "$dest"
        fi
        write_record "$dest" "$new"
      elif [ "$current" = "$new" ]; then
        # 内容は宣言どおり。記録がない、または古いときは記録だけを合わせる。
        if [ "$recorded" != "$new" ]; then
          say "$dest: 内容が宣言と同じなので管理に入れる"
          write_record "$dest" "$new"
        fi
        if [ "$dry_run" = 0 ]; then
          chmod "$mode" "$dest"
        fi
      elif [ -n "$recorded" ]; then
        warn "$dest: 前回置いた後に変更されているので触らない"
      else
        warn "$dest: この flake が置いたファイルではないので触らない"
      fi
      rm -f "$tmp"
    }

    while IFS="$(printf '\t')" read -r secret dest mode; do
      update "$secret" "$dest" "$mode"
    done <<'DECLARATIONS'
    ${declarations}DECLARATIONS

    # 記録にあって宣言にないファイル。前回置いたままのものだけを消す。
    if [ -f "$state_file" ]; then
      cp "$state_file" "$work/before"
      while IFS="$(printf '\t')" read -r recorded dest; do
        if grep -q -x -F -- "$dest" "$declared"; then
          continue
        fi
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
          write_record "$dest" ""
        elif [ -f "$dest" ] && [ ! -L "$dest" ] && [ "$(hash_of "$dest")" = "$recorded" ]; then
          say "$dest: 宣言から外れたので削除"
          if [ "$dry_run" = 0 ]; then
            rm -f -- "$dest"
          fi
          write_record "$dest" ""
        else
          warn "$dest: 宣言から外れたが、前回置いた後に変更されているので残す"
          write_record "$dest" ""
        fi
      done < "$work/before"
    fi

    exit "$status"
  '';

  updateSecrets = pkgs.writeShellApplication {
    name = "update-secrets";
    runtimeInputs = [
      pkgs.sops
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.flock
    ];
    text = updateText;
    # tests/default.nix が偽の sops で本文を実行する。
    passthru.text = updateText;
  };
in
{
  config = lib.mkIf enable {
    home.packages = [ updateSecrets ];
    home.extraActivationPath = [
      pkgs.gawk
      pkgs.flock
    ];

    home.activation.secrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${stateLib}

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        # dry-run 時はファイルを絶対に触らない(リダイレクトは DRY_RUN_CMD で包めないため)。
        ${lib.concatMapStringsSep "\n        " dryRunSnippet items}
      elif [ ! -f "$age_key" ]; then
        # 復号の種が無ければ何も進められない。ここで止めないと「switch は成功したのに秘密が無い」
        # 状態が黙って出来上がり、後続の clone や LAN SSH が原因の分かりにくい形で失敗する。
        ${ageKeyMissing}
        exit 1
      else
        mkdir -p "$state_dir"
        (
          flock 9
          ${lib.concatMapStringsSep "\n\n          " (k: "(\n            ${extractSnippet k}\n          )") items}
        ) 9> "$state_dir/lock"
      fi
    '';
  };
}
