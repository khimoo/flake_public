# 一時的な overlay 集。不要になったものから削除すること。
[
  # TODO: mypaint のバージョンが 2.0.1 より上がるか、nixpkgs 側でパッチが取り込まれたら削除する。
  # 背景: PyGObject 3.51.0 で GLib enum が stdlib enum ベースに変わり、
  #       value_name 属性が廃止された。MyPaint 2.0.1 はこれに対応していない。
  # 参照: https://github.com/mypaint/mypaint/issues/1292
  (final: prev: {
    mypaint = prev.mypaint.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace lib/glib.py \
          --replace-warn 'k.value_name' 'k.name'
      '';
    });
  })

  # TODO: nixpkgs の anki が uv の CA 証明書の設定に対応したら削除する。
  # 背景: nixpkgs の uv は UV_SYSTEM_CERTS=1 を既定にするラッパーで包まれ、OS の証明書ストアだけを読む。
  #       uv は UV_OFFLINE=1 でも起動時に HTTP クライアントを作り、証明書の無い build sandbox では
  #       "No CA certificates were loaded from the system" で終了する。ラッパーは --set-default なので
  #       ここで渡した値が優先され、uv は組み込みの証明書を使う。
  # 参照: https://github.com/NixOS/nixpkgs/pull/576558
  (final: prev: {
    anki = prev.anki.overrideAttrs (old: {
      env = (old.env or { }) // {
        UV_SYSTEM_CERTS = "0";
      };
    });
  })
]
