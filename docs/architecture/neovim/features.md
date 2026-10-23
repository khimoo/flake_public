# プラグインと外部ツールを機能として組にする

外部コマンドや Nix の生成物を使うプラグインは、Nix 側の「機能」の定義と `lua/features/<名前>.lua` の spec を組にする。
機能を外すと、spec の読み込み、Neovim の PATH に入れる道具、Lua に渡す値が一緒に外れる。
設定ファイル: [`../../../default.nix`](../../../modules/home-manager/dev/neovim/default.nix)（仕組み）、[`../../../features.nix`](../../../modules/home-manager/dev/neovim/features.nix)（機能ごとの依存）、[`../../lua/config/lazy.lua`](../../../modules/home-manager/dev/neovim/config/lua/config/lazy.lua)、[`../../lua/config/nix.lua`](../../../modules/home-manager/dev/neovim/config/lua/config/nix.lua)

## 仕組み

`local.neovim.features.<名前>` は `enable`、`packages`（Neovim の PATH だけに入るコマンド）、`luaPackages`（nixpkgs の Lua モジュール）、`data`（spec に渡す値）を持つ。
Home Manager は有効な機能の名前と `data` を `~/.local/share/nvim/nix/features.lua` に書き出す。
`lua/config/lazy.lua` は `{ import = "plugins" }` に加えて、有効な機能ごとに `{ import = "features.<名前>" }` を足す。
spec は `require("config.nix").data.<名前>` で値を読む。

`lua/features/` の各ファイルと、定義済みの機能名は一致しなければならない。
片方だけが残ると評価が assertion で止まるので、spec を消して道具が残る、道具を消して spec が壊れる、のどちらも switch の前に分かる。

外部の道具を使わないプラグインは `lua/plugins/` に置く。
すべてのプラグインを機能にする必要はない。

RustOwl のように別のモジュールが持つ道具は、そのモジュールが機能を定義する（[`../../../../rustowl.nix`](../../../modules/home-manager/dev/neovim/rustowl.nix)）。

## 編集と適用の境界

Lua の本文は checkout のファイルを直接読むので、spec の中身の編集は switch なしで次の起動から効く。
機能の追加と削除、`packages` と `data` の変更は Home Manager の適用で反映される。
spec のファイルを消して適用する前に Neovim を起動すると、古い世代の一覧がまだその機能を読もうとして import に失敗する。

## 道具を共有するとき

複数の機能が同じ道具を使う場合は、それぞれの機能の `packages` に書く（例：wl-clipboard は clipboard と img_clip）。
PATH には一度だけ入り、片方の機能を外しても、もう一方が使う間は残る。

## 採用しなかった案

- 道具の一覧にコメントで使い手を書く：削除時に対応を人が思い出す必要があり、消し忘れても何も起きない。
- プラグイン本体をすべて nixpkgs から取る：[plugin-manager.md](./plugin-manager.md) の理由で採らない。smart-splits は kitty の kitten と同じ版を使うため、例外として nixpkgs のパッケージを `dir` で読む。
- `lua/plugins/` の中に置いたまま機能を判定する：一括 import が無効な機能も拾うので、読み込みを止められない。
