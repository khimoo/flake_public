# ゲーム用ターボ（右クリック連打）。右 Alt を押している間、右クリックを送り続ける。
#
# Minecraft の右クリックには 2 経路ある（1.8〜1.18 で構造は同一）。押しっぱなし経路は
# startUseItem() が rightClickDelay=4 を代入するため 4 tick (200ms) に 1 回しか発火しない
# が、クリック経路 `while (keyUse.consumeClick()) startUseItem();` は rightClickDelay を
# 見ないため押下 1 回 = 使用 1 回になる。連打が押しっぱなしより速いのはこの非対称性による。
#
# 間隔 40ms: 押下イベントは tick (50ms) ごとにまとめて消費されるため上限は 1 tick 1 回。
# 50ms ちょうどにすると keyd の周期は設定値以上にしかならず、押下 0 回の tick が周期的に
# 生じる。40ms なら任意の tick に必ず 1 回以上入る。
#
# 押下時間なし: Minecraft が数えるのは押下イベント数であって押下状態ではないため保持は不要。
# むしろ keyd は macro 内の待ちを usleep で実装しており、保持中は keyd のイベントループ
# 全体が止まって他キーの入力が遅れる。
#
# 制約: 継続使用アイテム（食事・弓・盾）には使えない。isUsingItem() 中は
# `if (!keyUse.isDown()) releaseUsingItem()` で毎 tick 使用がキャンセルされる。
# 副作用: 右 Alt は AltGr (lv3:ralt_switch) として機能しなくなる（素の us 配列では無害）。
{ ... }:

let intervalMs = 40;
in {
  services.keyd = {
    enable = true;
    keyboards.default = {
      # ワイルドカードはマウス専用デバイスにはマッチしない（keyd の仕様）
      ids = [ "*" ];
      settings.main.rightalt =
        "macro2(${toString intervalMs}, ${toString intervalMs}, macro(rightmouse))";
    };
  };
}
