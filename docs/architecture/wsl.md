# 会社PCのNixOS-WSLを、秘密情報と外部への接続経路を持たないCLI専用ホストとして追加する

設定ファイル: [modules/nixos/base.nix](../../modules/nixos/base.nix)、[profiles/home/pomu-agents.nix](../../profiles/home/pomu-agents.nix)（実装済み）、`hosts/nixos-wsl/`（未実装）

**現状：一部実装済み。** `base.nix` と `pomu-agents.nix` への分割は実装済みで、`nixos-wsl` ホストは未実装です。ホストを追加する前に、リポジトリ全体の nixpkgs および Home Manager を 26.05 へアップデートする必要があります。その設計は別途行います。
実装後はセットアップ手順を `docs/howtouse/wsl.md` へ切り出し、本ファイルには意思決定の経緯（判断根拠）を記録します。

会社のWindows PCに導入したNixOS-WSLを `nixosConfigurations.nixos-wsl` として定義し、`sudo nixos-rebuild switch --flake .#nixos-wsl` を一度実行するだけで、Home Manager環境まで一括で構築できるようにします。
このホストは会社PC内で完結するCLI環境とし、個人の秘密情報や自宅マシンへのアクセス経路は一切持たせないようにします。

## 現状の課題

現在、WSL環境はスタンドアロンのHome Manager設定である `homeConfigurations.pomu-wsl` としてしか定義されていません。
[flake.nix](../../flake.nix) の `nixosConfigurations` には `nixos-desktop` と `nixos-spin713` のみが登録されているため、WSL上で `sudo nixos-rebuild switch --flake .` を実行すると、イメージ既定のホスト名である `nixos` の設定が見つからずエラーになります。

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
その結果、WSL上にはGeminiのAPIキーが存在しなくなります。ただし、`agents-private` の管理設定に含まれるコミット前校正フック（`claude/hooks/gemini-proofread-commit.py`）は、校正処理に失敗してもコミット自体はそのまま通す仕様になっているため、キーがなくても開発作業（コミット）が妨げられることはありません。
また、キーを持たせないことで、業務上のコミットメッセージが意図せずGeminiへ送信される事態を確実に防げる利点もあります。

GitのID情報（名前やメールアドレス）は、本リポジトリのどのファイルにも記載しません。会社用のGitHubアカウント情報をパブリックリポジトリにハードコードすると、個人アカウント `khimoo` と現在の勤務先との関連性が一般に公開されてしまうためです。
会社用のID情報は、WSL環境上の `~/.gitconfig` に手動で設定します。GitはHome Managerが配置する `~/.config/git/config` と、個別設定用の `~/.gitconfig` の両方を自動で読み込むため、リポジトリ側で特別な仕組みを用意する必要はありません。
ただし、`~/.gitconfig` が存在しない状態で `git config --global` を実行すると、Home Managerによって読み取り専用リンクとして生成された `~/.config/git/config` へ直接書き込もうとしてエラーになります（Git 2.51.2 の `git-config(1)` における `--global` の説明を参照）。そのため、初回設定時は `git config --file ~/.gitconfig` のようにファイルパスを明示して書き込みます。

`khimoo` アカウントの書き込み（push）権限を持つ認証情報も配置しません。WSLの仮想ディスクはWindows側のファイルとして保存されており、会社のシステム管理ツールや管理者権限からアクセス可能な状態にあるためです。
パブリックリポジトリ（`flake_public`）はHTTPS経由でクローンし、pull（閲覧・同期）専用とします。コードの変更作業はすべて自宅マシンで行い、WSL環境で見つかった不具合も帰宅後に自宅環境で修正・反映する運用とします。

### 2. agents-private は読み取り専用のデプロイキー（Deploy Key）で取得する

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

### 3. デフォルトユーザー名 `nixos` をそのまま使用する

Home Managerのモジュール群は、すべてのパスを `home.homeDirectory` を基準に動的に組み立てています。`/home/pomu` という絶対パスを直接指定しているのは `desktop` と `spin713` のホスト設定のみであり、WSL用のホスト設定はこれらとは独立して記述します。
ユーザー名をあえて `pomu` に変更する利点は他マシンと絶対パスが揃う点のみですが、その一方で、構築済みのNixOS-WSL環境でユーザー名を変更するには `nixos-rebuild boot` の実行後にWSLインスタンスを再起動するなど煩雑な手順が必要になります。そのため、デフォルトの `nixos` のままで運用します。

### 4. 共通設定を `base.nix` に分離する

