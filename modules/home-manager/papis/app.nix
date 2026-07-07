# papis 本体（CLI）＋宣言的設定。GUI 環境でのみ導入する。
#
# PDF 同期（sync.nix）はこの papis ライブラリ（~/papis-library）を同期対象にするが、
# 依存の向きは一方向（sync → library）。papis 側は同期 backend（gdrive/NAS 等）を
# 一切知らないので、backend を差し替えても app.nix は無改造で済む。
#
# citekey は各 item の info.yaml の `ref:` に手動 pin する運用（引用は citekey で参照し、
# ファイルパスに依存しない）。自動生成 ref-format はあえて設定しない。
{ settings, config, lib, ... }:
let
  # papis ライブラリの実体。sync.nix の libraryDir と同一パスにすること（bisync 対象）。
  libraryDir = "${config.home.homeDirectory}/papis-library";
in
{
  # programs.papis.enable が pkgs.papis 本体も home.packages に入れる。
  config = lib.mkIf settings.features.gui {
    programs.papis = {
      enable = true;
      # papis open が使う外部ビューア。デスクトップの既定アプリに委譲する。
      settings.opentool = "xdg-open";
      libraries.library = {
        isDefault = true;
        settings.dir = libraryDir;
      };
    };
  };
}
