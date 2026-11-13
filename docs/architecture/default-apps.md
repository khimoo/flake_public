# デフォルトアプリケーション設定

使い方: [GUI アプリの管理](../howtouse/gui-apps.md)

## ブラウザとリンクの振り分け

既定ブラウザは [web_browsing.star](../../config/elements/web_browsing.star) で選びます。HTML を開くアプリと、HTTP/HTTPS のリンクを最後に開くブラウザをここで合わせるためです。Zen と Firefox は、それぞれの要素が公開する `command` と `desktop` で選べます。

[teams_dispatcher.star](../../config/elements/teams_dispatcher.star) は、Teams のリンクを Junction へ、その他のリンクを既定ブラウザへ渡します。Teams のアカウントは Junction で選ぶため、HTTP/HTTPS の既定アプリはブラウザではなくディスパッチャになります。ディスパッチャが選ばれたことは `writes(web_browsing)` で伝え、MIME の設定は `web_browsing` がまとめて出します。複数のアプリを同じスキームの既定として登録することを防ぐためです。

`web_browsing` だけを選んだ場合は、HTTP/HTTPS も直接ブラウザへ渡します。Firefox は既定ブラウザでなくなっても、Zen と並べて使えるように入れたままにします（利用者の選択）。両方の拡張機能と pref の管理は [ブラウザ](../howtouse/browsers.md) にまとめています。

Zen の flake は、ホストと同じ `nixpkgs` 入力を参照します。別系統の GUI ライブラリを重ねずに使うためです。採用した上流リビジョン [a7cac935 のパッケージ定義](https://github.com/0xc000022070/zen-browser-flake/blob/a7cac935fd58b6f177d2412ea00c566ed4f0abab/package.nix) は、nixpkgs 26.05 にない FFmpeg 9 を FFmpeg 8 へ置き換えます。

## ブラウザ以外の関連付け

[gui_apps.star](../../config/elements/gui_apps.star) は、アプリの `mime` から `xdg.mimeApps.defaultApplications` を作ります。アプリの追加と関連付けの追加を同じエントリで行えるためです。同じ MIME を複数のエントリに書くと、後のエントリが優先されます。

Slack・Discord・Spotify・Zoom の URL スキームも、各エントリの `mime` に書きます。GNOME でスキームを解決するために必要な指定です（[理由](./xdg-scheme-workaround.md)）。Obsidian のスキームは [obsidian.star](../../config/elements/obsidian.star) が担当し、行動 `grow_notes` か `write_documents` の `requires` から `obsidian` が入った場合だけ登録します。
