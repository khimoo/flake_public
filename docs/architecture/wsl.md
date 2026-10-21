# 会社PCのNixOS-WSLを、秘密情報と外部への接続経路を持たないホストとして追加する

設定ファイル: [hosts/nixos-work-wsl/default.nix](../../hosts/nixos-work-wsl/default.nix)、[hosts/nixos-work-wsl/home.nix](../../hosts/nixos-work-wsl/home.nix)、[modules/nixos/restricted-host.nix](../../modules/nixos/restricted-host.nix)、[modules/nixos/base.nix](../../modules/nixos/base.nix)、[profiles/home/pomu-agents.nix](../../profiles/home/pomu-agents.nix)

導入と更新の手順は [docs/howtouse/wsl.md](../howtouse/wsl.md) を参照してください。本ファイルには判断の根拠を記録します。

会社のWindows PCに導入したNixOS-WSLを `nixosConfigurations.nixos-work-wsl` として定義し、`sudo nixos-rebuild switch --flake .#nixos-work-wsl` を一度実行するだけで、Home Manager環境まで一括で構築できるようにします。
このホストは会社PC内で完結する環境とし、個人の秘密情報や自宅マシンへのアクセス経路は一切持たせないようにします。
当初は CLI だけのホストにしていましたが、kitty を使うために GUI アプリを WSLg で表示するよう改めました（「7. GUI アプリを WSLg で表示する」）。

## 導入前の課題

導入前の WSL 環境は、スタンドアロンの Home Manager 設定 `homeConfigurations.pomu-wsl` としてしか定義されていませんでした。
[hosts/machines.nix](../../hosts/machines.nix) の `machines.nixos-work-wsl.nixos` から NixOS 構成を生成する。会社 PC の項目には `sshUser` と `builder` を指定せず、マシン間 SSH とリモートビルドには参加させない。

2026年9月30日時点で確認した NixOS-WSL 2605.7.2 イメージの状態は以下の通りです。

- NixOS 26.05 および NixOS-WSL の `release-26.05` ブランチで構成されています。調査した時点の当リポジトリは `nixos-25.11` に固定しており、そのまま `switch` するとダウングレードになるため、先にリポジトリ全体を 26.05 に上げました。
- デフォルトユーザーは `nixos` です。イメージが自動生成する `configuration.nix` は `system.stateVersion = "26.05"` に設定されており、Flakesは有効化されていません。

既存のホスト用コンポーネントは、そのままではWSL環境に流用できません。
[common.nix](../../modules/nixos/common.nix) では systemd-boot、NetworkManager、GNOME、PipeWire、libvirt、Bluetooth を一括で導入しますが、これらはWSL環境では不要か、WSL自体が管理する仕組みと衝突します。
分割前の [nix-settings.nix](../../modules/nixos/nix-settings.nix) には、GUIアプリの gparted や gsconnect、Android端末をUSB経由で操作する adb など、WSLでは使わない設定も混在していました。
Home Manager側の [pomu.nix](../../profiles/home/pomu.nix) には、個人アカウント（`khimoo`）のGit ID情報や、Gemini APIキーのシークレットが含まれています。シークレットを復号するための [secrets.nix](../../modules/home-manager/secrets.nix) は、ローカルにage暗号鍵が存在しない場合、アクティベーションを `exit 1` で異常終了させてしまいます。

## 設計上の意思決定

### 1. 会社PCから外部（自宅環境など）への接続経路を持たせない

[ssh.nix](../../modules/nixos/ssh.nix)、[tailscale.nix](../../modules/nixos/tailscale.nix)、[remote-builders.nix](../../modules/nixos/remote-builders.nix) は導入せず、`lanSsh` も有効化しません。会社のセキュリティ規定に配慮し、会社PCから `ssh desktop-ts` のように自宅マシンへ直接接続できる経路は作成しません。
自宅のデスクトップPCへビルド処理を逃がす（リモートビルドする）ことができないため、ビルドはWSL環境単体で完結させます。

