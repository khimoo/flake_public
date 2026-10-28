# 会社 PC の NixOS-WSL。個人の秘密と自宅への経路を持たせない。GUI アプリは WSLg で表示する。
# 社用の AI アカウントがない会社なので、自分用のエージェントの設定（agents-private）も置かない
# （docs/architecture/wsl.md）。
{ inputs, settings, ... }:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../modules/nixos/base.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = settings.primaryUser;
  # WSLg がスタートメニューに並べるのは /usr/share/applications の .desktop だけなので、
  # ユーザーのプロファイルにある kitty などをそこへ写させる。
  wsl.startMenuLaunchers = true;

  # 会社の Python プロジェクトで、uv が取得する Python と PyPI の manylinux wheel を動かす。
  # Home Manager の uv の設定がこの値を読む（docs/architecture/wsl.md）。
  programs.nix-ld.enable = true;

  local.restrictedHost.enable = true;
}
