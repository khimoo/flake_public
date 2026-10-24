# リモートビルド

ラップトップ（`nixos-spin713`）のビルドは、デスクトップ（`nixos-desktop`）で行われます。
`nix build`、`nix develop`、direnv、`nixos-rebuild` のいずれも、特別なオプションを追加せず通常通り実行できます。
ただし `cargo run` だけは対象外のため、代わりに `cargo remote-run` を使用します。

設計: [リモートビルドの設計](../architecture/remote-build.md)

## 普段使う

両ホストが tailnet に参加しており（[tailscale.md](./tailscale.md) 参照）、デスクトップが起動していれば利用できます。
ラップトップの `pomu` ユーザーには `~/.ssh/id_lan` が必要です（`local.profile.lanSsh = true` を設定して switch すると自動で書き出されます）。

```sh
nix develop
nixos-rebuild switch --flake .#nixos-spin713 --sudo
```

バイナリキャッシュにあるパスはラップトップが直接ダウンロードし、デスクトップでビルドされるのは実際にビルドが必要な derivation のみとなります。
どこでビルドされたかは `-v` オプションで確認できます。ログに `on 'ssh-ng://desktop-ts'` と出力されていれば、デスクトップでビルドされています。

```sh
nix build -v .#<出力> 2>&1 | grep '^building'
```

ビルドが不要な状態で通信経路だけをテストしたいときは、毎回名前が変わる derivation をビルドします。

```sh
nix build -v --no-link --impure --expr \
  "derivation { name = \"rb-test-$(date +%s)\"; system = \"x86_64-linux\"; builder = \"/bin/sh\"; args = [ \"-c\" \"echo ok > \$out\" ]; }" \
  2>&1 | grep -E '^building|cannot build'
```

## デスクトップに接続できないとき

