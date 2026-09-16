# 全マシン共通の秘密を secrets/secrets.yaml から復元する。
#
# 入口は 2 つ。SSH 鍵は用途で名付けて ~/.ssh へ 600 で置くので
# config.local.profile.sshKeys = [{ secret, name }] という短い入口を保つ。それ以外は
# config.local.profile.secrets = [{ secret, path, mode }] で置き先を明示する。
# 復号の実装はこのファイルに 1 つだけ持ち、前者はここで後者へ変換する。
#
# 鍵は用途で名付ける。アルゴリズム名(id_ed25519)だと 1 ファイルに複数の役割が同居しても
# 気づけず、片方を rotate したときにもう片方を巻き込む:
#   ~/.ssh/id_github … GitHub 認証(clone/push)。private-repos.nix の clone が使う
#   ~/.ssh/id_lan    … LAN 内 machine-to-machine。hosts/machines.nix の lanPublicKey と対
#
# 復号の種は専用 age 鍵 1 本(~/.config/sops/age/keys.txt)。これを out-of-band で置くことだけが
# 新マシンの手作業で、秘密の実体は switch が書き出す。
#
# どちらの入口も空(既定)なら activation 自体が生えない。
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

  # コミット済みの暗号文。store path になる(暗号化済みなので world-readable でも安全)。
  secretsFile = ../../secrets/secrets.yaml;

  # 既存ファイルは上書きしない(非破壊)。手で差し替えたい場合は消してから switch する。
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
      fi
    '';

  dryRunSnippet =
    { secret, path, ... }: "echo 'secrets: (dry-run) ${secret} を ${path} へ書き出す予定' >&2";
in
{
  config = lib.mkIf enable {
    home.activation.secrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      age_key=${lib.escapeShellArg ageKeyFile}
      secrets=${lib.escapeShellArg (toString secretsFile)}

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        # dry-run 時はファイルを絶対に触らない(リダイレクトは DRY_RUN_CMD で包めないため)。
        ${lib.concatMapStringsSep "\n        " dryRunSnippet items}
      elif [ ! -f "$age_key" ]; then
        # 復号の種が無ければ何も進められない。ここで止めないと「switch は成功したのに秘密が無い」
        # 状態が黙って出来上がり、後続の clone や LAN SSH が原因の分かりにくい形で失敗する。
        echo "secrets: age 復号鍵 $age_key が無い。" >&2
        echo "  既存マシンから送る: ( umask 077; ssh <既存機> 'cat ~/.config/sops/age/keys.txt' > $age_key )" >&2
        echo "  または Bitwarden から取り出して同じパスに 600 で置く。" >&2
        exit 1
      else
        ${lib.concatMapStringsSep "\n\n        " (k: "(\n          ${extractSnippet k}\n        )") items}
      fi
    '';
  };
}
