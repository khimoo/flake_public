{ pkgs, lib, settings, ... }:

# NixOS の XDG MIME がスキームハンドラを自動登録しない問題のワークアラウンド。
# GNOME は mimeapps.list に明示的なデフォルトがないとスキームハンドラを解決できない。
# これにより、ブラウザ認証後のアプリへのリダイレクト（slack:// 等）が失敗する。
#
# Issue: https://github.com/NixOS/nixpkgs/issues/301893
# Fix:   https://github.com/NixOS/nixpkgs/pull/494847
# ↑ がマージされたらこのファイルは削除可能。

lib.mkIf settings.features.gui {
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/slack" = "slack.desktop";
    "x-scheme-handler/discord" = "discord.desktop";
    "x-scheme-handler/obsidian" = "obsidian.desktop";
    "x-scheme-handler/zoommtg" = "us.zoom.Zoom.desktop";
    "x-scheme-handler/zoomus" = "us.zoom.Zoom.desktop";
    "x-scheme-handler/spotify" = "spotify.desktop";
  };
}
