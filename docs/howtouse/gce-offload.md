# Google Cloud（GCE）へのビルド・xsaved のオフロードとローカル復帰

Google Cloud のウェルカムクレジット（無料トライアル）期間中、Google Compute Engine（GCE）上の NixOS VM（`nixos-gce`）に Nix リモートビルド、Rust の `cargo remote-run`、および `xsaved`（常駐検索サーバー）を移して動かし、期間終了前に `nixos-desktop` へ戻す手順です。

設計ドキュメント: [GCE オフロードの設計](../architecture/gce-offload.md)

## 1. 初回構築（`nixos-anywhere` による GCE VM の NixOS 化）

1. **GCE インスタンスの作成**:
   Google Cloud コンソールまたは `gcloud` で、Debian または Ubuntu の標準 VM（例: `e2-standard-8` Spot または `e2-standard-4`、UEFI / Shielded VM 既定、ブートディスク 200 GB 以上、`tailscale` タグ付き）を作成します。作成時のメタデータ `ssh-keys` に、`config/owner.toml` の `lan_public_key`（`~/.ssh/id_lan.pub`）を `pomu:` プレフィックス付きで登録します。
2. **`nixos-anywhere` の実行**:
   `nixos-desktop` のチェックアウトから以下を実行し、ビルド済みの `nixos-gce` 構成を書き込んで再起動させます（ブート用の永続ディスク `/dev/disk/by-id/google-persistent-disk-0` が [hardware.nix](../../hosts/nixos-gce/hardware.nix) の `diskoScript` で自動初期化されます）。
   ```sh
   nix run nixpkgs#nixos-anywhere -- -i ~/.ssh/id_lan --flake .#nixos-gce --target-host pomu@<GCEの外部IP>
   ```
3. **Tailscale への参加**:
   再起動後に `ssh -i ~/.ssh/id_lan pomu@<GCEの外部IP>` でログインし、tailnet に参加させます（[tailscale.md](./tailscale.md) 参照。`nixos-gce` の `wheel` グループはパスワードなしで `sudo` を実行できます）。
   ```sh
   sudo tailscale up
   ```
   参加後、手元のマシンから `ssh gce-ts` で接続できることを確認し、Google Cloud 側のファイアウォールでは外部からの直接の TCP 22 番を閉じて Tailscale（UDP 41641）経由の接続に絞ります。
