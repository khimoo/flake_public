# OpenClaw シークレット設定

nix-openclaw を動かす前に、以下のシークレットを用意してください。

**重要**: キーは **どの Git リポジトリにも置きません**（公開・非公開どちらも）。ローカルだけのファイル（例: `~/.secrets/openclaw-secrets.nix`）に書き、環境変数でそのパスを Nix に渡します。

## 1. シークレットの置き場所（リポジトリ外のローカルファイル）

1. このリポジトリの `hosts/nixos-desktop/openclaw-secrets.example.nix` を **リポジトリ外**（例: `~/.secrets/openclaw-secrets.nix`）にコピーする。
2. そのファイルを編集して、`gatewayToken` と `telegramAllowFrom` を実際の値に書き換える。
3. ビルド・適用時は、そのファイルの絶対パスを環境変数で渡し、**`--impure`** を付けて実行する:

   ```bash
   OPENCLAW_SECRETS_NIX=$HOME/.secrets/openclaw-secrets.nix \
     nixos-rebuild switch --flake '.#nixos-desktop' --impure
   ```

`OPENCLAW_SECRETS_NIX` を渡さない、またはファイルが存在しない場合は OpenClaw 用のトークン・allowFrom は空になり、サービスは動作しません。

## 2. シークレット用ディレクトリ

```bash
mkdir -p ~/.secrets
chmod 700 ~/.secrets
```

## 3. Gateway 認証トークン

- 上記ローカルファイル（`openclaw-secrets.nix`）の `gatewayToken` に、長いランダムトークンを書く。
- 生成例: `openssl rand -hex 32`

## 4. Telegram Bot トークン

1. Telegram で [@BotFather](https://t.me/BotFather) を開く
2. `/newbot` でボットを作成し、表示されたトークンをコピー
3. トークンをファイルに保存（`openclaw-secrets.nix` で `telegramTokenFile` を省略した場合は `~/.secrets/telegram-bot-token`）:
   ```bash
   echo -n 'YOUR_BOT_TOKEN' > ~/.secrets/telegram-bot-token
   chmod 600 ~/.secrets/telegram-bot-token
   ```

## 5. Telegram ユーザー ID

1. Telegram で [@userinfobot](https://t.me/userinfobot) を開く
2. 表示された「Id」の数字をコピー
3. ローカルファイルの `telegramAllowFrom = [ あなたのID ];` に設定

## 6. Anthropic API キー（Claude 用）

**Nix の store や Git に入れず**、環境変数または .env で渡します。

- ユーザー systemd の環境で `ANTHROPIC_API_KEY` を設定する。
- 例: `~/.config/environment.d/openclaw.conf` に `ANTHROPIC_API_KEY=sk-ant-...` を書き、systemd の user セッションで読み込む。
- または `~/.openclaw/.env` に `ANTHROPIC_API_KEY=sk-ant-...` を記載（daemon が読む場合）。

Anthropic キー取得: https://console.anthropic.com/

## チェックリスト

- [ ] `~/.secrets/openclaw-secrets.nix` を用意（example をコピーして値を埋める）
- [ ] `~/.secrets` 作成・パーミッション 700
- [ ] `~/.secrets/telegram-bot-token` に BotFather のトークンを保存・chmod 600
- [ ] 適用時は `OPENCLAW_SECRETS_NIX=... nixos-rebuild switch --flake ... --impure`
- [ ] Anthropic API キーを環境変数または `.env` で設定

## 適用とサービス確認

1. **ビルド・適用**（nixos-desktop の場合）:
   ```bash
   cd /path/to/flake_public
   OPENCLAW_SECRETS_NIX=$HOME/.secrets/openclaw-secrets.nix \
     nixos-rebuild switch --flake '.#nixos-desktop' --impure
   ```
   - シークレットをリポジトリ外のファイルから読むため `OPENCLAW_SECRETS_NIX` と `--impure` が必要です。
   - 初回は openclaw のビルドで時間がかかることがあります。

2. **systemd ユーザーサービスの確認**:
   ```bash
   systemctl --user status openclaw-gateway
   journalctl --user -u openclaw-gateway -f
   ```

3. **起動していない場合**:
   - シークレット（gateway token, Telegram token, allowFrom）が正しいか確認
   - `~/.secrets/telegram-bot-token` が存在し、中身が BotFather のトークンと一致しているか確認
   - ログでエラー内容を確認: `journalctl --user -u openclaw-gateway -n 100 --no-pager`
