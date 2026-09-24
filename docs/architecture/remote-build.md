# リモートビルドの設計

ラップトップ（`nixos-spin713`）のビルドを、デスクトップ（`nixos-desktop`）に SSH で回す構成。
ラップトップには nix-daemon の常設ビルダー（`nix.buildMachines`）を設定し、`nix develop` を含む全ビルドを回す。
`nixos-rebuild --build-host` も、常設ビルダーを設定していないホストのために使える状態で残す。

設定ファイル:

- `modules/nixos/remote-builders.nix` — `local.remoteBuilders.enable` から `nix.buildMachines` を生成する
- `hosts/machines.nix` — ホスト一覧、LAN 共通鍵の公開鍵、ビルダーの能力（`builders`）
- `modules/nixos/ssh.nix` — openssh + avahi publish + マシン間 SSH の生成
- `modules/nixos/nix-settings.nix` — `nix.settings.trusted-users`

> SSH の鍵管理・ホスト鍵受理・`.local` 接続の配線はリモートビルド専用ではなく、
> flake 内マシン間 SSH の共通基盤である [machine-ssh.md](./machine-ssh.md) に集約した。
> このドキュメントはその上に乗る「ビルドのオフロード」固有の判断だけを扱う。
>
> 使い方は [docs/howtouse/remote-build.md](../howtouse/remote-build.md) を参照

## 方式選択：常設の `nix.buildMachines` を主にする

| 方式 | 特徴 | 使う場面 |
|------|------|------|
| `nix.distributedBuilds` + `nix.buildMachines` | nix-daemon が透過的にビルダーへオフロードする常設方式 | ラップトップの全ビルド |
| `nixos-rebuild --build-host` | コマンド実行時のみ SSH で接続する ad-hoc 方式 | 常設ビルダーのないホストの `nixos-rebuild` |

当初は `--build-host` だけを採用し、`buildMachines` は見送った。
その後ラップトップで `nix develop` を日常的に使うようになり、`--build-host` では `nixos-rebuild` 以外のビルドを回せないことが問題になった。
`nix develop` には `--build-host` に当たるフラグがない。ビルドを別ホストに回す経路は、nix-daemon のビルダー（`builders` 設定）だけだ。

見送ったときの理由は、今の構成では当たらない。

