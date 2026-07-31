# TODO: nixos-anywhere ベースの新マシン一括プロビジョニング

**現状: 未実装（設計メモ）**。実装したら使い方は `docs/howtouse/new-machine.md`
に分離し、このファイルは設計判断だけを残す。

## 何を解決するか

いまの flake は「宣言的な rebuild」の部分は綺麗に決まっているが、**新マシンを 0 から
steady state に持ってくる導線が silent skip の温床**になっている:

- age 鍵の受け渡し経路が「別マシンから SSH 送信 or Bitwarden から取得」の 2 択で
  併存 ([howtouse/private-repo-clone.md](../howtouse/private-repo-clone.md) 参照)、
  どちらもドキュメントに書かれているが強制されない
- age 鍵が置かれないまま `nixos-rebuild switch` が走ると activation は warning を
  出しつつ skip、**rebuild は成功して終わる**
- 結果、`claude-private` や `zettelkasten-workflow` が clone されないまま週単位で
  放置される（実際に発生した事象）

原因は「install ワークフローと rebuild ワークフローが分離されず、bootstrap が rebuild に
こっそり紛れ込んでいる」ことにある。ここではその境界を引き直す。

## 理想状態の性質（不変条件）

1. **Bootstrap は install ワークフローの明示的な 1 ステップ** — 「そのうち気付いてね」
   ではなく install 手順書に組み込まれた stage
2. **Bootstrap 完了後、`nixos-rebuild switch` は自己完結** — 環境変数・別マシンとの
   通信・手動 SSH コピーを一切要求しない
3. **鍵は「1 度だけ、責任のはっきりした経路で運ぶ」** — 2 経路併存禁止（今の silent
   skip の温床）。運ぶこと自体は許容
4. **State drift は fail-fast で止まる** — silent skip を原理的に禁止
5. **新マシン追加は既存機から 1 コマンド** — 新機側で人間が対話する必要無し

## 完成形のワークフロー

### 一度だけ、永久に（既に完了）

- age 鍵を生成
- **保管先を 1 つ決める**: Bitwarden secure note（推奨）+ 物理バックアップ（USB / 紙印刷）
- flake_public を GitHub に push

### 最初の 1 台目（一生に 1 回 or disaster recovery）

既存機が世に存在しない状態からのブートストラップ。以下いずれかの経路 —
**どちらでもよい（両方許容）**。分岐は明示的な選択であり silent skip とは別物:

- **Bitwarden 経路**: `nix run nixpkgs#bitwarden-cli -- get item nixos-age-key > ~/.config/sops/age/keys.txt`
- **USB 経路**: 物理媒体から `cp /media/.../keys.txt ~/.config/sops/age/keys.txt`

いずれも標準 NixOS installer で入れた直後の user shell から実行。以降 `nixos-rebuild switch`
で activation が走り、SSH 鍵復号 → private-repos clone まで一気に完了する。

このマシンが以降「既存機」となり、次からは N 台目フローが使える。

### N 台目（typical case, 数分）

既存機のシェルから 1 コマンド（**粗い粒度**）:

```sh
sagyo-install pomu@<new-ip> nixos-<newhost>
```

内部で:

1. `nixos-anywhere --flake .#nixos-<newhost>` を新機に対して実行
2. 新機の disk を disko で partition（新機は disko config を持つ前提、後述）
3. `nixos-install` で system 適用
4. **age 鍵 (`~/.config/sops/age/keys.txt`) を `--extra-files` 経由で新機の
   `/home/pomu/.config/sops/age/keys.txt` に配置**
5. 再起動 → 初回 activation で SSH 鍵復号 + private-repos clone

新機側で対話は不要。新機は installer ISO 起動 + SSH 待ち受け状態にしておくだけ
（nixos-anywhere が kexec で installer に切り替えてくれるので、汎用 Linux LiveCD
でも可）。

### 日常

- `sudo nixos-rebuild switch --flake .#<host>` これだけ
- activation は **strict**: age 鍵が消えていたら error で停止し「上記のフローを再実行」と一言
- silent skip は原理的に発生しない

