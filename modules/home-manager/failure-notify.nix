# ユーザーのサービスが失敗したら、デスクトップに通知する。
# 通知させたいサービスは Unit.OnFailure に local.failureNotify.onFailure を入れる。
# 使い方と設計判断: docs/howtouse/failure-notify.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  notifyFailure = pkgs.writeShellScript "notify-failure" ''
    unit=$1
    # 同じユニットが失敗を繰り返しても通知が積み重ならないよう、前回の通知を置き換える。
    # 閉じた通知の ID を渡したときは、新しい通知になる。
    ids="$XDG_RUNTIME_DIR/notify-failure"
    mkdir -p "$ids"
    id=$(cat "$ids/$unit" 2>/dev/null) || id=0
    id=$(${lib.getExe pkgs.libnotify} --urgency=critical --app-name=systemd --print-id --replace-id="$id" \
      "$unit が失敗しました" "journalctl --user -u $unit で原因を確かめる") &&
      printf '%s\n' "$id" > "$ids/$unit"
  '';
in
{
  options.local.failureNotify.onFailure = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = [ "notify-failure@%n.service" ];
    description = "失敗をデスクトップに通知したいユーザーのサービスの Unit.OnFailure に入れる値。";
  };

  config = lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.services."notify-failure@" = {
      Unit.Description = "%i の失敗をデスクトップに通知する";
      Service = {
        Type = "oneshot";
        ExecStart = "${notifyFailure} %i";
      };
    };
  };
}
