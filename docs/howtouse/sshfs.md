# sshfs でデスクトップのファイルを編集する

外出先のラップトップ（`nixos-spin713`）から、デスクトップ（`nixos-desktop`）のファイルを sshfs でマウントして編集します。
デスクトップで動いているエージェントと同じファイルを、手元のエディタとツールで扱えます。

設定: [sshfs_editing.star](../../config/elements/sshfs_editing.star) と [direnv_on_sshfs.star](../../config/elements/direnv_on_sshfs.star)。目的 `sshfs_editing` を選んだホスト（[nixos-spin713.star](../../config/hosts/nixos-spin713.star)）で入る（[confgen.md](./confgen.md)）。

## マウントする

デスクトップが起動していて、両ホストが tailnet に参加していれば使えます（[tailscale.md](./tailscale.md) 参照）。
マウント先は任意です。どこにマウントしても、次節の対策は同じように適用されます。

```sh
mkdir -p ~/mnt/desktop
sshfs desktop-ts:/home/pomu/sagyo ~/mnt/desktop
fusermount3 -u ~/mnt/desktop   # 解除する
```

## sshfs 上で自動的に変わること

sshfs 上では、ファイルを読み書きするたびにデスクトップとの通信が発生します。
そのため、頻繁に書き込まれる生成物とキャッシュは、sshfs 上にあるときだけ手元に置きます。

| 対象 | sshfs 上での置き場所 | 詳細 |
|------|----------------------|------|
| Typst の PDF（tinymist） | `$XDG_RUNTIME_DIR/typst-out/` の下 | [lang-typst.md](./neovim/lang-typst.md) |
| direnv のキャッシュ | `~/.cache/direnv/layouts/<パスのハッシュ><パス>` | この文書の「設計」 |

direnv のキャッシュを作り直したいときは、該当するディレクトリを `~/.cache/direnv/layouts/` から削除します。

## 設計

findmnt のパスは `util_linux` の要素が公開し、tinymist の PDF 対策（`sshfs_editing` から Neovim への書き込み）と direnv の対策（派生要素 `direnv_on_sshfs`）がそれを読みます。direnv の対策は、`sshfs_editing` と `direnv` の両方が入るホストでだけ入ります。
判定を FUSE 全体に広げないのは、FUSE であること自体は遅さや下記の問題と関係しないためです。

direnv のキャッシュを手元に置くのは、sshfs ではキャッシュが毎回作り直されるためです。
`.direnv` の中身は各 PC の `/nix/store` を指すリンクで、sshfs では 2 台が同じ `.direnv` を使います。`nixos-spin713` から sshfs 越しに入ると、nix-direnv が profile を存在しないと判定し、入るたびにキャッシュを作り直していました。片方の PC が作ったリンクの先が、もう片方の `/nix/store` に無いためと見ています。