### Disaster recovery（全マシン喪失）

- 家が焼けて 2〜3 台全部失った場合
- Bitwarden にログイン（あるいは USB / 紙印刷から）→ age 鍵取得
- 「最初の 1 台目」フローで 1 台目を復元
- 以降「N 台目」フローで残りを復元

Bitwarden 自体もアクセス不能なら？ → 物理バックアップ（USB・紙印刷）を金庫・実家に
分散配置しておく。個人利用の判断。

## 解決される問題

この設計を Phase 4 まで完成させた時点で、以下が同時に解決される:

1. **今回発生した silent skip の再発防止** — activation の strict 化により、age 鍵不在
   なら次の rebuild で必ず気付く。「rebuild は成功したのに実は clone されてなかった」
   が原理的に起きない
2. **新マシン追加の手数削減** — 現状「NixOS install → age 鍵配送を手で判断 → rebuild
   → warning 見逃し確認」の 4 段階から、「installer 起動 + `sagyo-install pomu@<ip> <host>`
   を既存機から叩く」の 1 段階に短縮
3. **ドキュメント経路併記の腐敗防止** — `private-repo-clone.md` の「SSH 送信 or Bitwarden
   から取得」の 2 経路併記が撤去され、new-machine.md の single-path 手順書に一本化。
   将来自分で読み直したときにどちらが正解か迷わなくなる
4. **DR パニック時の実行可能性** — 家焼失時に「どうやるんだっけ」のパニック下でも
   new-machine.md の「最初の 1 台目」節を上から読むだけで復元できる。手順の暗記が不要
5. **bootstrap 挙動の予測可能性** — 今は「rebuild すると activation が clone するかも
   しれないししないかもしれない」という条件付き挙動。strict 化後は「rebuild が成功した
   = bootstrap 済み」と一意に決まる。他人（未来の自分含む）がコードを読むときの認知
   負荷が下がる
6. **新マシンの disk layout の宣言化（副次的）** — Phase 3 で新機に disko を導入する
   ことで、パーティション定義が nix expression 化される。将来同じマシンを再構築する
   ときにパーティション作業が消える（既存機は無理に移行しないので恩恵無し）

## 解決されない問題（正直に）

この設計は install 時 bootstrap の silent skip 問題を解くが、以下は依然として人間の
責務として残る:

- **最初の 1 台目の chicken-and-egg** — 世界に NixOS 機が 0 台の状態からのブートストラップ
  は物理的に人間の対話が要る（Bitwarden or USB）。詳細は下記「検討事項」節参照
- **Bitwarden アカウント運用リスク** — master password 紛失、2FA デバイス紛失は自動化
  できない。物理バックアップの分散配置で保険をかけるのは個人の判断
- **ハードウェア故障の物理的復旧** — 通販でマザーボード買うのは自動化できない
- **`secrets.yaml` 内の他シークレット追加 / rotate** — SSH 鍵以外のシークレット追加時は
  `sops` を手で叩く手順が残る（bootstrap とは別関心）
- **`flake.lock` 更新の判断** — 依然人間の責務（bootstrap の話とは別関心）

## 決定事項（このセッションで決まったこと）

| 論点 | 決定 |
|------|------|
| プロビジョニング基盤 | **nixos-anywhere を採用** |
| disko の適用範囲 | **新規マシンから**（既存マシンは無理に移行しない） |
| 最初の 1 台目の鍵経路 | **Bitwarden / USB の両方を許容**（明示的な選択肢として） |
| `sagyo-install` の粒度 | **粗い版**（`sagyo-install <ip> <hostname>` で全部やる） |
| Bitwarden CLI の位置づけ | **最初の 1 台目 or disaster recovery 専用**。全マシンに常設せず `nix run` で ephemeral 使用 |

## 必要な部品

### 新設

