# 定期実行の失敗の通知

実装: [failure-notify.nix](../../modules/home-manager/failure-notify.nix)

Home Manager で定義したユーザーの定期実行が失敗すると、GNOME に通知が出る。
通知のタイトルは「`<ユニット名>` が失敗しました」で、本文に原因を確かめるコマンドが出る。

```bash
journalctl --user -u xsaved-process.service
```

通知は緊急度 critical で出すので、閉じるまで画面に残り、通知の一覧にも残る。
同じユニットが失敗を繰り返したときは、通知を増やさず、前の通知を置き換える。

## 対象

Home Manager で定義したユーザーの timer のサービスすべてが対象になる。
`tests/default.nix` の nixos-desktop の確認が、timer を持つサービスに通知が付いていることを確かめる。

timer を足すときは、そのサービスの `Unit.OnFailure` に `config.local.failureNotify.onFailure` を入れる。

```nix
systemd.user.services.example = {
  Unit = {
    Description = "...";
    OnFailure = config.local.failureNotify.onFailure;
  };
  # ...
};
```

外部の flake が定義するサービス（Zettelkasten の同期）には、取り込む側のモジュール（[zettelkasten.nix](../../modules/home-manager/zettelkasten.nix)）で足す。

## 確かめる

switch したあと、通知用のユニットを手で起動すると、テストの通知が出る。

```bash
systemctl --user start notify-failure@test.service
```

通知が出ないときは、通知用のユニットのログを見る。

```bash
journalctl --user -u 'notify-failure@*'
```

## 設計

systemd の `OnFailure=` で、失敗したユニットの名前をインスタンス名にして `notify-failure@<ユニット名>.service` を起動し、`notify-send` で通知する。
systemd だけで完結し、各ユニットに足すのは `OnFailure` の 1 行で済む。

同じユニットの通知を置き換えるため、`notify-send --print-id` が返す通知の ID を `$XDG_RUNTIME_DIR/notify-failure/<ユニット名>` に保存し、次の通知で `--replace-id` に渡す。
置き換えないと、Zettelkasten の同期のように 15 分ごとに動くユニットは、原因が残っている間、15 分ごとに critical の通知を積み重ねる。

代償として、誰もログインしていないとき（linger で動いている間）に失敗した分は、通知を受け取る GNOME のセッションがないので通知されない。
失敗したユニットは次に成功するまで `systemctl --user --failed` に残るので、ログイン後にそこで確かめられる。

退けた案:

- `~/.config/systemd/user/service.d/` のドロップインで、すべてのユーザーのサービスに `OnFailure=` を付ける。GNOME やアプリのサービスの失敗まで通知され、通知用のユニット自身を除外する設定も要るので退けた。
- メールで通知する。送信の設定と認証情報の管理が増える。普段は GNOME にログインしたままなので、デスクトップの通知で足りると判断した。