- **root の SSH 鍵管理**: `buildMachines` では nix-daemon（root）が SSH で接続するので、`/root/.ssh/` に鍵と `known_hosts` を置く必要があると考えていた。実際には、`sshKey` で既存の `id_lan` のパスを指せば新しい鍵は要らない（[後述](#鍵は-primaryuser-の-id_lan-を絶対パスで読む)）。ホスト鍵は、`ssh.nix` が生成する `/etc/ssh/ssh_config` の `accept-new` で root の known_hosts に自動で入る。2026-09-24 に nixos-spin713 で `--builders` を指定してビルドしたとき、nix-daemon のログに `Warning: Permanently added 'nixos-desktop' (ED25519) to the list of known hosts.` と出た
- **透過的なフォールバックの分かりにくさ**: Nix のソースで挙動を確かめた（[後述](#デスクトップに届かないときの-nix-の動作)）。標準では、待ちはビルド要求一回（`nix build` なら一コマンド）につき一度で、その後のビルドは手元で走る。spin713 ではこの切り替え自体を止めた（[後述](#spin713-では手元でビルドしないmax-jobs--0)）

## 接続先は tailnet の接続名（`desktop-ts`）にする

`buildMachines` の `hostName` は、`ssh.nix` が生成する `<短縮名>-ts` にした。
自宅 LAN の中でも外でも同じ経路で繋がり、ビルダー一台につきエントリが一つで済む。

退けた案と理由:

- **`.local` の接続名**: LAN の外では名前が引けない（[tailscale.md](./tailscale.md)）。出先ではビルダーに毎回繋がらない
- **`.local` と `-ts` の両方をエントリにする**: Nix は二つを別のマシンとして数えるので、同じデスクトップに `maxJobs` の 2 倍のビルドを送る。出先では、コマンドのたびに `.local` への接続失敗も表示される
- **MagicDNS 名の `nixos-desktop`**: `ssh.nix` の `Host desktop nixos-desktop nixos-desktop.local` ブロックに当たり、`HostName nixos-desktop.local`（mDNS）に書き換わる

代償として、自宅 LAN の中でも常設ビルダーは tailscaled に依存する。
tailscaled が止まっていると、`localBuilds` が真のホストでは手元のビルドに戻り、偽のホスト（spin713）ではビルドが失敗する。

`hostName` の接続名は、`remote-builders.nix` が `ssh.nix` と同じ規則（`nixos-` を剥がして `-ts` を付ける）で組み立てる。
`tests/default.nix` の module contracts で、生成した `hostName` が `ssh.nix` の `Host` ブロックにあることを確かめている。どちらかの規則だけを変えると評価で失敗する。

## 鍵は primaryUser の `id_lan` を絶対パスで読む

`sshKey` は、primaryUser の home（`users.users.<primaryUser>.home`）の下の `.ssh/id_lan`。
[machine-ssh.md](./machine-ssh.md) の「他ユーザーの絶対パスを共有しない」の例外になる。
パスは `/etc/nix/machines` に書かれ、読むのは nix-daemon（root）だけだ。ほかのユーザーの ssh クライアントの設定には入らない。

- root はもともと全ファイルを読めるので、鍵の露出は増えない
- nixos-spin713 の `/home` はルートと同じ ext4 パーティション（`/dev/mmcblk0p2`）にあり、ログイン前でも読める
- 鍵ファイルは home-manager が書き出す（`local.profile.lanSsh = true`）。無ければ接続に失敗する（その後の扱いは[届かないときと同じ](#デスクトップに届かないときの-nix-の動作)）
- ラップトップの全ユーザーのビルドが、`pomu` としてデスクトップに送られる。nixos-spin713 のユーザーは `pomu` だけだ。デスクトップ側では nix-daemon のサンドボックスでビルドされ、`pomu` のシェルでコマンドが動くわけではない

## デスクトップに届かないときの Nix の動作

`max-jobs` が 1 以上のホストでは、Nix はビルダーに届かないと一度だけ待って手元でビルドする。
Nix 2.31.5（`cc38c0c5`）のソースで確かめた挙動:

- nix-daemon は、ビルドが要る derivation ごとに build hook（`nix __build-remote`）へビルダーを選ばせる（`src/libstore/build/derivation-building-goal.cc` の `tryBuildHook`）。ストアか binary cache にあるパスはビルドしないので、hook も SSH も使わない
- 接続に失敗したビルダーには `bestMachine->enabled = false` が立ち、その hook のプロセスの中では選ばれなくなる（`src/nix/build-remote/build-remote.cc`）。hook のプロセスはビルドを断っている間は同じビルド要求の中で使い回されるので、待ちはビルド要求一回（`nix build` なら一コマンド）につき一度で済む
- 使えるビルダーがなく手元でビルドできるなら、hook は `decline` を返し、ビルドは手元で走る。失敗するのは `max-jobs = 0` のときだけだ
- `preferLocalBuild` の付いた derivation は、`max-jobs` が 0 でなければ hook を通さず手元でビルドする（`willBuildLocally`）
- Nix の `connect-timeout` は binary cache の HTTP（curl）用の設定で、ssh には渡らない。`src/libstore/ssh.cc` が ssh に足すのは `-i <sshKey>` と `NIX_SSHOPTS` などで、タイムアウトの指定はない

観測（2026-09-24、nixos-spin713）: 名前の引けないビルダーを `--builders` に指定し、依存関係のある二つの derivation をビルドした。`cannot build on ...` は一度だけ出て、二つとも手元でビルドが始まった。

待ち時間の上限は ssh の `ConnectTimeout` で決まる。
`ssh.nix` の生成する `Host` ブロックに `ConnectTimeout 10` を入れた。
指定しないと、SYN が黙って捨てられる経路では TCP の再送が尽きるまで待つ（`net.ipv4.tcp_syn_retries = 6` で約 2 分）。
tailnet 上でデスクトップが落ちているとき、パケットが捨てられるのか即座に拒否されるのかは確かめていない。どちらでも待ちは 10 秒以内に収まる。
`ConnectTimeout` は人が打つ `ssh desktop` にも適用される。LAN か tailnet の相手が 10 秒応答しなければ、落ちていると見てよい。

デスクトップは無操作ではサスペンドしない（[tailscale.md](./tailscale.md#デスクトップは無操作でサスペンドさせない)）。届かなくなるのは、手動でサスペンドしたときと停電のときくらいだ。

## spin713 では手元でビルドしない（`max-jobs = 0`）

`local.remoteBuilders.localBuilds = false` で、ラップトップの `nix.settings.max-jobs` を 0 にした。
Nix の `max-jobs` の説明文にある「`0` で手元のビルドを止め、`builders` のマシンだけを使う」設定だ。

理由は二つある。

- spin713 は非力（4 スレッド、メモリ 7 GiB、`/nix` は SD カード）で、重い処理を手元で始めると応答しなくなる。2026-09-24 には `scripts/check.sh` の実行中に約 2 時間固まり、電源を切った。評価とビルドのどちらが原因かは切り分けていない
- 標準の切り替えは黙って起きる。エージェントは `cannot build on` の一行を見落とすと、手元でビルドしたことに気づかない。失敗させれば、エージェントは手元で実行してよいかを判断する機会を得る（フリーズしないかの概算）（エージェントへの指示は [agent-config.md](./agent-config.md#マシン固有の指示はシステム層に置く)）

観測（2026-09-24、nixos-spin713、Nix 2.31.5）:

- `--max-jobs 0 --builders ''` でも、binary cache にあるパス（`sl-5.05`）は取得できた
- `--max-jobs 0` では、`preferLocalBuild = true` の derivation もビルダーに回った。`max-jobs` の説明文は「`preferLocalBuild` の derivation は常に手元でビルドする」としているが、ソース（`derivation-building-goal.cc` の `willBuildLocally(...) && maxBuildJobs != 0`）と観測はそうなっていない
- ビルダーに届かないときは、`Failed to find a machine for remote build!` の後に `Unable to start any build` で失敗した

代償:

- 出先で tailnet に入れないときは、ビルドが要る `nix develop` も `nixos-rebuild` も失敗する。手元でビルドするには、そのコマンドに `--max-jobs 4` を付ける
- `writeText` のような小さな derivation もデスクトップに回り、SSH と転送の分だけ遅くなる
- デスクトップのスロット（32）が埋まると、あふれた分は手元でビルドされず、空きを待つ（build hook が `postpone` を返す）
- IFD（評価中のビルド）もデスクトップに回る。評価そのものは手元で走るので、重い評価はこの設定では防げない。そこはエージェントへの指示で扱う

`localBuilds` の既定は true にした。
ビルダーを使うホストすべてで手元のビルドを止めるのではなく、非力なホストが選ぶ設定だからだ。

## ビルダーの能力は machines.nix に置く

`hosts/machines.nix` の `builders` に、ビルダーごとの `system`、`maxJobs`、`supportedFeatures` を置く。
これらは呼び出し側でなくビルダーの性質なので、ホスト一覧と同じファイルに置いた。
呼び出し側は `local.remoteBuilders.enable` を立てるだけで、`builders` のうち自分以外の全ホストを使う。自分しかいなければ assertion で拒否する。

- `maxJobs = 32`: デスクトップ自身の `max-jobs`（`auto`。32 スレッド）と揃えた。デスクトップが自分をビルドするときと同じ並列度になる。スロットが埋まると、`localBuilds` が真のホストはあふれた分を手元でビルドし、偽のホストは空きを待つ
- `supportedFeatures`: デスクトップの `nix config show system-features`（`benchmark big-parallel kvm nixos-test`）と同じ値。`big-parallel` を載せないと、LLVM のように `requiredSystemFeatures = [ "big-parallel" ]` を持つ derivation はデスクトップに回らない

## `builders-use-substitutes = true`

ビルドの入力のうち binary cache にあるものを、デスクトップが cache.nixos.org から直接取る。
無効だと、ラップトップが自分のストアから tailnet 越しに送る。
出先の回線や DERP 経由の経路は、cache.nixos.org への経路より遅いことが多い（[tailscale.md](./tailscale.md#出先のリモートビルドでは---use-substitutes-を付ける)）。

## `--build-host` のホスト解決：mDNS（`.local`）

`--build-host` では `pomu@nixos-desktop.local` のように `.local` ドメインで接続する。

- **固定 IP に依存しない**：自宅 LAN・宿泊先 LAN・テザリングなどで IP が変わっても、同セグメント内であれば mDNS が解決する
- **DNS サーバ不要**：ルータの DHCP/DNS 設定に手を入れない
- **トレードオフ**：mDNS が届かない環境（別のネットワーク、VLAN 分離等）では解決できない。LAN の外からは tailnet 経由の接続名 `desktop-ts` を使う（[tailscale.md](./tailscale.md)）

実装は `modules/nixos/ssh.nix` の `services.avahi.publish` で：

```nix
services.avahi.publish = {
  enable = true;
  addresses = true;
  domain = true;
  workstation = true;
};
```

`services.avahi.enable` と `nssmdns4 = true`（解決側）は `printing.nix` で先に有効化されており、モジュール合成によって `publish` 設定が後から追加される形になっている。SSH 関連の設定は印刷とは独立した責務なので `ssh.nix` に分けたが、avahi の有効化自体は重複できないため、`publish` だけを書く形にした。

### 既知の落とし穴：libvirt 等の仮想ブリッジ

`libvirt` が `virbr0`（`192.168.122.0/24`）を作っていると、avahi がそのインタフェースでもホスト名を広告し、LAN 外からは到達できない IP を返すことがある。観測した事象としては、デスクトップ自身で `getent hosts nixos-desktop.local` を引くと `192.168.122.1` が返るケースがあった。

対症療法：`services.avahi.denyInterfaces = [ "virbr*" "vnet*" ];` を追加する。現状は LAN 経由の解決では問題が出ていないため未設定だが、再発したら導入する。

## `trusted-users = [ "@wheel" ]`

`modules/nixos/nix-settings.nix`：

```nix
nix.settings.trusted-users = [ "@wheel" ];
```

### 必要性

リモートビルドの受け側は、接続してきたユーザが trusted でないと以下を拒否する：

- 署名なしの派生物の構築
- ストアパスのプッシュ／プル

常設ビルダーでは、ラップトップの nix-daemon が `ssh-ng` でデスクトップに `pomu` として入り、derivation を送って構築させる。
デスクトップ側で `pomu` が trusted でないと、デスクトップの nix-daemon は `you are not privileged to build input-addressed derivations` で拒否する（Nix 2.31.5 の `src/libstore/daemon.cc`）。
`--build-host` でも同じくデスクトップに derivation を送るので、trusted でないと「`cannot add path '/nix/store/...' because it lacks a signature`」エラーになる。

`--build-host` では、呼び出し側のラップトップにも同じ設定が要る。`--sudo` で実行すると、デスクトップから戻る成果物を `pomu` のまま手元のストアに取り込むので、ラップトップ側で trusted でなければ同じ署名エラーになる。
常設ビルダーでは成果物を取り込むのが root の nix-daemon なので、呼び出し側の設定は関係しない。
`nix-settings.nix` は全ホストが読み込むので、両側とも `@wheel` が trusted になる。

### `@wheel` を使う理由

- ホスト固有のユーザ名（`pomu`）をハードコードしたくない
- admin 権限（wheel）と「nix-daemon を信頼できる」のスコープがこの flake では一致している
- 新規 admin ユーザを追加するときに `trusted-users` を別途編集する必要がない

非 admin ユーザにビルダー権限を渡したくなったら明示的に `[ "@wheel" "someuser" ]` のように個別追加する。

### セキュリティ上の判断

`trusted-users` は実質的に root 相当の権限（任意のストアパスを書き込めるため、`/nix/store` 経由でシステムを汚染可能）。`@wheel` は既に sudo 権限を持っており、信頼レベルは等価なので拡大はしていない。

## SSH 鍵管理・ホスト鍵受理は machine-ssh に集約

以前はデスクトップの `authorizedKeys.keys` とラップトップの `programs.ssh.extraConfig`
（`accept-new`）を各 `hosts/<host>/default.nix` に直書きしていたが、マシン間 SSH を
双方向化した際に `hosts/machines.nix` を単一の情報源とする方式へ移した。

- 誰の鍵を受け入れるか（`authorizedKeys`）と、`.local` / `-ts` への `accept-new` 接続設定は、
  `ssh.nix` が `machines.nix` から全ホストぶん生成する
- リモートビルドの SSH が host key を `known_hosts` に accept-new で入れる動作も、
  この生成される `/etc/ssh/ssh_config` が兼ねる。`--build-host` では実行ユーザの、常設ビルダーでは root の `known_hosts` に入る

設計判断（LAN 共通鍵、集約、accept-new の TOFU トレードオフ、CA 不採用など）は
[machine-ssh.md](./machine-ssh.md) を参照。

## `--build-host` では `sudo` を付けず `--sudo` で実行する

`nixos-rebuild` 全体を `sudo` で実行せず、一般ユーザのまま `--sudo` を付ける。

```sh
nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop.local --sudo
```

nixos-rebuild-ng 25.11 のソース（`nixos_rebuild/process.py` の `run_wrapper` と `nixos_rebuild/nix.py`）を読むと、`--sudo` がローカルで `sudo` を付けるのはアクティベートのコマンド（`nix-env -p <profile> --set` と `switch-to-configuration` の呼び出し）だけである。flake の評価、ビルドホストへの SSH、`nix-copy-closure` による転送は、呼び出したユーザのまま動く。

### 不採用：`sudo` と `SSH_AUTH_SOCK` の引き継ぎ

`sudo nixos-rebuild --build-host ...` では SSH が root として動く。`/etc/ssh/ssh_config` の `IdentityFile ~/.ssh/id_lan` は root の home で解決され、root は `id_lan` を持たない。`users.nix` の `Defaults env_keep += "SSH_AUTH_SOCK"` でユーザの agent を渡しても、agent に `id_lan` が入っていなければ認証できない。`id_lan` は home-manager がファイルとして書き出すだけで、agent には登録しない。この方式を使うには、ログインのたびに `ssh-add ~/.ssh/id_lan` が要る。

観測（2026-09-16、nixos-spin713）：agent には `id_lan` 以外の RSA 鍵が 1 本だけ入っており、`sudo SSH_AUTH_SOCK=$SSH_AUTH_SOCK nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop.local` は `pomu@nixos-desktop.local: Permission denied (publickey).` で失敗した。同じ接続を `pomu` から `ssh -v` すると `Server accepts key: /home/pomu/.ssh/id_lan` で認証が通った。

`env_keep` の設定は `nixos-rebuild` を sudo で実行するワークフロー全般のために入れたもので、リモートビルドの前提ではない。

常設ビルダーはこの問題を持たない。nix-daemon が `sshKey` で鍵のパスを ssh に直接渡すので、`sudo nixos-rebuild switch` でもビルドは回る。

### トレードオフと再検討の条件

`users.nix` で NOPASSWD にしているのは `nixos-rebuild` 本体だけなので、`--sudo` が `sudo` 付きで呼ぶアクティベートのコマンドではパスワードを聞かれる。プロンプトはビルドと転送が終わった後に出る。

このパスワード入力が負担になったら見直す。候補は二つある。一つは `id_lan` を agent に載せて `sudo` と `SSH_AUTH_SOCK` の方式に戻す案で、root から gcr の agent ソケットを使えるかは確認していない。もう一つはアクティベートのコマンドを NOPASSWD にする案で、パスワードなしで root として動かせるコマンドが増える。

## モジュール責務の分離

| モジュール | 責務 |
|-----------|------|
| `modules/nixos/remote-builders.nix` | `local.remoteBuilders` から `nix.buildMachines`、`builders-use-substitutes`、`max-jobs` を生成 |
| `modules/nixos/ssh.nix` | openssh の有効化、mDNS publish、`machines.nix` から authorized_keys とクライアント設定（`ConnectTimeout` を含む）を生成 |
| `modules/nixos/nix-settings.nix` | trusted-users（nix-daemon の信頼境界） |
| `modules/nixos/users.nix` | `nixos-rebuild` 本体の NOPASSWD（`--sudo` のアクティベートは対象外） |
| `hosts/machines.nix` | ホスト一覧、LAN 共通鍵の公開鍵、ビルダーの能力（マシンの単一の情報源） |
| `hosts/nixos-spin713/default.nix` | `local.remoteBuilders.enable = true` と `localBuilds = false`（どのホストがビルドを回し、手元でビルドするかの方針） |

「共通インフラ」と「マシン登録簿」を分離し、新ホストを追加するときに触る場所を
`hosts/machines.nix` の1エントリに局所化している（詳細は [machine-ssh.md](./machine-ssh.md)）。

## 見直す条件

- ラップトップにほかのユーザーを足すなら、そのユーザーのビルドも `pomu` としてデスクトップに送られることを見直す。`sshKey` を root 専用の鍵に分ける案がある
- 出先で DERP 経由になり、成果物を持ち帰るほうが手元でビルドするより遅い場面が続いたら、その場では `--builders '' --max-jobs 4` で手元のビルドに切り替える。常態化したら、tailnet の経路ごとに有効にする仕組みを考える
- tailnet をやめるなら、`hostName` を `.local` に戻す。そのときは出先で常設ビルダーが使えなくなる
- デスクトップのスレッド数やメモリが変わったら、`builders` の `maxJobs` と `supportedFeatures` をそのホストの `nix config show` の値に合わせ直す
- 出先で tailnet に入れない場面が増え、`--max-jobs 4` を付ける手間が目立ったら、spin713 の `localBuilds` を true に戻す。エージェントへの指示は残るので、エージェントが黙って手元でビルドすることは指示の側で防ぐ