| 部品 | 責務 |
|------|------|
| `sagyo-install` (flake apps output) | nixos-anywhere の薄いラッパー。既存機の `~/.config/sops/age/keys.txt` を自動で `--extra-files` に載せる。ホスト名だけ引数で受け、flake の宣言的定義から target 設定を解決する |
| 新規マシン向け disko config | 新機を追加するときは `hosts/<newhost>/disko.nix` を書き、`hardware.nix` の `fileSystems` はそこから生成させる |
| `docs/howtouse/new-machine.md` | N 台目追加手順（既存機から 1 コマンド）+ 最初の 1 台目手順（Bitwarden または USB） |

### 修正

| 部品 | 変更 |
|------|------|
| `modules/home-manager/ssh-keys.nix` | activation を **strict** 化: age 鍵不在なら error で停止（**実装済み**。残りはエラー文言に `sagyo-install` 経路を足すだけ） |
| `docs/howtouse/private-repo-clone.md` | 「SSH 送信 or Bitwarden から取得」の 2 経路併記を削除、`new-machine.md` にリダイレクト |

### 温存

- `secrets/secrets.yaml`、`.sops.yaml`、`hosts/machines.nix`、既存の age → sops → SSH 鍵チェーン
- 既存マシンの `hardware.nix` の `fileSystems`（disko 化はやらない）

## 実装優先度と日程感

### 優先度

**Phase 0 → 1 → 4 のセットが最優先で価値が高い**:

- **Phase 4** で silent skip の根絶が達成される（今回問題の根本解決）
- ただし Phase 4 単独では復元手段が Bitwarden 手入力しか残らず UX が退化する
- **Phase 0 → 1** で `sagyo-install` の受け皿を先に作っておくことで、Phase 4 の
  エラーメッセージから誘導先が実在する状態を作る
- **Phase 3**（実マシン検証）は実機購入まで自然に遅延するので、Phase 4 を先にやっても良い
- **Phase 2**（howtouse docs）・**Phase 5**（architecture doc 書き直し）は保守性のため

### 日程感の目安

- **Phase 0〜2** 集中してやれば 1 日
- **Phase 4** は別日で 1 時間（既存マシンでの検証込み）
- **Phase 3** は実マシン購入次第（数ヶ月〜数年後もあり得る）
- **Phase 5** は Phase 3〜4 完了後、30 分

## 実装ステップ（Phase 単位）

### Phase 依存グラフ

```
Phase 0 ──▶ Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5
(nixos-      (sagyo-      (howtouse    (実マシン    (activation   (arch doc
 anywhere    install      docs)        検証・       strict 化)   書き直し)
 素で試す)   wrapper)                  disko)
```

Phase 0〜2 は連続してやるのが集中力的に良い。Phase 3 は実マシン準備次第で自然に延びる。
Phase 4 は Phase 3 完了直後にやるのが理想（頭の中に文脈がある間）。

### Phase 0: 素の nixos-anywhere を触る

- **やること**: 既存の nixos-spin713 の設定を VM に対して `nixos-anywhere` で流し込む。
  `--extra-files` で任意ファイルが指定パスに落ちることも確認
- **なぜ最初**: ツール自体の挙動を知らないと `sagyo-install` の設計が空想になる。
  VM でやるのは壊しても失うものが無いから
- **既存機への影響**: なし（VM のみ）
- **完了時の便益**: nixos-anywhere の挙動理解（無形資産）。設計を差し戻すなら今が
  最も低コスト

### Phase 1: sagyo-install wrapper 実装

- **やること**: `flake.nix` の `apps.x86_64-linux.sagyo-install` として nixos-anywhere の
  薄いラッパーを追加。既存機の `~/.config/sops/age/keys.txt` を自動で `--extra-files` に
  載せる
- **なぜここ**: Phase 0 で挙動が分かった直後にラップする。VM で 2 回目を実行して
  one-shot で age 鍵まで含まれることを確認
- **既存機への影響**: なし（flake output が増えるだけ）
- **完了時の便益**: `nix run .#sagyo-install` が実装完了

### Phase 2: `docs/howtouse/new-machine.md` 作成 + `private-repo-clone.md` 置換

- **やること**: 最初の 1 台目 + N 台目の手順書を書き、`private-repo-clone.md` の
  bootstrap 節を new-machine.md にリダイレクト
