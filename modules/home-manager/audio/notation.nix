# 楽譜作成（GUI エディタ・組版エンジン）

{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.audio {
  home.packages = with pkgs; [
    musescore # GUI の楽譜エディタ。MusicXML / MIDI の入出力もここが担う
    lilypond  # テキスト記述から楽譜を組版するエンジン
  ];
}
