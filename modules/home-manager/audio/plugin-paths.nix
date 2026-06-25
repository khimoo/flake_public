# NixOS 上の DAW にプラグインを発見させるための標準パス互換層
#
# LV2/VST3/CLAP 規格は "user installation path" として ~/.lv2, ~/.vst3, ~/.clap
# 等を定めているが、NixOS では home-manager のパッケージは
# /etc/profiles/per-user/$USER/lib/{lv2,vst3,clap,vst,lxvst}/ に配置される。
# 規格パスのみをスキャンする DAW（例: zrythm 1.0 は LV2_PATH を読まない）からは
# プラグインが見えなくなるため、標準パスを NixOS のプロファイルに symlink する。
#
# mkOutOfStoreSymlink を使うことで、後で楽器パッケージを追加した際も
# 次回 rebuild の実体差し替えのみで反映され、再 symlink は不要。

{ settings, config, lib, ... }:

lib.mkIf settings.features.audio {
  home.file = let
    link = subdir: {
      source = config.lib.file.mkOutOfStoreSymlink
        "/etc/profiles/per-user/${config.home.username}/lib/${subdir}";
    };
  in {
    ".lv2"   = link "lv2";
    ".vst3"  = link "vst3";
    ".clap"  = link "clap";
    ".vst"   = link "vst";
    ".lxvst" = link "lxvst";
  };
}
