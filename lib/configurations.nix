{ inputs }:
let
  inherit (inputs) nixpkgs home-manager;
  inherit (nixpkgs) lib;
  overlays =
    import ../overlays
    ++ [ (import ../overlays/unstable-packages.nix inputs) ]
    ++ [ inputs.codex-cli-nix.overlays.default ];
  homeModules = [
    ../modules/home-manager/profile.nix
    ../modules/home-manager/core.nix
    ../modules/home-manager/git.nix
    ../modules/home-manager/ssh-keys.nix
    ../modules/home-manager/private-repos.nix
    ../modules/home-manager/rclone.nix
    ../modules/home-manager/zettelkasten.nix
    ../modules/home-manager/yazi.nix
    ../modules/home-manager/dev
    ../modules/home-manager/gui
    ../modules/home-manager/gui/gnome.nix
    ../modules/home-manager/gui/ime.nix
    ../modules/home-manager/gui/apps.nix
    ../modules/home-manager/gui/firefox.nix
    ../modules/home-manager/gui/teams-dispatcher.nix
    ../modules/home-manager/gui/xdg-scheme-workaround.nix
    ../modules/home-manager/audio
  ];
  mkHomeArgs = system: {
    inherit inputs;
    inherit (inputs) kiro;
    skk-dict = nixpkgs.legacyPackages.${system}.stdenv.mkDerivation {
      name = "skk-jisyo-dict";
      src = inputs.skk-jisyo;
      nativeBuildInputs = [ nixpkgs.legacyPackages.${system}.gzip ];
      unpackPhase = "gzip -d < $src > $out";
      dontInstall = true;
    };
  };
in
{
  inherit overlays;

  # Machine settings are only passed to NixOS. Each home owns its local.profile.
  mkSystem =
    {
      hostname,
      system,
      users,
      timezone,
      stateVersion,
      keymap ? "us",
      primaryUser ? (builtins.head users).username,
      hostModule ? ../hosts + "/${hostname}/default.nix",
      modules ? [ ],
    }:
    assert lib.assertMsg (users != [ ]) "mkSystem: users must not be empty";
    assert lib.assertMsg (
      builtins.length (lib.unique (map (u: u.username) users)) == builtins.length users
    ) "mkSystem: duplicate username";
    assert lib.assertMsg (builtins.elem primaryUser (
      map (u: u.username) users
    )) "mkSystem: primaryUser must be in users";
    nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        settings = {
          inherit
            hostname
            system
            users
            timezone
            keymap
            stateVersion
            primaryUser
            ;
          locale = "ja_JP.UTF-8";
        };
      };
      modules = [
        {
          nixpkgs = {
            hostPlatform = system;
            inherit overlays;
          };
        }
        inputs.musnix.nixosModules.musnix
        hostModule
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            backupFileExtension = "bak";
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = mkHomeArgs system;
            users = builtins.listToAttrs (
              map (user: {
                name = user.username;
                value = {
                  imports =
                    homeModules
                    ++ lib.optional ((user.homeFile or null) != null) user.homeFile
                    ++ (user.homeModules or [ ]);
                  home.stateVersion = lib.mkDefault stateVersion;
                  local.profile.standalone = false;
                };
              }) (builtins.filter (user: user.manageHome or true) users)
            );
          };
        }
      ]
      ++ modules;
    };

  mkHome =
    {
      username,
      system,
      stateVersion,
      homeFile ? null,
      modules ? [ ],
      allowUnfree ? true,
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { inherit system overlays; };
      extraSpecialArgs = mkHomeArgs system;
      modules =
        homeModules
        ++ [
          (
            { lib, pkgs, ... }:
            {
              nixpkgs.config.allowUnfree = allowUnfree;
              home.username = username;
              home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
              home.stateVersion = lib.mkDefault stateVersion;
            }
          )
        ]
        ++ lib.optional (homeFile != null) homeFile
        ++ modules;
    };
}
