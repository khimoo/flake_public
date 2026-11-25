# デフォルトアプリケーション設定

使い方: [GUI アプリの管理](../howtouse/gui-apps.md)

## ブラウザとリンクの振り分け

既定ブラウザは [web_browsing.star](../../config/elements/web_browsing.star) で選びます。HTML を開くアプリと、HTTP/HTTPS のリンクを最後に開くブラウザをここで合わせるためです。Zen と Firefox は、それぞれのコンポーネントが公開する `command` と `desktop` で選べます。

[teams_dispatcher.star](../../config/elements/teams_dispatcher.star) は、Teams のリンクを Junction へ、その他のリンクを既定ブラウザへ渡します。Teams のアカウントは Junction で選ぶため、HTTP/HTTPS の既定アプリはブラウザではなくディスパッチャになります。ディスパッチャが選ばれたことは `writes(web_browsing)` で伝え、MIME の設定は `web_browsing` がまとめて出します。複数のアプリを同じスキームの既定として登録することを防ぐためです。

`web_browsing` だけを選んだ場合は、HTTP/HTTPS も直接ブラウザへ渡します。Firefox は既定ブラウザでなくなっても、Zen と並べて使えるように入れたままにします（ユーザーの選択）。両方の拡張機能と pref の管理は [ブラウザ](../howtouse/browsers.md) にまとめています。

Zen の flake は、ホストと同じ `nixpkgs` 入力を参照します。別系統の GUI ライブラリを重ねずに使うためです。採用した上流リビジョン [a7cac935 のパッケージ定義](https://github.com/0xc000022070/zen-browser-flake/blob/a7cac935fd58b6f177d2412ea00c566ed4f0abab/package.nix) は、nixpkgs 26.05 にない FFmpeg 9 を FFmpeg 8 へ置き換えます。

## ブラウザ以外の関連付け

[gui_apps.star](../../config/elements/gui_apps.star) は、アプリの `mime` から `xdg.mimeApps.defaultApplications` を作ります。アプリの追加と関連付けの追加を同じエントリで行えるためです。同じ MIME を複数のエントリに書くと、後のエントリが優先されます。

Slack・Discord・Spotify・Zoom の URL スキームも、各エントリの `mime` に書きます。portal 経由のスキーム解決を確実にするための指定です（[理由](./xdg-scheme-workaround.md)）。Obsidian のスキームは [obsidian.star](../../config/elements/obsidian.star) が担当し、利用目的 `grow_notes` か `write_documents` の `requires` から `obsidian` が入った場合だけ登録します。

## 自動起動と常駐の扱い

通知を見落とさないための常駐 GUI アプリは、[gui_apps.star](../../config/elements/gui_apps.star) の `autostart = True` から `xdg.configFile` で `~/.config/autostart/<name>.desktop` を生成し、XDG Autostart でログイン時に 1 回だけ起動します。

- **却下した案（`systemd.user.services`）**: `WantedBy = ["graphical-session.target"]` のユーザーサービスにすると、Home Manager（`release-26.05` / `sd-switch` 0.6.3）の activation が `nixos-rebuild switch` のたびに介入し、手動で閉じていたアプリの再起動やパッケージ更新時の再起動で作業画面にウィンドウが割り込みます。
- **トレイと専用ワークスペースの併用**: Slack（`--silent`）・Discord（`--start-minimized`）・TwinDesk（`--hidden`）は Waybar のトレイへ隠します。ウィンドウを閉じるとメール通知も止まる Thunderbird と、付箋は [Niri のウィンドウルール](../../config/elements/niri_background_apps.star) で名前付きワークスペースへ置き、起動時のフォーカス移動を抑えます。対象 app-id と実際の配置は実機確認が必要です。
- **起動の持ち主**: Niri の `niri.service` と `niri-headless.service` が要求する `xdg-desktop-autostart.target` で起動します。dex を併用すると同じ desktop entry が二重に実行されるため追加しません。
- **境界**: `gui_apps` は WSLg でも使うため、配置ルールは `niri_background_apps` に置きます。バーやセッションの設定方法は [Niri の使い方](../howtouse/niri.md) を参照してください。
