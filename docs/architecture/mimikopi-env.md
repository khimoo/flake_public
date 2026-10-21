# mimikopi-env の導入

[howtouse/cli-tools/mimikopi-env.md](../howtouse/cli-tools/mimikopi-env.md) の設計判断。

## 使いみち

耳コピ（楽曲の自動採譜）のスキルは、音源分離と採譜の ML モデル（basic-pitch、Transkun、YourMT3+ など）を、モデルごとに分けた uv の環境で動かす。
モデルによって PyTorch と TensorFlow のどちらを使うか、どの版を要求するかが違うので、一つの環境には同居させられない。
どのモデルも PyPI の manylinux wheel で入るため、NixOS では [uv-mode](../howtouse/cli-tools/uv-mode.md) と同じく FHS 環境の中でしか動かない。

## 確かめた結果

2026-10-18 に nixos-desktop で確かめた。

- GPU は PCI ID `1002:73ff`（Navi 23 世代、RX 6600 系、gfx1032）。`/dev/kfd` と `/dev/dri/renderD128` は誰でも読み書きできる。
- Nix の Python 3.11.16 で作った uv の venv に torch 2.14.1+cpu を入れると、`import torch` が `ImportError: libstdc++.so.6: cannot open shared object file` で失敗した。Nix の `stdenv.cc.cc.lib` と `zlib` を `LD_LIBRARY_PATH` に入れると動いた。
- torch 2.9.1+rocm6.4 は、上の二つに加えて `zstd`、`libdrm`、`numactl`、`elfutils`、`xz`、`bzip2` を `LD_LIBRARY_PATH` に入れると import できた。
- `HSA_OVERRIDE_GFX_VERSION=10.3.0` を付けると、GPU で 4096 次の行列積 10 回が 0.39 秒で終わり、Conv1d も通った。付けないと HIP のカーネルエラーで失敗した。
- torch 2.9.1+rocm6.4 の環境は展開後に約 15GB あった。ルートの空きが約 18GB だったので、検証中に空きが 119MB まで減った。
- 同じ日に、`mimikopi-env` の中で上の 8 つのライブラリが `/usr/lib` に見え、uv が取得した Python 3.11.15 が起動することを確かめた。データディレクトリには tmpfs の `/run/user/1000` を使った。
- `@mimikopi` を作って適用した後、`mimikopi-env` の中で uv が取得した Python 3.11 に torch 2.9.1+rocm6.4 を入れ、GPU で同じ行列積（0.393 秒）と Conv1d が通ることを確かめた。`LD_LIBRARY_PATH` は使っていない。
- このとき uv のキャッシュは `du` で 15GB だったが、`df` で見た sda1 の使用量は 176G から 181G へ約 5GB しか増えなかった。`compress=zstd` で ROCm のライブラリが縮むためと考えられる。

## FHS 環境を uv-mode と分ける

[packages/mimikopi-env](../../packages/mimikopi-env/default.nix) は uv-mode と同じ形の buildFHSEnv で、`targetPkgs` に ROCm 版の torch が読むライブラリと、音声の読み込みに使う `ffmpeg` を足している。
uv-mode に足せば定義は一つで済むが、耳コピ以外で uv-mode を使うときにも、これらのライブラリが環境に入る。
影響を耳コピだけに閉じるため別の環境にした。代わりに、uv-mode とほぼ同じ定義をもう一つ保守する。

環境の中では、uv のキャッシュ（`UV_CACHE_DIR`）、uv が取得する Python（`UV_PYTHON_INSTALL_DIR`）、Hugging Face と PyTorch のチェックポイント（`HF_HOME`、`TORCH_HOME`）をデータディレクトリに向ける。
uv はキャッシュから環境へハードリンクで展開するので、キャッシュと環境を同じファイルシステムに置くと、同じ版の torch を複数のモデルの環境で共有できる。
スキルがモデルの環境を置く場所は `MIMIKOPI_DATA_DIR` で渡す。

`HSA_OVERRIDE_GFX_VERSION` は GPU で決まる値なので、パッケージの引数にして [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) から渡す。
PyTorch の ROCm 版の wheel には gfx1032 向けのカーネルが入っていないので、`10.3.0` を指定して gfx1030 として扱わせる。
データディスクも GPU も nixos-desktop に固有なので、[core.nix](../../modules/home-manager/core.nix) ではなくこのホストの Home Manager の設定で入れる。

## データを SATA の専用 subvol に置く

ルートの空き約 18GB に対して、ROCm 版の torch だけで約 15GB を使う。
[mimikopi.nix](../../modules/home-manager/mimikopi.nix) の `local.mimikopi` でパッケージと保存先を設定する。ホストの Home Manager 設定で `dataDir` を一度指定し、OS は有効な場合だけその値へマウントする。

SATA SSD に `@mimikopi` を作り、`~/.local/share/mimikopi` にマウントする（[data-disk.nix](../../hosts/nixos-desktop/data-disk.nix)）。
モデルの読み込みはシーケンシャル読みが中心で、[disk-tiering.md](./disk-tiering.md) の分け方ではコールド層に当たる。

`/mnt/backup` の下にディレクトリを作る案もあった。`systemd.tmpfiles` に一行足すだけで済むが、再取得できる数十 GB をバックアップの退避先に混ぜることになるので退けた。

subvol は手で作るので、作る前に switch や再起動をすると、マウントの失敗で起動が止まる。
これを避けるためにマウントに `nofail` を付けている。
ただし `nofail` だと、マウントに失敗してもマウント先のディレクトリはルート側に残り、そこへ書き込めてしまう。
検証中にルートを埋めかけたので、`mimikopi-env` は起動時に `mountpoint -q` でデータディレクトリを確かめ、マウントされていなければ止まる。
[tests/default.nix](../../tests/default.nix) は `nofail` が付いていることを確かめる。

## 退けた案

- uv-mode の `targetPkgs` に足す。上の「FHS 環境を uv-mode と分ける」に書いた理由で退けた。
- nix-ld をシステムで有効にする。[uv-mode.md](../howtouse/cli-tools/uv-mode.md#設計) で退けたのと同じ理由になる。
- `/mnt/backup` の下にディレクトリを作る。上の「データを SATA の専用 subvol に置く」に書いた理由で退けた。

## 代償

モデルの環境の Python を実行するものは、`mimikopi-env` の中で起動する必要がある（uv-mode と同じ）。
`@mimikopi` がマウントされていない間は、`mimikopi-env` は何も実行せずに止まる。

## 未確定

- ROCm 7.x の wheel で同じ回避策が通るか。試したのは ROCm 6.4 だけ。
- `/opt/amdgpu/share/libdrm/amdgpu.ids` が見つからないという警告が出るが、GPU の名前が汎用の「AMD Radeon Graphics」になるだけで、計算には影響しなかった。
