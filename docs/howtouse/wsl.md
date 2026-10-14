# 会社PCの NixOS-WSL（nixos-work-wsl）

会社の Windows PC にセットアップした NixOS-WSL は、本 flake の `nixosConfigurations.nixos-work-wsl` で管理します。
このホストでは `local.restrictedHost.enable` を有効にしており、個人の機密情報や自宅マシンへの接続経路を含まない構成になっています。設計方針や判断理由の詳細は [docs/architecture/wsl.md](../architecture/wsl.md) を参照してください。

## 新しいPCへの導入手順

1. Windows 側で NixOS-WSL のイメージをインポート（インストール）して起動します。イメージは flake 内の nixpkgs と同じリリースのものを使用してください（例: 26.05 なら 2605.x）。起動すると、デフォルトユーザーの `nixos` でログインした状態になります。
2. GitHub から flake を直接指定して switch を実行します。この時点ではまだ git コマンドがインストールされていないため、事前の clone は不要です。また、`nixos-rebuild` が自動的に Flakes 機能を有効化して Nix を呼び出すため、事前に `nix.conf` を設定する必要もありません。

   ```sh
   sudo nixos-rebuild switch --flake github:khimoo/flake_public#nixos-work-wsl
   ```

3. Windows 側の PowerShell で WSL を一度停止し、再度起動します。これによりホスト名が `nixos-work-wsl` に切り替わります。

   ```powershell
   wsl --terminate NixOS
   ```

4. flake を HTTPS 経由で clone します（なお、この PC から push することはありません）。

   ```sh
   git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

## 会社の Git と SSH の設定

会社用の Git identity（ユーザー名やメールアドレス）は `~/.gitconfig` に直接記述します。本リポジトリのコード内には絶対に記述しないでください（記述すると `local.restrictedHost` のアサーションエラーが発生し、評価が停止します）。

```sh
git config --file ~/.gitconfig user.name "<会社での名前>"
git config --file ~/.gitconfig user.email "<会社のメールアドレス>"
```

`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Git は Home Manager が管理する読み取り専用ファイル `~/.config/git/config` に書き込もうとしてエラーになります。初回設定時は必ず `--file ~/.gitconfig` を指定してください。

会社の GitHub 用 SSH 鍵は、`~/.ssh/config` に手動で設定します。このホストでは Home Manager が `~/.ssh/config` を管理しないため、会社指定の手順どおりに記述できます。

## uv を使う開発

会社の Python プロジェクトを uv で開発するときは、`uv-mode` で入った環境の中で作業します。uv が取得する Python と manylinux wheel は、この環境の外では起動しません。モードの中では、プロンプトに `uv-mode` と表示されます。共有リポジトリに shell.nix などを置く必要はありません。使い方は [cli-tools/uv-mode.md](./cli-tools/uv-mode.md) を参照してください。

## kitty と GUI アプリ

このホストでは `features.gui` を有効にしており、kitty などの GUI アプリは WSLg で Windows のデスクトップに表示されます。kitty の設定とキー操作は自宅のマシンと同じです（[cli-tools/kitty.md](./cli-tools/kitty.md)）。

GUI アプリは Windows のスタートメニューに並びます。kitty はスタートにピン留めしておくと、すぐに起動できます。

日本語は、Neovim の中で skkeleton を使って入力します。Windows の IME は kitty には届かないので、シェルのプロンプトなど Neovim の外では日本語を打てません。

`features.gui` を有効にした後の最初の switch の前に、Cursor の AppImage の取得先に届くかを確かめてください。switch のたびにここから取得しており、初回の取得に失敗するとアクティベーションが止まります。

```sh
curl -fsSI https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/latest | head -1
```

`HTTP/2 200` などの応答が返れば問題ありません。エラーになる場合は switch せず、[docs/architecture/wsl.md](../architecture/wsl.md) の見直し契機に従って、制限付きのホストで取得を飛ばす変更を先に入れます。

## 更新手順

```sh
git -C ~/sagyo/flake_public pull
sudo nixos-rebuild switch
```

手順 2 の switch を実行すると、`/etc/nixos` は `~/sagyo/flake_public` へのリンクに置き換わります。そのため `--flake` を指定しなくても、`nixos-rebuild` はチェックアウト先を参照し、ホスト名と同じ名前の構成（`nixos-work-wsl`）を適用します。イメージによって作成された `/etc/nixos/configuration.nix` はこの時点で削除されます。仕組みの詳細については [docs/architecture/configuration.md](../architecture/configuration.md#etcnixos-のリンク) を参照してください。

手順 4 の clone が完了するまではリンク先が存在しないため、`--flake` を省略して `nixos-rebuild` を実行するとエラーで停止します。それまでに再度 switch する場合は、手順 2 と同じコマンドを使用してください。

flake の変更は自宅マシン側で行って push し、この PC では pull のみを実施します。

## このPCに配置してはいけないもの

- **age 秘密鍵（`~/.config/sops/age/keys.txt`）**：自宅マシン接続用の `lan_ssh_key` や GitHub 用の `git_ssh_key` なども同一の鍵で復号できてしまうため。
- **個人アカウントでの Claude や Codex へのログイン**：会社のコードや情報が、会社と契約していない外部サービスへ個人として送信されてしまいます。また、ログイン資格情報（`~/.claude/.credentials.json`、`~/.codex/auth.json`）も会社から閲覧可能なディスク上に残ります。`claude` や `codex` コマンドは他ホストと共通の設定として導入されていますが、社用アカウントが支給されていない場合は使用しないでください。なお、個人用の設定（agents-private）もこのホストには配置していません。
- **`khimoo` の push 権限を持つ認証情報**：WSL の仮想ディスクは、会社の端末管理ツールや管理者アカウントから読み取り可能です。

リポジトリ側でこのホストに secret、SSH 鍵、Git identity、sshd、tailnet、リモートビルドなどを追加しようとすると、`local.restrictedHost:` で始まるアサーションエラーによって評価が中断されます。エラーメッセージには制限に抵触した設定項目が表示されます。もし制限を解除すべき正当な理由がある場合（会社用ではなく個人の PC で使用することになった場合など）は、事前に `docs/architecture/wsl.md` の「今後の見直し契機」を確認してください。
