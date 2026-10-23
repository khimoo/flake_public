# SSH 鍵の配布と private repo の clone

新しい環境のセットアップで手作業が必要なのは、age 鍵を 1 つ配置することと `clone-repos` を実行することだけです。
switch 実行時に `secrets/secrets.yaml` が age 鍵で復号されて SSH 鍵が書き出され、その鍵を使って `clone-repos` が private repo を clone します。
NixOS でも macOS でも同じ手順で利用できます。なお、会社 PC の nixos-work-wsl には age 鍵を配置しないため対象外です（[wsl.md](./wsl.md) 参照）。

設計: [private repo の clone の設計](../architecture/private-repo-clone.md)

## 新しい環境を準備する

1. age 鍵を `~/.config/sops/age/keys.txt` に配置します（既存のマシンから SSH 経由で転送するか、Bitwarden から取得します）。
2. switch を実行します。これにより `~/.ssh/id_github`（GitHub 用）と `~/.ssh/id_lan`（LAN 用、[machine-ssh.md](./machine-ssh.md) 参照）が書き出されます。
3. `clone-repos` を実行します（`clone-repos --dry-run` を指定すると、clone 予定の repo を確認できます）。

age 鍵はすべての環境で共通のため、マシンごとに受信者を追加したり SSH 鍵を個別に登録したりする必要はありません。

age 鍵が存在しない場合や復号に失敗した場合は、switch がエラーで中断します。
`clone-repos` は `dest` ディレクトリが存在しない repo のみを clone し、すでに checkout 済みの既存 Git ディレクトリには手を加えません。
もし `dest` に Git 管理外のディレクトリがすでに存在している場合は、その repo を失敗として報告したうえで残りの処理を続行します。中身を確認して退避させた後、再度実行してください。
clone の途中で失敗した場合でも一時領域はクリーンアップされるため、そのまま再実行できます。

## 手元の checkout を一括で更新する

```sh
pull-repos
```

clone 対象の repo と flake 自身に対して `git pull --ff-only` を実行します。
ローカルコミットによって分岐している repo は git に拒否されるため、該当する repo のみ手動で rebase または merge してください。
1 つの repo で失敗しても残りの処理は継続し、最終的に非ゼロのステータスで終了します。まだ clone されていない repo はスキップされ、その旨のみ報告されます。

## clone する repo を変更する

対象ユーザーの home モジュールの `local.profile` で、repo の URL と配置先を指定します。
pomu では [pomu-workstation.nix](../../profiles/home/pomu-workstation.nix) に定義されており、`agentConfigRoot` のみ [pomu-agents.nix](../../profiles/home/pomu-agents.nix) で設定します。

- vault: `zettelkastenRepoUrl` と `zettelkastenRoot`
- エージェント設定: `agentConfigRepo` と `agentConfigRoot`
- zettelkasten-workflow: `vaultSkeletonRepoUrl` と `vaultSkeletonRepo`
- LLM Wiki: `llmWikisRepoUrl` と `llmWikisRoot`
- それ以外: `local.profile.privateRepos` に `{ url; dest; }` を追加

URL を設定しない（デフォルトの `null` のままにする）場合、その repo は手動で clone する運用になります。配置先パスだけを残しておけば、symlink や同期、`mirror-vault` などの機能はそのまま利用可能です。
vault は `services.zettelkasten.initializeVault` で作成することも可能ですが、有効にはしません。先に空フォルダが作成されると clone が失敗するためです。

clone 対象の repo がなく、`lanSsh = false` で、かつ `sshKeys` と `secrets` も空であれば、age 鍵は不要です。
ただし pomu では `lanSsh = true` に設定されているため、repo の clone を行わない場合でも age 鍵が必要です。

## SSH 鍵以外のシークレットを配布する

シークレットを `secrets/secrets.yaml` に追加したうえで、配置先を宣言します。

```sh
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops secrets/secrets.yaml
```

```nix
local.profile.secrets = [
  { secret = "gemini_api_key"; path = "${config.home.homeDirectory}/.config/gemini/api-key"; }
];
```

`mode` のデフォルトは `600` であり、home ディレクトリ外のパスを指定すると評価時に拒否されます。
switch を実行するたびに、宣言されたファイルは暗号化データの内容および指定された mode へ同期されます。シークレットを変更したい場合は `secrets/secrets.yaml` を編集してください。
宣言から削除されたファイルは次回の switch 時に削除されます（symlink やディレクトリの場合は警告を出してそのまま残します）。
なお、`~/.ssh` 配下にパーミッション `600` で配置する SSH 鍵であれば、`local.profile.sshKeys = [{ secret; name; }]` のように簡潔に記述できます。

