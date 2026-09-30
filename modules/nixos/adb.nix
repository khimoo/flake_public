# USB で Android 端末を扱う機能なので、base.nix ではなく common.nix から読む。
{ ... }: {
  programs.adb.enable = true;
}