[base.nix](../../modules/nixos/base.nix) には、どのホストでも共通して必要となる最小限の設定を集約しています。
このファイルで [locale.nix](../../modules/nixos/locale.nix)、[users.nix](../../modules/nixos/users.nix)、nix-settings.nix（GUI関連を除く）、[codex.nix](../../modules/nixos/codex.nix)、[agent-instructions.nix](../../modules/nixos/agent-instructions.nix)、[claude-managed-settings.nix](../../modules/nixos/claude-managed-settings.nix)、[permit-insecure.nix](../../modules/nixos/permit-insecure.nix) をインポートし、`networking.hostName` や `system.stateVersion` もこの `base.nix` で設定します。
Codexのサブエージェント無効化設定（`codex.nix`）を `base.nix` に含めるのは、WSL環境にもCodexを導入するためです。また、`permit-insecure.nix` は、Home ManagerをNixOSに組み込んでいる全ホストで必須となります。

[common.nix](../../modules/nixos/common.nix) は `base.nix` をインポートした上で、デスクトップ環境（desktop）向けの残りの設定を保持します。具体的には、boot、networking（NetworkManagerやKDE Connect用のポート）、desktop、printing、ssh、tailscale、remote-builders、Bluetooth、libvirt、audio（musnix）、sns-block、gnome-transparent-fullscreenがこれに該当します。
分割前に `nix-settings.nix` にあった gparted や gsconnect は [desktop.nix](../../modules/nixos/desktop.nix) にに置いています。adb は、26.05 で USB の権限を systemd が扱うようになったので、Home Manager の [dev/apps.nix](../../modules/home-manager/dev/apps.nix) で `android-tools` を入れています。

[users.nix](../../modules/nixos/users.nix) は現状維持とします。
このモジュールでは、WSL環境には存在しない `networkmanager` や `libvirtd` などのグループをユーザーに付与していますが、NixOSの仕様上、グループ定義側から所属メンバーを評価するため（`elem config.name u.extraGroups`）、システムに定義されていないグループは自動的に無視されます（nixos-25.11 の `nixos/modules/config/users-groups.nix` の仕様）。そのため、不要なグループが指定されていてもエラーは発生しません。
`audio` グループはNixOSのデフォルトで定義されているため `nixos` ユーザーにも割り当てられます。WSL環境にオーディオ機能はありませんが、所属していても実害はありません。

WSL用のホスト設定（`hosts/nixos-wsl/default.nix`）は、NixOS-WSLモジュールと `base.nix` のみをインポートするシンプルな構成にします。`wsl.defaultUser` は `settings.primaryUser` から動的に取得します。
また、`local.claudeManagedSettings` はパスをハードコードせず、Home Manager側の `agentConfigRoot` をもとに組み立てます。
Flakeの `inputs` に `nixos-wsl`（`github:nix-community/NixOS-WSL/release-26.05`）を追加し、`nixpkgs` は `follows` を用いて全体のバージョンと統一します。
システム全体の構築には、既存の `mkSystem`（[configurations.nix](../../lib/configurations.nix)）を使用します。`mkSystem` は常に `musnix` のNixOSモジュールをインポートしますが、`musnix` の各機能はデフォルトで無効化されているため、WSL向けに個別の条件分岐を設ける必要はありません。

NixOS-WSLは、`wheel` グループに属する全ユーザーに対し、パスワードなしでの `sudo` 実行をデフォルトで許可しています（release-26.05、b98199a の `modules/wsl-distro.nix` における `security.sudo.wheelNeedsPassword = mkDefault false` 設定）。この挙動は変更しません。Windows側から `wsl -u root` を実行すればパスワードなしでroot権限にアクセスできるため、WSL内部だけで `sudo` のパスワード入力を強制してもセキュリティ上の意味をなさないためです。

不採用とした代替案は以下の2点です：

- **各モジュールを個別にインポートする案**：既存の共通モジュールを変更せずに済みますが、結局 `nix-settings.nix` からGUI部分を分離する必要がある上、将来的に `common.nix` に基礎的な共通設定が追加された際、WSL環境だけが更新から取り残されるリスクがあります。
- **`common.nix` 内で `local.wsl.enable` などのフラグにより分岐させる案**：ファイル構成を変更せずに済みますが、WSL固有の処理が多くのモジュールに分散してしまい、今後ホストの種類が増えるたびに条件分岐が複雑化する恐れがあります。

### 5. Home Manager設定は agents-private 向けの設定のみを共有する

