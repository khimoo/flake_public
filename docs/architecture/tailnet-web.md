# tailnet の端末に自分用サーバの Web UI を届ける

実装: [tailnet_web.star](../../config/elements/tailnet_web.star)（名前とポート）、[tailnet_gate.star](../../config/elements/tailnet_gate.star)（サーバの門番）、[tailnet-gate](../../packages/tailnet-gate/tailnet_gate_auth.py)（接続元の端末を調べる）、各 `serve_*` / `use_*`（[serve_aiboard.star](../../config/elements/serve_aiboard.star)、[use_aiboard.star](../../config/elements/use_aiboard.star)、[serve_xsaved.star](../../config/elements/serve_xsaved.star)、[use_xsaved.star](../../config/elements/use_xsaved.star)）

## 目的

自分用サーバの Web UI（aiboard、xsaved）を、次の形で使う。

- 本体は 1 台だけで動く。
- 使う端末を、各ホストの `purposes` で `use_*` を選んで列挙する。ほかの利用目的から自動では入らない。
- 列挙した端末はどれも対等で、サーバ自身も含めて同じ URL（`http://aiboard.home.arpa/`、`http://xsaved.home.arpa/`）をブックマークして開く。サーバを別のホストへ移しても URL は変わらない。
- 列挙していない端末からは、SSH の鍵を持っていても届かない。

## 経路

```text
ブラウザ ─ http://aiboard.home.arpa/ ─▶ 手元の Caddy（127.0.0.1:80、/etc/hosts で名前を自分へ向ける）
        ─ nixos-desktop:8780 ─▶ サーバの Caddy（門番。tailscale0 だけに開ける）
        ─ forward_auth ─▶ tailnet-gate-auth（接続元を tailscale whois で調べる）
        ─ 127.0.0.1:15280 ─▶ Web UI
```

- **名前**: `/etc/hosts` で `*.home.arpa` を自分自身へ向ける。`home.arpa` は家庭内ネットワーク用に予約された名前なので、インターネットの名前とぶつからない。値は IP を含まないので、リポジトリだけで決まる。
- **手元の Caddy**: `use_*` が、`find_home_server` から求めたサーバのホスト名（MagicDNS で引く）と門番のポートへ渡す。`Host` は書き換えない。
- **門番**: サーバの Caddy が `http://<名前>:8780` で名前ごとに Web UI を選ぶ。名前の合わない要求（IP で直接来たもの、ほかの名前に向け直されたもの）は `http://:8780` が 403 で返す。
- **接続元の確認**: 門番は `forward_auth` で `tailnet-gate-auth` に、接続元のアドレス（`{remote_host}`。端末が同じ見出しを送ってきても `header_up` で上書きする）と、通してよい端末の一覧を渡す。`tailnet-gate-auth` は `tailscale whois` で MagicDNS 名の先頭を求め、一覧にあれば 200、なければ 403 を返す。結果は 1 分間覚える。調べられないアドレス（tailnet の外）は通さない。
- **サーバ自身**: サーバが自分の名前へ接続すると、接続元は tailnet のアドレスとは限らない（`/etc/hosts` の `127.0.0.2 nixos-desktop` など）。接続元がこのマシンのアドレス（ループバックか、bind できるアドレス）なら、このマシン（`--self`）とみなす。LAN からの接続はファイアウォールが門番のポートに届かせないので、ほかの端末がこの扱いになることはない。
- **通す端末の一覧**: `tailnet_web` が `roles` から、`use_*` を選んだホストの名前を集める。Tailscale の端末名とこのリポジトリのホスト名が同じであることを前提にする。

## 名前とポートを tailnet_web にまとめる

名前（`aiboard.home.arpa`）と門番のポートは、サーバの側（`serve_*`）と端末の側（`use_*`）の両方が使う。`use_*` が `serve_*` を引数に取るとその端末でサーバが有効になり、`serve_*` が `use_*` を引数に取ると逆になるので、値だけを持つ `tailnet_web` を両方が読む。

門番の設定の土台（Caddy、ファイアウォール、`tailnet-gate-auth`）は `tailnet_gate` が持ち、サーバの側だけが `requires` に挙げる。端末の側は Caddy を有効にしてサイトを足すだけで、門番のポートは開けない。

## 1 台で動かすサービスは 1 人まで

名前は tailnet に 1 つなので、同じホストで 2 人が同じ `serve_*` を選ぶと、門番はどちらへ渡すか決められない。`serve_xsaved` は、1 台で選ぶユーザーが 2 人以上なら confgen で止める。

## 退けた案と理由

- **アプリ本体に判定を書く**: aiboard と xsaved（別リポジトリ）に同じ処理が 2 か所でき、xsaved が Tailscale を知ることになる。
- **Tailscale の ACL で制限する**: ポリシーがリポジトリの外（管理画面）にあり、`use_*` を選ぶと許される連動が作れない。
- **各端末の `/etc/hosts` にサーバの Tailscale IP を書く**: IP は Tailscale が決めた値を写すだけで、端末を登録し直すと黙って古くなる。
- **SSH のポート転送（以前の `aiboard-web` / `xsaved-web`）**: 端末ごとにコマンドと手元のポートが要り、サーバ自身だけ別の URL になる。使う端末も SSH の鍵の有無で決まり、列挙できない。

## 代償

- ブラウザを使う端末すべてで Caddy が常に動く。経路は「手元の Caddy → 門番 → Web UI」と 1 段長い。
- `/etc/hosts` を書けない端末（スマホなど）では名前を引けない。
- 端末を足したり外したりしたときと、サーバを移したときは、サーバと端末の両方で `nixos-rebuild switch` を実行するまで反映されない。
- `use_*` は `find_home_server` を使うので、サーバのホスト名を知るためだけに SSH の鍵と接続設定も入る。
- Tailscale 側で端末名が変わると（重複時の自動改名など）、その端末は通らなくなる。
