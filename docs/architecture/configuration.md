# ホストとユーザープロファイルの境界

使い方: [ユーザー管理](../howtouse/users.md) / [検証](../howtouse/validation.md)
実装: [factory](../../lib/configurations.nix) / [個人の値](../../config/users/)

## 責務

[config/hosts/](../../config/hosts/) の TOML をマシンの正本とし、`kind` が `nixos` なら `nixosHosts`、`home` なら `homeHosts` に構成を作る。factory は system とユーザーを読み、confgen の結果を NixOS と Home Manager に渡す。specialArgs には `inputs` を渡す。

ホストの `machine` が機体を、`[[users]]` の `purposes` が利用者ごとの行動を選び、[要素](../../config/elements/) が依存をたどって設定を生成する。ホストを動かす `machine_*` は共通部品を `requires` で参照し、生成済み `hardware.nix` を import する。値を TOML、処理を要素に分けることで、選択と実装を二重管理しない（[confgen](confgen.md)）。

個人の Git identity、鍵、mutable checkout は `config/users/<ユーザー>.toml` に置く。各 Home Manager は本人のファイルだけを読み、同じホストの別のユーザーにも個人の値を渡さない。NixOS には利用者ごとの confgen の結果を合わせ、`home_manager = false` の人にはホーム構成を作らない。

## 機能の実装をたどる

機体と行動から要素の `requires` と仮引数をたどる。GUI の基本は `gui`、GNOME は `gnome`、日本語入力は `japanese_input` にある。GNOME と日本語入力は GUI を依存に含めるので、WSLg のように GUI だけを選ぶ構成も維持できる。

Neovim の道具と生成する Lua は `nvim_<名前>` の要素が機能ごとに持つ（[設計](neovim/features.md)）。Neovim の設定ディレクトリは checkout への live symlink なので、生成するファイルは XDG data 配下に置く。kitty のフォントは `gui` の公開値を読む。

## 制約

clone の宛先と秘密の復号先はホーム配下に限定し、重複する宛先を要素の `fail` で拒否する。エージェント設定の URL には checkout の場所も必要になる。

checkout の場所はホームからの相対パス `flake_root` とし、`checkout.root` が絶対パスを公開する。mutable checkout と秘密のパスの検査は設定ミスを防ぐもので、symlink や OS 権限を検証するセキュリティ境界ではない。

## 行動ごとの OS とホームの選択

[music_production.star](../../config/elements/music_production.star) は musnix・JACK・低レイテンシー設定と音楽アプリを選び、行動 `make_music` を選んだ利用者を audio グループに入れる。`call_audio` とともに `pipewire` を依存に含める。musnix の import も音楽制作を選んだホストだけに入る。

[windows_vm.star](../../config/elements/windows_vm.star) は libvirt・OVMF とネットワークの自動起動を設定し、`windows_vm` が入る利用者（分類 `category_work` か `category_life` を選んだ利用者）を libvirtd グループに入れる。GUI もあるホストでは、派生要素 `windows_vm_gui` が `windows_vm_domain` の VM を開くランチャーを作る。GUI が無ければ `windows_vm_domain` は使われない。

## OS との接点

SSH の IdentityFile は `~/.ssh/` を使い、全ユーザーへ最初のユーザーの絶対パスを配らない。接続先のユーザー名は各ホストの `ssh_user` から作る。LAN 鍵は `personal_files` と `lan_ssh = true` を選んだ場合だけ配る。

例外は常設のリモートビルドで、nix-daemon（root）が最初のユーザーの `id_lan` を絶対パスで読む（[remote-build.md](remote-build.md)）。`--build-host` は root を使わず、実行ユーザーのまま SSH する。

## /etc/nixos のリンク