[pomu-agents.nix](../../profiles/home/pomu-agents.nix) には、`agentConfigRoot`（`~/sagyo/agents-private`）、`agentProfiles`（Claudeのopus・fable、Codexのastra）、`agentCompression` の設定を置いています。なお、`agentConfigRepo` はこの共通ファイルには含めません。
[pomu-workstation.nix](../../profiles/home/pomu-workstation.nix) は `pomu.nix` と `pomu-agents.nix` をインポートし、`agentConfigRepo` などの固有設定のみを保持します。

WSL環境のHome Manager設定（`hosts/nixos-wsl/home.nix`）は、`pomu-agents.nix` のみをインポートします。`pomu.nix` は読み込まないため、`khimoo` のGit ID情報、Geminiのシークレット、`antigravity-cli` は導入されません。また、各種機能フラグ（feature）はすべてデフォルトの無効状態を維持します。
リポジトリルート（`flakeRoot`）は、デフォルトの `~/sagyo/flake_public` を使用します。Neovimの設定はこのパスを直接参照するシンボリックリンクとして構成されているため、WSL上でも同じディレクトリ階層にクローンする必要があります。
これに伴い、既存の `homeConfigurations.pomu-wsl` は削除します。なお、`pomu-macos` および `pomu-nixos` は従来通り `pomu.nix` を直接インポートするため影響を受けません。

初回のビルドと適用（`switch`）は、`agents-private` をクローンする前でも実行可能です。`~/.claude` などへのシンボリックリンクはクローンするまでリンク切れの状態になるだけで、アクティベーション自体はエラーになりません。[claude.nix](../../modules/home-manager/dev/claude.nix) のアクティベーション処理が実行されるのは、古い形式のシンボリックリンクが残存している場合のみです。
デプロイキーのエイリアス設定は `switch` を実行することで `/etc/ssh/ssh_config` に反映されるため、導入手順は「1. `switch` の実行」「2. デプロイキーの作成とGitHubへの登録」「3. `agents-private` のクローン」の順になります。

## 検証方針

モジュールの分割リファクタリングは、`nixpkgs` を `25.11` に固定したまま行い、作業の前後で `desktop` と `spin713` の構成を比べました。
`system.build.toplevel.drvPath` は分割の前後で変わりますが、これは挙動の変化によるものではありません。[secrets.nix](../../modules/home-manager/secrets.nix) が flake のソース内にある `secrets.yaml` のパスを activation に埋め込んでおり、このパスはソース全体のハッシュを含むため、リポジトリのどのファイルを変えても変わります。
そこで、次の方法で挙動が変わっていないことを確かめました（2026年9月30日、nixos-25.11 b6018f8）。

- `config.system.path` のストアパスが、分割の前後で両ホストとも同じだった。パッケージの並び順が変わると、同じファイルを持つパッケージのうちどちらが残るかが変わりうる（`buildEnv` の `ignoreCollisions = true`）が、それも起きていない。
- `nix-diff` で見た中身の差分は、`secrets.yaml` のパスだけだった。`nix-diff` は入力が変わった途中の derivation の環境の比較を省くので、最終レビューでは、違う derivation の組すべての環境を、対応するストアパスのハッシュを置き換えたうえで比べた。残る差は同じ `secrets.yaml` のパスと、mutter の置換で書き換えるパスの組の並び順だけだった。
- home 側の分割については、pomu の `local.profile`、`local.agentCompression`、`home.file` と `home.activation` の名前、`home.packages` の名前の評価結果が、前後で一致した。

「会社PC内でクローズドな環境を維持する」というセキュリティ要件が満たされているかは、実際の `nixos-wsl` の構成を評価して得られる設定値（`config` の値）を調べる必要があります。この検証ではビルドを実行せず、生成された成果物も検証しません。そのため、[tests/default.nix](../../tests/default.nix) の制約テスト（`contracts`）に、モック（仮想ホスト）ではなく実機想定の `inputs.self.nixosConfigurations.nixos-wsl` を直接アサーションする検証テストを追加します。

- **システムレベルの検証**：`sshd` および `tailscale` が完全に無効化されており、リモートビルド用の `nix.buildMachines` が空であることを確認します。また、`/etc/ssh/ssh_config` において、`github-agents-private` 用のホスト定義ブロックが存在し、`Host github.com` ブロックが存在しないことを確認します。
- **ユーザーレベルの検証（nixosユーザー）**：Home Managerの設定において、`privateRepos`、`sshKeys`、`secrets` がすべて空であり、`secrets` 関連のアクティベーション処理が含まれていないことを確認します。併せて、GitのID（identity）設定が `null` であり、`lanSsh` やその他すべての機能フラグ（feature）が無効化されていることを確認します。

