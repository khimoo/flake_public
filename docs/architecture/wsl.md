# 会社 PC の NixOS-WSL の設計

使い方: [会社 PC の NixOS-WSL](../howtouse/wsl.md)
実装: [hosts/nixos-work-wsl/](../../hosts/nixos-work-wsl/default.nix)、[restricted-host.nix](../../modules/nixos/restricted-host.nix)、[base.nix](../../modules/nixos/base.nix)

会社の Windows PC の NixOS-WSL を、`sudo nixos-rebuild switch --flake .#nixos-work-wsl` 一回で Home Manager まで揃うホストにする。
このホストは会社 PC の中で完結させ、個人の秘密と自宅のマシンへの接続経路を持たせない。

## 自宅への接続経路と秘密を持たせない

`ssh.nix`、`tailscale.nix`、`remote-builders.nix` を入れず、`lanSsh` も有効にしない。会社 PC から `ssh desktop-ts` のように自宅のマシンへつながる経路を作らない。
自宅のデスクトップでビルドできないので、ビルドは WSL の中で完結させる。

age 鍵は置かない。この flake の age 鍵は 1 本で、同じ鍵から GitHub の `git_ssh_key` と自宅へログインする `lan_ssh_key` も復号できる（[.sops.yaml](../../.sops.yaml)）。そのため Gemini の API キーもない。

Git の identity はこのリポジトリに書かない。会社の GitHub アカウントを公開リポジトリに書くと、`khimoo` と勤務先の結び付きが公開される。
Git は Home Manager の `~/.config/git/config` と `~/.gitconfig` の両方を読むので、会社の identity は `~/.gitconfig` に手で書けばよい。
ただし `~/.gitconfig` がないと `git config --global` は読み取り専用の `~/.config/git/config` に書こうとして失敗する（Git 2.51.2 の `git-config(1)` の `--global`）。

`khimoo` の push 権限を持つ認証情報も置かない。WSL の仮想ディスクは Windows のファイルで、会社の管理ツールや管理者から読める。flake_public は HTTPS で clone して pull だけをし、変更はすべて自宅で行う。

## 制限をオプションと assertion で表す

制限は `local.restrictedHost.enable` で表し、`nixos-work-wsl` だけが有効にする。有効にすると、次のどれかを含む構成は理由を示す assertion で評価が止まる。

- 外からの SSH（`services.openssh`）、tailnet（`services.tailscale`）、リモートビルド（`nix.buildMachines`、`nix.distributedBuilds`）
- Home Manager のユーザーの秘密の復号（`local.profile.secrets`、`sshKeys`）、`lanSsh`、private repo の clone（`privateRepos`）
- Home Manager のユーザーの Git の identity（`gitUsername`、`gitUserEmail`）

`ssh.nix` などを import しないだけでは、制限していることが設定から読み取れず、後からうっかり足しても評価が通る。
`tests/default.nix` は、実際の `nixos-work-wsl` がこのオプションを有効にしていることと、制限を破る架空のホストで assertion が止まることを確かめる。

ホスト名は既存の `nixos-desktop`、`nixos-spin713` に合わせて `nixos-` で始め、`work` で会社の機械であることを示す。`pomu-wsl` や `nixos-wsl` では個人の WSL と区別がつかない。

## 自分用のエージェント設定を置かない

会社に Claude や Codex の公認のアカウントはない（2026-10-14 時点）。個人のアカウントを業務で使うと、会社のコードが契約のない外部のサービスへ送られ、個人のプランでは設定によって学習にも使われる。
認証情報は会社から読めるディスクに残り、会話の履歴を通じて業務の内容が個人のアカウントに溜まる。
使わないのに agents-private を置くと、その中身が会社から読めるリスクだけが残るので置かない。

`claude` と `codex` のコマンドは、ほかのホストと共有する Home Manager のモジュールで入る。コマンドがあるだけでは何も送られないので、共有のモジュールに分岐を足してまで外さない。どのアカウントでログインするかは assertion で強制できないので、使い方の文書に書いて運用で守る。

### 社用のアカウントがある会社で agents-private を戻すとき

以前は agents-private を読み取り専用の deploy key で入れていた（4c54a17 と 1d685c5）。戻すときは次の判断を引き継ぐ。

- deploy key は GitHub に repo ごとに登録する鍵で、`khimoo` の権限と切り離せる。代わりに agents-private の中身（指示、設定、`decisions/` の履歴）は会社から読める
- `agentConfigRoot` だけを指定し、`agentConfigRepo` は `null` にして手で clone する。`agentConfigRepo` を指定すると `profile.nix` が `sshKeys` に `id_github` を足し、age 鍵のないこのホストでは activation が止まる
- deploy key は `github.com` ではなく、別名のホスト `github-agents-private`（`HostName github.com`、`IdentitiesOnly yes`）に結び付け、clone の URL を `git@github-agents-private:khimoo/agents-private.git` にする。GitHub は最初に認証が通った鍵でアカウントを決めるので、`github.com` 全体に deploy key を使うと、会社のリポジトリへの接続まで deploy key で認証されて失敗する
- この別名は `/etc/ssh/ssh_config`（NixOS の `programs.ssh.extraConfig`）に書く。Home Manager の `programs.ssh` を使うと `~/.ssh/config` が読み取り専用になり、会社の設定を書けなくなる
- 会社の鍵を `~/.ssh/config` の `Host *` に書くと分離が崩れる。OpenSSH は `~/.ssh/config` を先に読み、一致したブロックの `IdentityFile` をすべて候補に足すので（OpenSSH 10.3p1 の `ssh_config(5)`）、`github-agents-private` への接続でも会社の鍵が先に試される。会社の鍵は `Host github.com` に限って書く。ブロックの一致は `HostName` で置き換える前の名前で判断されるので、`github-agents-private` は `Host github.com` に一致しない。これはリポジトリから強制できないので、戻すときは `ssh -G github-agents-private` で使われる鍵を確かめる手順を使い方の文書に書く

