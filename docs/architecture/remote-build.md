# リモートビルドの設計

使い方: [リモートビルド](../howtouse/remote-build.md)
実装: [remote-builders.nix](../../modules/nixos/remote-builders.nix)、[cargo-remote-run.sh](../../modules/home-manager/dev/cargo-remote-run.sh)

マシン間 SSH の鍵とホスト鍵の扱いは [machine-ssh.md](./machine-ssh.md) にある。この文書は、ビルドを別のホストで行うための判断だけを扱う。

## 常設の `nix.buildMachines` を主にし、`--build-host` は補助にする

`nix develop` や direnv のビルドを別のホストで行わせる手段は、nix-daemon のビルダー（`builders` 設定）しかない。
`--build-host` は `nixos-rebuild` にしか使えないので、`local.remoteBuilders` を有効にしていないホスト向けに残している。

## 接続先は tailnet の接続名（`desktop-ts`）にする

`hostName` は `ssh.nix` が生成する `<短縮名>-ts` にした。
自宅 LAN の内外で同じ経路で接続でき、ビルダー 1 台につきエントリが 1 つで済む。

退けた案と理由:

- `.local` の接続名: LAN の外で名前が引けない
- `.local` と `-ts` の両方をエントリにする: Nix が二つを別のマシンとして数え、同じデスクトップに `maxJobs` の 2 倍のビルドを送る。出先ではコマンドのたびに `.local` への接続失敗も表示される
- MagicDNS 名の `nixos-desktop`: `ssh.nix` の `Host desktop nixos-desktop nixos-desktop.local` ブロックに一致し、`HostName nixos-desktop.local`（mDNS）に書き換わる

代償として、自宅 LAN の中でも常設ビルダーは tailscaled に依存する。

接続名は `remote-builders.nix` と `ssh.nix` がそれぞれ同じ規則で組み立てる。
`tests/default.nix` の module contracts が両者の一致を確かめるので、片方の規則だけを変えると検査で失敗する。

## 鍵は primaryUser の `id_lan` を絶対パスで読む

SSH するのは nix-daemon（root）で、root は `id_lan` を持たない。
そこで `sshKey` に primaryUser の `~/.ssh/id_lan` の絶対パスを渡す。
[machine-ssh.md](./machine-ssh.md) の「他ユーザーの絶対パスを共有しない」の例外になる。

- パスは `/etc/nix/machines` に書かれ、読むのは nix-daemon だけ。root はもともと全ファイルを読めるので、鍵の露出は増えない
- spin713 の `/home` はルートと同じ ext4 パーティションにあり、ログイン前でも読める
- ラップトップの全ユーザーのビルドが `pomu` としてデスクトップに送られる。spin713 のユーザーは `pomu` だけなので許容している

## デスクトップに届かないときの Nix の動作

Nix 2.31.5（`cc38c0c5`）のソースと、2026-09-24 の spin713 での観測で確かめた挙動:

- ストアか binary cache にあるパスはビルドしないので、SSH もしない
- 接続に失敗したビルダーは、同じビルド要求（`nix build` なら 1 コマンド）の中では選ばれなくなる。待ちは 1 回で済む（`src/nix/build-remote/build-remote.cc`）
- 使えるビルダーがないとき、`max-jobs` が 1 以上なら手元でビルドし、0 なら失敗する
- `preferLocalBuild` の derivation は、`max-jobs` が 0 でなければ手元でビルドし、0 ならビルダーでビルドされる。`max-jobs` の説明文は「常に手元でビルドする」としているが、ソース（`derivation-building-goal.cc` の `willBuildLocally(...) && maxBuildJobs != 0`）と観測はそうなっていない
- Nix の `connect-timeout` は binary cache の HTTP 用の設定で、ssh には渡らない

そのため、待ち時間の上限は ssh の `ConnectTimeout 10`（`ssh.nix`）で決めている。
指定しないと、SYN が黙って捨てられる経路では TCP の再送が尽きるまで約 2 分待つ。
この設定は人が打つ `ssh` にも適用される。

## spin713 では手元でビルドしない（`max-jobs = 0`）

`localBuilds = false` で、spin713 の `nix.settings.max-jobs` を 0 にしている。理由は二つある。

