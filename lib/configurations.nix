{ inputs }:
let
  inherit (inputs) nixpkgs home-manager;
  inherit (nixpkgs) lib;
  overlays =
    import ../overlays
    ++ [ (import ../overlays/unstable-packages.nix inputs) ]
    ++ [ (import ../overlays/neovim-tools.nix inputs) ]
    ++ [ inputs.codex-cli-nix.overlays.default ]
    ++ [ inputs.claude-code-nix.overlays.default ]
    ++ [ (import ../overlays/claude-code-node.nix) ];
  homeModules = [
    ../modules/home-manager/profile.nix
    ../modules/home-manager/secrets.nix
    ../modules/home-manager/private-repos.nix
    ../modules/home-manager/failure-notify.nix
    ../modules/home-manager/minecraft-backup.nix
    ../modules/home-manager/windows-vm.nix
    ../modules/home-manager/mimikopi.nix
    ../modules/home-manager/xsaved.nix
    ../modules/home-manager/quaderno.nix
    ../modules/home-manager/dev
  ];
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
            extraSpecialArgs = { inherit inputs; };
            users = builtins.listToAttrs (
              map (user: {
                name = user.username;
                value = {
                  imports =
                    homeModules
                    ++ lib.optional (builtins.pathExists ../config/hosts/${hostname}.star) (
                      import ../modules/home-manager/confgen.nix {
                        host = hostname;
                        inherit system;
                        user = user.username;
                      }
                    )
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
      ++ lib.optional (builtins.pathExists ../config/hosts/${hostname}.star) (
        import ../modules/nixos/confgen.nix {
          host = hostname;
          inherit system;
          user = primaryUser;
        }
      )
      ++ modules;
    };

  mkHome =
    {
      name,
      username,
      system,
      stateVersion,
      homeFile ? null,
      modules ? [ ],
      allowUnfree ? true,
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { inherit system overlays; };
      extraSpecialArgs = { inherit inputs; };
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
        ++ lib.optional (builtins.pathExists ../config/hosts/${name}.star) (
          import ../modules/home-manager/confgen.nix {
            host = name;
            inherit system;
            user = username;
          }
        )
        ++ lib.optional (homeFile != null) homeFile
        ++ modules;
    };
}