NixOS ホストでは、`/etc/nixos` を `etc_nixos_link` を選んだ利用者の `checkout.root` へのシンボリックリンクとして設定する（[etc_nixos_link.star](../../config/elements/etc_nixos_link.star) 参照）。`--flake` を指定しない `nixos-rebuild` は `/etc/nixos/flake.nix` を探し、シンボリックリンクであれば解決先のディレクトリを Flake とみなして、現在のホスト名と同名の `nixosConfigurations` を適用する（nixpkgs 26.05 の nixos-rebuild-ng、`nixos_rebuild/models.py` の `Flake.from_arg` および `Flake.parse` による挙動）。そのため、初回のみ `--flake <参照>#<構成名>` で適用しておけば、以降は `sudo nixos-rebuild switch` だけで済むようになる。

`flake.nix` のみリンクする形でも `nixos-rebuild` は動作する（`nixos-rebuild` が `flake.nix` のリンク先から親ディレクトリを特定するため）。しかし、ディレクトリごとリンクしているのは、`/etc/nixos` を Flake 参照として `nix` コマンドに直接渡せるようにするためである。`flake.nix` のみリンクした場合、Nix は `/etc/nixos` を Flake のルートとして store にコピーしようとするが、リンク先の絶対パスは store 内に存在しないため評価に失敗してしまう。また、インストール時に生成される `configuration.nix` や `hardware-configuration.nix` は残さない。本構成ではこれらを使用せず、ハードウェア固有の設定は `hosts/<ホスト>/hardware.nix` に配置する。

この設定は `systemd.tmpfiles.rules` の `L+` ルールとして定義されており、起動時および switch 時に適用される。systemd 260.4 においては以下の挙動を確認している。既存の `/etc/nixos` がディレクトリの場合は中身ごと削除してシンボリックリンクに置き換える。ディレクトリ内にシンボリックリンク（手動で張った `flake.nix` のリンクなど）がある場合はリンクのみを削除し、リンク先の実体（チェックアウト先）は保持する。また、リンク先が変更された場合は自動で張り直され、変更がない状態で再度ルールが適用されても影響はない。

チェックアウトが存在しない間はリンク切れの状態となる。このとき `--flake` なしで `nixos-rebuild` を実行すると、`/etc/nixos/flake.nix` が見つからないため従来の構成ファイルを探索しようとする。しかし、本構成の Nix 検索パスには `nixos-config` が含まれていないため、`file 'nixos-config' was not found in the Nix search path` というエラーで停止し、何も適用されないようになっている。

`etc_nixos_link` を選ぶ利用者がいないホストには、`/etc/nixos` のリンクのルールを配置しない。また、ホスト名と構成名を一致させない運用にする場合は、この仕組みを見直す必要がある。

## 外部状態と検証

Nix評価はcheckoutの実在やage鍵を要求しない。秘密鍵の復元はactivation、初回のcloneは `clone-repos` で実施し、switchにネットワークからの取得を含めない。秘密の通常のファイルはswitchのたびに暗号文の内容とmodeに揃え、手で変更したものも戻す。配置したパスを記録し、宣言から外した通常のファイルは削除する。既存cloneもpullせず、更新は `pull-repos` に分ける。

activation を変更するときは、対応 OS、dry-run、再実行、中断・失敗後の回復を扱う。途中の結果を完了済みと判定しない。

live symlinkの内容はNix世代のロールバックでは戻らない。Gitで内容を復元する。

検証は実際のfactoryで複数ユーザーを生成し、他人の鍵・private repo・Git identityが漏れないこと、OS制約と不正設定の拒否を確認する。NixOS本体・Home Manager全構成の評価と、実機でのactivationを区別して報告する。

パッケージの出自と互換性パッチは `packages/` または `overlays/` に置き、パッチを外せる条件を記録する。

## 共通文書と作業の入口

人とエージェントは [文書整備](../howtouse/documentation.md) と [検証ガイド](../howtouse/validation.md)、既存のコマンドを共通に使う。Claude Code の `/workflow` は文書整備の入口であり、別の規約や検証方針を持たない。常時読む指示は入口と安全境界に絞り、詳細は対象文書で扱う。
