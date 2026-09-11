# lazy.nvim 本体だけを nixpkgs から取る構成

lazy.nvim 本体は nixpkgs の `vimPlugins.lazy-nvim` を `programs.neovim.plugins` で入れ、
プラグイン本体は lazy.nvim 自身が `~/.local/share/nvim/lazy` に clone して `lazy-lock.json` で固定する。
設定ファイル: [`../../../default.nix`](../../../default.nix)、[`../../lua/config/lazy.lua`](../../lua/config/lazy.lua)

## 役割分担

| 対象 | 持ち主 | 固定の仕組み |
|------|--------|--------------|
| lazy.nvim 本体 | nixpkgs (`programs.neovim.plugins`) | `flake.lock` の nixpkgs |
| プラグイン本体 | lazy.nvim (git clone) | `lazy-lock.json` (リポジトリ内で git 追跡) |
| Nix 側で組むもの (rustowl プラグイン、codelldb、LSP 一覧、SKK 辞書) | Home Manager | `~/.local/share/nvim/nix/*.lua` のブリッジファイルを `dofile` で読む |

Nix のラッパが lazy.nvim を packpath に載せるので、git clone によるブートストラップは要らない。
その代わり `performance.reset_packpath = false` と `performance.rtp.reset = false` が必要で、
これを外すと lazy.nvim が自分自身を見失う。

`~/.config/nvim` は `mkOutOfStoreSymlink` でリポジトリ実体を指すため、`:Lazy update` で
書き換わった `lazy-lock.json` はそのままリポジトリの差分になる。再現性の根拠はこのファイルなので、
更新したらコミットする。

## 採用しなかった案

### 全プラグインを nixpkgs の `vimPlugins` から取る

lazy.nvim の `dev.path` を Nix の packDir に向け、`dev = true` で nixpkgs 版を使う構成。
switch がオフラインで完結し、再現性も `flake.lock` に一本化できる。

採用しない理由は安定チャンネルの遅れ。nixos-25.11 の `vimPlugins.nvim-treesitter` は 2025-05-24 の
master 版で、Neovim 0.12 ではハイライトが壊れるため main ブランチへ移した経緯がある
([treesitter.md](../plugins/treesitter.md))。この遅れを 50 個近いプラグインぶん引き受けることになり、
neovim と tree-sitter を unstable に差し替えて回避している方針
([unstable-packages.md](../../../../../../../docs/architecture/unstable-packages.md)) と逆行する。
プラグインを一つ更新するたびに rebuild が要る点も、Lua を rebuild なしで反映させる現行の設計目標と合わない。

### nixvim / nvf

設定全体を Nix の型付きオプションに移す。設定の検証は強くなるが、Lua を直接編集して即反映する
運用を失い、全面書き直しになる。

### nixCats

lazy.nvim を残したまま nixpkgs のプラグインを使う。上の「全プラグインを nixpkgs から」と同じく
安定チャンネルの古さを引き受ける。

### lazy.nvim 本体も git clone でブートストラップする

nixpkgs 依存が消えるが、本体の版が Nix で固定されなくなるだけで得るものがない。

## 見直す条件

- nixpkgs 安定チャンネルの `vimPlugins` が使いたい版に追いつく状態が続くなら、再現性を優先して
  nixpkgs 側へ寄せる案を再検討する。
- lazy.nvim 本体の nixpkgs 版が上流から大きく遅れ、必要な機能に届かなくなったら、
  `overlays/unstable-packages.nix` の採用基準に照らして差し替えを検討する。
  2026-09 時点では nixpkgs の 2025-11-06 版が上流最新 (v11.17.5) と同じコミット。
