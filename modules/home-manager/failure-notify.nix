{ lib, ... }:
{
  options.local.failureNotify.onFailure = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = [ "notify-failure@%n.service" ];
    description = "失敗をデスクトップに通知したいユーザーのサービスの Unit.OnFailure に入れる値。";
  };
}
