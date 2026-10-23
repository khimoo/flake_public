# Neovim のプラグインと外部の道具を機能として組にする

使い方: [Neovim の設定の変更](../../howtouse/neovim/README.md#設定の変更)
実装: [default.nix](../../../modules/home-manager/dev/neovim/default.nix)（仕組み）、[features.nix](../../../modules/home-manager/dev/neovim/features.nix)（機能ごとの依存）、[lazy.lua](../../../modules/home-manager/dev/neovim/config/lua/config/lazy.lua)、[nix.lua](../../../modules/home-manager/dev/neovim/config/lua/config/nix.lua)

外部コマンドや Nix の生成物を使うプラグインは、Nix の `local.neovim.features.<名前>` と `lua/features/<名前>.lua` の spec を組にする。
機能を外すと、spec の読み込み、Neovim の PATH に入れる道具、Lua に渡す値が一緒に外れる。プラグインと道具の対応を、コメントや人の記憶ではなく Nix の構造で持つため。

## 名前の一致を評価で確かめる

`lua/features/` のファイルと、定義した機能の名前が一致しないと、評価が assertion で止まる。spec を消して道具が残る場合も、道具を消して spec が壊れる場合も、switch の前に分かる。
Home Manager は有効な機能の名前と値を `~/.local/share/nvim/nix/features.lua` に書き出し、`lazy.lua` は有効な機能の spec だけを import する。`lua/plugins/` の一括の import に機能の spec を混ぜると、無効な機能も読み込んでしまうので、置き場所を分けている。

外部の道具を使わないプラグインは `lua/plugins/` に置き、機能にしない。

## 道具の持ち主

複数の機能が同じ道具を使うときは、それぞれの機能の `packages` に書く（例: wl-clipboard は clipboard と img_clip）。PATH には一度だけ入り、片方の機能を外しても、もう一方が使う間は残る。

RustOwl のように、Neovim のためだけに別の flake から取る道具は、その道具のモジュール（[rustowl.nix](../../../modules/home-manager/dev/neovim/rustowl.nix)）が機能を定義する。このモジュールも Neovim のモジュールから import するので、Neovim を外すと一緒に外れる。

## 採用しなかった案

- 道具の一覧にコメントで使い手を書く: 削除するときに人が対応を思い出す必要があり、消し忘れても何も起きない。
- `lua/plugins/` の中に置いたまま機能の有無を判定する: 一括の import が無効な機能も読み込むので、読み込みを止められない。
- プラグイン本体も Nix から入れる: [プラグインの管理](./plugin-manager.md) を参照。smart-splits だけは、kitty の kitten と同じ版を使うため、nixpkgs のパッケージを `dir` で読む。
