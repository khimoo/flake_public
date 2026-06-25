# 楽器プラグイン（LV2/VST3/CLAP 形式）
# プラグインパスは musnix が PIPE WIRE/JACK と合わせて自動設定するため、
# ここでは home.packages に並べるだけで zrythm から認識される

{ settings, pkgs, lib, ... }:

lib.mkIf settings.features.audio {
  home.packages = with pkgs; [
    # 減算/汎用シンセ
    surge-XT
    vital        # unfree
    helm
    zynaddsubfx
    odin2

    # FM シンセ
    dexed

    # ドラムシンセ / サンプラー
    geonkick
    drumgizmo

    # vee-one シリーズ（軽量・統一感のある UI）
    synthv1
    drumkv1
  ];
}