## 既定のユーザー `nixos` を使う

Home Manager のモジュールは、パスを `home.homeDirectory` から組み立てる。`/home/pomu` を直接書いているのは desktop と spin713 のホスト設定だけ。
ユーザー名を `pomu` に変えても、ほかのマシンと絶対パスが揃うだけで、作った後の NixOS-WSL でユーザー名を変えるには `nixos-rebuild boot` と WSL の再起動が要る。

## 共通の設定を `base.nix` に分ける

`base.nix` には、どのホストにも要る最小限（locale、users、GUI を除く nix-settings、codex、agent-instructions、`networking.hostName`、`system.stateVersion`）を置く。
`common.nix` は `base.nix` を import したうえで、boot、NetworkManager、GNOME、printing、ssh、tailscale、remote-builders、Bluetooth など、WSL では要らないか WSL 自身の仕組みとぶつかるものを持つ。
WSL のホスト設定は、NixOS-WSL のモジュールと `base.nix` だけを import する。

退けた案と理由:

- 各モジュールを WSL から個別に import する: `common.nix` に基礎的な設定が足されたとき、WSL だけ取り残される
- `common.nix` の中で `local.wsl.enable` のようなフラグで分岐する: WSL 固有の分岐が多くのモジュールに散り、ホストの種類が増えるたびに分岐が増える

`users.nix` は WSL にない `networkmanager` や `libvirtd` のグループをユーザーに付けるが、変えていない。NixOS はグループの側からメンバーを数えるので（`elem config.name u.extraGroups`、nixos-25.11 の `users-groups.nix`）、定義されていないグループは無視される。

NixOS-WSL は既定で `wheel` のユーザーにパスワードなしの `sudo` を許す（release-26.05 の b98199a、`modules/wsl-distro.nix` の `security.sudo.wheelNeedsPassword = mkDefault false`）。変えない。Windows から `wsl -u root` でパスワードなしに root になれるので、WSL の中だけパスワードを求めても意味がない。

## Home Manager の個人設定を読まない

`nixos` ユーザーは `pomu.nix` も `pomu-agents.nix` も読まない。`khimoo` の Git の identity、Gemini の秘密、`antigravity-cli`、agents-private の設定は入らない。
home は [hosts/nixos-work-wsl/home.nix](../../hosts/nixos-work-wsl/home.nix) で、機能は `gui` だけを有効にする。
`flakeRoot` は既定の `~/sagyo/flake_public` のまま。Neovim の設定がこのパスへの symlink なので、WSL でも同じ場所に clone する。

## GUI アプリを WSLg で表示する

会社 PC でも自宅と同じ kitty のキー体系と、Neovim との smart-splits の連携で作業するため、`features.gui` を有効にする。
kitty は Windows 向けの配布物がないので WSL の中で動かし、WSLg で表示する。`wsl.startMenuLaunchers` で `.desktop` ファイルを Windows のスタートメニューに並べる。

2026-10-14 に会社 PC で確かめたこと:

- WSLg が使え、`WAYLAND_DISPLAY=wayland-0` と `DISPLAY=:0` が設定されている
- NixOS-WSL が `hardware.graphics.enable` を有効にしているので、mesa のソフトウェア描画で kitty が表示され、Windows とのコピーと貼り付けは双方向に動く
- Windows の IME では kitty に日本語を入力できない

日本語は kitty に IME を入れず、Neovim の skkeleton で入力する。
WSL に fcitx5-skk を入れる案は退けた。WSLg の Wayland では IME のプロトコルを設定できないので、kitty を X11 で動かして IBus 互換の経路で fcitx5 につなぐことになり、それが会社 PC で動くかを試しながら進めることになる。

kitty と端末のフォントだけを入れる機能を新しく作る案も退け、既存の `gui` を使った。
代償として OBS、Chrome、IntelliJ、LibreOffice、Zoom なども入り、ダウンロードと WSL のディスクが数 GB 単位で増える。どれも binary cache から取るので、会社 PC でのビルドは起きない。
Slack などの自動起動は `graphical-session.target` に結び付いていて、WSL ではこの target に到達しないので起動しない。
kitty の remote control はローカルのソケット（`unix:${XDG_RUNTIME_DIR}/kitty.sock`）だけを使うので、`local.restrictedHost` の制限は変えない。
描画は mesa のソフトウェア描画のままにし、遅いと感じたら `wsl.useWindowsDriver` で Windows の GPU ドライバーを使う。

## 見直す条件

- 会社 PC ではなく個人の PC で使うことになったら、制限を外し、age 鍵、秘密、tailnet を入れ直す
- 社用の Claude や Codex のアカウントがある会社に移ったら、上の手順で agents-private を戻す。その前に、自分用のプラグインやフック（コミット前に Gemini で校正するフックなど）を会社の作業で使ってよいかを、その会社の規程で確かめる
- NixOS のリリースを上げるときは、`nixos-wsl` の input も対応する `release-YY.MM` に上げる
- Neovim の外でも日本語を打つ必要が出たら、kitty を X11 で動かして fcitx5-skk をつなぐ案を会社 PC で試す
