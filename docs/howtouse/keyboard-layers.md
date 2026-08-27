# キーボードのレイヤーを調べる

修飾キーを押したときに各キーが何になるかを確認する手順。

「GNOME の設定に出ていない変換が実際には効いている」という状況が起きるのは、
変換が複数の層に分かれていて、GNOME が見せるのはそのうち 1 層だけだから。

## 変換は 3 層ある

| 層 | 担当 | 設定 | 調べる道具 |
|----|------|------|-----------|
| keyd | evdev レベルのキーコード変換 | `/etc/keyd/*.conf` | `keyd monitor`, `keyd listen` |
| xkb | レイアウトと段（Shift / AltGr） | `services.xserver.xkb` | `xkbcli compile-keymap`, GNOME のレイアウト表示 |
| アプリ | ショートカット解釈 | 各アプリ | 各アプリの設定画面 |

keyd は物理キーボードを掴んで、変換済みのキーコードを `keyd virtual keyboard` という
仮想デバイスとして流し直す。
xkb に届くのは変換後の結果だけなので、GNOME の「キーボードレイアウトを表示」に
keyd の分は出てこない。

例として spin713 では Alt+Backspace が Delete になるが、xkb 側にその定義は無い。
`/etc/keyd/internal.conf` の `[alt]` セクションにある `backspace=delete` が実体。

## keyd の設定を読む

`/etc/keyd/*.conf` はレイヤーごとにセクション分けされているので、そのまま一覧として読める。

```
[main]
f1=back              素の f1 は「戻る」（ChromeOS の上段キーの再現）

[meta]
f1=f1                検索キー + f1 で本来のファンクションキー

[alt]
backspace=delete     Alt+Backspace で Delete
```

生成元は以下。

| ホスト | ファイル | 対象 |
|--------|---------|------|
| nixos-spin713 | [chrome-audio.nix](../../hosts/nixos-spin713/chrome-audio.nix) | 内蔵キーボード（ChromeOS 配列の再現） |
| nixos-desktop | [keyd-turbo.nix](../../hosts/nixos-desktop/keyd-turbo.nix) | 全キーボード（右 Alt の連打マクロ） |

## 書かれていないキーはどうなるか

暗黙の上書きは無い。設定に現れないキーはそのまま通る。
keyd は `main` レイヤーで各キーを自分自身に束縛しているため、未記載なら素通しになる。

`[alt]` や `[control]` は keyd の組み込みレイヤーで、内部的には `alt:A` のように
修飾子付きで定義されている。
明示マッピングが無いキーについては単にその修飾子を再現するだけなので、
`Alt+j` は設定に書かなくても `Alt+j` のまま出る。

注意すべきなのはむしろ書かれている方の副作用で、以下の 3 点は直感に反する。

**レイヤー内の binding は、そのレイヤー自身の修飾子を受けない。**
`[alt]` の `backspace=delete` が出すのは Alt+Delete ではなく素の Delete。
Ctrl+Alt+Backspace で Ctrl+Alt+Delete を出すために `[controlalt]` へ
`backspace = "C-A-delete"` と修飾子を明示して書いてあるのはこのため。

レイヤーは物理キー名で引かれ、上位レイヤーが `main` を遮蔽する。
`[main]` の `f1=back` は Meta 押下中には参照されず、`[meta]` の `f1=f1` が勝つ。
`[meta]` の `f1` が指すのは物理の f1 キーであって、`main` で変換された後の `back` ではない。

`[ids]` に載っていないデバイスは keyd を通らない。
spin713 の設定は `*` を使わず ID を明示列挙しているので、外付けキーボードを挿すと
リマップが効かず素の配列で動く。

## 実際のイベントを見る

`keyd monitor` が変換前後のキーイベント、`keyd listen` が活性レイヤーの遷移を出す。
evdev の読み取りに root が要る。

```sh
# keyd の実体パスを取る（世代を切り替えると変わる）
systemctl cat keyd | grep ExecStart

pkexec /run/current-system/sw/bin/bash -c '<上で得たパス> monitor'
```

`services.keyd` は keyd を `environment.systemPackages` に入れないので PATH には無い。
常用するなら `pkgs.keyd` を足す。

xkb 側の段を一覧したいときは以下。
`[ 素, Shift, AltGr, AltGr+Shift ]` の順に並ぶ。

```sh
nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap --layout us | grep 'key <'
```

押した瞬間の解決結果（keyd 変換後の keysym と修飾状態）は `xkbcli interactive-wayland`。

## 設定を壊して入力できなくなったとき

keyd は物理入力デバイスを掴むので、設定を間違えるとログインもできなくなりうる。
`backspace` + `escape` + `enter` の同時押しが脱出用のパニックシーケンスで、
keyd を強制終了させて素のキーボードに戻す。

## 関連

- [wezterm のキーバインド](./cli-tools/wezterm.md)
- [Neovim のキーバインド](../../modules/home-manager/dev/neovim/config/docs/README.md)
