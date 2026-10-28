# 会社 PC の NixOS-WSL（nixos-work-wsl）

会社の Windows PC 上で動かす NixOS-WSL は、本 flake の `nixosConfigurations.nixos-work-wsl` で管理します。
`local.restrictedHost.enable` が有効化されており、個人の機密情報や自宅マシンへの接続経路を持たせない安全な構成になっています。

設計: [会社 PC の NixOS-WSL の設計](../architecture/wsl.md)

## 新しい PC へのセットアップ

1. Windows に NixOS-WSL のイメージをインストールして起動します。イメージは flake の nixpkgs と同じリリース（26.05 なら 2605.x）のものを使用してください。起動すると既定のユーザー `nixos` でログインした状態になります。
2. GitHub 上の flake を直接指定して switch を実行します。この時点では git は未導入ですが、リポジトリの clone も `nix.conf` の事前設定も不要です。

   ```sh
   sudo nixos-rebuild switch --flake github:khimoo/flake_public#nixos-work-wsl
   ```

3. Windows の PowerShell から WSL を再起動します。これによりホスト名が `nixos-work-wsl` に切り替わります。

   ```powershell
   wsl --terminate NixOS
   ```

4. flake を HTTPS 経由で clone します（※この PC からは push しないでください）。

   ```sh
   git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

## 更新手順

```sh
git -C ~/sagyo/flake_public pull
sudo nixos-rebuild switch
```

手順 2 の switch により `/etc/nixos` が `~/sagyo/flake_public` へのシンボリックリンクになっているため、`--flake` を指定しなくてもホスト名と一致する構成が自動で適用されます（[configuration.md](../architecture/configuration.md#etcnixos-のリンク) 参照）。
手順 4 の clone を行う前はリンク先が存在しないため、`--flake` を省略すると失敗します。clone が完了するまでは手順 2 と同様に flake を明示して switch を実行してください。
flake の設定変更は自宅マシン側で行って push し、この PC では pull のみを行います。

## 会社の Git と SSH 設定

会社用の Git ユーザー名とメールアドレスは `~/.gitconfig` に直接記述し、本リポジトリ内には記述しないでください（記述すると `local.restrictedHost` の assertion に引っかかり評価が停止します）。
`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Home Manager が管理する読み取り専用の `~/.config/git/config` に書き込もうとして失敗します。そのため、初回は `--file` オプションでファイルを明示して設定してください。

```sh
git config --file ~/.gitconfig user.name "<会社での名前>"
git config --file ~/.gitconfig user.email "<会社のメールアドレス>"
```

会社の GitHub 用 SSH 鍵の設定（`Host` や `IdentityFile`）は、`~/.ssh/config` に手動で記述します。鍵ファイル自体は `~/.ssh/` に配置してください。このホストでは Home Manager による `~/.ssh/config` の管理を行わないため、会社の規定手順に従って柔軟に設定できます。

## uv による開発

会社の Python プロジェクトは、uv が取得する Python と PyPI の manylinux wheel で動かします。このホストでは nix-ld が有効化されているため、任意のシェルから `uv sync` や `uv run` を実行でき、`.venv` 内の Python もそのまま起動します（[設計](../architecture/wsl.md#uv-が取得する-python-を-nix-ld-で動かす)）。
uv は Home Manager が生成する `~/.config/uv/uv.toml` の設定に従い、uv が取得・管理する Python のみを使用します。

wheel のインポート時に `cannot open shared object file` が発生した場合は、該当ライブラリを含むパッケージを [hosts/nixos-work-wsl/default.nix](../../hosts/nixos-work-wsl/default.nix) の `programs.nix-ld.libraries` に追記して switch してください。指定したパッケージは、zlib や libstdc++ などの既定ライブラリ群に追加されます。

Neovim の pyright にプロジェクト固有の `.venv` を認識させるには、`source .venv/bin/activate` を実行してから nvim を起動してください。pyright はプロジェクト内の `.venv` を自動検索せず、PATH 上の `python` を参照します。activate しないと Nix 提供の python3 が使われてしまい、依存パッケージや uv workspace 内の別パッケージの import が `could not be resolved` エラーになります。

## kitty と GUI アプリ

kitty などの GUI アプリケーションは WSLg を通じて Windows デスクトップ上にシームレスに表示され、Windows のスタートメニューにも登録されます。kitty はスタートメニューにピン留めしておくと便利です。
kitty の設定やキーバインドは自宅マシンと共通です（[cli-tools/kitty.md](./cli-tools/kitty.md) 参照）。

日本語入力は Neovim 内で skkeleton を利用して行います。Windows 側の IME は kitty には反映されないため、シェルプロンプトなど Neovim の外部では日本語を入力できない点に注意してください。

## この PC に配置してはならないもの

- age 秘密鍵（`~/.config/sops/age/keys.txt`）: 同一の鍵で自宅マシンログイン用の `lan_ssh_key` や GitHub 用の `git_ssh_key` まで復号できてしまうため。
- 個人アカウントでの Claude や Codex へのログイン: 会社のソースコードや業務情報が、会社契約のない外部サービスへ個人として送信されてしまうリスクがあるほか、認証情報（`~/.claude/.credentials.json`、`~/.codex/auth.json`）が社内から参照可能なディスク上に残ってしまうため。パッケージ（`claude` や `codex`）自体は導入されていますが、社用アカウントが支給されるまでは使用しないでください。
- `khimoo` の push 権限を持つ認証情報: WSL の仮想ディスクは、会社の端末管理ツールや管理者から閲覧可能な状態にあるため。

このホストに secret、SSH 鍵、Git identity、sshd、tailnet、リモートビルドなどの設定を追加しようとすると、`local.restrictedHost:` で始まる assertion により評価が停止し、違反した設定内容が表示されます。
正当な理由があって制限を解除する場合（私用 PC として利用することになった場合など）は、あらかじめ[設計の見直す条件](../architecture/wsl.md#見直す条件)を確認してください。