共通モジュールの構成とユーザーごとのHome Manager設定の分離（設計方針文書『AGENTS.md』における「profile/user isolation」の原則）の双方を変更するため、ローカル開発環境（desktop）で事前に `bash scripts/check.sh` によるテストを実行します。なお、`check.sh` はトップレベルの `drvPath` を評価するのみであるため、WSL用のトップレベルビルドはデスクトップPC上で別途実行して検証します。
ただし、初回適用（`switch`）、WSL再起動後のログイン挙動、Neovimの動作、デプロイキーを用いたクローンとプル、`ssh -G` による実際の鍵解決結果などは、実機環境（会社のWindows PC上のWSL）でのみ検証可能です。

## 移行手順

1. **モジュールの分離**（実施済み）：`25.11` のロックファイルを維持したまま、`base.nix` および `pomu-agents.nix` への分割（リファクタリング）を行いました。`nixpkgs` のバージョンが異なると `drvPath` の比較検証が機能しないため、3つの手順の最初に行いました。
2. **システム全体のアップデート**（実施済み）：リポジトリ全体のNixOSおよびHome Managerのバージョンを `26.05` に上げました（別設計に基づく）。
3. **WSL環境の構築**：WSL用のホスト定義、検証用の自動テスト、利用ガイドなどのドキュメントを追加し、従来の `pomu-wsl` 設定を削除します。

## ドキュメントの更新計画

新規に `docs/howtouse/wsl.md` を作成し、新しいPCにNixOS-WSL環境をセットアップする際の標準手順を整理します。具体的には、HTTPS経由での初期クローン、初回のみFlakesを一時的に有効化して実施する `switch` 手順、デプロイキーの生成と登録、`agents-private` のクローン方法、会社用Gitアカウント情報の設定方法、`Host github.com` 定義に関する注意点と `ssh -G` を用いた検証方法、セキュリティ観点からGemini APIキーを配置しない理由について記載します。
なお、従来の `pomu-wsl` から新構成への移行は一度きりの作業であるため、恒常的な利用ガイド（howtouse）には記載せず、コミットメッセージに詳細を記録します。

また、WSLをスタンドアロンのHome Manager環境として記述している既存の各種ドキュメントを修正します。対象は、`README.md`、`howtouse` および `architecture` の各インデックス、`agent-config.md`、`codex-subagents.md`（利用ガイド・設計の双方）、`private-repo-clone.md`、`comma.md`、`unstable-packages.md` です。

## 今後の見直し契機（トリガー）

- **WSLの利用環境が「会社PC」から「個人PC」に変更された場合**：制限を解除し、age暗号鍵や各種シークレット、Tailscaleネットワーク（tailnet）への接続設定を再構成します。
- **会社のセキュリティポリシーや規程により、会社PC上への `agents-private` の配置が不適当と判断された場合**（現状の規程の再確認結果や、今後の改定によるもの）：デプロイキーの利用を取りやめ、`agents-private` なしで動作する構成にダウングレードします。
- **`agents-private` のコミット前校正フックが「エラー時にコミットをブロックする仕様」に変更された場合**：WSL環境においてClaude Code経由でのコミット処理が妨げられるようになるため、対策を検討します。
- **NixOS全体のシステムリリースをアップデートする場合**：NixOS-WSLのインプットソース（Flake input）も同期して対応するリリースブランチ（`release-YY.MM`）へ追従させます。

## 参考資料・リンク

- [NixOS-WSL 2605.7.2 リリースノート](https://github.com/nix-community/NixOS-WSL/releases/tag/2605.7.2)（2026年6月6日公開）：Flakesにおける `nixpkgs` のターゲットは `nixos-26.05`。インストールイメージに含まれる `configuration.nix` は内部の `modules/build-tarball.nix` によって自動生成されます。
- [NixOS-WSL release-26.05 ブランチ `modules/wsl-distro.nix`](https://github.com/nix-community/NixOS-WSL/blob/b98199a76ab180be55f7a6a97bd4984a87c99964/modules/wsl-distro.nix)（コミットハッシュ: `b98199a`、2026年9月11日時点）：`defaultUser` のデフォルト値の設定、既定ユーザーの生成、および `sudo` 実行時のデフォルト権限の仕様。
- **査読（ピアレビュー）実績**：2026年9月30日に `codex-astra`（gpt-6-astra）を用いて本設計内容の整合性をレビュー（読み取り専用）しました。その際、SSH鍵分離設計の不備（会社用の鍵を `Host *` に書くと分離が崩れる点）、`adb.nix` のインポート漏れ、`audio` グループの仕様に関する誤認の指摘を受け、それらを本設計案に反映しました。
