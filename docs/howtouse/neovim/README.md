# Neovim の使い方

本環境における Neovim の設定変更方法と、各プラグインの使い方をまとめています。
設定ファイルは [modules/home-manager/dev/neovim/](../../../modules/home-manager/dev/neovim/) に配置されており、本ドキュメント内で `lua/...` と表記しているパスは、その配下の `config/` からの相対パスです。

## 設定の変更

`~/.config/nvim` はチェックアウトした `modules/home-manager/dev/neovim/config/` へのシンボリックリンクになっているため、Lua ファイルを編集すれば、Home Manager を switch（反映）しなくても次回の Neovim 起動時から反映されます。

外部コマンドや Nix の値を利用するプラグインは、`lua/features/<名前>.lua` の spec と、`features.nix` 内の同名機能がペアになっています。
機能の追加・削除や、利用するツール・設定値の変更は、Home Manager の適用（switch）によって反映されます。
spec ファイル名と機能名が一致しない場合、Nix の評価時に assertion エラーで停止します。
なお、機能の spec ファイルを削除した際は、Neovim を起動する前に switch を実行してください。先に起動してしまうと、前世代の機能一覧が削除済みのファイルを読み込もうとして import エラーが発生します。

## プラグインの更新

```vim
:Lazy update
```

更新を実行すると `config/lazy-lock.json` が書き換わり、リポジトリに変更差分が生じます。正常に動作することを確認してからコミットしてください。
更新を取り消したい場合は、git で `lazy-lock.json` を元に戻してから `:Lazy restore` を実行します。

`:Lazy update` は nvim-treesitter の更新後に `:TSUpdate` も実行し、パーサーを再構築します。
LSP サーバーや ripgrep などの外部ツールは Nix 経由で導入されるため、`:Lazy update` では更新されません。これらを更新するには、flake の input を更新して switch します。

## トラブルシューティング

| 症状 | 確認事項 |
|------|----------|
| プラグインが読み込まれない、または起動時にエラーが出る | `:Lazy` で読み込み状態やエラー内容を確認する |
| LSP が動かない | `:checkhealth vim.lsp` でサーバーが正常に接続されているか確認する |
| 外部ツールが見つからないと警告される | `:checkhealth` を確認する。ツールは Neovim 内部の PATH にのみ追加されるため、シェルから見えなくても問題ない |
| シンタックスハイライトが適用されない | 初回起動時はパーサーが非同期でコンパイルされるため、完了するまで待つ |

## ドキュメント一覧

| 用途 | プラグイン | ドキュメント |
|------|------------|--------------|
| キー操作の確認 | | [cheatsheet.md](./cheatsheet.md) |
| 作業別のキー操作 | | [workflows.md](./workflows.md) |
| 検索・ファイラー | telescope, oil.nvim | [telescope.md](./telescope.md) |
| LSP | nvim-lspconfig | [lsp.md](./lsp.md) |
| 構文解析 | treesitter, treesj, textobjects, aerial | [treesitter.md](./treesitter.md) |
| テスト | neotest, neotest-rust | [neotest.md](./neotest.md) |
| Git 操作 | gitsigns, diffview | [git.md](./git.md) |
| デバッグ | nvim-dap, dap-view, dap-go | [dap.md](./dap.md) |
| 編集支援 | Comment, surround, dial, hlslens, undotree, guess-indent | [editing.md](./editing.md) |
| 診断・Quickfix | trouble.nvim | [trouble.md](./trouble.md) |
| 補完 | blink.cmp | [completion.md](./completion.md) |
| 日本語入力 | skkeleton | [skkeleton.md](./skkeleton.md) |
| ファイル間移動 | harpoon2 | [navigation.md](./navigation.md) |
| ウィンドウと kitty ペイン操作 | smart-splits | [smart-splits.md](./smart-splits.md) |
| 外観・キー候補表示 | lualine, hlchunk, fidget, which-key | [appearance.md](./appearance.md) |
| Markdown | render-markdown.nvim, autolist.nvim, img-clip.nvim, marksman, diagram.nvim, image.nvim | [markdown.md](./markdown.md) |
| Rust | rustaceanvim, rustowl | [lang-rust.md](./lang-rust.md) |
| Typst | tinymist, typst-preview.nvim | [lang-typst.md](./lang-typst.md) |

## 設計・アーキテクチャ

- [プラグインの管理](../../architecture/neovim/plugin-manager.md): プラグインを lazy.nvim で取得し、`lazy-lock.json` でバージョンを固定する設計方針
- [機能の組](../../architecture/neovim/features.md): spec と Nix の依存関係をペアにし、まとめて着脱可能にする仕組み
- [spec のマージ](../../architecture/neovim/spec-merge.md): 言語固有の設定を共通プラグインの spec に統合する仕組み