age暗号鍵（`~/.config/sops/age/keys.txt`）は配置しません。
本リポジトリ用のage鍵は1本のみで、同じ鍵から `gemini_api_key` だけでなく、GitHub用の `git_ssh_key` や自宅PCへのログイン用となる `lan_ssh_key` も復号できる構成になっています（[.sops.yaml](../../.sops.yaml)）。会社PCにこの鍵を置くと、自宅マシンへ侵入可能な秘密鍵を容易に取り出せてしまうため、配置を避けます。
その結果、WSL上にはGeminiのAPIキーも存在しません。

GitのID情報（名前やメールアドレス）は、本リポジトリのどのファイルにも記載しません。会社用のGitHubアカウント情報をパブリックリポジトリにハードコードすると、個人アカウント `khimoo` と現在の勤務先との関連性が一般に公開されてしまうためです。
会社用のID情報は、WSL環境上の `~/.gitconfig` に手動で設定します。GitはHome Managerが配置する `~/.config/git/config` と、個別設定用の `~/.gitconfig` の両方を自動で読み込むため、リポジトリ側で特別な仕組みを用意する必要はありません。
ただし、`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Home Managerによって読み取り専用リンクとして生成された `~/.config/git/config` へ直接書き込もうとしてエラーになります（Git 2.51.2 の `git-config(1)` における `--global` の説明を参照）。そのため、初回設定時は `git config --file ~/.gitconfig` のようにファイルパスを明示して書き込みます。

`khimoo` アカウントの書き込み（push）権限を持つ認証情報も配置しません。WSLの仮想ディスクはWindows側のファイルとして保存されており、会社のシステム管理ツールや管理者権限からアクセス可能な状態にあるためです。
パブリックリポジトリ（`flake_public`）はHTTPS経由でクローンし、pull（閲覧・同期）専用とします。コードの変更作業はすべて自宅マシンで行い、WSL環境で見つかった不具合も帰宅後に自宅環境で修正・反映する運用とします。

### 2. 自分用のエージェント設定（agents-private）は配置しない

現在の会社には、会社公認の Claude や Codex のアカウントがありません（2026-10-14 時点）。個人アカウントを業務で使用した場合、次のような問題が生じます。

- 会社のコードや情報が、会社と契約のない外部サービスへ個人として送信されてしまう。個人向けプランには法人向けのようなデータ取り扱いに関する契約がなく、設定によっては会話内容がモデルの学習に利用される。
- ログインの認証情報（`~/.claude/.credentials.json`、`~/.codex/auth.json`）が、会社側から参照可能なディスク上に残ってしまう。
- 会話履歴や別端末からのセッション継続機能などを通じて、業務内容が個人アカウント側に蓄積されてしまう。

そのため、このホストでは Claude Code や Codex を使用せず、個人用の設定（agents-private）も配置しません。利用機会がないにもかかわらず、設定内容が会社から閲覧可能な状態になるリスクだけが残るためです。

なお、`claude` や `codex` コマンドは他ホストと共有している Home Manager モジュールによって導入されるため、このホストにもインストールされます。ただし、コマンドが存在するだけでは外部への送信は行われないため、共有モジュールにわざわざ条件分岐を追加してまで除外することはしていません。また、どのアカウントでログインするかは実行時の操作であり、`restrictedHost` の assertion では強制できないため、手順書（[docs/howtouse/wsl.md](../howtouse/wsl.md)）に記載して運用で対応します。

#### 社用アカウントのある会社で設定を戻す際の設計

当初は、agents-private を読み取り専用の deploy key で導入する設計にしていました（4c54a17 と 1d685c5 で実装しており、ホスト設定、テスト、手順書に該当箇所があります）。社用アカウントがある環境で元の構成に戻す際は、以下の判断を引き継ぎます。

デプロイキーはGitHub上でリポジトリごとに個別に登録するSSH公開鍵であり、`khimoo` アカウント本来の権限と切り離して管理できます。読み取り専用として登録することで、`agents-private` のクローンとプルのみを許可します。
その代わり、`agents-private` に含まれる指示書、設定、`decisions/` の履歴などのコンテンツは、会社の管理者や管理ツールが会社PCのディスクを通じて閲覧可能な状態になります。なお、WSL側から `agents-private` への直接プッシュはできません。

WSL用のHome Manager設定では `agentConfigRoot` のみを指定し、`agentConfigRepo` は `null` に設定して手動でクローンを行う構成にします。
もし `agentConfigRepo` を明示的に指定すると `privateRepos` が空ではなくなり、[profile.nix](../../modules/home-manager/profile.nix) が `sshKeys` に `id_github`（`git_ssh_key` を復号して配置する鍵）を自動で追加してしまいます。WSL環境にはage暗号鍵が存在しないため、アクティベーションの途中でエラー停止してしまいます。

デプロイキーは `github.com` に直接紐付けるのではなく、SSHのエイリアスホストとして `github-agents-private`（`HostName github.com`、`IdentitiesOnly yes`）を定義し、`agents-private` のクローン用URLには `git@github-agents-private:khimoo/agents-private.git` を使用します。
SSH接続は提示された鍵を順に試行し、最初に認証が成功した鍵に基づいてGitHub上のアカウントを判定します。仮にデプロイキーを `github.com` 全体に対して有効にしてしまうと、会社用のプライベートリポジトリへ接続する際にもデプロイキーで認証されてしまいます。デプロイキーには会社用リポジトリのアクセス権がないため、結果として会社用コードのクローンやプッシュが失敗します。
このエイリアス設定は、NixOS側の `programs.ssh.extraConfig`（`/etc/ssh/ssh_config`）に記述します。Home Managerの `programs.ssh` を使用すると `~/.ssh/config` が読み取り専用のシンボリックリンクになり、会社用のGitHub設定を手動で追記できなくなるためです。

エイリアスを導入しても、会社用の鍵の設定方法によってはこの分離が機能しなくなる点に注意が必要です。
OpenSSHは、システム全体の `/etc/ssh/ssh_config` よりも先にユーザー固有の `~/.ssh/config` を読み込み、マッチした定義ブロック内の `IdentityFile` をすべて認証候補に追加します（OpenSSH 10.3p1 の `ssh_config(5)` の仕様）。もし会社用の鍵を `~/.ssh/config` の `Host *` ブロックに記述してしまうと、`github-agents-private` への接続時にも会社用の鍵が優先して試行され、会社アカウントとして認証されてしまい、`agents-private` のクローンに失敗します。
そのため、会社用の鍵は `Host github.com` ブロックに限定して記述する必要があります。ホスト名のマッチングには `HostName` で置き換えられる前の（コマンドやURLに指定された）エイリアス名が使われるため、`github-agents-private` は `Host github.com` ブロックには一致しません。
この設定ルールはリポジトリ側から強制できないため、利用ガイド（howtouse）に明記し、`ssh -G github-agents-private` を実行して実際に使用される鍵を確認する検証手順を案内します。

### 3. 会社PC向けであることと、制限していることを名前と設定で示す

ホスト名は `nixos-work-wsl` にします。既存の `nixos-desktop`、`nixos-spin713` に合わせて `nixos-` で始め、`work` で会社の機械であることを示します。`pomu-wsl` や `nixos-wsl` のような名前では、個人用の WSL と区別がつきません。
flake の input の `nixos-wsl` は、上流の NixOS-WSL プロジェクトの名前なので、そのまま使います。

制限は [restricted-host.nix](../../modules/nixos/restricted-host.nix) のオプション `local.restrictedHost.enable` で表し、`nixos-work-wsl` だけが有効にします。オプションの宣言は `base.nix` から読み込むので、どのホストでも使えますが、既定は無効です。
有効にすると、次のどれかが入った構成は、理由を示す assertion で評価が止まります。

- 外からの SSH 接続（`services.openssh`）、tailnet への参加（`services.tailscale`）、リモートビルド（`nix.buildMachines`、`nix.distributedBuilds`）
- Home Manager のユーザーの secret の復号（`local.profile.secrets`、`local.profile.sshKeys`）、LAN の共通鍵（`lanSsh`）、private repo の clone（`privateRepos` と `clone-repos`）
- Home Manager のユーザーの git の identity（`gitUsername`、`gitUserEmail`）

`ssh.nix` などを import しないだけでは、設定を読んでも制限していることが分からず、後からうっかり足しても評価が通ってしまいます。オプションにすると、`local.restrictedHost.enable = true` の一行で制限していることが読み取れ、破る構成は評価の時点で止まります。
代償として、モジュールが一つ増え、テストで確かめていた条件の一部が assertion と重なります。テストは、`nixos-work-wsl` がこのオプションを有効にしていることと、制限を破る構成を assertion が実際に止めることを確かめる形にします。

### 4. デフォルトユーザー名 `nixos` をそのまま使用する

Home Managerのモジュール群は、すべてのパスを `home.homeDirectory` を基準に動的に組み立てています。`/home/pomu` という絶対パスを直接指定しているのは `desktop` と `spin713` のホスト設定のみであり、WSL用のホスト設定はこれらとは独立して記述します。
ユーザー名をあえて `pomu` に変更する利点は他マシンと絶対パスが揃う点のみですが、その一方で、構築済みのNixOS-WSL環境でユーザー名を変更するには `nixos-rebuild boot` の実行後にWSLインスタンスを再起動するなど煩雑な手順が必要になります。そのため、デフォルトの `nixos` のままで運用します。

### 5. 共通設定を `base.nix` に分離する

[base.nix](../../modules/nixos/base.nix) には、どのホストでも共通して必要となる最小限の設定を集約しています。
このファイルで [locale.nix](../../modules/nixos/locale.nix)、[users.nix](../../modules/nixos/users.nix)、nix-settings.nix（GUI関連を除く）、[codex.nix](../../modules/nixos/codex.nix)、[agent-instructions.nix](../../modules/nixos/agent-instructions.nix)、[claude-managed-settings.nix](../../modules/nixos/claude-managed-settings.nix) をインポートし、`networking.hostName` や `system.stateVersion` もこの `base.nix` で設定します。
Codexのサブエージェント無効化設定（`codex.nix`）を `base.nix` に含めるのは、WSL環境にもCodexを導入するためです。

[common.nix](../../modules/nixos/common.nix) は `base.nix` をインポートした上で、デスクトップ環境（desktop）向けの残りの設定を保持します。具体的には、boot、networking（NetworkManagerやKDE Connect用のポート）、desktop、printing、ssh、tailscale、remote-builders、Bluetooth、vm、music、audio（エコーキャンセル）、sns-block、gnome-transparent-fullscreenがこれに該当します。
分割前に `nix-settings.nix` にあった gparted は [desktop.nix](../../modules/nixos/desktop.nix) に置いています。GSConnect は Home Manager の [gui/gnome.nix](../../modules/home-manager/gui/gnome.nix) が入れます。adb は、26.05 で USB の権限を systemd が扱うようになったので、Home Manager の [dev/apps.nix](../../modules/home-manager/dev/apps.nix) で `android-tools` を入れています。

[users.nix](../../modules/nixos/users.nix) は現状維持とします。
このモジュールでは、WSL環境には存在しない `networkmanager` や `libvirtd` などのグループをユーザーに付与していますが、NixOSの仕様上、グループ定義側から所属メンバーを評価するため（`elem config.name u.extraGroups`）、システムに定義されていないグループは自動的に無視されます（nixos-25.11 の `nixos/modules/config/users-groups.nix` の仕様）。そのため、不要なグループが指定されていてもエラーは発生しません。
`audio` グループはNixOSのデフォルトで定義されているため `nixos` ユーザーにも割り当てられます。WSL環境にオーディオ機能はありませんが、所属していても実害はありません。

WSL用のホスト設定（`hosts/nixos-work-wsl/default.nix`）は、NixOS-WSLモジュールと `base.nix` のみをインポートするシンプルな構成にします。`wsl.defaultUser` は `settings.primaryUser` から動的に取得します。
Flakeの `inputs` に `nixos-wsl`（`github:nix-community/NixOS-WSL/release-26.05`）を追加し、`nixpkgs` は `follows` を用いて全体のバージョンと統一します。
システム全体の構築には、既存の `mkSystem`（[configurations.nix](../../lib/configurations.nix)）を使用します。`mkSystem` は常に `musnix` のNixOSモジュールをインポートしますが、`musnix` の各機能はデフォルトで無効化されているため、WSL向けに個別の条件分岐を設ける必要はありません。

NixOS-WSLは、`wheel` グループに属する全ユーザーに対し、パスワードなしでの `sudo` 実行をデフォルトで許可しています（release-26.05、b98199a の `modules/wsl-distro.nix` における `security.sudo.wheelNeedsPassword = mkDefault false` 設定）。この挙動は変更しません。Windows側から `wsl -u root` を実行すればパスワードなしでroot権限にアクセスできるため、WSL内部だけで `sudo` のパスワード入力を強制してもセキュリティ上の意味をなさないためです。

不採用とした代替案は以下の2点です：

- **各モジュールを個別にインポートする案**：既存の共通モジュールを変更せずに済みますが、結局 `nix-settings.nix` からGUI部分を分離する必要がある上、将来的に `common.nix` に基礎的な共通設定が追加された際、WSL環境だけが更新から取り残されるリスクがあります。
- **`common.nix` 内で `local.wsl.enable` などのフラグにより分岐させる案**：ファイル構成を変更せずに済みますが、WSL固有の処理が多くのモジュールに分散してしまい、今後ホストの種類が増えるたびに条件分岐が複雑化する恐れがあります。

### 6. Home Manager の個人設定を読まない

[pomu-agents.nix](../../profiles/home/pomu-agents.nix) には、`agentConfigRoot`（`~/sagyo/agents-private`）、`agentProfiles`（Claudeのopus・fable、Codexのastra）、`agentCompression` の設定を置いています。なお、`agentConfigRepo` はこの共通ファイルには含めません。
[pomu-workstation.nix](../../profiles/home/pomu-workstation.nix) は `pomu.nix` と `pomu-agents.nix` をインポートし、`agentConfigRepo` などの固有設定のみを保持します。

`nixos-work-wsl` の `nixos` ユーザーは、`pomu.nix` も `pomu-agents.nix` も読み込みません。そのため、`khimoo` のGit ID情報、Geminiのシークレット、`antigravity-cli`、agents-private の設定は導入されません。
home のファイルには [hosts/nixos-work-wsl/home.nix](../../hosts/nixos-work-wsl/home.nix) を指定し、機能フラグ（feature）は `gui` だけを有効にします（「7. GUI アプリを WSLg で表示する」）。
リポジトリルート（`flakeRoot`）は、デフォルトの `~/sagyo/flake_public` を使用します。Neovimの設定はこのパスを直接参照するシンボリックリンクとして構成されているため、WSL上でも同じディレクトリ階層にクローンする必要があります。
これに伴い、既存の `homeConfigurations.pomu-wsl` は削除します。なお、`pomu-macos` および `pomu-nixos` は従来通り `pomu.nix` を直接インポートするため影響を受けません。

### 7. GUI アプリを WSLg で表示する

会社PCでも、自宅と同じ kitty（`Ctrl+a > 階層 > 動詞` のキー体系と、Neovim との smart-splits の連携）で作業するため、`nixos` ユーザーで `features.gui` を有効にします。
kitty は Windows 側に配布物がないので、WSL の中で動かし、WSLg で Windows のデスクトップに表示します。
`wsl.startMenuLaunchers` を有効にして、NixOS-WSL にユーザーのプロファイルの `.desktop` ファイルを `/usr/share/applications` へ写させ、WSLg が Windows のスタートメニューに並べるようにします。

2026-10-14 に会社PCで確かめたこと:

- WSLg が使える。`/mnt/wslg` があり、`WAYLAND_DISPLAY=wayland-0`、`DISPLAY=:0` が設定されている。
- NixOS-WSL が `hardware.graphics.enable` を有効にしているので、mesa のソフトウェア描画で OpenGL が使える。素の kitty（`nix run nixpkgs#kitty`）は Windows のデスクトップに表示され、Windows とのコピー＆ペーストは双方向に動いた。
- Windows の IME で kitty に日本語を入力することはできなかった。

