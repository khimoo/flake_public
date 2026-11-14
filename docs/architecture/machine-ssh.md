# マシン間 SSH の設計

使い方: [マシン間 SSH](../howtouse/machine-ssh.md)
実装: [ssh_server.star](../../config/elements/ssh_server.star)、[accept_ssh_admin.star](../../config/elements/accept_ssh_admin.star)、[accept_ssh_server.star](../../config/elements/accept_ssh_server.star)、[authorize_lan_key.star](../../config/elements/authorize_lan_key.star)、[connect_ssh.star](../../config/elements/connect_ssh.star)、[owner.toml](../../config/owner.toml)

ssh のログインを受け付ける利用者がいる NixOS ホストへ、ほかのホストから `ssh <短縮名>` で接続できるようにする。
リモートビルド（[remote-build.md](./remote-build.md)）はこの上に乗る。

## 接続を受ける側の判定から、両方向を生成する

接続を受ける側と接続する側を、別の要素にしている。

- `ssh_server`: sshd を動かし、mDNS で名前を知らせる。機体の要素が `requires` に挙げる。
- `accept_ssh_admin` と `accept_ssh_server`: `ssh_server` のある機体で、ホストを管理する利用者（`etc_nixos_link`）と、自分用サーバを動かす利用者（`run_home_server`）に入る派生要素。`requires` の `authorize_lan_key` が、持ち主の値 `lan_public_key` をその利用者の `authorized_keys` に入れる。
- `connect_ssh`: `accept_ssh_admin` か `accept_ssh_server` が入っている利用者のいるホストごとに、`Host` ブロック（短縮名、`IdentityFile`、`User`、`accept-new`）を作る。どのホストのどの利用者に入っているかは、confgen が全ホストの `purposes` から求めて `roles` で渡す。`User` は、ホストを管理する利用者にする。

接続する側は、接続を受ける側の判定そのものを読む。
ホストの TOML に `ssh_user` のような目印を書き、接続する側がそれを読む形は退けた。sshd を動かす機体と目印を別々に書くことになり、sshd のない機体への `Host` ブロックや、公開鍵の入っていないアカウントへのログイン名を、confgen が止められない。

ログイン名をホストごとに 1 つにするため、1 台で `accept_ssh_admin` が入る利用者が 2 人いると `connect_ssh` が生成を止める。
自分用サーバのサービスを別の利用者が動かしている場合は、クライアントの要素が `find_home_server` の公開値から `<利用者>@<接続名>` を受け取る。

各ホストに `authorizedKeys` を直接書くと、双方向にしたときマシンの数の 2 乗だけ書くことになる。

`ssh <短縮名>` で接続するには、認証、名前解決、ホスト鍵の受け入れが要る。
名前解決は avahi の mDNS（LAN の外では tailnet の MagicDNS を引く `<短縮名>-ts`、[tailscale.md](./tailscale.md)）に任せ、認証とホスト鍵の扱いと短縮名を `connect_ssh` が作る。

## 鍵は用途で名付ける

`~/.ssh/id_lan` は LAN の中のマシン同士に、`~/.ssh/id_github` は GitHub に使う。GitHub 用の `Host` ブロックは [github_ssh.star](../../config/elements/github_ssh.star) が書き、GitHub 用の鍵を置く要素（`personal_files`、`agent_links`）が `requires` に挙げる。
`id_ed25519` のようなアルゴリズムの名前にすると、1 本に複数の役割が載っても気づけない。
この repo では `~/.ssh/id_ed25519` が LAN と GitHub を兼ねていて、GitHub の鍵を作り直したときに LAN の接続まで壊れた。

## LAN の認証は全マシン共通の 1 本にする

新しいマシンで要る作業は age 鍵を置くことだけになり、マシンを足すときに既存の全マシンで switch しなくて済む（`authorized_keys` が変わらないため）。
代わりに、マシンごとに失効させられない。1 台をなくしたら `lan_ssh_key` を作り直し、全マシンで switch する。3 台の規模では、増やすたびに全マシンで switch する手間を消すほうが効く。

マシンごとの鍵にしていた理由は、同じ SSH 鍵を `ssh-to-age` で変換して sops の復号にも使っていたことで、1 本漏れると全部の秘密が危うかった。
今は復号の種は独立した age 鍵（`~/.config/sops/age/keys.txt`）で、`id_lan` は LAN へのログインにしか使えない。

## 鍵は実行するユーザーの home から読む

`Host` ブロックの `IdentityFile` は `~/.ssh/id_lan` で、一般ユーザーも root も自分の home を見る。ほかのユーザーの絶対パスを共有しない。鍵を持たないユーザーでは、この指定は読み飛ばされる。

root は `id_lan` を持たないので、`sudo nixos-rebuild --build-host` のように root として SSH すると失敗する。`--build-host` は `sudo` を付けずに `--sudo` で実行する（[remote-build.md](./remote-build.md)）。
この手順は ssh-agent に頼らないので、`IdentitiesOnly yes` でも通る（2026-09-16 に spin713 から確認）。

例外は常設のリモートビルダーで、nix-daemon（root）が `/etc/nix/machines` の `sshKey` で利用者の `id_lan` を絶対パスで読む（[remote-build.md](./remote-build.md#鍵は利用者の-id_lan-を絶対パスで読む)）。

## 鍵は ssh で接続する要素が入る利用者にだけ配る

ほかの機体へ ssh で接続する要素（`use_xsaved`、`remote_build` など）が、`requires` の `find_home_server` を通して `lan_ssh_key` を入れ、その要素が入る利用者だけが共通鍵を受け取る。OS が NixOS というだけでは配らない。
共通鍵を持つユーザーは、接続先でログインを受け付ける利用者として認証できるため。

ホストかユーザーの TOML の `lan_ssh = true` で選ぶ案は退けた。鍵が要る理由（ssh で接続する要素）と鍵を配る指定が別の場所になり、要素を選んだのに鍵がない状態や、要素をやめたのに鍵だけ残る状態を confgen が止められない。

代償として、これらの要素が入らない利用者は、`ssh desktop` のように人が打つ ssh にも使える鍵を持たない。

## ホスト鍵は accept-new で受け入れる

初回の接続ではホスト鍵を自動で受け入れ、以後の変更は拒否する。家庭の LAN の脅威にはこれで足りる。
`programs.ssh.knownHosts` にホスト鍵を直接書く案は、入れ直すたびに書き換えが要るので退けた。
`--build-host` の SSH では実行ユーザーの known_hosts に、常設のリモートビルダーでは root の known_hosts に、同じ設定で追加される。

## セキュリティ

- repo に入るのは `config/owner.toml` の公開鍵と、age で暗号化した `secrets/secrets.yaml` だけ
- 全マシンの秘密鍵は同じ鍵なので、1 台が侵害されたら LAN の認証を全部作り直す
- `PasswordAuthentication = false` で、鍵の認証しか受け付けない
- 対象は NixOS ホストだけで、standalone home-manager（macOS）には `id_lan` を配らない

## 見直す条件

- マシンの台数や共有する人が増えたら、マシンごとの鍵か SSH の証明書（CA）に戻す
