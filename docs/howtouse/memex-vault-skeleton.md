# vault 骨格の配布とミラーリング

Obsidian vault の基本骨格（分類用フォルダ構造、運用ドキュメントである `Home.md`、`AGENTS.md`、`CLAUDE.md`、`Templates/`、`System/Bases/`、`.obsidian`、および `.agents/skills/` と `.claude/skills` のシンボリックリンク群）を、公開リポジトリである memex-nix でも追跡・共有できるようにするための手順です。
個々のノート本文は骨格には含まれません。desktop と spin713 の間の実データ同期は、vault のプライベートリポジトリを通じた `obsidian-git` が担います。

- mirror: vault 側の運用や設定を変更した際に、公開リポジトリの `skeleton/` へ手動で同期してコミットする操作です。
- seed: vault を新規作成する初期環境（`initializeVault = true`）にのみ骨格を展開する機能です。既存の vault を clone して利用する本環境では使用しません。

設計ドキュメント: [vault の骨格の設計](../architecture/memex-vault-skeleton.md)
※ 添付ファイルや papis の Google Drive 同期は別の仕組みで管理されています（[memex-attachments-sync.md](./memex-attachments-sync.md) 参照）。

## mirror: vault の骨格を公開リポジトリへ反映する

プラグイン設定、運用ルール、テンプレート、フォルダ構成などを変更し、配布用の骨格にもその内容を反映させたい場合に実行します。新規マシンを追加する際にはこの作業は不要です。
`mirror-vault` コマンドは、`local.profile.vaultSkeletonRepo` を設定したユーザー環境にのみインストールされます。vault のパスと同期先リポジトリはデフォルトで設定されているため、通常は引数なしで実行可能です。

```sh
mirror-vault --dry-run   # コミットを行わず差分のみ確認する
mirror-vault             # rsync で同期してコミットする（push は行わない）
git -C ~/sagyo/memex-nix diff HEAD~1   # 意図しない秘密情報が含まれていないか確認する
git -C ~/sagyo/memex-nix push
mirror-vault --push      # コミットから push まで一括で実行する
```

デフォルトで自動 push しない理由は、`.obsidian` 内のファイルをブラックリスト（除外リスト）形式で管理しているためです。新しく導入したプラグインが `data.json` 内に機密情報を書き込んだ場合、意図せず公開されてしまうリスクがあります。必ず push 前に `git diff` で差分を確認してください（詳細は [設計ドキュメント](../architecture/memex-vault-skeleton.md#配るものの選び方は-2-通り) を参照）。

なお、公開リポジトリへ push しただけでは、本リポジトリ側の inputs は更新されません。取り込むには `nix flake update memex-nix` を実行して `flake.lock` を更新してください。

## 公開対象と除外対象の仕様

`.obsidian` 配下からは、vault で git 追跡されているファイルのうち以下のものが除外されて配布されます（`--dry-run` 時にこれらが削除対象として表示されるのは正常な挙動です）。

- `workspace.json`、`workspace-mobile.json`、`plugins/realclaudian/data.json`: vault 側の `.gitignore` で元々除外されているファイル
- `bookmarks.json`、`workspaces.json`: 個人のノートへの参照が含まれるため、配布時に自動削除
- typst プラグイン関連: WSL 上の Obsidian をクラッシュさせる原因となるため、`community-plugins.json` 内のプラグイン ID もあわせて除外
- `obsidian-git` の `autoPullOnBoot`: リモートが設定されていない配布先環境で起動時にエラーとなるのを防ぐため、`false` に書き換え

骨格側のドキュメント類は、workflow リポジトリの `nix/skeleton-paths.nix` に明記されたファイルおよび空フォルダのみが公開対象となります。`Zettel/` や `Dailies/` などのノート本文は同期されません。
骨格に新しいファイルを追加したい場合は、まず vault 内にファイルを配置してから `nix/skeleton-paths.nix` にパスを追記してください。定義されたファイルが vault 側に存在しない場合、mirror コマンドはエラーで停止します。

## 削除したはずの骨格ファイルが vault に復元される場合

本リポジトリの設定では `services.memex.initializeVault = false` となっており、seed は生成されない仕様です。削除したファイルが勝手に復活する場合は、古いバージョンの workflow を参照している可能性があります。

```sh
nix flake update memex-nix
nix build .#checks.x86_64-linux.vault-seed-isolation --no-link
```

このチェックにより、desktop および spin713 の構成において seed が生成されないことが検証されます。パスしたことを確認したら、各マシンで switch を実行してください。
なお、すでにローカルの vault に復元されてしまったファイルは flake の更新だけでは消去されないため、notes リポジトリ側で直接削除してコミット・同期してください。

## 任意の vault を別リポジトリへミラーリングする

パスを引数で直接指定して実行することも可能です。

```sh
nix run github:khimoo/memex-nix#mirror-vault -- /path/to/vault /path/to/config-repo
```

ノート用のリポジトリを持たない環境に骨格のみを展開したい場合は、`initializeVault = true` に設定して switch を実行します（詳細は memex-nix の README を参照）。

## トラブルシューティング

mirror 実行前のバリデーションでエラーとなった場合は、解決策が表示されますので案内に従ってください。

- `vault パスが未指定です`: 第 1 引数または環境変数 `MEMEX_ROOT` で vault のパスを指定してください。Home Manager 環境では `memexRoot` の設定を確認します。
- `ミラー先 config repo が未指定です`: 第 2 引数または環境変数 `MEMEX_CONFIG_REPO` で同期先を指定してください。Home Manager 環境では `vaultSkeletonRepo` の設定を確認します。
- `.obsidian が vault で git tracked ではありません`: vault 内で `.obsidian` が `git add` されていません。誤消去を防ぐための安全ガードです。
- `vault に .obsidian がありません`: 一度 Obsidian を起動して設定を生成した上で再実行してください。
- `配布対象が vault にありません`: `nix/skeleton-paths.nix` の指定と vault の実ファイル構成が食い違っています。vault 側にファイルを作成するか、定義リストから削除してください。
- `--dry-run` で `(差分なし)` と表示される: vault と公開リポジトリの内容がすでに一致している状態です。
