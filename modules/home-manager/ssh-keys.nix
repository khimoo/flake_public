# 全マシン共通の SSH 鍵を secrets/secrets.yaml から復元する。
#
# 鍵は用途で名付ける。アルゴリズム名(id_ed25519)だと 1 ファイルに複数の役割が同居しても
# 気づけず、片方を rotate したときにもう片方を巻き込む:
#   ~/.ssh/id_github … GitHub 認証(clone/push)。private-repos.nix の clone が使う
#   ~/.ssh/id_lan    … LAN 内 machine-to-machine。hosts/machines.nix の lanPublicKey と対
#
# 復号の種は専用 age 鍵 1 本(~/.config/sops/age/keys.txt)。これを out-of-band で置くことだけが
# 新マシンの手作業で、鍵の実体は switch が書き出す。
#
# どの鍵を配るかは settings.sshKeys = [{ secret, name }] で受ける。空リスト(既定)なら
# activation 自体が生えない。
{ config, lib, pkgs, settings, ... }:

let
  keys = settings.sshKeys or [];
  enable = keys != [];

  home = config.home.homeDirectory;
  ageKeyFile = "${home}/.config/sops/age/keys.txt";

  # コミット済みの暗号文。store path になる(暗号化済みなので world-readable でも安全)。
  secretsFile = ../../secrets/secrets.yaml;

  # 既存ファイルは上書きしない(非破壊)。手で差し替えたい場合は消してから switch する。
  #
  # 復号は一時ファイル経由。dest へ直接リダイレクトすると、sops が失敗しても空の dest が
  # 残り、次の switch が「もうある」と判定して二度と復号し直さない(壊れた鍵が固定される)。
  extractSnippet = { secret, name }: ''
    dest=${lib.escapeShellArg "${home}/.ssh/${name}"}
    if [ ! -f "$dest" ]; then
      tmp="$dest.tmp.$$"
      if ! ( umask 077
             SOPS_AGE_KEY_FILE="$age_key" \
               ${pkgs.sops}/bin/sops --decrypt --extract '["${secret}"]' "$secrets" > "$tmp" ); then
        rm -f "$tmp"
        echo "ssh-keys: ${secret} の復号に失敗した。$age_key がこの暗号文の受信者か確認する" >&2
        exit 1
      fi
      mv "$tmp" "$dest"
    fi
  '';

  dryRunSnippet = { secret, name }:
    "echo 'ssh-keys: (dry-run) ${secret} を ~/.ssh/${name} へ書き出す予定' >&2";
in
{
  config = lib.mkIf enable {
    home.activation.sshKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      age_key=${lib.escapeShellArg ageKeyFile}
      secrets=${lib.escapeShellArg (toString secretsFile)}

      mkdir -p ${lib.escapeShellArg "${home}/.ssh"}

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        # dry-run 時は鍵ファイルを絶対に触らない(リダイレクトは DRY_RUN_CMD で包めないため)。
        ${lib.concatMapStringsSep "\n        " dryRunSnippet keys}
      elif [ ! -f "$age_key" ]; then
        # 復号の種が無ければ何も進められない。ここで止めないと「switch は成功したのに鍵が無い」
        # 状態が黙って出来上がり、後続の clone や LAN SSH が原因の分かりにくい形で失敗する。
        echo "ssh-keys: age 復号鍵 $age_key が無い。" >&2
        echo "  既存マシンから送る: ( umask 077; ssh <既存機> 'cat ~/.config/sops/age/keys.txt' > $age_key )" >&2
        echo "  または Bitwarden から取り出して同じパスに 600 で置く。" >&2
        exit 1
      else
        ${lib.concatMapStringsSep "\n\n        " (k: "(\n          ${extractSnippet k}\n        )") keys}
      fi
    '';
  };
}