4. **チェックアウトの配置**:
   GCE 上で `/etc/nixos` のリンク先となる `~/sagyo/flake_public` を clone します。
   ```sh
   mkdir -p ~/sagyo && git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

## 2. 役割の切り替え（`nixos-desktop` → `nixos-gce`）

サービス（`serve_*`）の担当ホストは、[find_home_server.star](../../config/elements/find_home_server.star) が `expose_services` を持つアカウントの `purposes` からサービスごとに解決します。同じ `serve_*` を 2 台同時に有効にすると評価が止まるため、移すサービスは `nixos-desktop` から外して `nixos-gce` に追加します。

### ステップ A: Nix / Rust ビルドを GCE に移す場合

1. [config/hosts/nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) の `pomu` の `purposes` から、GCE へ移すサービス（`serve_builds`、`serve_kvm_builds`、`serve_workspace`）を外し、デスクトップ自身も GCE にビルドを投げるなら `"remote_build"` や `"cargo_remote_run"` を追加します。
   ```toml
   # nixos-desktop.toml（抜粋）
   "expose_services",
   "serve_quaderno_archive",
   "serve_xsaved",
   "xsaved_data",
   "xsaved_web_socket",
   "xsaved_backup",
   "serve_alook",
   "serve_remote_desktop",
   "stay_awake",
   "remote_build",
   "cargo_remote_run",
   ```
   `serve_remote_desktop` は Niri + Sunshine の配信役です。配信の準備と実機確認は [Tailscale](tailscale.md) を参照してください。

   ※ `serve_workspace` を GCE に移した場合、`program_on_home_server` を選ぶホスト（`nixos-spin713`）の `agent_offload_notes` の接続先も `gce-ts` に変わります。
2. [config/hosts/nixos-gce.toml](../../config/hosts/nixos-gce.toml) の `pomu` の `purposes` に `"serve_builds"` と `"serve_workspace"` を追加します（Nested Virtualization を有効にした N2D 等の場合は `"serve_kvm_builds"` と、ハードウェアプロファイルへの `"local_kvm"` も追加できます）。
   ```toml
   # nixos-gce.toml（抜粋）
   purposes = [
     "expose_services",
     "serve_builds",
     "serve_workspace",
     "etc_nixos_link",
   ]
   ```
3. 各ホストへ適用します（`nixos-gce` は `@wheel` を `trusted-users` に入れているため、初回から `--target-host` で切り替えられます）。
   ```sh
   bash scripts/check.sh
   nixos-rebuild switch --flake .#nixos-gce --target-host gce-ts --sudo
   sudo nixos-rebuild switch --flake .#nixos-desktop
   ```

### ステップ B: `xsaved`（常駐検索サーバー）も GCE に移す場合

> [!CAUTION]
> `~/.config/sops/age/keys.txt` は `secrets/secrets.yaml` 内の `lan_ssh_key`（自宅マシンへログインできる共通鍵）も復号できるため、**GCE には `keys.txt` を置かないでください**。`nixos-gce` では `xsaved_backup` を有効にせず、データ移行と復帰は `nixos-desktop` 側から SSH / rsync で行うか、GCE 専用の別 age 鍵を使う構成にします。

1. **`nixos-desktop` でのタイマー停止と最新バックアップ**:
   ```sh
   systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-web.socket xsaved-sync xsaved-process xsaved-frames xsaved-web-server
   systemctl --user start xsaved-backup.service
   ```
2. **`purposes` の切り替えと switch**:
   - `nixos-desktop.toml` から `"serve_xsaved"`、`"xsaved_data"`、`"xsaved_web_socket"`、`"xsaved_backup"` を外す（`nixos-desktop` から GCE の Web UI を開くなら `"use_xsaved"` が `grow_notes` 等から自動で入ります）。
   - `nixos-gce.toml` の `purposes` に `"serve_xsaved"` と `"xsaved_web_resident"`（Web UI をソケット起動ではなく常駐させるコンポーネント）を追加する。
   - `nixos-gce`、`nixos-desktop`、`nixos-spin713` で switch を実行する（`use_xsaved` の接続先が自動的に `gce-ts` に切り替わります）。
   - ※ [tests/hosts.nix](../../tests/hosts.nix) の `desktop-contracts` と [tests/elements/xsaved.nix](../../tests/elements/xsaved.nix) は `nixos-desktop` が `serve_xsaved` を持つ通常構成を検査しているため、移行中はこれらの契約も移行先に合わせて更新します。
3. **`nixos-gce` へのデータとチェックアウトの転送**:
   `nixos-desktop` から `gce-ts` へ本番用チェックアウト、データ（`tweets/`、`huggingface/`、`x-user`）、および PostgreSQL ダンプを送って投入します。
   ```sh
   ssh gce-ts 'systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-sync xsaved-process xsaved-frames xsaved-web-server'
   rsync -a ~/.local/share/xsaved-app/ gce-ts:.local/share/xsaved-app/
   rsync -a ~/.local/share/xsaved/tweets ~/.local/share/xsaved/huggingface ~/.local/share/xsaved/x-user gce-ts:.local/share/xsaved/
   pg_dump -h /run/postgresql xsaved | ssh gce-ts 'psql -h /run/postgresql -d xsaved -c "DROP OWNED BY CURRENT_USER" && psql -h /run/postgresql -d xsaved'
   ssh gce-ts 'systemctl --user start xsaved-sync.timer xsaved-process.timer xsaved-web-server'
   ```

## 3. クレジット終了前のローカル（`nixos-desktop`）への復帰手順

無料トライアルのまま運用する場合、クレジット残高が尽きるか 90 日が経過した時点でインスタンスが停止します。**必ず残高と期間が残っているうちに**以下の順序で `nixos-desktop` へ戻します。

1. **`nixos-gce` での書き込み停止**:
   ```sh
   ssh gce-ts 'systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-sync xsaved-process xsaved-frames xsaved-web-server'
   ```
2. **`purposes` を `nixos-desktop` に戻して switch（DB とマウントの有効化）**:
   - `config/hosts/nixos-gce.toml` の `purposes` から `serve_*` と `xsaved_web_resident` を外す。
   - `config/hosts/nixos-desktop.toml` の `pomu` の `purposes` に `"serve_xsaved"`、`"xsaved_data"`、`"xsaved_web_socket"`、`"xsaved_backup"`、`"serve_builds"`、`"serve_kvm_builds"`、`"serve_workspace"` を戻し、`"remote_build"` や `"cargo_remote_run"` を外す。
   - `nixos-desktop` で `sudo nixos-rebuild switch --flake .#nixos-desktop` を実行し、PostgreSQL と `@xsaved` のマウントを有効化してから、即座に `nixos-desktop` のタイマーを止めます。
     ```sh
     systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-backup.timer xsaved-web.socket xsaved-sync xsaved-process xsaved-frames xsaved-backup xsaved-web-server
     ```
3. **`nixos-gce` から `nixos-desktop` へのデータ書き戻しと再開**:
   ```sh
   rsync -a gce-ts:.local/share/xsaved/tweets/ ~/.local/share/xsaved/tweets/
   ssh gce-ts 'pg_dump -h /run/postgresql xsaved' | (psql -h /run/postgresql -d xsaved -c 'DROP OWNED BY CURRENT_USER' && psql -h /run/postgresql -d xsaved)
   systemctl --user start xsaved-sync.timer xsaved-process.timer xsaved-backup.timer xsaved-web.socket
   systemctl --user start xsaved-backup.service
   ```
   `xsaved search` および <http://xsaved.home.arpa/> で最後のブックマーク・いいねが検索できることを確認し、`nixos-spin713` でも switch を実行します（手元の Caddy の転送先が nixos-desktop に変わります）。
4. **GCE リソースの削除**:
   Google Cloud コンソールで VM インスタンスと永続ディスクを削除します。
