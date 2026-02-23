# OpenClaw シークレットの「中身の例」
#
# このファイルを「どの Git リポジトリにも含めず」ローカルに置いて使います。
# 例: ~/.secrets/openclaw-secrets.nix にコピーし、値を埋めてから:
#
#   OPENCLAW_SECRETS_NIX=$HOME/.secrets/openclaw-secrets.nix \
#     nixos-rebuild switch --flake '.#nixos-desktop' --impure
#
# 公開・非公開を問わず、リポジトリにはキーを置かないでください。

{
  gatewayToken = "openssl rand -hex 32 で生成したトークン";
  telegramAllowFrom = [ 12345678 ];  # @userinfobot で取得した自分の Telegram ID
  # 省略時は ~/.secrets/telegram-bot-token を使用
  # telegramTokenFile = "/home/you/.secrets/telegram-bot-token";
}
