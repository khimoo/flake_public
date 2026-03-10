# ユーザー設定
{ pkgs, specialArgs, lib, ... }:

let
  users = specialArgs.settings.users or [];
  usersByName = builtins.listToAttrs (map (user: {
    name = user.username;
    value = user;
  }) users);
in {
  users.users = lib.genAttrs (builtins.attrNames usersByName) (username:
    let
      user = usersByName.${username};
    in {
      isNormalUser = true;
      description = user.description or username;
      extraGroups = (user.extraGroups or [])
        ++ [ "networkmanager" "libvirtd" "adbusers" ]
        ++ lib.optionals (user.isAdmin or false) [ "wheel" ];
      shell = user.shell or pkgs.bash;
      initialPassword = user.initialPassword or null;
      initialHashedPassword = user.initialHashedPassword or null;
      hashedPassword = user.hashedPassword or null;
    }
  );

  # sudo nixos-rebuild switchでsshキーを引き継ぐ
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
