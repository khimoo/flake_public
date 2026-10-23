# 会社 PC の NixOS-WSL（nixos-work-wsl）

会社の Windows PC 上で動かす NixOS-WSL は、本 flake の `nixosConfigurations.nixos-work-wsl` で管理する。
`local.restrictedHost.enable` が有効化されており、個人の機密情報や自宅マシンへの接続経路は持たせない構成になっている。

設計: [会社 PC の NixOS-WSL の設計](../architecture/wsl.md)

## 新しい PC へのセットアップ

1. Windows に NixOS-WSL のイメージをインストールして起動する。イメージは flake の nixpkgs と同じリリース（26.05 なら 2605.x）のものを使用する。起動すると既定のユーザー `nixos` でログインした状態になる。
2. GitHub の flake を直接指定して switch を実行する。この時点では git は未導入だが、リポジトリの clone も `nix.conf` の事前設定も不要である。

   ```sh
   sudo nixos-rebuild switch --flake github:khimoo/flake_public#nixos-work-wsl
   ```

3. Windows の PowerShell から WSL を再起動する。これによりホスト名が `nixos-work-wsl` に切り替わる。

   ```powershell
   wsl --terminate NixOS
   ```

4. flake を HTTPS 経由で clone する（※この PC からは push しない）。

   ```sh
   git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

## 更新手順

```sh
git -C ~/sagyo/flake_public pull
sudo nixos-rebuild switch
```

手順 2 の switch により `/etc/nixos` が `~/sagyo/flake_public` へのシンボリックリンクになっているため、`--flake` を指定しなくてもホスト名と一致する構成が適用される（[configuration.md](../architecture/configuration.md#etcnixos-のリンク) 参照）。
手順 4 の clone を行う前はリンク先が存在しないため、`--flake` を省略すると失敗する。clone 完了までは手順 2 と同様に flake を指定して switch を実行する。
flake の設定変更は自宅マシン側で行って push し、この PC では pull のみを行う。

## 会社の Git と SSH 設定

会社用の Git ユーザー名とメールアドレスは `~/.gitconfig` に直接記述し、本リポジトリ内には記述しない（記述すると `local.restrictedHost` の assertion に引っかかり評価が停止する）。
`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Home Manager が管理する読み取り専用の `~/.config/git/config` に書き込もうとして失敗するため、初回は `--file` でファイルを明示して設定する。

```sh
git config --file ~/.gitconfig user.name "<会社での名前>"
git config --file ~/.gitconfig user.email "<会社のメールアドレス>"
```

会社の GitHub 用 SSH 鍵の設定（`Host` や `IdentityFile`）は、`~/.ssh/config` に手動で記述する。鍵ファイル自体は `~/.ssh/` に配置する。このホストでは Home Manager による `~/.ssh/config` の管理を行わないため、会社の規定手順に従って設定できる。

## uv による開発

会社の Python プロジェクトを uv で開発する際は、必ず `uv-mode` 環境内で作業する（[cli-tools/uv-mode.md](./cli-tools/uv-mode.md) 参照）。uv が取得する Python や manylinux wheel は、この環境内でなければ正常に動作しない。

## kitty と GUI アプリ

kitty などの GUI アプリは WSLg を通じて Windows デスクトップ上に表示され、Windows のスタートメニューにも登録される。kitty はスタートメニューにピン留めしておくと便利である。
kitty の設定やキー操作は自宅マシンと共通（[cli-tools/kitty.md](./cli-tools/kitty.md) 参照）。

日本語入力は Neovim 内で skkeleton を利用して行う。Windows の IME は kitty には効かないため、シェルプロンプトなど Neovim の外部では日本語を入力できない。

## この PC に配置してはならないもの

- age 秘密鍵（`~/.config/sops/age/keys.txt`）: 同じ鍵で自宅マシンログイン用の `lan_ssh_key` や GitHub 用の `git_ssh_key` まで復号できてしまうため。
- 個人アカウントでの Claude や Codex へのログイン: 会社のソースコードや情報が、会社と契約のない外部サービスへ個人として送信されてしまうほか、認証情報（`~/.claude/.credentials.json`、`~/.codex/auth.json`）が社内から閲覧可能なディスク上に残ってしまうため。パッケージ（`claude` や `codex`）自体は導入されているが、社用アカウントが支給されるまでは使用しない。
- `khimoo` の push 権限を持つ認証情報: WSL の仮想ディスクは、会社の端末管理ツールや管理者から閲覧可能な状態にあるため。

このホストに secret、SSH 鍵、Git identity、sshd、tailnet、リモートビルドなどの設定を追加しようとすると、`local.restrictedHost:` で始まる assertion により評価が停止し、どの設定に抵触したかが表示される。
正当な理由があって制限を解除する場合（私用 PC で利用することになった場合など）は、あらかじめ[設計の見直す条件](../architecture/wsl.md#見直す条件)を確認すること。
