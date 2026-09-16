# nixos-unstable からの部分的な差し替え

設定ファイル: `overlays/unstable-packages.nix`、input は `flake.nix` の `nixpkgs-unstable`

## 問題

この flake は nixpkgs を `nixos-25.11` にピン止めしている。安定チャンネルは分岐後に新機能を取り込まない
ため、更新の速いパッケージほど上流との差が開く。

codex (OpenAI のコーディングエージェント CLI) の場合:

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.92.0 |
| nixos-unstable | 0.146.0 |
| 上流 openai/codex の最新リリース | 0.146.0 (2026-07-29) |

claude-code も同じ性格のクライアントで、こちらは遅れがモデル選択に出た。

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 2.1.140 |
| nixos-unstable | 2.1.263 |
| 上流 anthropics/claude-code の最新リリース | 2.1.268 |

Claude Fable 5.1 (`claude-fable-5-1`) を既定の Fable モデルとして追加したのは 2.1.257 で、`/model` の
一覧も課金の同意もクライアント側の実装に依存する。2.1.140 のままではサーバが提供しているモデルに
届かない。ここでの遅れは unstable と上流の間で数日、安定チャンネルと上流の間で 100 版以上ある。

古いままで困るかどうかはパッケージの性格による。ローカルで完結するツールなら機能が少し古いだけで済むが、
codex は認証とモデル選択を OpenAI のサーバとやりとりするクライアントで、サーバ側の変更に追随できないと
機能欠落ではなく動作不能に転びうる。

遅れが動作不能に転ぶ経路はもう一つある。安定チャンネルが取り込んだ版がたまたま既知のバグ持ちで、
上流では修正済みという場合で、tinymist (Typst の LSP 兼プレビュー) がこれに当たった。

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.14.2 |
| nixos-unstable | 0.15.2 |

