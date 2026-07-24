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
| `modules/home-manager/private-repos.nix` | activation を **strict** 化: age 鍵不在なら error で停止。silent skip を撤廃 |
| `docs/howtouse/private-repo-clone.md` | 「SSH 送信 or Bitwarden から取得」の 2 経路併記を削除、`new-machine.md` にリダイレクト |

### 温存

- `secrets/secrets.yaml`、`.sops.yaml`、`hosts/machines.nix`、既存の age → sops → SSH 鍵チェーン
- 既存マシンの `hardware.nix` の `fileSystems`（disko 化はやらない）

## 実装ステップ（TODO checklist）

- [ ] `nixos-anywhere` を試す: 既存の nixos-desktop → 適当な VM に対して素の
      `nixos-anywhere --flake .#nixos-spin713 ...` を叩いて感触を掴む
- [ ] `sagyo-install` を `flake.nix` の `apps.x86_64-linux.sagyo-install` として実装:
      nixos-anywhere を呼び、`--extra-files` に age 鍵を自動注入
- [ ] `private-repos.nix` の activation を strict 化（age 鍵不在で error 停止）
- [ ] `docs/howtouse/new-machine.md` を書く: N 台目手順 / 最初の 1 台目手順（両経路）
- [ ] `docs/howtouse/private-repo-clone.md` の bootstrap 節を new-machine.md に置換
- [ ] 実装完了後、この doc を「設計判断のみ」に絞って書き直す（TODO tag を外す）

新マシンを実際に足すタイミングで最終ステップ:

- [ ] 新マシンの `hosts/<newhost>/disko.nix` を書く
- [ ] `sagyo-install pomu@<ip> nixos-<newhost>` で実プロビジョニング

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