日本語は、kitty に IME を入れず、Neovim の skkeleton で入力します。シェルのプロンプトなど、Neovim の外では日本語を打てません。
WSL に fcitx5-skk を入れる案は退けました。WSLg の Wayland では IME のプロトコルを設定できないので、kitty を X11 で動かし、IBus 互換の経路で fcitx5 につなぐ必要があり、その経路が会社PCで動くかを試しながら進めることになるためです。

kitty と端末フォントだけを有効にする機能（`features.terminal`）を新設する案も退けました。機能を増やさず、既存の `gui` をそのまま使うことを選んでいます。
代償として、OBS、Chrome、Brave、IntelliJ、LibreOffice、Zoom なども入り、ダウンロードの量と WSL のディスク使用量が数 GB 単位で増えます。どれも binary cache から取得するので、会社PCでのビルドは発生しません。これらのアプリはすべてスタートメニューにも並びます。
Slack、Discord、Thunderbird などの自動起動は `graphical-session.target` に結び付いています。WSL にはデスクトップのセッションがなくこの target に到達しないので、自動では起動しません。
`local.restrictedHost` の制限は変えません。kitty の remote control は `listen_on unix:${XDG_RUNTIME_DIR}/kitty.sock` というローカルのソケットだけを使い、外への接続経路にはなりません。

