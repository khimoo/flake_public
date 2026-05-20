# Teams マルチアカウント ディスパッチャ

設定ファイル: `modules/home-manager/gui/teams-dispatcher.nix`

## 背景

teams-for-linux はマルチアカウントに対応しておらず、アカウント切り替えに毎回ログアウトが必要。
公式のマルチプロファイル機能 ([#1830](https://github.com/IsmaelMartinez/teams-for-linux/issues/1830)) が完成すれば不要になる。

## 仕組み

1. 複数の teams-for-linux インスタンスを `--partition` オプションで起動し、アカウントごとに分離
2. `teams-url-dispatcher` シェルスクリプトが URL を振り分け:
   - Teams URL (`teams.microsoft.com`, `teams.live.com`) → [Junction](https://apps.gnome.org/Junction/)（アプリ選択ダイアログ）を表示
   - その他の URL → Firefox に直接渡す
3. HTTP/HTTPS の `xdg.mimeApps.defaultApplications` にディスパッチャの `.desktop` を設定

Junction 自体に URL フィルタリング機能がないため、シェルスクリプトで補っている。

### Firefox 無限ループの回避

`x-scheme-handler/https` をディスパッチャに向けると、Firefox が `mimeapps.list` を参照して HTTPS をディスパッチャに委譲 → ディスパッチャが Firefox を開く → 無限ループになる。
`firefox.nix` で `network.protocol-handler.expose.{http,https} = true` を設定し、Firefox 自身に HTTP/HTTPS を内部処理させることで回避している。

**検証時の注意:** この設定は `user.js` 経由で適用されるため、rebuild 後に Firefox の再起動が必要。

## アカウント管理

`teamsAccounts` リストにアカウントを追加・削除する:

```nix
teamsAccounts = [
  { id = "uni"; label = "Teams (Uni)"; }
  # { id = "work"; label = "Teams (Work)"; }  # 追加例
];
```

各アカウントに対して `teams-{id}.desktop` が自動生成される。

## 関連

- MIME 設定の全体像: [default-apps.md](./default-apps.md)
