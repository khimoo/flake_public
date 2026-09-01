# ディスク階層構成（設計判断）

設定ファイル:
- `hosts/nixos-desktop/data-disk.nix`（SATA SSD の btrfs subvol マウント定義。fileSystems を map 生成）
- `hosts/nixos-desktop/default.nix`（data-disk.nix を import）

使い方・セットアップ手順は [../howtouse/disk-tiering.md](../howtouse/disk-tiering.md) を参照。

## 全体構成

nixos-desktop は 2 台の SSD を **速度で 2 層に分けて**使う。

```
NVMe (Samsung 980, 466G) = ホット層          SATA (Samsung 860, 233G) = コールド/バルク層
  /            (ext4)                           btrfs 単一パーティション（1 UUID）
  /nix/store   ← rebuild/GC の小ファイル IO      @papis     → ~/sagyo/zettelkasten/references (Drive ミラー)
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
直接マウントする。アプリから見たパスは `~` のまま、実体だけ SATA になる。

papis も同様だが、マウント先が **NVMe 側の `~/sagyo` ツリーの内側**にある点が特殊:
`@papis` を `~/sagyo/zettelkasten/references`（vault clone の直下）へマウントする。
`references/` という**ディレクトリだけ**が NVMe の `~/sagyo` 上に存在し、そこに SATA の
`@papis` を被せるので、中身（papis のライブラリ本体）は SATA に載る。papis のライブラリ位置は
workflow flake が `<vaultDir>/references` に規約で固定していて、マウントはその保存先を SATA に
差し替えるだけ。papis 層が保存 backend を知らないという依存方向
（[papis-gdrive-sync.md](./papis-gdrive-sync.md)）と一致する。

この配置は 2 つの要求を同時に満たすための折衷:
- **papis を vault の中に置く**（Obsidian vault で完結。`references/` は vault の 1 フォルダ）
- **papis を SATA に置く**（同期はネットワーク律速なので SATA で体感差ゼロ、NVMe を空ける）

### `@papis` だけ条件付き systemd.mounts にする

マウント先の親 `~/sagyo/zettelkasten` は vault の clone なので、**マウントが clone より先に
走ってはいけない**。`fileSystems` に書くと systemd が boot 時に無条件でマウント先を作り、
root 所有の中間ディレクトリができる。すると
[private-repos.nix](./private-repo-clone.md) の `git clone` が「空でないディレクトリ」
「書き込めない」で失敗し、`dest` があるので次の switch 以降は skip される——vault が永久に
来ないまま静かに壊れる。実際に起きた。

そこで `@papis` だけ `fileSystems` から外し、`systemd.mounts` に
`ConditionPathExists = "${zettelkastenRoot}/.git"` を付けて表現している。vault が実在するとき
だけマウントする、という順序制約を条件として書けるのが `systemd.mounts` を選ぶ理由。
新マシンでは初回 clone の後に一度 reboot（または `systemctl start`）してマウントを有効にする。

条件が偽の間 `references/` は NVMe 上の（存在しないか空の）ディレクトリになる。ここは
`nofail` によるサイレント障害（後述）とは別で、「vault がまだ無いのだから papis ライブラリも
無い」という一貫した状態なので、書き込みが NVMe に落ちる事故は起きない。

### fileSystems は map 生成する

subvol マウントを手書きすると device/fsType/オプションが重複する。`{subvol, path,
opts}` のリストから `builtins.listToAttrs` で生成し、共通部分を一箇所に閉じる。

### 旧 Windows のブート設定は残骸を残していない

SATA を転用するにあたり、旧 Windows のブート設定が残っていないかを EFI で確認した。
**Windows Boot Manager エントリも `/boot/EFI/Microsoft` も存在せず**、SATA 上の旧 Windows は
既に UEFI から起動不能な孤立状態だった。消すべきデュアルブートの仕組みは無い。

起動時に見える「OS 選択画面」は Windows とは無関係で、systemd-boot の世代メニューそのもの。
これは復旧手段なので残す。なお `boot.loader.timeout = 0` は「メニューを出さない」ではなく
「隠すが、キー入力で復帰でき、復帰後はタイムアウトが効かない」の意味になるため、
即起動の手段としては使わない。

### data 層マウントに nofail を付けない

データは SATA のみに存在するため、マウント失敗を `nofail` で握り潰すと、空のマウント
ポイント（NVMe 上）へアプリが書き込み NVMe を圧迫する・データが無いのに気づけない、という
サイレント障害になる。内蔵ディスクで常時存在する前提なので、失敗時はむしろ loud に
気づける既定（required）のままにしている。