2026-10-20 に Kiro と Cursor の導入設定を削除しました。[gui/apps.nix](../../modules/home-manager/gui/apps.nix) の Cursor 取得処理もなくなり、この取得先に対する会社ネットワークの到達性は適用の前提ではなくなりました。既存の AppImage の扱いは [GUI アプリの管理](../howtouse/gui-apps.md)を参照してください。
描画は mesa のソフトウェア描画のままにし、遅いと感じたときだけ `wsl.useWindowsDriver` で Windows の GPU ドライバーを使います。


## 検証方針

モジュールの分割リファクタリングは、`nixpkgs` を `25.11` に固定したまま行い、作業の前後で `desktop` と `spin713` の構成を比べました。
`system.build.toplevel.drvPath` は分割の前後で変わりますが、これは挙動の変化によるものではありません。[secrets.nix](../../modules/home-manager/secrets.nix) が flake のソース内にある `secrets.yaml` のパスを activation に埋め込んでおり、このパスはソース全体のハッシュを含むため、リポジトリのどのファイルを変えても変わります。
そこで、次の方法で挙動が変わっていないことを確かめました（2026年9月30日、nixos-25.11 b6018f8）。

- `config.system.path` のストアパスが、分割の前後で両ホストとも同じだった。パッケージの並び順が変わると、同じファイルを持つパッケージのうちどちらが残るかが変わりうる（`buildEnv` の `ignoreCollisions = true`）が、それも起きていない。
- `nix-diff` で見た中身の差分は、`secrets.yaml` のパスだけだった。`nix-diff` は入力が変わった途中の derivation の環境の比較を省くので、最終レビューでは、違う derivation の組すべての環境を、対応するストアパスのハッシュを置き換えたうえで比べた。残る差は同じ `secrets.yaml` のパスと、mutter の置換で書き換えるパスの組の並び順だけだった。
- home 側の分割については、pomu の `local.profile`、`local.agentCompression`、`home.file` と `home.activation` の名前、`home.packages` の名前の評価結果が、前後で一致した。

