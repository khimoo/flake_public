# 会社 PC（nixos-work-wsl）で GUI アプリと kitty を使う

> 履歴: この文書は作成時点の仕様・計画の記録であり、当時の工程指定は現在の必須手順ではありません。現在の指示・手順は [AGENTS.md](../../../AGENTS.md)、[文書整備](../../howtouse/documentation.md)、[検証ガイド](../../howtouse/validation.md) に従います。実装の現状は設定と現在の詳細文書で確認してください。

状態: 実装済み（2026-10-14）。「未確認」の項目は会社 PC での確認待ち。

## 目的

会社 PC でも、自宅と同じ kitty（`Ctrl+a > 階層 > 動詞` のキー体系と、Neovim との smart-splits の連携）で作業できるようにする。
あわせて、uv-mode の中にいるかをプロンプトで見分けられるようにする。uv-mode の外で `uv sync` を実行し、uv が取得した Python を起動できずに失敗したことがきっかけ。

デスクトップの keyd のような OS レベルのキー変換は対象外とする。WSL の中からは Windows のキー入力を変えられない。

## 確認済みの前提

いずれも 2026-10-14 に確かめた。

- 会社 PC では WSLg が使える。`/mnt/wslg` があり、`WAYLAND_DISPLAY=wayland-0`、`DISPLAY=:0` が設定されている。
- nixos-work-wsl では、NixOS-WSL が `hardware.graphics.enable` を有効にしている（評価で確認）。mesa のソフトウェア描画で OpenGL が使える。
- 会社 PC で素の kitty（`nix run nixpkgs#kitty`）を起動すると、ウィンドウは Windows のデスクトップに表示され、Windows とのコピー＆ペーストは双方向に動いた。Windows の IME で日本語を入力することはできなかった。
- nixos-work-wsl で `features.gui` を有効にした構成を `extendModules` で評価すると、system と Home Manager の assertion はどちらも通る。

## 決めたこと

### 会社 PC のユーザーで `features.gui` を有効にする

`hosts/nixos-work-wsl/home.nix` を作って `local.profile.features.gui = true;` を書き、`flake.nix` の nixos-work-wsl のユーザーに `homeFile` として渡す。spin713 の `hosts/nixos-spin713/home.nix` と同じ形にする。

kitty と端末フォントだけを有効にする `features.terminal` を新設する案は退けた。機能を増やさず、既存の `gui` をそのまま使うことを選んだ。
代償として、OBS、Chrome、Brave、IntelliJ、LibreOffice、Zoom なども入り、ダウンロードの量と WSL のディスク使用量が数 GB 単位で増える。どれも binary cache から取得するので、会社 PC でのビルドは発生しない。
Slack、Discord、Thunderbird などの自動起動は `graphical-session.target` に結び付いている。WSL にはデスクトップのセッションがなくこの target に到達しないので、自動では起動しない。

### Windows のスタートメニューから起動する

`hosts/nixos-work-wsl/default.nix` で `wsl.startMenuLaunchers = true` にする。NixOS-WSL がユーザーのプロファイルの `.desktop` ファイルを `/usr/share/applications` に写し、WSLg がスタートメニューに並べる。
代償として、`gui` で入るアプリがすべてスタートメニューに並ぶ。kitty はスタートにピン留めして使う。

### 描画は mesa のソフトウェア描画のままにする

素の kitty はソフトウェア描画で表示できた。遅いと感じたときだけ `wsl.useWindowsDriver` で Windows の GPU ドライバーを使う。

### 日本語入力は Neovim の skkeleton で行う

kitty には IME を入れない。Neovim の中では skkeleton（`core.nix` で辞書を設定済み）で日本語を打つ。シェルのプロンプトなど、Neovim の外では日本語を打てない。

WSL に fcitx5-skk を入れる案は退けた。WSLg の Wayland では IME のプロトコルを設定できないので、kitty を X11 で動かし、IBus 互換の経路で fcitx5 につなぐ必要がある。その経路が会社 PC で動くかを試しながら進めることになる。

### `local.restrictedHost` の制限は変えない

kitty の remote control は `listen_on unix:${XDG_RUNTIME_DIR}/kitty.sock` というローカルのソケットだけを使い、外への接続経路にはならない。

### uv-mode の中にいることをプロンプトに表示する

`packages/uv-mode/default.nix` の起動スクリプトで `IN_UV_MODE=1` を設定する。名前に `UV_` を付けないのは、uv が `UV_` で始まる環境変数を自分の設定として読むから。Nix の `IN_NIX_SHELL` と同じ付け方にした。
`modules/home-manager/core.nix` の starship の設定に `env_var.IN_UV_MODE` を足し、この変数があるときだけ `uv-mode` と表示する。starship の既定の並びには `$env_var` が入っているので、表示順は指定し直さない。

## 未確認

- Cursor の AppImage の取得（`api2.cursor.sh`）が会社のネットワークで通るか。`gui/apps.nix` はこの取得を switch のたびに行い、初回の取得に失敗するとアクティベーションが `exit 1` で止まる。switch の前に会社 PC で `curl -fsSI` を実行して確かめる。通らなければ、制限付きのホストでこの取得を飛ばす変更を足す。
- WSLg で kitty の背景の透過（`background_opacity 0.75`）が表示されるか。表示されない場合でも、不透明になるだけで操作には影響しない。
- WSLg の下で `XDG_RUNTIME_DIR` に kitty のソケットを作れ、smart-splits の移動が動くか。

## 変更するファイル

- `hosts/nixos-work-wsl/home.nix`（新規）
- `flake.nix`（nixos-work-wsl のユーザーに `homeFile` を渡す）
- `hosts/nixos-work-wsl/default.nix`（`wsl.startMenuLaunchers`）
- `packages/uv-mode/default.nix`（`IN_UV_MODE`）
- `modules/home-manager/core.nix`（starship の `env_var.IN_UV_MODE`）
- `tests/default.nix`（会社 PC の assertion）
- `docs/architecture/wsl.md`、`docs/howtouse/wsl.md`、`docs/howtouse/cli-tools/kitty.md`、`docs/howtouse/cli-tools/uv-mode.md`

## 確かめ方

テストでは、会社 PC の「機能を一つも有効にしない」という assertion を、「有効な機能が `gui` だけであること」と「kitty が入っていること」に置き換える。制限についての既存の assertion は残す。

手元のデスクトップでは次を確かめる。

- `module-contracts` の check（x86_64-linux と aarch64-darwin）
- nixos-work-wsl の `system.build.toplevel.drvPath` の評価
- 変更後の設定から生成される `starship.toml` を使い、uv-mode の中と外で `starship prompt` を実行して、`uv-mode` の表示が切り替わること
- `python3 scripts/check-docs.py .` と `git diff --check`

会社 PC では、switch の前に Cursor の URL に届くかを確かめる。switch した後に、スタートメニューからの kitty の起動、`Ctrl+a ?` のキー一覧、Neovim との smart-splits の移動、背景の透過の見え方、uv-mode の表示を確かめる。
