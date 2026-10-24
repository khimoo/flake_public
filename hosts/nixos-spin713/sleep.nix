# 蓋を閉じたときのサスペンドと hibernate の設定。hibernate のイメージはスワップパーティションに
# 書くので、スワップパーティションもここで定義する。
{ ... }:
let
  swapDevice = "/dev/disk/by-uuid/ad09652b-13f2-455f-8614-1488908f71dd";
in
{
  boot.kernelParams = [ "mem_sleep_default=s2idle" ];
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchDocked = "suspend";
    HandleLidSwitchExternalPower = "ignore";
  };
  systemd.sleep.settings.Sleep.HibernateDelaySec = "10m";

  swapDevices = [ { device = swapDevice; } ];
  boot.resumeDevice = swapDevice;
}