- spin713 は 4 スレッド、メモリ 7 GiB、`/nix` が SD カードで、重い処理を手元で始めると応答しなくなる。2026-09-24 には `scripts/check.sh` の実行中に約 2 時間固まり、電源を切った。評価とビルドのどちらが原因かは切り分けていない
- 手元のビルドへの切り替えは `cannot build on` の一行が出るだけで、エージェントが見落とすと気づかない。失敗させれば、エージェントが手元で実行してよいかを判断できる（[agent-config.md](./agent-config.md#マシン固有の指示はシステム層に置く)）

代償:

- 出先で tailnet に入れないと、ビルドが要るコマンドは失敗する
- `writeText` のような小さな derivation もデスクトップでビルドされ、SSH と転送の分だけ遅くなる
- デスクトップのスロット（32）が埋まると、あふれた分は手元でビルドせずに空きを待つ
- IFD のビルドはデスクトップで行われるが、評価そのものは手元で走る。重い評価はこの設定では防げないので、エージェントへの指示で扱う

`localBuilds` の既定は true にした。非力なホストだけが選ぶ設定だからだ。

## ビルダーの能力は `machines.nix` に置く

`maxJobs` と `supportedFeatures` は呼び出し側ではなくビルダーの性質なので、`hosts/machines.nix` のホスト一覧に置いた。
値はデスクトップ自身の `max-jobs`（32 スレッド）と `nix config show system-features` に合わせている。
`big-parallel` を載せないと、LLVM のようにそれを要求する derivation はデスクトップでビルドされない。

## `builders-use-substitutes = true`

ビルドの入力のうち binary cache にあるものは、デスクトップが cache.nixos.org から直接取る。
無効だとラップトップが tailnet 越しに送ることになり、出先の回線や DERP 経由の経路は cache.nixos.org への経路より遅いことが多い（[tailscale.md](./tailscale.md#出先のリモートビルドでは---use-substitutes-を付ける)）。

## `trusted-users = [ "@wheel" ]`

デスクトップの nix-daemon は、接続してきたユーザーが trusted でないと derivation のビルドを拒否する（`you are not privileged to build input-addressed derivations`）。
`--build-host` では成果物を `pomu` のまま手元のストアに取り込むので、呼び出し側でも trusted が要る。
`nix-settings.nix` は全ホストが読み込むので、両側とも満たす。

ユーザー名ではなく `@wheel` にしたのは、wheel がすでに sudo を持っていて、trusted-users の権限（ストアに任意のパスを書ける。実質 root 相当）と信頼の範囲が同じだからだ。
wheel 以外のユーザーを trusted にするときは、個別に追加する。

## `--build-host` は `.local` で接続し、`sudo` を付けずに `--sudo` で実行する

`.local`（mDNS）にしたのは、IP が変わっても同じセグメントなら名前が引け、ルーターの DHCP や DNS の設定に手を入れずに済むからだ。
LAN の外では `desktop-ts` を使う。

nixos-rebuild-ng 25.11 のソース（`nixos_rebuild/process.py`、`nixos_rebuild/nix.py`）では、`--sudo` が `sudo` を付けるのはアクティベートのコマンド（`nix-env -p <profile> --set` と `switch-to-configuration`）だけだ。
評価、SSH、転送は呼び出したユーザーのまま動く。
`sudo nixos-rebuild` にすると SSH が root として動き、root は `id_lan` を持たないので失敗する。

`sudo` に `SSH_AUTH_SOCK` を引き継ぐ案は退けた。
`id_lan` は home-manager がファイルとして書き出すだけで agent には登録しないので、ログインのたびに `ssh-add` が要る（2026-09-16 に、agent に `id_lan` がない状態で `Permission denied (publickey)` になるのを確かめた）。

代償として、`users.nix` の NOPASSWD は `nixos-rebuild` 本体だけなので、アクティベートでパスワードを聞かれる。
[手順](../howtouse/remote-build.md#パスワードを聞かれずに切り替える)では、ビルドと切り替えを分けて避けている。
1 回のコマンドのままパスワードをなくす案は二つある。`id_lan` を agent に載せて `sudo` の方式に戻す案（root から gcr の agent ソケットを使えるかは確かめていない）と、アクティベートのコマンドを NOPASSWD にする案（パスワードなしで root として動かせるコマンドが増える）だ。

## cargo のビルドは `cargo remote-run` でデスクトップに任せる

`cargo run` は nix-daemon を経由せずに rustc を起動するので、常設のビルダーではビルドされない。
spin713 で Bevy のプロジェクトを `cargo run` すると、4 スレッドで数百のクレートをコンパイルすることになる。
rsync、ssh、`nix copy` を組み合わせた自前のスクリプトで、ビルドだけをデスクトップに任せている。

退けた案と理由:

- Nix パッケージにして `nix run`（crane、`buildRustPackage`）: derivation の中では incremental compilation が使えず、編集のたびに自分のクレートを最初からコンパイルする
- デスクトップに SSH で入って開発する: GUI の画面がデスクトップに出て、RDP 越しに見ることになる
- sccache-dist: 分散されるのは主に依存クレートで、編集中のクレートとリンクは手元に残る。スケジューラとビルドサーバーの設置も要る
- [cargo-remote](https://github.com/sgeisler/cargo-remote): 同じ方式の既製品だが、既定ブランチの最終コミットが 2021-04-24 で（2026-09-26 に確認）、devShell を手元と揃える仕組みもない

### 手元の devShell をデスクトップへ送る

devShell の中でビルドした実行ファイルの ELF interpreter と RUNPATH は、devShell のストアパスを指す。
デスクトップで flake を評価し直すと、手元と devShell がずれたとき（checkout の版、未コミットの変更）に、持ち帰った実行ファイルが手元にない glibc を探して起動できない。
そこで手元で `nix print-dev-env --profile` を実行して `nix copy` で送り、デスクトップはその出力（bash の rc）を読み込むだけにした。

- `nix copy` に `--no-check-sigs` を付ける。env は手元か常設ビルダーで作った未署名のパスで、付けないと `lacks a signature by a trusted key` で失敗する（2026-09-26 に確認）
- rc はワークスペースの中で読み込む。aquaponics-sim の shellHook は `just --list` を実行し、ホームディレクトリでは `error: no justfile found` になった
- rc の標準出力は捨てる。shellHook の出力が runner の出力に混ざるため
- rc が作る一時ディレクトリ（`NIX_BUILD_TOP`）は終了時に消す。読み込む前に `NIX_BUILD_TOP` を unset し、rc が作ったものだけを消す

### 実行ファイルの選択は `cargo run` に任せる

デスクトップでも `cargo run` を実行し、`--config` で `target.'cfg(all())'.runner` を差し替えて、実行ファイルを動かさずにパスなどを返させる。
`default-run`、cwd のパッケージ、`-p`、`--bin`、`--example` による選択を、cargo と同じに作り直さずに済む。

- cargo は cwd の下にある実行ファイルを相対パスで、それ以外を絶対パスで runner に渡す（cargo 1.91.1 で確認）。スクリプトは両方を扱う
- [cargo の設定の仕様](https://doc.rust-lang.org/cargo/reference/config.html#targetcfgrunner)では、triple の runner は cfg の runner より優先され、cfg の runner が複数当たるとエラーになる。そのため、プロジェクトが runner を設定している構成には対応しない

### そのほかの判断

- rsync で `target/` を除外する。除外したパスは `--delete` でも消えないので、デスクトップの `target/` が残って incremental compilation に使われる。`-a` で mtime を保つ
- 手元の cwd のワークスペースからの相対位置を、デスクトップでも揃える。`cargo run` が選ぶパッケージは cwd で変わるため
- 実行ファイルは debug 情報を残したまま持ち帰る。aquaponics-sim の debug ビルドは 961 MB で、`objcopy --strip-debug` すると 85 MB になるが、panic のバックトレースからファイル名と行番号が消える。転送の速さと手元の容量より、行番号を優先した（2026-09-26 にユーザーが選んだ）
- 持ち帰る前に前回の実行ファイルを消す。rsync は一時ファイルに書いてから置き換えるので、残すと大きな実行ファイル 2 つ分の空きが要る。spin713 の空きが 739 MB のとき、2 回目の転送が `No space left on device` で失敗した
- 手元で実行するとき、`CARGO_MANIFEST_DIR` を手元のパッケージのディレクトリにする。Bevy 0.14.2 はこの変数で asset のルートを決め、設定しないと `target/remote-run/bin/assets` を探して読み込みに失敗する
- `ssh` に端末を割り当てない（`-t` を付けない）。割り当てると標準出力と標準エラー出力が一つになり、runner の出力を分けて読めない。代わりに、Ctrl-C で手元の ssh が終わってもデスクトップのプロセスに SIGHUP が届かない

## 見直す条件

- ラップトップにほかのユーザーを追加するなら、そのユーザーのビルドも `pomu` として送られることを見直す。`sshKey` を root 専用の鍵に分ける案がある
- 出先で DERP 経由になり、手元でビルドするほうが速い場面が続いたら、その場では `--builders '' --max-jobs 4` を付ける。常態化したら、tailnet の経路ごとに有効にする仕組みを考える
- tailnet をやめるなら、`hostName` を `.local` に戻す。出先では常設ビルダーが使えなくなる
- デスクトップのスレッド数やメモリが変わったら、`builder` の `maxJobs` と `supportedFeatures` を `nix config show` の値に合わせ直す
- 出先で tailnet に入れない場面が増え、`--max-jobs 4` を付ける手間が目立ったら、spin713 の `localBuilds` を true に戻す。エージェントが黙って手元でビルドすることは、エージェントへの指示の側で防ぐ
- `cargo remote-run` で実行ファイルの転送が待ち時間の大半を占めるようになったら（出先の回線など）、持ち帰る前に `objcopy --strip-debug` する。ラップトップの空きが実行ファイル 1 つ分を下回ったときも同じ。Bevy の `dynamic_linking` を使いたくなったら、`target/<profile>/deps/` の共有ライブラリも持ち帰って `LD_LIBRARY_PATH` に加える
- Ctrl-C の後にデスクトップで cargo が残り、次の実行がロック待ちになるのが目立ったら、rc を別のファイルで送り、ssh の標準入力が閉じたらデスクトップ側で cargo を止める
- devShell の評価が毎回遅いと感じたら、nix-direnv が `.direnv/` に残す profile を使う。nix-direnv の内部のファイル名に依存するので、最初は採らなかった
