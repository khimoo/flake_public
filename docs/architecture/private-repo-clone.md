# private repo の clone の設計

使い方: [SSH 鍵の配布と private repo の clone](../howtouse/private-repo-clone.md)
実装: [secrets.nix](../../modules/home-manager/secrets.nix)（秘密の書き出し）、[private-repos.nix](../../modules/home-manager/private-repos.nix)（`clone-repos` と `pull-repos`）

## 復号の種はユーザーが読める age 鍵にし、home-manager で書き出す

ホスト鍵（`/etc/ssh/ssh_host_ed25519_key`）で無人復号する NixOS の systemd サービスは退けた。
ホスト鍵は root しか読めず、home-manager から扱えないので、NixOS 専用になって macOS で使えない。
ユーザーが読める age 鍵なら root が要らず、`home.activation` で書き出せば `home-manager switch` でも `nixos-rebuild switch` でも、Darwin でも同じ経路で動く。

## age 鍵は全環境で 1 本にする

同じ age 鍵が、全環境の復号の種と、暗号文を編集する鍵を兼ねる。
マシンを足すたびに受信者を足して `sops updatekeys` で暗号化し直す作業がなくなり、Bitwarden の 1 本からどの環境も同じ手順で用意できる。

代償として、1 台から鍵が漏れると全部の暗号文を復号できる。
個人の 2〜3 台では、Bitwarden での保管と漏れたときの作り直しで足りると判断した。

## 鍵は用途で名付ける

`git_ssh_key` は `~/.ssh/id_github` に、`lan_ssh_key` は `~/.ssh/id_lan` に書き出す。
`id_ed25519` のようなアルゴリズム名にすると、1 本に複数の用途が載っても気づけず、片方を作り直すともう片方も巻き込む（[machine-ssh.md](./machine-ssh.md)）。

## 復号と clone を別のモジュールに分ける

`secrets.yaml` が配るのは GitHub の鍵だけではなく、LAN の鍵や API キーもある。
clone のモジュールは sops も age 鍵も知らず、`~/.ssh/id_github` があるかを実行時に確かめるだけにした。

復号は `secrets.nix` に一つだけ置き、入口を二つ持つ。
`sshKeys` は `~/.ssh` に `600` で置く鍵のための短い入口で、`secrets` は書き出し先と mode を明示する一般の入口。
`secrets.nix` の中で前者を後者に変換するので、復号の手順は二重にならない。

## switch は秘密を宣言どおりに揃える

宣言した秘密は switch のたびに復号し、通常のファイルを暗号文の内容と mode に揃える。手で書き換えたファイルも戻す。
宣言から外したファイルは、switch が置いたと記録したものだけを消す。

既存のファイルに触らない案と、内容のハッシュで手での編集を守る別の更新コマンドを置く案は、どちらも退けた。
手で差し替えた鍵をそのまま使う運用はなく、鍵は `secrets.yaml` を直して変えるため。

復号の結果は宛先と同じディレクトリの一時ファイルに書き、内容が違うときだけ `mv -f` で置き換える。
宛先へ直接リダイレクトすると、復号に失敗したときに空の秘密が残る。

## age 鍵がなければ switch を失敗させる

新しいマシンで age 鍵を置き損ねたまま switch したとき、警告だけ出して続ける作りでは `nixos-rebuild switch` が成功と表示し、鍵がないことに気づけなかった。
警告は `home-manager-<user>.service` の journal に出るだけで、端末には出ない。

そのため、秘密の宣言があるのに復号できなければ activation を `exit 1` で止める。
`lanSsh` のユーザー（desktop と spin713 の pomu）は常に `id_lan` を宣言しているので、age 鍵を失うと switch が通らなくなる。
age 鍵を置く作業に switch は要らないので、回復できなくなることはない。

## clone は switch の後のコマンドにする

clone を activation で行う案は退けた。

- switch にネットワークからの取得が混ざると、環境の適用が GitHub への到達や認証の状態に左右される
- 鍵の書き出しとの順序を DAG の依存名で表すことになる。Home Manager は存在しない依存名をエラーにしないので、名前を間違えると順序の保証が黙って消える。実際に、存在しないノード名を指していた。activation の依存名が実在するノードを指していることは、`tests/default.nix` で確かめている
- clone が要るのは新しい環境を用意する一度だけ

`clone-repos` は `dest` がないときだけ clone し、既存の checkout には触らない。
clone は一時領域で終えてから `dest` に移すので、途中で失敗しても `dest` を作りかけのまま残さない。
Git の checkout かどうかは `.git` があるかで判断し、remote の URL までは比べない。

## 更新は `pull-repos` にし、switch に混ぜない

switch が pull もすると、システムの世代を切り替えるつもりの操作で working tree も動き、更新のタイミングをユーザーが選べなくなる。
`git pull --ff-only` なので、分岐した repo で merge commit を勝手に作らない。
同じ GitHub の鍵で更新できるので、flake 自身も対象に入れた。

## vault は clone で用意する

外部 flake の `services.zettelkasten.initializeVault` も、switch の中でフォルダを作って `git init` する。
両方を有効にすると、先にできた空のフォルダに `git clone` できずに失敗する。
ノートはすでに GitHub にあるので、clone 側に一本化した。

同じ理由で、vault の中にマウントする papis の subvol（[disk-tiering.md](./disk-tiering.md)）も、clone より先にマウント先を作らない。

## 制約

- 新しい環境の評価に SSH 鍵は要らない。`inputs.zettelkasten` を `github:`（https）で取得しているため。`git+ssh://` に戻すと、age 鍵だけでは用意できなくなる
- `lanSsh` のユーザーがいると `secrets/secrets.yaml` を評価で参照する。この repo を fork したら、自分の暗号文をコミットするまで評価が通らない
- 暗号文は `"${secretsFile}"` で単独で store にコピーし、世代の closure に入れる。flake のソースは closure に入らない（2026-10-03、desktop の 26.05 の toplevel で確認）。ソースの中のパスを参照すると、GC でソースが消えた後の起動時の activation で復号に失敗する
- `secrets.yaml` に同居させている Gemini の API キーは、課金を紐づけていない無料枠のキーで、漏れたときの被害は無料枠の消費に留まる。SSH 秘密鍵と同じ扱いでよいのはそのため

## 見直す条件

- マシンの台数や共有する人が増えたら、age 鍵をマシンごとの受信者に分ける
- 漏れたときの被害が大きい秘密を足すなら、受信者を分けることを考える
- age 鍵を新しいマシンに置く経路（SSH で送る、Bitwarden から取り出す）は、[new-machine.md](./new-machine.md) の nixos-anywhere での用意に一本化する予定