## SSH 鍵を差し替える手順

switch を実行するとローカルの既存鍵は暗号化データの内容に更新されますが、GitHub や他のマシン側の設定は自動で更新されません。GitHub の鍵を更新する際は、以下の手順で行います。

1. 新しい鍵で [secrets.yaml を再生成](#secretsyaml-を作成する) してコミットする
2. GitHub に新しい公開鍵を登録する（`gh ssh-key add`）。登録前に switch してしまうと、その時点で GitHub との通信ができなくなるため注意してください
3. 各マシンで pull して switch を実行し、`ssh -T git@github.com` で接続できることを確認する
4. すべてのマシンで動作確認が取れたら、GitHub から古い鍵を削除（失効）する。失効後は Nix の世代をロールバックしても古い鍵での認証は行えなくなります

LAN 用の鍵については、全マシンの `authorized_keys` も書き換わるため、すべてのマシンの更新が完了するまでは一部のマシン間で SSH 接続ができなくなります。手順の詳細は [machine-ssh.md](./machine-ssh.md#lan-共通鍵の再生成手順) を参照してください。

## age 鍵を再作成する手順

age 鍵を紛失すると `secrets.yaml` を復号できなくなり、pomu の switch もエラーで停止します。
中身は再生成可能な SSH 鍵なので、新しい age 鍵を使って [secrets.yaml を作り直します](#secretsyaml-を作成する)。

- 紛失した場合: いずれかのマシンの `~/.ssh/` に SSH 秘密鍵が残っていればそれを再利用します。どこにも残っていない場合は SSH 鍵も再作成し、GitHub への再登録と `hosts/machines.nix` の `lanPublicKey` の差し替えを行ってください。
- 漏洩した場合: 漏洩した age 鍵を入手した人物は、Git 履歴にある過去の `secrets.yaml` もすべて復号できてしまいます。そのため、中に含まれる SSH 鍵も漏洩したものとみなし、再作成したうえで GitHub 上の古い鍵を失効させてください。

再作成が完了したら、各マシンの `~/.config/sops/age/keys.txt` を新しい鍵に差し替えます。古い鍵のままでは switch が失敗します。

## secrets.yaml を作成する

初期セットアップ時、または age 鍵や SSH 鍵を作り直す際の手順です。
`git_ssh_key` は `~/.ssh/id_github` に、`lan_ssh_key` は `~/.ssh/id_lan` にそれぞれ書き出されます。

1. age 鍵を生成します。新しい環境を構築する際は Bitwarden からこの鍵を取得するため、`keys.txt` は Bitwarden に保管してください。公開 repo には決してコミットしないでください。

   ```sh
   mkdir -p ~/.config/sops/age
   ( umask 077; nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt )
   ```

2. 出力された公開鍵（`Public key: age1...`）を、[.sops.yaml](../../.sops.yaml) の `&deploy` アンカーに設定します。
3. SSH 鍵がない場合は作成します。GitHub 用の鍵は `gh` コマンドで登録します。LAN 用の鍵は無人実行で使用するためパスフレーズなしで生成し、`~/.ssh/id_lan.pub` の内容を `hosts/machines.nix` の `lanPublicKey` に指定します。

   ```sh
   ssh-keygen -t ed25519 -C "$(hostname)" -f ~/.ssh/id_github
   gh ssh-key add ~/.ssh/id_github.pub --title "$(hostname) $(date +%F)"
   ssh-keygen -t ed25519 -C pomu@lan -f ~/.ssh/id_lan -N ''
   ```

4. 平文をターミナルに表示させずに暗号化を行い、`secrets/secrets.yaml` をコミットします。`.sops.yaml` は `secrets/*.yaml` のパスをもとに受信者を判定するため、一時ファイルを暗号化する際は `--filename-override` オプションの指定が必要です。

   ```sh
   tmp=$(mktemp -p "$XDG_RUNTIME_DIR"); chmod 600 "$tmp"
   { echo 'git_ssh_key: |'; sed 's/^/  /' ~/.ssh/id_github;
     echo 'lan_ssh_key: |'; sed 's/^/  /' ~/.ssh/id_lan; } > "$tmp"
   nix shell nixpkgs#sops -c sops --encrypt --filename-override secrets/secrets.yaml \
     --input-type yaml --output-type yaml "$tmp" > secrets/secrets.yaml
   shred -u "$tmp"
   grep -c 'BEGIN OPENSSH' secrets/secrets.yaml   # 0 なら暗号化されている
   ```