「会社PC内でクローズドな環境を維持する」というセキュリティ要件は、`local.restrictedHost.enable` の assertion が評価の時点で強制します。[tests/default.nix](../../tests/default.nix) の制約テスト（`contracts`）では、次のことを確かめます。

- 実際の `inputs.self.nixosConfigurations.nixos-work-wsl` が `local.restrictedHost.enable` を有効にしていて、assertion がすべて成り立つこと。
- 制限を破る構成（sshd を有効にしたホストと、`lanSsh` を有効にした Home Manager のユーザーを持つホスト）では、assertion が成り立たないこと。テスト用の架空のホストで確かめます。
- assertion では表せない設定：自分用のエージェントの設定がないこと（`agentConfigRoot` と `local.claudeManagedSettings` が null で、`claude-opus` などの起動用のコマンドがなく、`/etc/ssh/ssh_config` に `IdentityFile` がない）。`secrets` と `privateRepos` の activation がないこと。
- 有効な機能フラグが `gui` だけで、kitty が入り、`wsl.startMenuLaunchers` が有効なこと。

共通モジュールの構成とユーザーごとのHome Manager設定の分離（設計方針文書『AGENTS.md』における「profile/user isolation」の原則）の双方を変更するため、ローカル開発環境（desktop）で事前に `bash scripts/check.sh` によるテストを実行します。なお、`check.sh` はトップレベルの `drvPath` を評価するのみであるため、WSL用のトップレベルビルドはデスクトップPC上で別途実行して検証します。
ただし、初回適用（`switch`）、WSL再起動後のログイン挙動、Neovimの動作などは、実機環境（会社のWindows PC上のWSL）でのみ検証可能です。