- **なぜここ**: 実装が動いた直後に書くのが最も正確（「動いた通りに書く」）。
  実装前に書くと理想論になる
- **既存機への影響**: なし（docs のみ）
- **完了時の便益**: 手順書と実装が一致した状態、DR 手順が明文化される

### Phase 3: 実マシンでの検証

- **やること**: 実際に新マシンが必要になったタイミングで `hosts/<newhost>/disko.nix` を
  書き、`sagyo-install` で通す
- **なぜここ**: 実マシンでしか本当の検証はできない。Phase 2 まで既存機に影響しない
  ので、ここまで待っても損は無い
- **既存機への影響**: なし（新規マシンのみ）
- **完了時の便益**: **実利: 新マシンを 1 コマンドで足せることが実証される**
- **タイミング**: 実マシン購入待ち。テスト用に VM でもう 1 回検証するのも可

### Phase 4: activation の strict 化 — **実装済み**

`modules/home-manager/ssh-keys.nix` が age 鍵不在で `exit 1` する。誘導先は
「既存マシンから SSH で送る」「Bitwarden から取り出す」の 2 経路
（`sagyo-install` は未実装なのでまだ挙げていない。Phase 1 完了時に追記する）。

Phase 1〜3 を待たずに前倒しした。SSH 鍵配布を `ssh-keys.nix` に切り出した際、
実際に silent skip を踏んで「switch は成功したのに鍵が無い」状態を作ってしまい、
原因が journal に埋もれて分かりにくかったため。

同時に、復号が失敗しても空の鍵ファイルが残って以降 clone-if-absent が
「もうある」と誤判定する経路も塞いだ（一時ファイルへ復号してから `mv`）。

### Phase 5: architecture doc 書き直し

- **やること**: この `new-machine.md` から TODO tag を外し、「設計判断のみ」に絞る
  （実装ステップ節は削除、実装済み事項に置換）
- **なぜここ**: 実装完了後に書き直すのがドキュメントとして最も正確
- **既存機への影響**: なし（docs のみ）
- **完了時の便益**: 保守性（doc が正確）

## 検討事項・トレードオフ

### disko の既存マシン移行

既存機の `hardware.nix` はそのまま。無理に disko 化するとパーティション操作が絡み
リスクが高い。新規マシンから徐々に disko 化していく段階的移行。この方針の副作用として
「disko で書かれたホストと `fileSystems` で書かれたホストが flake 内に混在する」期間が
発生するが、宣言的 module として両立できるので実害は少ない。

### chicken-and-egg（最初の 1 台目）

nixos-anywhere は「既存機」の存在を前提にするため、世界に 1 台も NixOS 機が無い状態
からのブートストラップには使えない。この 1 回だけ標準 install + Bitwarden/USB 経路を
残す。頻度が「一生に 1 回 + disaster recovery のみ」なので手数が増えても実害小。

### `sagyo-install` の冪等性

`nixos-anywhere` は install 対象を **消去して書き直す** 性質なので、`sagyo-install` は
冪等ではない（2 回目を叩くと disk が飛ぶ）。対策として:

- コマンド名に `install` を含めて「初回専用」を暗示
- 対象 IP に既に NixOS が動いていたら stop する dry-run 的な安全弁を入れる（nixos-anywhere
  側にこの機能があるかは要調査）

### fail-fast の副作用

activation を strict 化すると、既存マシンで何らかの理由で age 鍵が消えた場合に
`nixos-rebuild switch` が完全に失敗するようになる。この場合の回復手順を new-machine.md
に「既存マシンで age 鍵を紛失した場合」節として書いておく（Bitwarden or 別既存機から
scp で復元）。

## 参考

- nixos-anywhere: https://github.com/nix-community/nixos-anywhere
- disko: https://github.com/nix-community/disko
- 既存の private-repo-clone 設計: [private-repo-clone.md](./private-repo-clone.md)
- 既存のマシン間 SSH 設計: [machine-ssh.md](./machine-ssh.md)
