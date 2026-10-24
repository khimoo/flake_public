# TODO: nixos-anywhere で新しいマシンを用意する

**未実装の計画。** 実装したら使い方を `docs/howtouse/new-machine.md` に分け、この文書には判断だけを残す。
マシンを足す今の手順は [machine-ssh.md](../howtouse/machine-ssh.md#マシンの追加手順) と [private-repo-clone.md](../howtouse/private-repo-clone.md) にある。

## 解決したいこと

新しいマシンを用意するとき、age 鍵を運ぶ経路が「既存のマシンから SSH で送る」と「Bitwarden から取り出す」の 2 つあり、どちらも手作業で、手順書に並んでいるだけで強制されない。
age 鍵を置き損ねたまま switch すると、以前は警告だけ出して成功し、`agents-private` や `memex-nix` が週単位で clone されないまま残った。
この部分は、age 鍵がなければ activation を止める変更（[private-repo-clone.md](./private-repo-clone.md#age-鍵がなければ-switch-を失敗させる)）ですでに直した。残っているのは、鍵を運ぶ手作業と経路の二重化である。

目指す状態:

1. 鍵を運ぶのは、インストールの手順の中の明示的な 1 ステップにする
2. その後の `nixos-rebuild switch` は、環境変数、別のマシンとの通信、手での SSH のコピーを要らない
3. 鍵を運ぶ経路は 1 つに決める
4. 2 台目以降は、既存のマシンから 1 コマンドで用意でき、新しいマシンの側で対話が要らない

## 目指す手順

2 台目以降は、新しいマシンをインストーラーの ISO で起動して SSH を待ち受けさせ、既存のマシンから次を実行する。

```sh
sagyo-install pomu@<new-ip> nixos-<newhost>
```

`sagyo-install` は nixos-anywhere の薄いラッパー（flake の `apps`）で、`nixos-anywhere --flake .#nixos-<newhost>` を実行し、disko でディスクを切り、既存のマシンの `~/.config/sops/age/keys.txt` を `--extra-files` で新しいマシンの同じ場所に置く。再起動後の最初の activation が SSH 鍵を復号し、`clone-repos` で private repo を clone する。
nixos-anywhere は kexec でインストーラーに切り替えるので、汎用の Linux の LiveCD からでもよい。

最初の 1 台（と全マシンを失ったとき）は、既存のマシンがないので nixos-anywhere を使えない。標準のインストーラーで入れたあと、Bitwarden（`nix run nixpkgs#bitwarden-cli -- get item nixos-age-key`）か USB などの物理的な控えから age 鍵を置く。どちらも明示的に選ぶ経路として認める。Bitwarden CLI は全マシンに常に入れず、`nix run` で一時的に使う。

## 決めたこと

- 基盤は nixos-anywhere にする
- disko は新しいマシンから使い、既存のマシンの `hardware.nix` の `fileSystems` は移さない。パーティションの操作が絡み危険なため。しばらく disko と `fileSystems` のホストが混在するが、どちらも宣言的なモジュールなので両立する
- `sagyo-install` は、IP とホスト名を受け取って全部を行う粗い単位にする

## 残る課題

- `sagyo-install` は冪等ではない。nixos-anywhere は対象のディスクを消して書き直すので、2 回目を実行するとディスクが消える。名前に `install` を入れて初回専用であることを示し、対象ですでに NixOS が動いていれば止める仕組みを入れる（nixos-anywhere にその機能があるかは調べていない）
- 最初の 1 台の鍵の受け渡し、Bitwarden のマスターパスワードや 2 要素認証の機器を失うこと、ハードウェアの故障は自動化できない。Bitwarden も使えないときのため、物理的な控えを分けて置くかは個人の判断
- age 鍵がないと既存のマシンでも switch が止まる。`sagyo-install` を作ったら、activation のエラーの文言にもその経路を足す

## 進める順序

1. VM に nixos-spin713 の設定を nixos-anywhere で入れ、`--extra-files` で任意のファイルを置けることを確かめる。挙動を知らずにラッパーを設計しない
2. `sagyo-install` を flake の `apps` に足し、VM で age 鍵まで入ることを確かめる
3. `docs/howtouse/new-machine.md` に、最初の 1 台と 2 台目以降の手順を書き、`private-repo-clone.md` の鍵を運ぶ 2 つの経路をそこへの案内に置き換える
4. 新しいマシンが要るときに `hosts/<newhost>/disko.nix` を書き、`sagyo-install` で通す

参考: [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)、[disko](https://github.com/nix-community/disko)