ビルドが必要なコマンドを実行すると、最大 10 秒待機したあとに次のエラーで失敗します。
自動的にローカルビルドへフォールバックすることはありません（理由は[設計](../architecture/remote-build.md#spin713-では手元でビルドしないmax-jobs--0)を参照）。

```
cannot build on 'ssh-ng://desktop-ts': error: failed to start SSH connection to 'desktop-ts'
Failed to find a machine for remote build!
```

失敗した原因は nix-daemon のログから確認できます。

```sh
journalctl -u nix-daemon --since -10min | grep ssh
```

- `Could not resolve hostname nixos-desktop`: ラップトップが tailnet に接続されていません。`tailscale status` を確認してください。
- 接続がタイムアウトする: デスクトップの電源が切れているか、サスペンド状態になっています。
- `Permission denied (publickey)`: `/home/pomu/.ssh/id_lan` が存在しません。`local.profile.lanSsh = true` を設定して switch してください。
- `Host key verification failed`: デスクトップのホスト鍵が変更されています。`sudo ssh-keygen -R nixos-desktop -f /root/.ssh/known_hosts` で古いエントリを削除すれば、次回接続時に新しい鍵が登録されます。

問題をすぐに解決できない場合は、そのコマンドにだけ手元のジョブ数を指定してローカルでビルドします。
リモートビルダーへの接続を試みずに即座に開始したい場合は、`--builders ''` も併せて指定します。

```sh
nix develop --max-jobs 4
```

## `cargo run` をデスクトップでビルドする（`cargo remote-run`）

cargo は nix-daemon を経由しないため、通常の `cargo run` では上述のリモートビルドが機能しません。
`cargo remote-run` は `cargo run` と同等の引数を受け取り、デスクトップ上でビルドを行った上で、生成された実行ファイルを手元で実行します。GUI アプリケーションの画面も手元に表示されます。
direnv で devShell に入ったプロジェクト内で利用します（spin713 の `pomu` では、[home.nix](../../hosts/nixos-spin713/home.nix) の `local.cargoRemoteRun` で有効化されています）。

```sh
cargo remote-run
cargo remote-run --release -- --foo bar  # -- の後ろは実行時の引数
cargo remote-run --bin dump_diagrams
```

実行ファイルはデバッグ情報を含んだ状態で手元に転送されます。
Bevy の debug ビルドは約 1 GB あるため、自宅 LAN 内でも転送に 20 秒ほどかかります。手元のストレージにもそれだけの空き容量が必要です。

ビルド中に Ctrl-C を押すと手元のプロセスは即座に停止しますが、デスクトップ側の cargo は実行中の rustc や build script が終了するまで稼働し続けます。
そのため、直後に再実行するとファイルロックの解放待ちが発生することがあります。

以下の環境・構成では利用できません。

- `.envrc` に `use flake` が記述されていない
- ワークスペース外へのパス依存（`path = "../other"`）がある（デスクトップには `target/`、`.git/`、`.direnv/`、および `.gitignore` の対象ファイルを除いたワークスペースのみが転送されます）
- 実行時に `target/` 内の共有ライブラリを参照する（Bevy の `dynamic_linking` feature など）
- プロジェクトの `.cargo/config.toml` で runner が設定されている
- デスクトップ側のログインシェルが bash ではない

デスクトップ側には、プロジェクトごとにソースコードのコピーと `target/` ディレクトリが残ります。
ディスク容量を空けたいときはプロジェクトのディレクトリごと削除してください。次回実行時は最初からのフルビルドになります。

```sh
ssh desktop-ts rm -rf .cache/cargo-remote-run/nixos-spin713/home/pomu/sagyo/aquaponics-sim
```

## `--build-host` でビルドする

`local.remoteBuilders` を有効にしていないホストでは、`nixos-rebuild` に `--build-host` を指定してビルドします。
コマンド全体に `sudo` を付けるのではなく、オプションとして `--sudo` を渡してください。
全体を `sudo` で実行すると SSH 接続が root ユーザーとして試行され、`Permission denied (publickey)` で失敗します。

```sh
nixos-rebuild switch --flake .#<ホスト> --build-host pomu@nixos-desktop.local --sudo
```

アクティベートの直前に `sudo` のパスワードが求められます。

### LAN の外からビルドする

接続先に `desktop-ts` を指定し、`--use-substitutes` を付けます。
これにより、バイナリキャッシュにあるパスはデスクトップ経由で転送せず、手元で直接取得するようになります。

```sh
nixos-rebuild switch --flake .#<ホスト> --build-host desktop-ts --use-substitutes --sudo
```

### パスワードを聞かれずに切り替える

ビルドと切り替えの手順を分ければ、パスワードを入力せずに適用できます（`sudo nixos-rebuild` には NOPASSWD が設定されているため）。
ただし、flake の評価が計 2 回実行されます。

```sh
nixos-rebuild build --flake .#<ホスト> --build-host desktop-ts --use-substitutes \
  && sudo nixos-rebuild switch --flake .#<ホスト>
```

### 失敗するとき

- `Permission denied (publickey)`: コマンド先頭の `sudo` を外し、`--sudo` で実行してください。`sudo` なしでも失敗する場合は、手元に `~/.ssh/id_lan` が存在するかを確認します。
- `Host key verification failed`: デスクトップが `hosts/machines.nix` に登録されているか確認してください。手動で受け入れる場合は `ssh-keyscan -H nixos-desktop.local >> ~/.ssh/known_hosts` を実行します。
- `error: cannot add path '/nix/store/...' because it lacks a signature`: いずれかのホストで `pomu` ユーザーが trusted ユーザーになっていません。両ホストで `nix store info --store daemon` を実行し、`Trusted: 1` になるか確認してください（`pomu` が `wheel` グループに所属していれば `Trusted: 1` になります）。
- `ping: nixos-desktop.local: System error`: 初回は Avahi のキャッシュが空なだけの場合があるため、数秒待ってから再試行してください。
- `nixos-desktop.local` が `192.168.122.*` に解決される: デスクトップ側の libvirt 仮想ブリッジでもホスト名がアドバタイズされています。デスクトップ上で `getent hosts nixos-desktop.local` を実行し、LAN 側（`192.168.11.*`）以外が返される場合は、`modules/nixos/ssh.nix` に `services.avahi.denyInterfaces = [ "virbr0" "vnet*" ];` を追加してください。

## ホストを追加する

デスクトップでビルドを行うホストを追加するときは、次の手順で進めます。

1. [machine-ssh.md](./machine-ssh.md) の「マシンを追加するとき」に従い、age 鍵を配置して `hosts/machines.nix` に項目を追加します。
2. そのホストの `default.nix` に `local.remoteBuilders.enable = true;` を記述します。接続できないときに手元でビルドさせない場合は、併せて `localBuilds = false;` も指定します。
3. そのホストを tailnet に参加させてから switch します。Tailscale を有効にしていないと、評価時の assertion でエラーになります。

2 の設定を省くと、`--build-host` を明示的に指定したときだけデスクトップでビルドするホストになります。

ビルダーを追加するときは、`hosts/machines.nix` の該当マシンに `builder` 設定を記述します。
`maxJobs` にはそのホストのスレッド数（`nproc`）を、`supportedFeatures` にはそのホストが実際に満たせる feature を書いてください（`kvm` には `/dev/kvm` が要ります）。
ビルダー自身の `max-jobs` はこの `maxJobs` になり、`system-features` には `supportedFeatures` が足されます。
switch 後にビルダーで `nix config show max-jobs` と `nix config show system-features` を実行すると、反映を確かめられます。
`local.remoteBuilders.enable` が有効なホストは、次回の switch 以降、`builder` を持つ自身以外の全ホストをビルダーとして利用するようになります。