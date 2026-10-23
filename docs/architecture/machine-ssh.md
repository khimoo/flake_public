# マシン間 SSH の設計

使い方: [マシン間 SSH](../howtouse/machine-ssh.md)
実装: [machines.nix](../../hosts/machines.nix)、[ssh.nix](../../modules/nixos/ssh.nix)

`machines.nix` で `sshUser` を持つ NixOS ホストが、互いに `ssh <短縮名>` で接続できるようにする。
リモートビルド（[remote-build.md](./remote-build.md)）はこの上に乗る。

## `machines.nix` から両方向を生成する

`ssh.nix` が `machines.nix` から、サーバ側には `lanPublicKey` を primaryUser の `authorized_keys` に入れ、クライアント側には `sshUser` を持つマシンごとの `Host` ブロック（短縮名、`IdentityFile`、`User`、`accept-new`）を作る。
各ホストに `authorizedKeys` を直接書くと、双方向にしたときマシンの数の 2 乗だけ書くことになる。

`ssh <短縮名>` で接続するには、認証、名前解決、ホスト鍵の受け入れが要る。
名前解決は avahi の mDNS（LAN の外では tailnet の MagicDNS を引く `<短縮名>-ts`、[tailscale.md](./tailscale.md)）に任せ、認証とホスト鍵の扱いと短縮名を `machines.nix` から作る。

## 鍵は用途で名付ける

`~/.ssh/id_lan` は LAN の中のマシン同士に、`~/.ssh/id_github` は GitHub に使う。
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

例外は常設のリモートビルダーで、nix-daemon（root）が `/etc/nix/machines` の `sshKey` で primaryUser の `id_lan` を絶対パスで読む（[remote-build.md](./remote-build.md#鍵は-primaryuser-の-id_lan-を絶対パスで読む)）。

## 鍵は `lanSsh` を選んだユーザーにだけ配る

`local.profile.lanSsh = true` のユーザーだけが共通鍵を受け取る。OS が NixOS というだけでは配らない。
共通鍵を持つユーザーは、接続先の `sshUser` として認証できるため。

## ホスト鍵は accept-new で受け入れる

初回の接続ではホスト鍵を自動で受け入れ、以後の変更は拒否する。家庭の LAN の脅威にはこれで足りる。
`programs.ssh.knownHosts` にホスト鍵を直接書く案は、入れ直すたびに書き換えが要るので退けた。
`--build-host` の SSH では実行ユーザーの known_hosts に、常設のリモートビルダーでは root の known_hosts に、同じ設定で追加される。

## セキュリティ

- repo に入るのは `machines.nix` の公開鍵と、age で暗号化した `secrets/secrets.yaml` だけ
- 全マシンの秘密鍵は同じ鍵なので、1 台が侵害されたら LAN の認証を全部作り直す
- `PasswordAuthentication = false` で、鍵の認証しか受け付けない
- 対象は NixOS ホストだけで、standalone home-manager（macOS）には `id_lan` を配らない

## 見直す条件

- マシンの台数や共有する人が増えたら、マシンごとの鍵か SSH の証明書（CA）に戻す
