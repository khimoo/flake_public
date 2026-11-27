# Dev モード（設定の個別ライブ編集）

実装: [dotfiles_mode.star](../../config/elements/dotfiles_mode.star) / [dotfiles-mode.py](../../modules/home-manager/dev/dotfiles-mode.py) / [RightColumn.qml](../../modules/home-manager/gui/quickshell/hub/RightColumn.qml)

Neovim・Niri・Quickshell ハブ・kanshi・kitty の設定は、既定でその世代の **Nix store（OFF）** を参照します。ローカル checkout を rebuild なしで編集・書き戻ししたいときだけ、対象ごとに **Dev モード（ON）** へ切り替えます。

`nixos-rebuild switch` や `flake-deploy switch` を実行すると、activation によって全対象が自動的に OFF（最新世代の Nix store）へ戻ります。

## Quickshell ハブから切り替える

スタートメニュー（`Super` 単押し / `Mod+D`）右カラムの **「Dev モード」** 欄に、そのホストで有効な対象のボタン（`Niri` / `Hub` / `kanshi` / `kitty` / `nvim`）が並びます。

- ボタンをクリック（または `Tab` → `Enter`）すると、その対象だけ ON（黄色・checkout）と OFF（Nix store）が切り替わります。
- 1 つ以上 ON のときは右上に **「全て戻す」** が表示され、全対象を一括で OFF へ戻せます。
- `Hub` を切り替えると `quickshell-hub.service` が再起動するため、ハブが一瞬閉じます。
- ローカル checkout に対象ファイルが無い環境では ON に切り替えず、通知を出して store モードを維持します。

## CLI から切り替える

WSL や SSH など GUI ハブが無い環境でも、`dotfiles-mode` コマンドで同じ操作ができます。

```sh
dotfiles-mode status              # 現在の状態一覧（--json / --status-json で JSON 出力）
dotfiles-mode toggle niri         # 指定対象を ON / OFF 切替
dotfiles-mode on nvim             # 指定対象を Dev モード（checkout）へ
dotfiles-mode off nvim            # 指定対象を通常モード（Nix store）へ
dotfiles-mode reset               # 全対象を通常モードへ戻す
```

## 対象ごとの反映と注意点

- **Niri（`niri`）**: 切替時に `niri msg action load-config-file` を実行します。
- **Quickshell ハブ（`quickshell`）**: 切替時に `systemctl --user restart --no-block quickshell-hub.service` を実行します。
- **kanshi（`kanshi`）**: 切替時に `kanshictl reload` を実行します。OFF（store）中は設定が読み取り専用のため、`kanshi-switch` でプロファイルの作成・編集・削除・既定変更を行う前に `kanshi` を ON にしてください（切替自体は OFF でも行えます）。
- **kitty（`kitty`）**: 切替時に起動中の `kitty` プロセスへ `SIGUSR1` を送ります（新規ウィンドウは自動で反映）。
- **Neovim（`nvim`）**: 次回起動から反映されます。OFF（store）中は `lazy-lock.json` が読み取り専用のため、[lazy.lua](../../modules/home-manager/dev/neovim/config/lua/config/lazy.lua) が lockfile の書き込み先を `~/.local/state/nvim/lazy-lock.json` へ逃がします（switch / OFF 時に store 版の `lazy-lock.json` を同期）。`:Lazy update` の結果をリポジトリへ反映するときは `nvim` を ON にして実行してください。

## 設計

- **二段シンボリックリンク**: Home Manager は `~/.config/...` を `~/.local/state/dotfiles-mode/links/<対象>` への固定リンクとして配置し、`dotfiles-mode` と activation（`home.activation.dotfilesMode`）がその先のリンク先（Nix store ↔ checkout）だけを原子的に差し替えます。Home Manager の管理下パスを直接書き換えないため `switch` と衝突せず、コンポーネントを外したときの後片付けも Home Manager 側で完結します。
- **ホスト分岐を持たない**: 全ホストで既定が store モードのため、`nixos-spin713` をリモート更新（`--target-host` / `flake-deploy`）した際も、ローカル checkout の有無や鮮度に依存せず新世代の設定がそのまま有効になります（[構成の境界](../architecture/configuration.md#ホストによる違いを受け持つ場所)）。
- **対象一覧の自動集約**: 各コンポーネント（`neovim`・`niri_config`・`kitty`・`quickshell_hub`・`display_layout`）が `writes(dotfiles_mode)` で自分自身を寄与するため、ホストで有効な対象だけが CLI とハブ UI に現れます。Home Manager を使わないユーザー（`mase`）には `dotfiles-mode` が入らず、ハブのセクション自体が非表示になります。
- **未確認事項**: 二段シンボリックリンク越しに Niri・Quickshell のファイル監視による自動リロードが発火するか、および Nix store 配下の設定に対する `lazy.nvim` の `import` 挙動は、実機適用後に確認します。
