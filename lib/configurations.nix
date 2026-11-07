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
    ../modules/home-manager/dev
  ];
  # config/hosts/<host>.toml。kind を持つファイルが実際のホストで、持たないものは tests の
  # 架空のホスト（目的と値だけを持つ）。
  hosts = lib.mapAttrs' (
    file: _: lib.nameValuePair (lib.removeSuffix ".toml" file) (builtins.fromTOML (builtins.readFile (../config/hosts + "/${file}")))
  ) (lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".toml" file) (builtins.readDir ../config/hosts));
  repoFile = rel: ../. + "/${rel}";
in
rec {
  inherit overlays hosts;

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
          machines = hosts;
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
                    ++ lib.optional (builtins.pathExists ../config/hosts/${hostname}.toml) (
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
      ++ lib.optional (builtins.pathExists ../config/hosts/${hostname}.toml) (
        import ../modules/nixos/confgen.nix {
          host = hostname;
          inherit system;
          user = primaryUser;
        }
      )
      ++ modules;
    };

  # ホストのファイルから mkSystem / mkHome の引数を作る。
  nixosHosts = lib.mapAttrs (
    hostname: h:
    mkSystem {
      inherit hostname;
      inherit (h) system timezone;
      stateVersion = h.state_version;
      users = map (
        u:
        {
          username = u.name;
          isAdmin = u.admin or false;
          manageHome = u.home_manager or true;
        }
        // lib.optionalAttrs (u ? initial_hashed_password) { initialHashedPassword = u.initial_hashed_password; }
        // lib.optionalAttrs (u ? home_file) { homeFile = repoFile u.home_file; }
      ) h.users;
    }
  ) (lib.filterAttrs (_: h: (h.kind or null) == "nixos") hosts);

  homeHosts = lib.mapAttrs (
    name: h:
    let
      u = builtins.head h.users;
    in
    mkHome {
      inherit name;
      inherit (h) system;
      username = u.name;
      stateVersion = h.state_version;
      homeFile = if u ? home_file then repoFile u.home_file else null;
    }
  ) (lib.filterAttrs (_: h: (h.kind or null) == "home") hosts);

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
        ++ lib.optional (builtins.pathExists ../config/hosts/${name}.toml) (
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
