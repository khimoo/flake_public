# Claude Desktop Cowork に必要なシステムパッケージ
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    bubblewrap
    socat
    virtiofsd
  ];
}