## 今後の見直し契機（トリガー）

- **WSLの利用環境が「会社PC」から「個人PC」に変更された場合**：制限を解除し、age暗号鍵や各種シークレット、Tailscaleネットワーク（tailnet）への接続設定を再構成します。
- **社用の Claude や Codex のアカウントがある会社に移った場合**：上の「社用アカウントのある会社で戻すときの設計」で agents-private を戻します。その前に、自分用のプラグインやフック（コミット前に Gemini で校正するフックなど）を会社の作業で使ってよいかを、その会社の規程で確かめます。
- **NixOS全体のシステムリリースをアップデートする場合**：NixOS-WSLのインプットソース（Flake input）も同期して対応するリリースブランチ（`release-YY.MM`）へ追従させます。
- **Neovim の外でも日本語を打つ必要が出た場合**：kitty を X11 で動かし、fcitx5-skk を IBus 互換の経路でつなぐ案を会社PCで試します。

## 参考資料・リンク

- [NixOS-WSL 2605.7.2 リリースノート](https://github.com/nix-community/NixOS-WSL/releases/tag/2605.7.2)（2026年6月6日公開）：Flakesにおける `nixpkgs` のターゲットは `nixos-26.05`。インストールイメージに含まれる `configuration.nix` は内部の `modules/build-tarball.nix` によって自動生成されます。
- [NixOS-WSL release-26.05 ブランチ `modules/wsl-distro.nix`](https://github.com/nix-community/NixOS-WSL/blob/b98199a76ab180be55f7a6a97bd4984a87c99964/modules/wsl-distro.nix)（コミットハッシュ: `b98199a`、2026年9月11日時点）：`defaultUser` のデフォルト値の設定、既定ユーザーの生成、および `sudo` 実行時のデフォルト権限の仕様。
- **査読（ピアレビュー）実績**：2026年9月30日に `codex-astra`（gpt-6-astra）を用いて本設計内容の整合性をレビュー（読み取り専用）しました。その際、SSH鍵分離設計の不備（会社用の鍵を `Host *` に書くと分離が崩れる点）、`adb.nix` のインポート漏れ、`audio` グループの仕様に関する誤認の指摘を受け、それらを本設計案に反映しました。
