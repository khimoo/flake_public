# ホストとユーザープロファイルの境界

使い方: [ユーザー管理](../howtouse/users.md) / [検証](../howtouse/validation.md)
実装: [factory](../../lib/configurations.nix) / [profile options](../../modules/home-manager/profile.nix)

## 責務

`flake.nix` は環境を選択し、factoryがモジュールを組み立てる。NixOS用の `settings` にはホスト名・ユーザー一覧・時刻・キーマップ・stateVersionだけを入れる。Home Managerへこの属性集合は渡さない。

Home Managerはユーザーごとに `config.local.profile` を評価する。個人のGit identity、clone先、Claude設定、LAN鍵配布はそのユーザーのhomeモジュールにだけ定義する。現在の個人設定は `profiles/home/pomu.nix`、2台のworkstationの選択は `profiles/home/pomu-workstation.nix`、Claude CodeとCodexの設定repo（agents-private）の置き場所とlauncherは `profiles/home/pomu-agents.nix` にある。新しいユーザーはこれを明示的にimportしない限り引き継がない。

機構は共通モジュール、選択はprofile、ハードウェアはhostsに置く。imports は静的に保ち、`config` に依存する条件は `mkIf` に置く。`optionalAttrs config...` でモジュール構造を変えない。機能の有効化に型付きboolを使うことは正常なモジュール合成であり、一般的な「制御結合を避ける」という順位表で禁止しない。

## 機能の実装をたどる

factory の `homeModules` は共通機能の入口を列挙する。GUI の子モジュールは [gui/default.nix](../../modules/home-manager/gui/default.nix) がまとめて import し、factory 側には重ねて列挙しない。GUI 全体・GNOME・IME の有効化条件は各モジュールの `mkIf` に残し、WSLg のように GUI だけを使う構成を維持する。アプリの変更箇所は [GUI アプリの管理](../howtouse/gui-apps.md) を参照。

Home Manager への `extraSpecialArgs` は `inputs` を渡す。アプリ専用の引数や derivation を factory で作らず、その機能のモジュールが必要な input を参照する。

- [dev/neovim/default.nix](../../modules/home-manager/dev/neovim/default.nix) は skkeleton の辞書の展開と `nvim/nix/skk-dict-path.lua` の生成を持つ。辞書の取得元は `inputs.skk-jisyo`、展開用パッケージは従来の `inputs.nixpkgs.legacyPackages` のまま。
- [dev/lsp.nix](../../modules/home-manager/dev/lsp.nix) は同じ `lspServers` からパッケージの導入と `nvim/nix/lsp-servers.lua` の生成を行う。Neovim モジュールへ一覧を引数で中継しない。

生成した Lua は Home Manager の適用で XDG data 配下に配置する。Neovim の設定ディレクトリは live symlink なので、生成物をその中へ混ぜない。端末フォントの `terminalFont` は GUI 内の `_module.args` から kitty に渡す。GUI 無効時も kitty モジュールが引数として受け取るため、この定義は `mkIf` の外に置く。

## 型と制約

`local.profile` は既定値・型・説明を持つNixオプション。変更可能な設定は型付き option と `mkEnableOption`、上書き可能な既定値は `mkDefault`、成立すべき制約は assertion で表す。誤字や型不一致は評価エラーにする。URLだけがありclone先がない設定、別ユーザーのhomeへのmutable checkout、重複clone先、vaultなしの同期、GUIなしのGNOME/IMEはassertionで拒否する。

`flakeRoot` は共有の読み取り用checkoutにもできるのでhome内への制約は付けない。mutableなprivate checkoutはユーザーのhome配下に限定する。ディスク階層化はその配下へmountする。これはパス設定ミスを防ぐ契約であり、symlinkやOS権限を検証するセキュリティ境界ではない。

名前付き checkout のパスと URL の対応は `profile.nix` の `pairs` にまとめ、clone 対象の生成、URL に対応するパスの必須判定、home 配下の制約に共用する。URL を省いた手動 clone 用のパスも home 配下の制約対象に含める。追加の `privateRepos` の宛先も同じ制約を受ける。

`local.rustowl.enable` は対応するx86_64 Linuxで既定true、それ以外でfalse。未対応OSへの明示的有効化は拒否する。GUI等の現在のLinux専用プロファイルもDarwinでは拒否する。

## OSとの接点

デスクトップのpapis用mountは、ホスト固有モジュールで primaryUser の `local.profile.zettelkastenRoot` を参照する。

