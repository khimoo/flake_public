# Neovim のプラグインの管理

使い方: [プラグインの更新](../../howtouse/neovim/README.md#プラグインの更新)
実装: [default.nix](../../../modules/home-manager/dev/neovim/default.nix)、[lazy.lua](../../../modules/home-manager/dev/neovim/config/lua/config/lazy.lua)

## lazy.nvim がプラグインを取り、lazy-lock.json で固定する

lazy.nvim の本体は nixpkgs の `vimPlugins.lazy-nvim` を `programs.neovim.plugins` で入れ、Nix のラッパーが packpath に載せる。プラグインは lazy.nvim が `~/.local/share/nvim/lazy` に clone し、`config/lazy-lock.json` で版を固定する。
`~/.config/nvim` は checkout への symlink なので、`:Lazy update` で書き換わった lockfile はそのままリポジトリの差分になり、コミットすれば全マシンで同じ版になる。

この形にしているのは、プラグインの更新を、switch せずに `:Lazy update` とコミットだけで済ませるため。
Nix から入れるのは、lazy.nvim の本体、機能の道具（[機能の組](./features.md)）、RustOwl と smart-splits のプラグインだけ。

Lua の設定を switch なしで編集できるのは、`~/.config/nvim` が checkout を指しているからで、プラグインをどこから取るかとは関係しない。

lazy.nvim の luarocks の統合は無効にし、Lua のモジュールが要るプラグインには、機能の `luaPackages` で nixpkgs から渡す。lazy.nvim が組み立てる hererocks が Nix の環境では作れないため。理由の詳細は `lazy.lua` のコメントにある。

## 採用しなかった案

### nixpkgs の vimPlugins からプラグインを取る

switch がオフラインで済み、版の固定も `flake.lock` にまとまる。
退けた理由は安定チャンネルの遅れ。nixos-25.11 の `vimPlugins.nvim-treesitter` は 2025-05-24 の master の版で、Neovim 0.12 ではハイライトが壊れた（[treesitter.md](../../howtouse/neovim/treesitter.md#設計)）。50 個近いプラグインで、この遅れを引き受けることになる。

### プラグインを Git のコミットで Nix に固定する（nixCats など）

nixpkgs を使わずに、プラグインごとの Git のコミットを Nix で固定する。安定チャンネルの遅れはなく、Lua も今と同じく checkout から読める。
退けた理由は、プラグインを更新するたびに Nix の側の固定を更新して switch する必要があること。switch がオフラインで済むことや、固定が `flake.lock` にまとまることを必要とする場面が今はない。

### nixvim、nvf

設定を Nix のモジュールのオプションで書く。どちらも Lua をそのまま渡す手段はある（2026-10 に公式の README で確認）が、今の spec の合成（[spec のマージ](./spec-merge.md)、[機能の組](./features.md)）を移し替える必要があり、移して得るものが今はない。

### lazy.nvim の本体も git clone で入れる

本体の版が Nix で固定されなくなるだけで、得るものがない。

## 単独のパッケージとしては公開しない

この Neovim を、Home Manager を使わない人も `nix run` で起動できるパッケージとして公開することを検討し、2026-10 にやめた。使う人がいないのに、次の仕組みを保守することになるため。

- lazy.nvim は、プラグインを clone したあとに lockfile を書き込む（v11.17.5 の `lua/lazy/manage/init.lua`）。Nix store に置いた設定の lockfile には書き込めないので、書き込める場所に写し、公開版を更新したときに揃え直す仕組みが要る。
- 初回の起動で、プラグインを GitHub から clone し、パーサーを手元でコンパイルする。配った時点では揃っておらず、ネットワークにつながらないと動かない。
- 公開版と Home Manager の Neovim を同じ定義から作るには、機能の合成とラッパーを Home Manager の外に出すか、Home Manager の評価から取り出す必要がある。

公開するなら、軽い案は次の形になる。Neovim のモジュールだけを入れた最小の Home Manager の構成を評価し、`config.programs.neovim.finalPackage` を、`NVIM_APPNAME` を設定して Nix store の `init.lua` を `-u` で読ませるシェルのラッパーで包む。Home Manager は生成した Lua を `--cmd` で読み込み、`wrapRc = false` なので、ラッパーが `-u` を足しても衝突しない（Home Manager 26.05 の `modules/programs/neovim/default.nix` で確認）。lazy.nvim の `import` が Nix store の設定を見つけられるかは確かめていない。

## 見直す条件

- nixpkgs の安定チャンネルの `vimPlugins` が使いたい版に追いつく状態が続くなら、nixpkgs の側へ寄せる。
- lazy.nvim の本体の nixpkgs の版が上流から大きく遅れたら、unstable からの差し替えを検討する（[unstable-packages.md](../unstable-packages.md)）。2026-09 の時点では、nixpkgs の 2025-11-06 版が上流の最新（v11.17.5）と同じコミット。
- オフラインでの switch のように、Nix で固定する利点が要る場面ができたら、Git のコミットで Nix に固定する案を見直す。
- Neovim を単独で配る相手ができたら、上の軽い案から試す。
