# nixos-unstable からの部分的な差し替えの設計

実装: [overlays/unstable-packages.nix](../../overlays/unstable-packages.nix)、input は `flake.nix` の `nixpkgs-unstable`

## 対象を絞った overlay で差し替える

この flake は nixpkgs を `nixos-26.05` に固定している。安定チャンネルは分岐した後の新機能を取り込まないので、更新の速いパッケージほど上流との差が開く。
そこで `nixpkgs-unstable` を input に足し、overlay で対象のパッケージだけを差し替える。

対象にする基準は、「安定チャンネルの版のままだと機能が動かず、unstable では直っている」こと。単に新しいほうがよいという理由では足さない。
外部のサービスのクライアントがサーバーの変更に追いつけない場合と、安定チャンネルの版に既知のバグがあって上流で直っている場合がこれに当たる。

- 利用側は `pkgs.tinymist` と書くだけで、どのチャンネルから来たかを知らずに済む。取得元を変えても利用側は変わらない
- overlay は `mkSystem` と `mkHome` の両方に適用されるので（`lib/configurations.nix` の `overlays`）、NixOS と standalone の Home Manager（macOS）で同じパッケージになる。devShell も同じ overlay を通る
- `overlays/default.nix` とはファイルを分ける。あちらは上流で直ったら消す一時的なパッチの置き場で、こちらは安定チャンネルが追いついたら外す差し替えなので、消す契機が違う

代償として、nixpkgs を 2 つ評価する時間とメモリがかかり、closure に unstable の stdenv の依存が別に載る。

全体を unstable に上げる案は退けた。home-manager が安定版の release ブランチに固定されていて master へ道連れになること、`follows` している小さな input（claude-history、memex-nix）が nixpkgs の破壊的な変更に追いつけるか読めないこと、musnix がリアルタイムオーディオのためにカーネルの設定に踏み込んでいることが理由。

## 今の対象

- tinymist: 0.14.2 はプレビューの表示範囲の計算を誤り、partial rendering を有効にすると範囲外のページを SVG ではなく canvas で描く。canvas には span の情報がないので、プレビューをクリックしてもエディタへ飛べない（既定の倍率では、おおむね 3 ページ目から）。上流の [issue #2267](https://github.com/Myriad-Dreamin/tinymist/issues/2267) で報告され、PR #2269（2025-11-23）で直った。修正を含む 0.15 以降が安定チャンネルに入ったら外す（nixos-26.05 は 0.14.18）
- graphify: 安定チャンネルにない（[graphify.md](../howtouse/graphify.md#設計)）
- GNOME 拡張の extension-list: nixos-26.05 の版 43 は `metadata.json` の `shell-version` が `["49"]` だけで、GNOME Shell 50 は読み込まない（`gnome-extensions info` が `OUT OF DATE`）。unstable には GNOME 50 に対応した版 45 がある（2026-10-03 に確認）。`gnomeExtensions` は入れ子の集合なので、extension-list だけを差し替える。GNOME と拡張の版のずれは `checks.x86_64-linux.gnome-extensions` が検出する

## codex と claude-code は専用の flake から取る

どちらも認証とモデルの選択をサーバーとやりとりするクライアントで、遅れると機能が欠けるだけでなく、動かなくなりうる。
クライアントは自分のカタログにないモデル ID を拒むので（claude-code 2.1.268 に `--model claude-opus-5-5` を渡すと `[claude-code:unrecognized_model]` で起動しない）、新しいモデルを使うには常に最新の版が要る。
nixos-unstable でも上流のリリースから数日（claude-code）から数週間（codex）遅れるので、この overlay ではなく専用の flake（`codex-cli-nix`、`claude-code-nix`）から取る。nixpkgs が上流のリリース当日に追いつくようになったら、overlay に戻して input を消す。

## 以前の対象から分かっていること

nixos-25.11 の間は neovim と tree-sitter も差し替えていた。26.05 は neovim 0.12.4 と tree-sitter 0.26.8 を持つので外した。安定チャンネルの版を下げるときに、次が効く。

- kitty の `scrollback_pager` を Neovim に向ける設定（[kitty.md](./kitty.md#スクロールバック)）は 0.12 以降でしか動かない。0.11 の `nvim_open_term` は、stdin から読み込んだ行を端末へ転送しないので、画面が空になる（[neovim#33720](https://github.com/neovim/neovim/pull/33720) で転送するように変わった）
- Neovim 0.12 では nvim-treesitter の master ブランチが使えず（0.11 で directive に渡る `match` が `table<integer, TSNode[]>` に変わったのに追随していない）、後継の main ブランチはパーサーの導入に tree-sitter の CLI 0.26.1 以上を要る（main の `lua/nvim-treesitter/health.lua` の `TREE_SITTER_MIN_VER`）

## 見直す条件

- NixOS のリリースを上げたら、差が縮んだ対象を外して安定チャンネルに戻す
- 全体を unstable に移したら、この overlay と input ごと要らなくなる
- 対象を増やすときは、上の基準に照らす
