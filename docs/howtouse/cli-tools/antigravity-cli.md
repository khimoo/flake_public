# Antigravity CLI（agy）

Google の Antigravity CLI を `agy` として入れる。
agents-private の gemini-proofread スキルが、Gemini の API で校正できないときと、Gemini 3.8 を指定されたときに使う。
パッケージは [packages/antigravity-cli](../../../packages/antigravity-cli/default.nix) で、x86_64-linux では [profiles/home/pomu.nix](../../../profiles/home/pomu.nix) から入る。
設計判断は [architecture/antigravity-cli.md](../../architecture/antigravity-cli.md)。

## ログイン

引数なしで起動し、ブラウザで Google アカウントにログインする。

```bash
agy
```

ログイン情報は `~/.gemini/antigravity-cli/` に保存される。Nix store や Git には入れない。

## 枠の残量を見る

モデルを呼ばずに、週の枠の残量とリセットの時刻を表示する。

```bash
agy -p /quota
```

## 版を上げる

1. マニフェストを取得する。

   ```bash
   curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
   ```

2. `packages/antigravity-cli/default.nix` の `version`、`url`、`sha512` を、マニフェストの値に書き換える。
3. `nix build .#antigravity-cli` を実行し、インストール時の確認（`agy --version` が `version` と一致すること）が通るのを確かめる。

agy は自分で自分を更新しようとするが、Nix store には書き込めないので失敗する。版はここで固定した値から変わらない。
