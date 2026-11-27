# Google Cloud（GCE）オフロードの設計

使い方: [GCE へのオフロードとローカル復帰](../howtouse/gce-offload.md)
実装: [find_home_server.star](../../config/elements/find_home_server.star)、[expose_services.star](../../config/elements/expose_services.star)、[machine_nixos_gce.star](../../config/elements/machine_nixos_gce.star)、[auto_upgrade.star](../../config/elements/auto_upgrade.star)、[xsaved_web_socket.star](../../config/elements/xsaved_web_socket.star)、[xsaved_web_resident.star](../../config/elements/xsaved_web_resident.star)、[hosts/nixos-gce/hardware.nix](../../hosts/nixos-gce/hardware.nix)

Google Cloud のウェルカムクレジット（$300 / 90日間、[Free Trial 仕様](https://cloud.google.com/free/docs/free-cloud-features)）を活用して、Nix リモートビルド、Rust の `cargo remote-run`、および `xsaved` を GCE 上の NixOS VM で動かし、期間終了後に `purposes` の変更だけで `nixos-desktop` へ戻せるようにするための判断。

## サービス単位で接続先を解決する（`find_home_server` と `expose_services`）

Quaderno の取り込みやリモートデスクトップ（Niri + Sunshine）は手元の `nixos-desktop` に残しつつ、ビルドや `xsaved` だけをクラウド VM（`nixos-gce`）へ移せるよう、サービスごとに担当ホストを解決する。

- `expose_services`: そのアカウントが持つ `serve_*` を他のホストへ SSH / Tailscale 越しに公開する役目（`role = True`）とし、`linger = True`、`ssh_server`、`authorize_lan_key`、`tailscale` を要求する。
- `find_home_server`: `expose_services` が有効なすべてのホスト・アカウントを走査し、`serve_*` ごとに「それを提供している唯一のホストとアカウント」を `services[<serve_*>]` に記録する。同じ `serve_*` を複数のサーバが同時に持った場合はエラーで止める。

クライアント側のコンポーネント（`remote_build`, `cargo_remote_run`, `use_xsaved`, `use_quaderno_archive`, `use_alook`）は、ホストの `purposes` でどの `serve_*` をどのサーバに置くかだけで接続先が切り替わる。
また、`tests/hosts/test-xsaved.toml` のように `expose_services` を選ばずにローカルで `serve_xsaved` だけを動かすテスト用ホストは、ネットワーク上のサービス提供者として衝突しない。

## クラウド VM には `personal_files` と age 鍵を配らず、`authorize_lan_key` で SSH を受ける

`connect_ssh` と `find_home_server` は、SSH ログインを受け付けるアカウントの目印として `authorize_lan_key`（`role = True`）を参照する。
`personal_files` は GitHub の秘密鍵（`id_github`）、個人の秘密一式、private repo の自動 clone まで有効にするため、クラウド VM には指定しない。

また、`.sops.yaml` は単一の age 鍵（`~/.config/sops/age/keys.txt`）で `secrets/secrets.yaml` の全項目（自宅マシンへログインできる `lan_ssh_key` を含む）を暗号化している。GCE に `keys.txt` を置くと、GCE 侵害時に `lan_ssh_key` を復号されて自宅の `nixos-desktop`（`nixos-rebuild` が NOPASSWD）まで奪われるため、`serve_xsaved` 本体から `xsaved_backup`（`xsaved_restic_password` の復号を要求する）を分離し、GCE には `keys.txt` を置かずに運用できるようにした。

## KVM を要するビルド（`serve_kvm_builds`）を通常のビルド（`serve_builds`）と分ける

GCE の E2 シリーズは Nested Virtualization（`/dev/kvm`）に非対応である一方、N2D 等のシリーズや `nixos-desktop` は KVM を持つ（[GCE 汎用マシンシリーズ仕様](https://cloud.google.com/compute/docs/general-purpose-machines)）。
`serve_builds` と `serve_kvm_builds`（`needs = ["local_kvm"]`, `requires = ["serve_builds"]`, `role = True`）を分け、`remote_build` は接続先のビルダーホストが `serve_kvm_builds` も持つときだけ `supportedFeatures` に `kvm` と `nixos-test` を加える。
同時に実行するジョブの上限は、引き受ける側の `nix.settings.max-jobs`（既定の `"auto"` は vCPU 数）がかけるため、クライアント側の `maxJobs`（32）は定数のまま維持する（[remote-build.md](./remote-build.md#任せる先は-find_home_server-が求めジョブ数と-feature-は-remote_buildstar-に置く)）。

`serve_workspace` には、`cargo remote-run` が内部で使用する `nix copy --no-check-sigs` 用の `trusted-users` 設定と `rsync` パッケージを持たせ、`serve_builds` と別のホストへ移しても単体で動作するようにした。

## `serve_xsaved` から専用ディスクマウントと Web 起動方式を分離する

[規則 A](./rules.md) に従い、TOML のフラグや寄与値による条件分岐ではなく、コンポーネントの組み合わせで環境差を表す。

- **データ置き場（`xsaved_data`）**: 専用のデータ用 Btrfs ディスク（`has_data_disk`）を持つ `nixos-desktop` では `xsaved_data` を選ぶ。単一ディスクの `nixos-gce` では `~/.local/share/xsaved` を通常のディレクトリとして使う。`data_subvolume` がある構成では `check_mount` の既定値を真にし、マウント失敗時にルートファイルシステムへ書き込む事故を防ぐ。
- **Web サーバーの起動方式（`xsaved_web_socket` と `xsaved_web_resident`）**:
  - `xsaved_web_socket`: ローカル PC（`nixos-desktop`）向け。ブラウザで開いたときにソケットから起動し、15 分間使われなければ `systemd-socket-proxyd` で停止して VRAM を解放する。
  - `xsaved_web_resident`: 専用サーバ（`nixos-gce`）向け。`xsaved-web-server.service` を `default.target` で常駐させ、初回検索時のプロセス起動・モデル読み込み待ちをなくす。常駐プロセスが `/run/xsaved-gpu.lock` を握り続けると夜間の `xsaved-process` と `xsaved-backup` がデッドロックするため、`XSAVED_NO_GPU_LOCK=1` で検索サーバー側の GPU ロック取得を無効化する。

## GCE ハードウェア設定と `nixos-anywhere`

[hosts/nixos-gce/hardware.nix](../../hosts/nixos-gce/hardware.nix) は nixpkgs 26.05（`f684076`）の `nixos/modules/virtualisation/google-compute-config.nix` を読み込んだうえで、このリポジトリの管理方式と食い違う既定値を上書きする。

- `security.googleOsLogin.enable = lib.mkForce false`: `google-compute-config.nix` が有効にする OS Login を止め、`machine_base` と `authorize_lan_key` による宣言的なアカウント・公開鍵管理に揃える。
- `security.sudo.wheelNeedsPassword = false` と `nix.settings.trusted-users = [ "@wheel" ]`: パスワードを持たない `pomu` が `id_lan` でログインして `sudo tailscale up` や初回の `--target-host` switch を行えるようにする。
- `system.build.diskoScript`: 外部の `disko` flake input を増やさずに `nixos-anywhere --flake .#nixos-gce` を実行できるよう、GCE のブート用永続ディスク（`/dev/disk/by-id/google-persistent-disk-0`）を優先して GPT（`ESP` と `nixos` ラベル）で初期化する。

## 自動更新は `flake-deploy` ではなく `system.autoUpgrade` で行う

`nixos-gce` の定期更新は [auto_upgrade.star](../../config/elements/auto_upgrade.star) で NixOS 標準の `system.autoUpgrade` を使い、持ち主のリポジトリ（[owner.toml](../../config/owner.toml) の `flake_repo`）の `main` を毎日 03:00（最大 15 分遅延）に自前ビルドして `switch` する。

- **既存の GCS キャッシュ配布（`flake-deploy`）に乗せない理由**: [publish-cache.sh](../../scripts/ci/publish-cache.sh) と `flake-cache-worker` は `nixos-desktop` / `nixos-spin713` 向けの恒久基盤であり、90 日間限定のオフロード VM のためにワーカー・テスト・VM サービスアカウント権限を広げると、追加と撤去の双方で保守負担が増える。`nixos-gce` 自身は `serve_builds` を引き受ける VM であり、ヘッドレス構成の自前ビルドに余裕がある。
- **時刻と再起動方針**: `xsaved-process` が毎日 04:00 に始まるため、それより前の 03:00 台に実行して CPU・メモリの競合を避ける。`xsaved` のバッチ系ユニットには `X-SwitchMethod = "keep-old"` が付いているため、再起動を伴わない `switch` なら処理中のバッチを止めない。一方、自動再起動（`allowReboot = true`）はバッチやリモートビルドを中断させるため無効にしている。
- **却下した案**: GitHub Actions から Tailscale / SSH で push する方式は、外部 TCP 22 を閉じて Tailscale に絞る方針に対して CI へ接続鍵を渡す必要があり、攻撃面を広げるため採用しない。

## 見直す条件

- **無料トライアルの制限と CPU メモリ**: 無料トライアル（非課金保証）のままでは GPU を追加できず、プロジェクト全体の同時稼働 vCPU クォータは最大 8 コアに制限される。`xsaved` を GPU なしの CPU 環境で動かす場合は、`xsaved` 本体側で CPU デバイス・CPU 用 PyTorch wheel への対応と、常駐 Web サーバーとバッチ処理が同時に `Qwen3-VL-Embedding-2B` をロードした際のメモリ使用量（16 GB RAM では不足しうる）の実測が必要になる。
- **Spot VM の中断**: Spot VM を使う場合、プリエンプト（強制停止）された際は再起動するまで検索とビルドが止まる（[Spot VM 仕様](https://cloud.google.com/compute/docs/instances/spot)）。
