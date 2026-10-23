# キーボードレイヤーの確認手順

修飾キーを押した際に各キーがどのように動作するかを確認する手順です。

「GNOME の設定画面に出てこないキー変換が実際には機能している」という状況が発生するのは、キー変換が複数のレイヤーに分かれて処理されており、GNOME が表示しているのはそのうちの 1 つの層に過ぎないためです。

## 3 つの変換レイヤー

| 層 | 担当役割 | 設定場所 | 調査用ツール |
|----|------|------|-----------|
| keyd | evdev レベルのキーコード変換 | `/etc/keyd/*.conf` | `keyd monitor`, `keyd listen` |
| xkb | レイアウトとシフトレベル（Shift / AltGr） | GNOME の `org.gnome.desktop.input-sources`（ログイン画面は `services.xserver.xkb`） | `xkbcli compile-keymap`, GNOME のレイアウト表示 |
| アプリ | ショートカットの解釈 | 各アプリケーション | 各アプリケーションの設定画面 |

keyd は物理キーボードの入力を直接キャッチし、変換後のキーコードを `keyd virtual keyboard` という仮想デバイスとしてシステムへ流し直します。
xkb に届くのは変換済みの結果のみであるため、GNOME の「キーボードレイアウトを表示」には keyd による変換内容は反映されません。

GNOME のキー配列には English (intl., with AltGr dead keys)（`us+altgr-intl`）が使用されており、Home Manager 経由で dconf に設定されています（[pomu-workstation.nix](../../profiles/home/pomu-workstation.nix)）。ベースは通常の US 配列と同じですが、右 Alt が AltGr として機能します。GNOME の設定画面から変更しても、次回の switch 実行時に元の設定へ上書きされます。

例として、spin713 では Alt+Backspace で Delete が入力されますが、xkb 側にはその定義は存在しません。`/etc/keyd/internal.conf` の `[alt]` セクションに記述された `backspace=delete` が実際の挙動を定義しています。

## keyd の設定ファイルの読み方

`/etc/keyd/*.conf` はレイヤーごとにセクション分けされているため、そのままマッピングの一覧として確認できます。

```
[main]
f1=back              単体の F1 は「戻る」（ChromeOS の最上段キーを再現）

[meta]
f1=f1                検索キー + F1 で本来のファンクションキーとして動作

[alt]
backspace=delete     Alt+Backspace で Delete
```

設定の生成元は以下のとおりです。

| ホスト | 設定ファイル | 対象 |
|--------|---------|------|
| nixos-spin713 | [chrome-audio.nix](../../hosts/nixos-spin713/chrome-audio.nix) | 内蔵キーボード（ChromeOS 配列の再現） |
| nixos-desktop | [keyd-turbo.nix](../../hosts/nixos-desktop/keyd-turbo.nix) | 全キーボード（右 Alt による右クリック連打機能。◇ + 右 Alt でオン/オフを切り替え可能。起動時はオフ） |

## 設定に書かれていないキーの挙動

暗黙的な上書きは行われません。設定に現れないキーはそのまま通過します。
keyd は `main` レイヤーで各キーを自分自身にバインドしているため、未指定のキーは素通しになります。

`[alt]` や `[control]` は keyd の組み込みレイヤーであり、内部的には `alt:A` のように修飾キー付きで定義されています。
明示的なマッピングがないキーについては単にその修飾キーを付与して出力するだけなので、`Alt+j` などは設定に記述がなくてもそのまま `Alt+j` として入力されます。

注意が必要なのは、むしろ明示的に記述されているキーの副作用です。以下の 3 点は直感に反しやすいため留意してください。

**レイヤー内のバインディングは、そのレイヤー自身の修飾キーを受け取らない**
`[alt]` セクション内の `backspace=delete` が出力するのは、Alt+Delete ではなく単体の Delete です。Ctrl+Alt+Backspace で Ctrl+Alt+Delete を出力するために、`[controlalt]` セクションに `backspace = "C-A-delete"` と修飾キーを明示的に指定しているのはこのためです。

**レイヤーは物理キー名で参照され、上位レイヤーが `main` を隠蔽する**
`[main]` に書かれた `f1=back` は、Meta キーの押下中には参照されず、`[meta]` の `f1=f1` が優先されます。ここで `[meta]` の `f1` が指しているのは物理的な F1 キーであり、`main` で変換された後の `back` ではありません。

**`[ids]` に記載のないデバイスは keyd を通過しない**
spin713 の設定ではワイルドカード（`*`）を使わずデバイス ID を明示的に列挙しているため、外付けキーボードを接続してもリマップは適用されず、素の配列のまま動作します。

## 実際のイベントを確認する

`keyd monitor` で変換前後のキーイベントを、`keyd listen` でアクティブなレイヤーの遷移を確認できます。evdev の読み取りには root 権限が必要です。

```sh
# keyd の実行ファイルパスを取得（世代を切り替えると変更されます）
systemctl cat keyd | grep ExecStart

pkexec /run/current-system/sw/bin/bash -c '<上で取得したパス> monitor'
```

`services.keyd` は keyd を `environment.systemPackages` に追加しないため、標準では PATH が通っていません。日常的にコマンドを利用する場合は、`pkgs.keyd` を追加してください。

xkb 側のシフトレベル（段）を一覧表示したい場合は、以下を実行します。
出力は `[ 素, Shift, AltGr, AltGr+Shift ]` の順に並びます。

```sh
nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap --layout us --variant altgr-intl | grep 'key <'
```

キーを押した瞬間の最終的な解決結果（keyd 変換後の keysym および修飾キーの状態）を確認するには、`xkbcli interactive-wayland` を使用します。

## 設定を誤って入力不能になった場合の復旧

keyd は物理入力デバイスを直接制御するため、設定を誤るとログインすらできなくなる可能性があります。
その場合は、`backspace` + `escape` + `enter` を同時に押してください。これが緊急脱出用のパニックシーケンスとなっており、keyd を強制終了して通常の素のキーボード状態へ復帰させることができます。
