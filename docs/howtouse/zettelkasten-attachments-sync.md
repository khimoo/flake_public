# Zettelkasten の Google Drive 同期（使い方）

vault 直下の `attachments/`（添付）と `references/`（papis ライブラリ）を Google Drive と
双方向同期する。実体はローカルにも残し、rclone bisync でミラーする。git には blob を載せない
（vault の `.gitignore` が両方を除外している）。

同期の入口は `zettelkasten-sync` 1 本。何が同期されるかは home-manager の options が決める。
papis 固有の使い方は [papis-gdrive-sync.md](./papis-gdrive-sync.md) を参照。
設計判断は [../architecture/zettelkasten-attachments-sync.md](../architecture/zettelkasten-attachments-sync.md) を参照。

## 対応環境

| feature | 同期対象 | Drive 側 |
|---|---|---|
| `zettelkastenSync` | `<vault>/attachments` | `gdrive:zettelkasten-attachments` |
| `referenceSync` | `<vault>/references` | `gdrive:papis-library` |

NixOS ホスト（`nixos-desktop`, `nixos-spin713`）は両方有効。standalone home-manager は
`mkHome` の `features` で個別に有効化する。偽の環境（WSL 等）では一切読み込まれない。

## 認証（rclone）

Google Drive の OAuth トークンは宣言的に作れないので、**各マシンの
`~/.config/rclone/rclone.conf` に委ねる**。flake_public も workflow repo も認証情報を持たない
（以前は sops で暗号化した rclone.conf を workflow repo に置いていたが、廃止した）。

remote 名は `gdrive`（`services.zettelkasten.rcloneRemote` の既定）。

## 新しいマシンのセットアップ

```sh
# 1. switch する（vault が clone され、Obsidian 設定が配置され、同期の unit が入る）
sudo nixos-rebuild switch --flake .#<hostname>

# 2. 残りを対話で片付ける
zettelkasten-setup
```

`zettelkasten-setup` が聞くのは 2 つだけ:

1. **Google Drive との接続確認** — remote `gdrive` に繋がらなければ `rclone config` を開く。
   remote 名は `gdrive` にすること（options と一致していないと動かない）。
   `Storage` は `drive`、`scope` は **`drive.file`**（フルの `drive` にしない。漏洩時の被害を
   rclone が作ったファイルに限定する）。他は既定のままでよい。
2. **初回同期** — そのまま `zettelkasten-sync` を実行する。

途中で止めても、もう一度実行すれば済んだところは飛ばす。進捗ファイルは持たず、実物
（rclone remote / bisync の記録）を見て判断する。

### 初回同期の挙動

bisync は「同期の記録」（baseline）が無い初回だけ `--resync` が要る。記録が無いときの
分岐は自動で、手で `--resync` を打つ必要は無い:

| ローカル | Drive | 挙動 |
|---|---|---|
| 何でも | 空 / 未作成 | Drive 側にフォルダを作って resync する |
| 空 | データあり | Drive の内容を取り込む（失うものが無いので自動） |
| データあり | データあり | **止まる**。中身の違う 2 つを合流させようとしている可能性があるため |

最後のケースだけ、Drive の中身を確認したうえで明示的に実行する:

```sh
ZK_FORCE_RESYNC=1 zettelkasten-sync --resync
```

## 日常運用

同期は自動で走る。ローカルの変更を検知する経路と、取りこぼしを拾う定期実行（既定 15 分）の
2 本立て。他マシンの追加は、次に自分が同期したときに pull される（リアルタイムではない）。

手で走らせるとき:

```sh
zettelkasten-sync                 # 設定どおり全部
zettelkasten-sync --only papis    # papis だけ
zettelkasten-sync --dry-run       # 以降の引数は rclone bisync へ素通し
```

同期先は options が持っていて、引数では変えられない。

ログ:

```sh
journalctl --user -u zettelkasten-sync -f     # 添付（Linux）
journalctl --user -u papis-sync -f            # papis（Linux）
# macOS: ~/Library/Logs/{zettelkasten-sync,papis-sync}.log
```

削除は双方向に伝播する。安全網は Drive のゴミ箱（30 日は復元可）と bisync の `--max-delete`
（既定 50% 超で中断）。

## 添付を貼る

- Obsidian: 通常どおり貼り付ける（`attachmentFolderPath=attachments` に保存される）
- Neovim: Markdown で `<leader>p`（img-clip が vault ルートの `attachments/` に保存）

どちらも同じ 1 フォルダに着地する
（[markdown プラグインのドキュメント](../../modules/home-manager/dev/neovim/config/docs/plugins/markdown.md)）。

## トラブルシューティング

エラーは復旧手順つきで出るので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `remote 'gdrive' が未定義です` | `rclone config` で remote を作る（`zettelkasten-setup` が案内する） |
| `認証に失敗しました` | token 失効。`rclone config reconnect gdrive:` |
| `両側にデータがあります` | 記録の喪失か、別々の中身を合流させようとしている。確認して `ZK_FORCE_RESYNC=1 zettelkasten-sync --resync` |
| `--resync が中止される` | 記録が既存（誤上書き防止）。意図的なら `ZK_FORCE_RESYNC=1` |
| unit が inactive のまま | 対象ディレクトリが未作成。`ConditionPathIsDirectory` で skip される（失敗ではない） |
| `.conflict` ファイルが出る | 2 台が同時に更新した。中身を見て正しい方を残す |
| token 書き戻しの warning | rclone が refresh 後の access token を書き戻すだけ。refresh token は長命なので無視してよい |