SSHクライアントのIdentityFileは `~/.ssh/` を使い、全ユーザーへprimaryUserの絶対パスを配らない。LAN接続先のユーザー名はprimaryUserで、鍵配布は `local.profile.lanSsh` を選んだユーザーだけ。例外は常設のリモートビルドで、nix-daemon（root）だけがprimaryUserの `id_lan` を絶対パスで読む（[remote-build.md](./remote-build.md)）。`--build-host` はrootを使わず、実行ユーザーのままSSHする。

## /etc/nixos のリンク

NixOS ホストでは、`/etc/nixos` を primaryUser の `local.profile.flakeRoot` へのシンボリックリンクとして設定する（[base.nix](../../modules/nixos/base.nix) 参照）。`--flake` を指定しない `nixos-rebuild` は `/etc/nixos/flake.nix` を探し、シンボリックリンクであれば解決先のディレクトリを Flake とみなして、現在のホスト名と同名の `nixosConfigurations` を適用する（nixpkgs 26.05 の nixos-rebuild-ng、`nixos_rebuild/models.py` の `Flake.from_arg` および `Flake.parse` による挙動）。そのため、初回のみ `--flake <参照>#<構成名>` で適用しておけば、以降は `sudo nixos-rebuild switch` だけで済むようになる。

`flake.nix` のみリンクする形でも `nixos-rebuild` は動作する（`nixos-rebuild` が `flake.nix` のリンク先から親ディレクトリを特定するため）。しかし、ディレクトリごとリンクしているのは、`/etc/nixos` を Flake 参照として `nix` コマンドに直接渡せるようにするためである。`flake.nix` のみリンクした場合、Nix は `/etc/nixos` を Flake のルートとして store にコピーしようとするが、リンク先の絶対パスは store 内に存在しないため評価に失敗してしまう。また、インストール時に生成される `configuration.nix` や `hardware-configuration.nix` は残さない。本構成ではこれらを使用せず、ハードウェア固有の設定は `hosts/<ホスト>/hardware.nix` に配置する。

この設定は `systemd.tmpfiles.rules` の `L+` ルールとして定義されており、起動時および switch 時に適用される。systemd 260.4 においては以下の挙動を確認している。既存の `/etc/nixos` がディレクトリの場合は中身ごと削除してシンボリックリンクに置き換える。ディレクトリ内にシンボリックリンク（手動で張った `flake.nix` のリンクなど）がある場合はリンクのみを削除し、リンク先の実体（チェックアウト先）は保持する。また、リンク先が変更された場合は自動で張り直され、変更がない状態で再度ルールが適用されても影響はない。

チェックアウトが存在しない間はリンク切れの状態となる。このとき `--flake` なしで `nixos-rebuild` を実行すると、`/etc/nixos/flake.nix` が見つからないため従来の構成ファイルを探索しようとする。しかし、本構成の Nix 検索パスには `nixos-config` が含まれていないため、`file 'nixos-config' was not found in the Nix search path` というエラーで停止し、何も適用されないようになっている。

primaryUser に Home Manager のユーザー設定がないホストでは `flakeRoot` が存在しないため、このルールは配置しない。また、ホスト名と構成名を一致させない運用にする場合は、この仕組みを見直す必要がある。

## 外部状態と検証

Nix評価はcheckoutの実在やage鍵を要求しない。clone・秘密鍵復元はactivationで実施する。既存の鍵は上書きせず、更新は手動のローテーション手順に委ねる。既存cloneもpullせず、更新は `pull-repos` に分ける。

activation を変更するときは、対応 OS、dry-run、再実行、中断・失敗後の回復を扱う。途中の結果を完了済みと判定しない。

live symlinkの内容はNix世代のロールバックでは戻らない。Gitで内容を復元する。

検証は実際のfactoryで複数ユーザーを生成し、他人の鍵・private repo・Git identityが漏れないこと、OS制約と不正設定の拒否を確認する。NixOS本体・Home Manager全構成の評価と、実機でのactivationを区別して報告する。

パッケージの出自と互換性パッチは `packages/` または `overlays/` に置き、パッチを外せる条件を記録する。

## 共通文書と作業の入口

人とエージェントは [文書整備](../howtouse/documentation.md) と [検証ガイド](../howtouse/validation.md)、既存のコマンドを共通に使う。Claude Code の `/workflow` は文書整備の入口であり、別の規約や検証方針を持たない。常時読む指示は入口と安全境界に絞り、詳細は対象文書で扱う。今回の整理では効果測定を行わず、運用で分かった問題に応じて調整する。