0.14.2 は preview のビューポート計算を誤り、partial rendering を有効にすると表示範囲外のページが
SVG ではなく canvas で描画される。canvas には span 情報が乗らないため、プレビューをクリックしても
エディタへジャンプできない。境界はズーム率次第で、既定の倍率ではおおむね3ページ目から効かなくなる。
上流の [issue #2267](https://github.com/Myriad-Dreamin/tinymist/issues/2267) として報告され、
PR #2269 (2025-11-23) で修正された。0.14.2 のリリースは 2025-11-22 で、この修正の直前に当たる。

3つ目の経路は、パッケージ自体は正常に動くのに、それを前提にした別の設定が成立しない場合で、
neovim がこれに当たる。

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.11.7 |
| nixos-unstable | 0.12.5 |

kitty は wezterm と違ってスクロールバックの検索も vi 風の選択も持たず、`scrollback_pager` で
外部ページャに委ねる。ページャを Neovim に向けるとこの2つが同時に埋まるので、端末移行の設計は
それを前提にしている。kitty のドキュメントが載せている設定行は `nvim_open_term(0, {})` で
バッファを端末に変えて ANSI を描画させるが、0.11 の `nvim_open_term` はチャンネルを開くだけで、
stdin から読み込み済みの行を端末へ転送しない。同じ入力を 0.11.7 と 0.12.5 に与えて比べると、
前者は画面が空になり、後者は色付きで全行が出る。
[neovim#33720](https://github.com/neovim/neovim/pull/33720) が転送する側に変更した。

4つ目の経路は、差し替えた版が別のパッケージの版を引き上げる場合で、tree-sitter がこれに当たる。

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.25.10 |
| nixos-unstable | 0.26.11 |

neovim を 0.12 に上げた結果、nvim-treesitter の master ブランチが使えなくなった。master は 0.11
互換用として凍結されており、directive ハンドラに渡る `match` が 0.11 で
`table<integer, TSNode>` から `table<integer, TSNode[]>` に変わったのに追随していない。
markdown を開くと injection クエリの `set-lang-from-info-string!` が単一ノードを期待したまま
リストを受け取り、`node:range` が nil で落ちる。後継の main ブランチは全パーサの導入を
`tree-sitter build` に一本化したので、CLI が 0.26.1 以上でないとパーサを一つも入れられない
(main の `lua/nvim-treesitter/health.lua` の `TREE_SITTER_MIN_VER`)。25.11 の 0.25.10 では足りない。

## 判断

`nixpkgs-unstable` を input に追加し、overlay で対象パッケージだけを差し替える。全体を unstable に
するのではなく、パッケージ単位の allowlist にする。

- 採用基準は「安定（stable）チャンネルのバージョンのままだと機能が動作しなくなり、かつ unstable 側で
  解決されているか」とする。これに該当するケースは2つある。1つは外部サービスのクライアントがサーバー側の
  変更に追従できなくなった場合（`codex`、`claude-code`）、もう1つは安定チャンネルのバージョンに既知の
  バグがあり、上流で修正済みの場合（`tinymist`）である。単に動作するバージョンが少し古いだけという
  理由では、ここには追加しない。
- `neovim` は、この基準を厳密には満たしていない。0.11.7 の Neovim 自体が壊れているわけではなく、
  `chansend` を使ってターミナルチャンネルに直接データを流し込む回避策を書けば、0.11.7 でも色付きで
  表示できる。それでも差し替えを選択したのは、この回避策を導入すると kitty の標準的な設定を非標準的な
  コードで維持することになり、0.12 が安定チャンネルに提供された際にそのコードを削除する手間（負債）が
  残るためである。overlay に1行追加してここに理由を記述しておく方が、`kitty.conf` に説明の必要な
  コードを残すよりも、後から経緯を追いやすい。この件は、基準を緩和した唯一の例外として扱う。
- `tree-sitter` は基準を満たしている。Neovim 0.12 環境下では、0.25.10 だとパーサーを1つも導入できず、
  すべての言語で Tree-sitter によるシンタックスハイライトが機能しなくなる。ただし、これは独立した
  判断ではなく Neovim の差し替えに伴う依存項目のため、Neovim を安定版（25.11）に戻す場合は、これも
  同時に除外する。
- `codex` はこの overlay から除外し、専用の flake である `codex-cli-nix`（`flake.nix` の inputs）から
  取得している。unstable チャンネルであっても上流のリリースから数週間の遅れが生じることがあり、その
  遅延自体が動作不良を引き起こす原因になるためである。
- `claude-code` は `codex` と同様のケースに該当するが、`codex` のように専用 flake には切り出していない。
  unstable と上流の差が数日程度であり、必要なバージョン（2.1.257）に対して十分に余裕があるためで、
  `codex` で問題になった「数週間の遅れ」がこちらでは発生していない。もし unstable が必要なバージョンに
  追いつかない状態が続くようであれば、その時点で専用 flake への移行を検討する。
- overlay を採用したのは、利用側が詳細を意識しなくて済むようにするためである。たとえば
  `modules/home-manager/dev/apps.nix` では単に `codex` と記述するだけでよく、それがどのチャンネルに
  由来するものかを意識する必要がない。パッケージの取得元を変更しても、利用側の記述を変更する必要はない。
- overlay は `mkSystem` と `mkHome` の両方に適用されている（`lib/configurations.nix` の `overlays`）ため、
  NixOS ホストとスタンドアロンの Home Manager（WSL / macOS）の双方で同じパッケージがインストールされる。
- 既存の `overlays/default.nix` とはファイルを分けている。あちらは上流で修正されたら削除する
  「一時的なパッチ」の置き場であり、こちらは安定チャンネルが追いついた時点で適用をやめる
  「パッケージの差し替え」であるため、削除（クリーンアップ）の契機が異なる。

コストは nixpkgs を 2 つ評価する分の時間とメモリ、および closure に unstable 側の stdenv 由来の依存が
別途乗ること。

全体を unstable に上げる案は見送った。home-manager が `release-25.11` に固定されていて `master` へ
道連れになること、`follows` している小規模な input (winapps / claude-history / zettelkasten) が
nixpkgs の破壊的変更に追随できるか読めないこと、musnix がリアルタイムオーディオでカーネル設定に
踏み込んでいることが理由。この数パッケージのために動かす範囲としては大きい。

## 見直しの契機

- NixOS のリリースを上げたとき: 差が縮んでいれば対象から外して安定チャンネルに戻す。tinymist は
  修正を含む 0.15 以降が安定チャンネルに入った時点で外せる。neovim は 0.12 以降が入った時点。
  tree-sitter は neovim と同時に判断する。安定チャンネルが 0.26.1 以降を持てば外せるが、
  neovim を戻すなら nvim-treesitter も master に戻るので不要になる。claude-code は上流の更新が速く、
  安定チャンネルが追いつく見込みが薄いので、リリースを上げても残る可能性が高い。
- 全体を unstable に移行したとき: この overlay と input ごと不要になる。
- 対象を増やすとき: 上の採用基準に照らす。「新しい方が嬉しい」だけでは足さない。

## 関連

- [devshells.md](./devshells.md) — devShell 側も同じ overlay を通る
- [agent-config.md](./agent-config.md) — Claude Code のユーザー設定の管理

## Graphify

安定チャンネルに存在しないため、既存 unstable の package を使う。[採用理由](graphify.md)を参照。
