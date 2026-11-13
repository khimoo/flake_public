# mimikopi-env の設計

使い方: [mimikopi-env](../howtouse/cli-tools/mimikopi-env.md)
実装: [packages/mimikopi-env](../../packages/mimikopi-env/default.nix)、[mimikopi.star](../../config/elements/mimikopi.star)

## 使いみち

耳コピ（楽曲の自動採譜）のスキルは、音源分離と採譜の ML モデル（basic-pitch、Transkun、YourMT3+ など）を、モデルごとに分けた uv の環境で動かす。
モデルによって PyTorch と TensorFlow のどちらを使うか、どの版を要求するかが違うので、一つの環境には同居させられない。
どのモデルも PyPI の manylinux wheel で入るため、NixOS では FHS 環境の中でしか動かない。

## 確かめた結果

2026-10-18 に nixos-desktop で確かめた。

- GPU は PCI ID `1002:73ff`（Navi 23 世代、RX 6600 系、gfx1032）。`/dev/kfd` と `/dev/dri/renderD128` は誰でも読み書きできる。
- Nix の Python 3.11.16 で作った uv の venv に torch 2.14.1+cpu を入れると、`import torch` が `ImportError: libstdc++.so.6: cannot open shared object file` で失敗した。Nix の `stdenv.cc.cc.lib` と `zlib` を `LD_LIBRARY_PATH` に入れると動いた。
- torch 2.9.1+rocm6.4 は、上の二つに加えて `zstd`、`libdrm`、`numactl`、`elfutils`、`xz`、`bzip2` を `LD_LIBRARY_PATH` に入れると import できた。
- `HSA_OVERRIDE_GFX_VERSION=10.3.0` を付けると、GPU で 4096 次の行列積 10 回が 0.39 秒で終わり、Conv1d も通った。付けないと HIP のカーネルエラーで失敗した。
- torch 2.9.1+rocm6.4 の環境は展開後に約 15GB あり、ルートの空き（約 18GB）が 119MB まで減った。
- `mimikopi-env` の中では、`LD_LIBRARY_PATH` を使わずに、uv が取得した Python 3.11 の torch 2.9.1+rocm6.4 で同じ行列積と Conv1d が GPU で通った。
- uv のキャッシュは `du` で 15GB だったが、sda1 の使用量は約 5GB しか増えなかった。`compress=zstd` で ROCm のライブラリが縮むためと考えられる。

## buildFHSEnv で動かす

[packages/mimikopi-env](../../packages/mimikopi-env/default.nix) は buildFHSEnv で、ROCm 版の torch が読むライブラリと `ffmpeg` を FHS の配置に並べる。
nix-ld をこのホストで有効にする案は退けた。uv が取得する Python に限らず、ダウンロードしたビルド済みのバイナリがホスト全体で動くようになり、Nix の管理外のものが入り込んでも起動の失敗で気づけなくなる。
会社 PC では nix-ld を有効にしている（[wsl.md](./wsl.md#uv-が取得する-python-を-nix-ld-で動かす)）。

環境の中では、uv のキャッシュ（`UV_CACHE_DIR`）、uv が取得する Python（`UV_PYTHON_INSTALL_DIR`）、Hugging Face と PyTorch のチェックポイント（`HF_HOME`、`TORCH_HOME`）をデータディレクトリに向ける。
uv はキャッシュから環境へハードリンクで展開するので、キャッシュと環境を同じファイルシステムに置くと、同じ版の torch を複数のモデルの環境で共有できる。
スキルがモデルの環境を置く場所は `MIMIKOPI_DATA_DIR` で渡す。

`HSA_OVERRIDE_GFX_VERSION` は GPU で決まる値なので、パッケージの引数にして [nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) の `mimikopi_hsa_override` から渡す。
PyTorch の ROCm 版の wheel には gfx1032 向けのカーネルが入っていないので、`10.3.0` を指定して gfx1030 として扱わせる。
GPU（ROCm）が要るので、[shell.star](../../config/elements/shell.star) ではなく派生要素 `mimikopi_for_music`（`when = ["make_music", "rocm_compute"]`）の `requires` で `mimikopi` を入れる。`rocm_compute` は、ROCm で計算できる機体の要素が `requires` に挙げる機体の事実で、今はデスクトップだけが挙げる。

## データを SATA の専用 subvol に置く

ルートの空き約 18GB に対して、ROCm 版の torch だけで約 15GB を使う。
[mimikopi.star](../../config/elements/mimikopi.star) がホストの `mimikopi_data_dir` をパッケージに渡す。OS のマウント先も [mimikopi.star](../../config/elements/mimikopi.star) が同じ値と `mimikopi_data_subvolume` から作る。

SATA SSD に `@mimikopi` を作り、`~/.local/share/mimikopi` にマウントする（[mimikopi.star](../../config/elements/mimikopi.star)）。mimikopi が入らない機体ではマウントも作らない。
モデルの読み込みはシーケンシャル読みが中心で、[disk-tiering.md](./disk-tiering.md) の分け方ではコールド層に当たる。

`/mnt/backup` の下にディレクトリを作る案もあった。`systemd.tmpfiles` に一行足すだけで済むが、再取得できる数十 GB をバックアップの退避先に混ぜることになるので退けた。

subvol は手で作るので、作る前に switch や再起動をすると、マウントの失敗で起動が止まる。
これを避けるためにマウントに `nofail` を付けている。
ただし `nofail` だと、マウントに失敗してもマウント先のディレクトリはルート側に残り、そこへ書き込めてしまう。
検証中にルートを埋めかけたので、`mimikopi-env` は起動時に `mountpoint -q` でデータディレクトリを確かめ、マウントされていなければ止まる。
[tests/default.nix](../../tests/default.nix) は `nofail` が付いていることを確かめる。

## 代償

モデルの環境の Python を実行するものは、`mimikopi-env` の中で起動する必要がある。
`@mimikopi` がマウントされていない間は、`mimikopi-env` は何も実行せずに止まる。

## 未確定

- ROCm 7.x の wheel で同じ回避策が通るか。試したのは ROCm 6.4 だけ。
- `/opt/amdgpu/share/libdrm/amdgpu.ids` が見つからないという警告が出るが、GPU の名前が汎用の「AMD Radeon Graphics」になるだけで、計算には影響しなかった。
