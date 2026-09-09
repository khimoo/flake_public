# ホストとユーザープロファイルの境界

使い方: [ユーザー管理](../howtouse/users.md) / [検証](../howtouse/validation.md)
実装: [factory](../../lib/configurations.nix) / [profile options](../../modules/home-manager/profile.nix)

## 責務

`flake.nix` は環境を選択し、factoryがモジュールを組み立てる。NixOS用の `settings` にはホスト名・ユーザー一覧・時刻・キーマップ・stateVersionだけを入れる。Home Managerへこの属性集合は渡さない。

Home Managerはユーザーごとに `config.local.profile` を評価する。個人のGit identity、clone先、Claude設定、LAN鍵配布はそのユーザーのhomeモジュールにだけ定義する。現在の個人設定は `profiles/home/pomu.nix`、2台のworkstationの選択は `profiles/home/pomu-workstation.nix` にある。新しいユーザーはこれを明示的にimportしない限り引き継がない。

機構は共通モジュール、選択はprofile、ハードウェアはhostsに置く。機能の有効化に型付きboolを使うことは正常なモジュール合成であり、一般的な「制御結合を避ける」という順位表で禁止しない。

## 型と制約

`local.profile` は既定値・型・説明を持つNixオプション。誤字や型不一致は評価エラーにする。URLだけがありclone先がない設定、別ユーザーのhomeへのmutable checkout、重複clone先、vaultなしの同期、GUIなしのGNOME/IMEはassertionで拒否する。

`flakeRoot` は共有の読み取り用checkoutにもできるのでhome内への制約は付けない。mutableなprivate checkoutはユーザーのhome配下に限定する。ディスク階層化はその配下へmountする。これはパス設定ミスを防ぐ契約であり、symlinkやOS権限を検証するセキュリティ境界ではない。

`local.rustowl.enable` は対応するx86_64 Linuxで既定true、それ以外でfalse。未対応OSへの明示的有効化は拒否する。GUI等の現在のLinux専用プロファイルもDarwinでは拒否する。

## OSとの接点

デスクトップのpapis用mountは、primaryUserの `local.profile.zettelkastenRoot` を参照する。アプリのinsecure許可は従来どおりHome ManagerからOSへ集約する。これらの境界をホスト固有モジュールと専用adapterに限定する。

SSHクライアントのIdentityFileは `~/.ssh/` を使い、全ユーザーへprimaryUserの絶対パスを配らない。LAN接続先のユーザー名はprimaryUserで、鍵配布は `local.profile.lanSsh` を選んだユーザーだけ。rootでのremote buildはSSH agent forwardingを利用する。

## 外部状態と検証

Nix評価はcheckoutの実在やage鍵を要求しない。clone・秘密鍵復元はactivationで実施する。既存の鍵は上書きせず、更新は手動のローテーション手順に委ねる。既存cloneもpullせず、更新は `pull-repos` に分ける。

live symlinkの内容はNix世代のロールバックでは戻らない。Gitで内容を復元する。

検証は実際のfactoryで複数ユーザーを生成し、他人の鍵・private repo・Git identityが漏れないこと、OS制約と不正設定の拒否を確認する。NixOS本体・Home Manager全構成の評価と、実機でのactivationを区別して報告する。
