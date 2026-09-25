# リモートビルドガイド

ラップトップ（`nixos-spin713`）のビルドを、デスクトップ（`nixos-desktop`）に回す運用方法。
ラップトップの nix-daemon は、ビルドが必要になるたびにデスクトップへ SSH で接続し、ビルドを任せて成果物を持ち帰る。`nix build`、`nix develop`、direnv の `use flake`、`nixos-rebuild` のどれでも、コマンドに何も足さずにこうなる。

`nixos-rebuild` のビルドだけを明示的に回す `--build-host` も使える（[`--build-host` で明示的に回す](#--build-host-で明示的に回す)）。

> 設計判断・実装の詳細は [docs/architecture/remote-build.md](../architecture/remote-build.md) を参照

## 前提条件

| 項目 | 要件 |
|------|------|
| ネットワーク | 両ホストが tailnet に参加している（[tailscale.md](./tailscale.md)）。自宅 LAN の中でも tailnet 経由で繋ぐ |
| アーキテクチャ | 両ホストとも `x86_64-linux`（クロスビルドはしない） |
| SSH 鍵 | ラップトップの `pomu` に `~/.ssh/id_lan` がある（`local.profile.lanSsh = true` で switch すると書き出される） |
| デスクトップ | 起動していて、サスペンドしていない |

設定ファイル側は構成済み:

- `hosts/nixos-spin713/default.nix` の `local.remoteBuilders.enable = true` で、ラップトップの nix-daemon がデスクトップをビルダーとして使う
- 同じ場所の `localBuilds = false` で、ラップトップ自身はビルドしない（`max-jobs = 0`）。binary cache からの取得は続く
- ビルダーの一覧と能力（同時に受けるビルドの数、system features）は `hosts/machines.nix` の `builders` にある
- 両ホスト: `nix.settings.trusted-users = [ "@wheel" ]`。デスクトップは、SSH で入ってくる `pomu` からビルドを受け入れるのに使う

## 普段の使い方

何も足さずに実行する。ビルドが要る derivation は自動でデスクトップに回る。

```sh
nix develop
nixos-rebuild switch --flake .#nixos-spin713 --sudo
```

binary cache にあるパッケージは、これまでどおりラップトップが cache.nixos.org から直接取る。
デスクトップに回るのは、cache になく手元でビルドするはずだった derivation だけ。

どこでビルドしたかは `-v` を付けると分かる。

```sh
nix build -v .#<出力> 2>&1 | grep '^building'
# building '/nix/store/...drv' on 'ssh-ng://desktop-ts'...
```

`on 'ssh-ng://desktop-ts'` が付いていればデスクトップでビルドしている。
ラップトップは `localBuilds = false` なので、`preferLocalBuild` の付いた小さな derivation（`writeText` など）もデスクトップに回る。

### デスクトップに届かないとき

デスクトップが落ちているときや、ラップトップが tailnet に入っていないときは、ビルドが要るコマンドは失敗する。
手元でビルドには切り替わらない。

```
cannot build on 'ssh-ng://desktop-ts': error: failed to start SSH connection to 'desktop-ts'
Failed to find a machine for remote build!
...
error: Unable to start any build; remote machines may not have all required system features.
```

接続の待ちは最大 10 秒（`ssh.nix` の `ConnectTimeout`）。
ビルドが要らないコマンド（binary cache とストアにあるものだけで済むコマンド）は接続しないので、このエラーも出ない。

原因はトラブルシューティングの「[`cannot build on 'ssh-ng://desktop-ts'` が出る](#cannot-build-on-ssh-ngdesktop-ts-が出る)」を見る。
直せないときに手元でビルドするなら、そのコマンドにだけ手元のジョブ数を渡す。

```sh
nix develop --max-jobs 4
```

ビルダーを試さずに最初から手元でビルドするなら、`--builders ''` も付ける。

デスクトップが 32 個のビルドを同時に抱えているときは、あふれた分は失敗せず、空きが出るまで待つ。

## `cargo run` のビルドだけを回す（`cargo remote-run`）

cargo は nix-daemon を通さずに rustc を起動するので、`cargo run` のビルドは常設のビルダーに回らない。
`cargo remote-run` は `cargo run` と同じ引数を受け取り、ビルドをデスクトップで行い、できた実行ファイルをラップトップで実行する。
Bevy などの GUI の画面はラップトップに出る。

direnv で devShell に入ったプロジェクトの中で、`cargo run` の代わりに使う。

```sh
cargo remote-run                         # cargo run と同じ実行ファイルを選ぶ（default-run も含む）
cargo remote-run --release -- --foo bar  # -- の後ろは実行時の引数
cargo remote-run --bin dump_diagrams
```

spin713 では `hosts/nixos-spin713/home.nix` の `local.cargoRemoteRun`（接続先は `desktop-ts`）で有効にしてある。
home-manager の switch の後から使える。

実行のたびに、次の順で動く。

1. `.envrc` の `use flake [ref]` から devShell を決め、`nix print-dev-env` で手元に用意する。それを `nix copy` でデスクトップへ送る。デスクトップにないパスは、デスクトップが cache.nixos.org から取る
2. cargo のワークスペースを、デスクトップの `~/.cache/cargo-remote-run/<手元のホスト名>/<手元の絶対パス>` へ `rsync` する。`target/`、`.git/`、`.direnv/` と、`.gitignore` に当たるファイルは送らない
3. デスクトップでその devShell を読み込み、`cargo run` を実行する。ただし実行ファイルは動かさず、cargo が選んだ実行ファイルのパスだけを返させる
4. 実行ファイルを手元の `target/remote-run/bin/` に持ち帰って実行する。`CARGO_MANIFEST_DIR` は手元のパッケージのディレクトリを指すので、Bevy は手元の `assets/` を読む

実行ファイルは debug 情報を含めたまま持ち帰る。
Bevy の debug ビルドは大きく（aquaponics-sim で約 1 GB）、自宅の LAN 内でも転送に 20 秒ほどかかる。
手元にはその大きさの空きが要る。
前回持ち帰ったものは転送の前に消すので、2 つ分は要らない。

コンパイルのエラーと警告は、手元の端末にそのまま出る。
ビルドに失敗したときは実行しない。

ビルド中に Ctrl-C を押すと、手元はすぐに止まる。
デスクトップの cargo は、そのとき走っている rustc や build script が終わるまで残る。
その間に実行し直すと、cargo はロックが空くのを待つことがある。

### 使えない構成

- `.envrc` に `use flake` がないプロジェクト。devShell を決められないので、最初に止まる
- ワークスペースの外にある path 依存（`path = "../other"`）。デスクトップに送らないので、ビルドが失敗する
- 実行時に `target/` の中の共有ライブラリを読む構成（Bevy の `dynamic_linking` feature など）。持ち帰るのは実行ファイルだけなので、起動時にライブラリが見つからない
- プロジェクトの `.cargo/config.toml` が runner を設定している構成。`target.<triple>.runner` ならそちらが優先され、プログラムがデスクトップで動く。`target.'cfg(...)'.runner` なら cargo がエラーで止まる
- デスクトップのログインシェルが bash でないとき。引数を bash の形式でエスケープして渡している
- デスクトップに繋がらないとき。手元でビルドするなら、普通の `cargo run` を使う

### デスクトップに残るもの

デスクトップにはプロジェクトごとのソースの写しと `target/` が残り、次の実行で incremental compilation に使われる。
容量を空けるときは、プロジェクトのディレクトリごと消す。
次の実行は最初からのビルドになる。

```sh
ssh desktop-ts rm -rf .cache/cargo-remote-run/nixos-spin713/home/pomu/sagyo/aquaponics-sim
```

## `--build-host` で明示的に回す

`local.remoteBuilders` を有効にしていないホストからは、`nixos-rebuild` に `--build-host` を付けてビルドを回す。
デスクトップでビルドし、成果物だけを手元に転送して、アクティベートは手元で行う。

ラップトップ側で、`sudo` を付けずに実行する:

```sh
nixos-rebuild switch \
  --flake .#nixos-spin713 \
  --build-host pomu@nixos-desktop.local \
  --sudo
```

- `--build-host` 指定先（デスクトップ）でビルドが実行される
- 完了後、結果のストアパスがラップトップに転送される
- アクティベート（switch）はラップトップ上で行われる。`sudo` で動くのはこの処理だけ

評価、ビルド、転送は `pomu` として動くので、SSH は `pomu` の `~/.ssh/id_lan` で認証する。
コマンド全体を `sudo nixos-rebuild ...` で実行すると SSH が root として動き、`/root/.ssh/id_lan` を探して `Permission denied (publickey)` で失敗する。
常設のビルダーは nix-daemon が鍵のパスを直接指定して繋ぐので、この制約を受けない。

アクティベートの直前に `sudo` のパスワードを聞かれる（同じ端末で直前に `sudo` を通していれば省略される）。
`users.nix` で NOPASSWD にしているのは `nixos-rebuild` 本体だけで、`--sudo` が `sudo` 付きで呼ぶ `nix-env` と `switch-to-configuration` は対象外だから。

### LAN の外からビルドする

ビルドホストを tailnet 経由の接続名 `desktop-ts` にし、`--use-substitutes` を付ける:

```sh
nixos-rebuild switch \
  --flake .#nixos-spin713 \
  --build-host desktop-ts \
  --use-substitutes \
  --sudo
```

両ホストが tailnet に参加している必要がある（[tailscale.md](./tailscale.md)）。
`--use-substitutes` を付けると、binary cache にあるパスはラップトップが cache.nixos.org から直接取り、デスクトップから tailnet 越しに運ぶのはデスクトップで作ったパスだけになる（[判断の根拠](../architecture/tailscale.md#出先のリモートビルドでは---use-substitutes-を付ける)）。

## 動作確認

### 常設のビルダー

switch した後に確認する:

```sh
# 1. 生成されたビルダーの設定
cat /etc/nix/machines
# ssh-ng://desktop-ts x86_64-linux /home/pomu/.ssh/id_lan 32 1 benchmark,big-parallel,kvm,nixos-test - -

# 2. デスクトップの Nix が pomu を trusted として扱うか（Trusted: 1）
nix store info --store ssh-ng://desktop-ts

# 3. nix-daemon（root）からの接続でビルドが回るか
nix build -v --no-link --impure --expr \
  "derivation { name = \"rb-test-$(date +%s)\"; system = \"x86_64-linux\"; builder = \"/bin/sh\"; args = [ \"-c\" \"echo ok > \$out\" ]; }" \
  2>&1 | grep -E '^building|cannot build'
```

2 は `pomu` として繋ぐので、root からの接続は確かめられない。
3 で `building '...' on 'ssh-ng://desktop-ts'` が出れば、nix-daemon の SSH も通っている。
名前に時刻を入れるのは、同じ derivation の成果物がストアに残っているとビルドが走らないため。

### `--build-host`

```sh
# 1. mDNS 名前解決
ping -c 1 nixos-desktop.local

# 2. SSH 疎通（sudo を付けない）
ssh pomu@nixos-desktop.local 'echo ok'

# 3. デスクトップの Nix が pomu を trusted として扱うか（Trusted: 1）
ssh pomu@nixos-desktop.local 'nix store info --store daemon'

# 4. ラップトップの Nix が pomu を trusted として扱うか（Trusted: 1）
nix store info --store daemon
```

4 まで通れば `--build-host` も通る。

## トラブルシューティング

### `cannot build on 'ssh-ng://desktop-ts'` が出る

ssh が失敗した理由は nix-daemon のログに出る。

```sh
journalctl -u nix-daemon --since -10min | grep ssh
```

- `Could not resolve hostname nixos-desktop`: ラップトップが tailnet に入っていない。`tailscale status` を見る
- 接続がタイムアウトする: デスクトップが落ちているか、サスペンドしている（[tailscale.md](./tailscale.md)）
- `Permission denied (publickey)`: `/home/pomu/.ssh/id_lan` が無い。`local.profile.lanSsh = true` で switch する
- `Host key verification failed`: デスクトップを入れ直すなどしてホスト鍵が変わった。root の known_hosts から古い行を消す（`sudo ssh-keygen -R nixos-desktop -f /root/.ssh/known_hosts`）。次の接続で `accept-new` が新しい鍵を入れる

### `ping: nixos-desktop.local: System error`（初回のみ）

avahi のキャッシュが温まっていないだけ。数秒待ってから再実行すると応答する。常時再発する場合は次項を疑う。

### 名前解決が変なアドレス（`192.168.122.*`）に向く

デスクトップで `libvirt` の `virbr0` を経由した IP が mDNS で広告されると、LAN 外からは到達できない。デスクトップ上で `getent hosts nixos-desktop.local` を実行して `192.168.11.*`（LAN 側）以外が返るなら、`services.avahi.denyInterfaces = [ "virbr0" "vnet*" ];` を `modules/nixos/ssh.nix` に追加して LAN 以外の IF を除外する。

### `error: cannot add path '/nix/store/...' because it lacks a signature`

デスクトップかラップトップの `nix.settings.trusted-users` に `pomu` が入っていない。デスクトップはビルドを受け入れるとき、ラップトップは `--build-host` の成果物を取り込むときに署名を要求する。`--build-host` の動作確認の 3 と 4 で `Trusted: 1` になるか確認する（`@wheel` グループに `pomu` が入っていれば通る）。

### `Host key verification failed`（`--build-host`）

`~/.ssh/known_hosts` に `nixos-desktop.local` のエントリが無く、かつ `accept-new` が適用されていない。`ssh.nix` が `machines.nix` から生成する `/etc/ssh/ssh_config` に `Host ... nixos-desktop.local` の `StrictHostKeyChecking accept-new` が含まれるはず。デスクトップが `machines.nix` に登録済みか確認。手動回避は `ssh-keyscan -H nixos-desktop.local >> ~/.ssh/known_hosts`。

### `Permission denied (publickey)`（`--build-host`）

コマンド全体を `sudo` で実行すると、SSH が root として動いて `id_lan` を読めない。`sudo` を外し、基本コマンドのとおり `--sudo` を付けて実行する。

`sudo` を付けていないのに失敗するなら、ラップトップに `~/.ssh/id_lan` があるか確認する。無ければ `local.profile.lanSsh = true` で switch する（[machine-ssh.md](./machine-ssh.md) を参照）。

## 新しいビルダー／クライアントを追加するとき

### クライアントを増やす（新しいホストからデスクトップでビルド）

LAN 認証は全マシン共通の鍵 1 本なので、鍵の生成も登録も要らない
（[machine-ssh.md](./machine-ssh.md) の「マシンを追加するとき」を参照）。

1. 新規ホストの `~/.config/sops/age/keys.txt` に age 鍵を置く
2. `hosts/machines.nix` の `hosts` に1行足す
3. 新規ホストの `default.nix` に `local.remoteBuilders.enable = true;` を足す
4. 新規ホストを rebuild（switch 中に `~/.ssh/id_lan` が書き出される）

3 を省けば、`--build-host` だけで回すホストになる。
デスクトップに繋がらないときに手元でビルドさせたくなければ、`localBuilds = false;` も足す（`hosts/nixos-spin713/default.nix` と同じ形）。
`local.remoteBuilders` は tailnet の接続名で繋ぐので、そのホストも tailnet に参加させる（[tailscale.md](./tailscale.md)）。

### ビルダーを増やす（別のホストもビルドサーバ化）

`hosts/machines.nix` の `builders` に 1 エントリ足す。
`maxJobs` と `supportedFeatures` は、そのホストで `nix config show max-jobs` と `nix config show system-features` を見て決める。

```nix
builders = {
  nixos-desktop = { ... };
  <new-builder> = {
    system = "x86_64-linux";
    maxJobs = <max-jobs の値>;
    supportedFeatures = [ <system-features の値> ];
  };
};
```

`local.remoteBuilders.enable` を立てたホストは、次の switch から自分以外の全ビルダーを使う。
ビルダー側で要るのは、`hosts/machines.nix` の `hosts` に載っていることだけ。sshd と `authorized_keys` は `ssh.nix` が、`trusted-users` は `nix-settings.nix` が全ホストに設定する。

## 関連ファイル

- [modules/nixos/remote-builders.nix](../../modules/nixos/remote-builders.nix) — `local.remoteBuilders` と `nix.buildMachines` の生成
- [modules/nixos/ssh.nix](../../modules/nixos/ssh.nix) — openssh + avahi publish + マシン間 SSH 生成（`ConnectTimeout` を含む）
- [hosts/machines.nix](../../hosts/machines.nix) — ホスト一覧、LAN 共通鍵の公開鍵、ビルダーの能力
- [modules/nixos/nix-settings.nix](../../modules/nixos/nix-settings.nix) — trusted-users
- [modules/nixos/users.nix](../../modules/nixos/users.nix) — `nixos-rebuild` 本体だけを NOPASSWD にする sudo 規則
- [modules/home-manager/dev/cargo-remote-run.nix](../../modules/home-manager/dev/cargo-remote-run.nix) / [cargo-remote-run.sh](../../modules/home-manager/dev/cargo-remote-run.sh) — `local.cargoRemoteRun` と `cargo remote-run` の本体
- マシン間 SSH の使い方・設計: [machine-ssh.md](./machine-ssh.md) / [../architecture/machine-ssh.md](../architecture/machine-ssh.md)
