# 設定どうしの関係の宣言と図

設定がどの用途のためにあり、どんな条件で働き、何を実行に使うかを `local.relations` に宣言します。
宣言は実際の設定の生成に使われ、同じ宣言から Mermaid の図を作れます。

設定: [relations.nix](../../modules/home-manager/relations.nix)

## 図を見る

ホストを指定して、そのホストのユーザー環境で宣言された関係を出力します。

```sh
nix eval --raw .#nixosConfigurations.nixos-spin713.config.home-manager.users.pomu.local.relations.mermaid
```

出力は Mermaid の `flowchart` です。Markdown の `mermaid` コードブロックに貼るか、`mmdc` で画像にします。
図には、そのホストで有効な設定の関係だけが出ます。

| 図の要素 | 意味 |
|----------|------|
| 角丸の箱（用途） | `purposes`。設定を置く目的 |
| ひし形（条件） | `conditions`。対策が実行時に働く条件 |
| 四角の箱（対策） | `measures`。用途のために置く設定と、その実装ファイル |
| 円柱（道具） | 条件の判定に使うパッケージ |

## 関係を宣言する

対策を追加するときは、対策を実装するモジュールに `local.relations.measures.<名前>` を書きます。

```nix
local.relations.measures.direnvCacheOnSshfs = {
  description = "direnv のキャッシュを手元に置く";
  source = "modules/home-manager/sshfs.nix";
  purpose = "sshfsEditing";
  condition = "onSshfs";
};
```

`purpose` と `condition` には、宣言済みの `purposes` と `conditions` の名前を書きます。存在しない名前を書くと評価エラーになります。
対策の実装は、`condition` で指定した条件の値（`mountType.findmnt` と `mountType.fsType`）を読んで作ります。Lua で実装する場合は、[features.nix](../../modules/home-manager/dev/neovim/features.nix) の `data` を通して値を渡します。

現在宣言されている用途と条件は、`sshfsEditing` と `onSshfs` です（[sshfs.nix](../../modules/home-manager/sshfs.nix)）。

## 設計

宣言は実際の設定の生成か検証に使い、図のためだけの宣言は置きません。図のためだけの宣言は、設定を変えても追従されず、図と設定で同じことを二重に管理することになるためです。
そのため、対策の実装は条件の種別やコマンドを自分で書かず、宣言から受け取ります。例えば tinymist の PDF 対策の Lua に `"fuse.sshfs"` や `"findmnt"` を直接書くと、宣言を通らない依存になります。

関係は「用途」「動作条件」「実行に必要な道具」に分けます。条件を有効化フラグに変換しないのは、対策が実行時の状態（開いた場所のマウント種別）で働くためです。例えば tinymist の PDF 対策は、`local.sshfs.enable` を有効にしていないホストでも、sshfs 上の文書なら働きます。

図に出るのは宣言した関係だけです。宣言を通らずに書かれた依存や、相手ホストが起動しているかなどの実行時の状態は図に出ません。
