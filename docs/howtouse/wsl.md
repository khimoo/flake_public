# 会社PCの NixOS-WSL（nixos-work-wsl）

会社の Windows PC にセットアップした NixOS-WSL を、この flake の `nixosConfigurations.nixos-work-wsl` で管理します。
このホストでは `local.restrictedHost.enable` を有効にしており、個人の機密情報や自宅マシンへの接続経路を持たない構成になっています。設計方針や判断の根拠については [docs/architecture/wsl.md](../architecture/wsl.md) を参照してください。

## 新しいPCへの導入手順

1. Windows 側で NixOS-WSL のイメージをインポート（インストール）して起動します。イメージは flake 内の nixpkgs と同じリリースのものを使用してください（例: 26.05 なら 2605.x）。デフォルトユーザーの `nixos` でログインした状態になります。
2. GitHub から flake を直接指定して switch を実行します。この時点ではまだ git コマンドがないため、clone は不要です。`nixos-rebuild` が自動的に Flakes 機能を有効にして Nix を呼び出すため、事前の `nix.conf` 設定も必要ありません。

   ```sh
   sudo nixos-rebuild switch --flake github:khimoo/flake_public#nixos-work-wsl
   ```

3. Windows 側の PowerShell で WSL を一度停止し、再度起動します。これによりホスト名が `nixos-work-wsl` に切り替わります。

   ```powershell
   wsl --terminate NixOS
   ```

4. flake を HTTPS 経由で clone します。なお、この PC から push することはありません。

   ```sh
   git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

5. agents-private リポジトリを読み取るための deploy key を作成します。

   ```sh
   ssh-keygen -t ed25519 -C nixos-work-wsl-agents-private -f ~/.ssh/id_agents_private
   cat ~/.ssh/id_agents_private.pub
   ```

   表示された公開鍵を、`khimoo` アカウントでログインしている自宅マシンなどから、GitHub の agents-private リポジトリ（Settings → Deploy keys）に登録します。この PC には `khimoo` の資格情報を置かないため、この環境のブラウザ等からは登録しないでください。また、「Allow write access」にはチェックを入れないでください。

6. 適用される SSH 鍵の設定を確認した上で、エイリアスホスト名を使って agents-private を clone します。

   ```sh
   ssh -G github-agents-private | grep -E '^(hostname|user|identityfile|identitiesonly) '
   git clone git@github-agents-private:khimoo/agents-private.git ~/sagyo/agents-private
   ```

   `identityfile` の出力が `~/.ssh/id_agents_private` の 1 行のみで、`identitiesonly yes` と表示されていれば問題ありません。

`~/.claude` などへのシンボリックリンクや `/etc/claude-code/managed-settings.json` は、agents-private を clone した時点でリンク先が解決されます。clone 後に改めて `nixos-rebuild switch` を実行する必要はありません。

## 会社の Git と SSH の設定

会社用の Git identity（名前やメールアドレス）は `~/.gitconfig` に直接記述します。本リポジトリのコード内には書かないでください（記述すると `local.restrictedHost` のアサーションエラーで評価が停止します）。

```sh
git config --file ~/.gitconfig user.name "<会社での名前>"
git config --file ~/.gitconfig user.email "<会社のメールアドレス>"
```

`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Git は Home Manager が管理する読み取り専用ファイル `~/.config/git/config` に書き込もうとして失敗します。初回は必ず `--file ~/.gitconfig` を指定して設定してください。

会社の GitHub 用 SSH 鍵は、`~/.ssh/config` の `Host github.com` セクションに記述します。

```
Host github.com
  IdentityFile ~/.ssh/id_company
  IdentitiesOnly yes
```

これを `Host *` に書いてしまうと、`github-agents-private` への接続時にも会社用鍵が優先して試行され、会社のアカウントとして認証されて agents-private の pull に失敗します。設定後は、手順 6 の `ssh -G` コマンドで agents-private 用の鍵のみが参照されていることを確認してください。

## 更新手順

```sh
git -C ~/sagyo/flake_public pull
git -C ~/sagyo/agents-private pull
sudo nixos-rebuild switch --flake ~/sagyo/flake_public#nixos-work-wsl
```

`#nixos-work-wsl` の指定は省略しないでください。手順 3 の再起動前など、ホスト名が `nixos` のままだと、省略時に存在しない `nixosConfigurations.nixos` を参照しようとしてエラーになります。

flake や agents-private の変更は自宅マシン側で行って push し、この PC では pull のみを行います。

## このPCに配置してはいけないもの

- **age 秘密鍵（`~/.config/sops/age/keys.txt`）**：自宅マシン接続用の `lan_ssh_key` や GitHub 用の `git_ssh_key` なども同一の鍵で復号できてしまうため。
- **Gemini の API キー**：配置すると、agents-private のコミット前校正フックが会社のコミットメッセージを Gemini に送信してしまいます。キーが未設定であれば校正フックは失敗しますが、コミット自体はそのまま通ります。
- **`khimoo` の push 権限を持つ認証情報**：WSL の仮想ディスクは、会社の端末管理ツールや管理者アカウントから読み取り可能です。

リポジトリ側でこのホストに secret、SSH 鍵、Git identity、sshd、tailnet、リモートビルドなどを追加しようとすると、`local.restrictedHost:` で始まるアサーションエラーにより評価が中断されます。エラーメッセージには制限に抵触した設定項目が表示されます。もし制限を解除すべき正当な理由がある場合（会社用ではなく個人の PC で使用することになった場合など）は、事前に `docs/architecture/wsl.md` の「今後の見直し契機」を確認してください。

## トラブルシューティング

agents-private の clone や pull が `Repository not found` で失敗する場合は、会社用の SSH 鍵が干渉している可能性が高いです。手順 6 の `ssh -G` の出力結果を確認し、`~/.ssh/id_agents_private` 以外の `identityfile` が含まれている場合は、`~/.ssh/config` の `Host *` に会社用の鍵が設定されていないか見直してください。
