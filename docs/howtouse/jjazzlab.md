# JJazzLab

JJazzLab は、コード進行とリズムのスタイルから伴奏を生成するアプリ。
パッケージは [packages/jjazzlab](../../packages/jjazzlab/default.nix) で、[music_production.star](../../config/elements/music_production.star) が行動 `make_music` の `requires` から入ると導入する。利用者の `[[users]]` の `purposes` で `make_music` を選ぶ。無効にするには利用者の `purposes` から `make_music` を外す。
行動 `make_music` は nixos-desktop の pomu が選んでいる。

## 起動する

GNOME のアプリ一覧から JJazzLab を選ぶか、端末で `jjazzlab` を実行する。

JJazzLab が使うディレクトリは二つある。
`~/JJazzLab` にはリズムのスタイルとサンプル曲が、初回の起動時にコピーされる。
`~/.jjazzlab/<バージョン>` には設定とログが置かれる。

## 音が出ないときに調べる

内蔵シンセの状態は、ログ `~/.jjazzlab/<バージョン>/var/log/messages.log` に出る。

```sh
grep -E 'FluidSynthNativeLoader|audio.driver|SoundFont' ~/.jjazzlab/5.2.1/var/log/messages.log
```

`loadNativeLibraries() Success` があれば FluidSynth のライブラリを読み込めている。
`audio.driver=` の後ろが、FluidSynth が音を出すのに使っているドライバ。
初回は FluidSynth の既定の `alsa` になり、PipeWire の ALSA 互換を通して既定の出力に出る。

ドライバは内蔵シンセの設定で変えられる。
nixpkgs の FluidSynth で選べるのは `alsa`、`jack`、`pulseaudio`、`oss`、`file` で、PipeWire に直接出すドライバは入っていない。
`jack` を選ぶと PipeWire の JACK 互換に出る（desktop では `services.pipewire.jack.enable` で有効）。

## バージョンを上げる

1. [GitHub のリリース](https://github.com/jjazzboss/JJazzLab/releases)で新しいバージョンを確かめる。
2. `packages/jjazzlab/default.nix` の `version` を書き換え、配布物とアイコンのハッシュを取り直す。

   ```sh
   nix store prefetch-file --json https://github.com/jjazzboss/JJazzLab/releases/download/<バージョン>/JJazzLab-<バージョン>-linux-x64.tar.xz
   nix store prefetch-file --json https://raw.githubusercontent.com/jjazzboss/JJazzLab/<バージョン>/graphics/logo-JJazzLab.svg
   ```

3. [検証ガイドの単体 build](validation.md#対象別の確認手順) で `./packages/jjazzlab` をビルドする。
   `etc/jjazzlab.conf` の書き換えに失敗したときと、`libfluidsynth.so.3` が無いときは、ビルドが止まる。
4. JJazzLab のリポジトリの `pom.xml` の `jjazzlab.compiler.release` が 25 から変わっていたら、`jdk25` をそのバージョンの JDK に替える。

## 設計

### nixpkgs の JDK で起動する

配布物は NetBeans Platform のアプリで、Temurin の JRE（5.2.1 では 25.0.2）を `jdk/` に同梱している。
同梱の JRE は FHS 向けの ELF で、NixOS で動かすには `autoPatchelfHook` でローダーと依存ライブラリのパスを書き換える必要がある。
パッケージでは `jdk/` を消し、`etc/jjazzlab.conf` の `jdkhome` を nixpkgs の `jdk25` のパスに書き換える。
これで Java のセキュリティ修正は `nix flake update` で取り込める。
JJazzLab は Java 25 向けにビルドされている（5.2.1 の `pom.xml` の `jjazzlab.compiler.release`）。

### FluidSynth の場所を起動オプションで渡す

内蔵シンセは、jextract で生成した Java のバインディング（[FluidSynthJava](https://github.com/jjazzboss/FluidSynthJava)）から `libfluidsynth` を読み込む。
Linux のローダー `FluidSynthNativeLoader` は、システムプロパティ `fluidsynthlib.path`、前回成功したパスの保存値、`/usr/lib` などの決まったディレクトリの順に探す。
NixOS には決まったディレクトリにライブラリが無いので、パッケージは `jjazzlab.conf` の `default_options` に `-J-Dfluidsynthlib.path=` を追加して nixpkgs のライブラリを渡す。
システムプロパティは保存値より先に調べられるので、古い store パスが保存値に残っても使われない。

バインディングは FluidSynth 2.3 のヘッダから生成されているので、soname 3 のファイルを指す。
nixpkgs の FluidSynth の soname が変わると、installCheck でビルドが止まる。
そのときは FluidSynthJava が新しい soname に対応したかを確かめる。

5.2.1 と nixpkgs の FluidSynth 2.5.6 の組み合わせで、ライブラリの読み込み、`alsa` ドライバの初期化、同梱の SoundFont の読み込みが成功することを、2026-11-01 にログで確かめた。

### ウィンドウとランチャーを WM_CLASS で結び付ける

JJazzLab のウィンドウは XWayland で開き、`WM_CLASS` は `java-lang-Thread` になる（5.2.1 で `xprop` を使って確かめた）。
GNOME は `.desktop` の `StartupWMClass` とこの値を照合して、ウィンドウをランチャーのアイコンと名前で表示する。
nixpkgs の Java アプリのパッケージと同じく、確かめた値を `StartupWMClass` に書いている。
同じ `WM_CLASS` を名乗る別の Java アプリがあると、そのウィンドウも JJazzLab としてまとめて表示される。
