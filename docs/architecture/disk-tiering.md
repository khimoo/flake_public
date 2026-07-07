# ディスク階層構成（設計判断）

設定ファイル:
- `hosts/nixos-desktop/data-disk.nix`（SATA SSD の btrfs subvol マウント定義。fileSystems を map 生成）
- `hosts/nixos-desktop/default.nix`（`boot.loader.timeout = 0`。data-disk.nix を import）

使い方・セットアップ手順は [../howtouse/disk-tiering.md](../howtouse/disk-tiering.md) を参照。

## 全体構成

nixos-desktop は 2 台の SSD を **速度で 2 層に分けて**使う。

```
NVMe (Samsung 980, 466G) = ホット層          SATA (Samsung 860, 233G) = コールド/バルク層
  /            (ext4)                           btrfs 単一パーティション（1 UUID）
  /nix/store   ← rebuild/GC の小ファイル IO      @papis     → ~/papis-library   (Google Drive ミラー)
  swap                                           @downloads → ~/ダウンロード
  ~/sagyo      ← 開発作業（cargo target 等）      @videos    → ~/ビデオ
  ~/.cache 他                                    @music     → ~/音楽
                                                 @pictures  → ~/画像
                                                 @documents → ~/ドキュメント
                                                 @vm        → /var/lib/libvirt/images (NOCOW)
                                                 @backup    → /mnt/backup
```

判断の軸は「SSD かどうか」ではなく **そのワークロードの IO パターン**。SATA が NVMe に
明確に負けるのは小ファイルへのランダムアクセス（低レイテンシ・高 IOPS が効く領域）で、
シーケンシャルやネットワーク律速のワークロードは SATA でも体感差がほぼ出ない。

## 背景

きっかけは NVMe が 94%（377G/423G）まで埋まっていたこと。`/nix` が 217G を占め、
残りを `/home`(111G) と `/var`(50G) が使っていた。もともと Windows 用だった SATA SSD
(`/dev/sda`) を全消去して NixOS のデータ層に転用し、**SATA で誤差になるデータを追い出して
NVMe を空ける**のが目的。

## 設計判断

### /nix/store は NVMe に据え置く（SATA へ落とさない）

store は rebuild / GC / optimise で数万個の小ファイルへランダム IO を叩く、NVMe が最も
効くワークロード。SATA へ落とすと rebuild の IO 律速部分が 2〜5 倍遅くなりうる。加えて
store は boot / activation の極初期に必要で別デバイスへの分離が難しい。「NVMe を空ける」
目的は、store ではなく **SATA で誤差になるユーザーデータ（メディア・papis・VM）を追い出す**
ことで達成する。

### SATA へ追い出すのは「ディスク速度がボトルネックにならない」データだけ

- **papis ライブラリ** … 同期のボトルネックはネットワーク（Google Drive）なので SATA でも体感ゼロ
- **メディア（動画・音楽・画像・ダウンロード）** … 再生は数〜数十 MB/s で SATA の
  シーケンシャル(~550MB/s)に対し 20〜100 倍の余裕。既圧縮で大きくシーケンシャル
- **VM イメージ** … デスクトップ用途の VM は起動時にバースト IO、以後は大半が page cache。
  Samsung 860 なら実用上問題ない（VM 内で重い DB/ビルドを回すなら別）
- **バックアップ** … 書き込み一度・読み出し稀。速度は要求されない

### ファイルシステムは btrfs（データ層の定石）

OS ではなくデータ/アーカイブ/バックアップ層なので、btrfs の強みが活きる:

- **チェックサム** … コールドなメディア/バックアップのビットロットを検出できる
- **snapshot** … バックアップ用途と相性が良い
- **subvol** … papis / メディア / VM / backup を 1 パーティション内でクリーンに分割できる

zstd 圧縮は付けているが、対象の大半（jpg/mp4/mp3/多くの PDF）は既圧縮で btrfs が自動
スキップするため容量効果は限定的。圧縮より上記 3 点が採用理由。

### VM subvol（@vm）だけ NOCOW にする

btrfs は CoW のため qcow2/raw の VM イメージを置くと激しく断片化して遅くなる。対策として
`@vm` の subvol ルートに `chattr +C` を適用し、以後作られる VM イメージが NOCOW を継承する
ようにしている。NOCOW ファイルには圧縮・チェックサムが効かないため、`@vm` のマウント
オプションに `compress=zstd` は付けない。

### 各 subvol を最終パスに直接マウント（bind/symlink を使わない）

`~/ダウンロード` 等を bind-mount や symlink で間接化せず、`subvol=@downloads` を最終パスへ
直接マウントする。アプリから見たパスは `~` のまま、実体だけ SATA になる。papis も同様で、
`~/papis-library` を `@papis` の直接マウントにすることで、`app.nix`/`sync.nix` の
`libraryDir`（`~/papis-library` とベタ書き）は**無改造**のまま保存先だけ差し替わる。papis 層が
保存 backend を知らないという依存方向（[papis-gdrive-sync.md](./papis-gdrive-sync.md)）と一致する。

### fileSystems は map 生成する

8 個の subvol マウントを手書きすると device/fsType/オプションが重複する。`{subvol, path,
opts}` のリストから `builtins.listToAttrs` で生成し、共通部分を一箇所に閉じる。

### ブートメニュー無効化（timeout=0）は desktop 限定

起動時の「OS 選択画面」の正体は systemd-boot の世代メニュー。EFI を調べた結果
**Windows Boot Manager エントリも `/boot/EFI/Microsoft` も存在せず**、SATA 上の旧 Windows は
既に UEFI から起動不能な孤立状態だった（消すべきデュアルブートの仕組みは無い）。よって
`boot.loader.timeout = 0` で世代メニューを出さず直起動にするだけでよい。共有
`modules/nixos/boot.nix` に置くと laptop(spin713) のメニューも消えるため、desktop の
`default.nix` に置いてスコープを絞っている。

### data 層マウントに nofail を付けない

データは SATA のみに存在するため、マウント失敗を `nofail` で握り潰すと、空のマウント
ポイント（NVMe 上）へアプリが書き込み NVMe を圧迫する・データが無いのに気づけない、という
サイレント障害になる。内蔵ディスクで常時存在する前提なので、失敗時はむしろ loud に
気づける既定（required）のままにしている。
