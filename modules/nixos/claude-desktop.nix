# Claude Desktop Cowork に必要なシステム設定
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    bubblewrap
    socat
    virtiofsd
  ];

  # Cowork がダウンロードする claude-code バイナリは動的リンクされているため、
  # NixOS の標準環境では実行できない。nix-ld で互換レイヤーを提供する。
  programs.nix-ld.enable = true;
}
