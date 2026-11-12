{ inputs, configDir ? ../config }:
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
  hosts = lib.mapAttrs' (
    file: _: lib.nameValuePair (lib.removeSuffix ".toml" file) (builtins.fromTOML (builtins.readFile "${configDir}/hosts/${file}"))
  ) (lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".toml" file) (builtins.readDir "${configDir}/hosts"));
in
rec {
  inherit overlays hosts;

  mkSystem = { hostname, modules ? [ ] }:
    let
      host = hosts.${hostname};
      inherit (host) system users;
    in
    assert lib.assertMsg (users != [ ]) "mkSystem: users must not be empty";
    assert lib.assertMsg (
      builtins.length (lib.unique (map (u: u.name) users)) == builtins.length users
    ) "mkSystem: duplicate username";
    nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        {
          nixpkgs = {
            hostPlatform = system;
            inherit overlays;
          };
        }
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            backupFileExtension = "bak";
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
            users = builtins.listToAttrs (
              map (user: {
                name = user.name;
                value = {
                  imports = [
                    (import ../modules/home-manager/confgen.nix {
                      host = hostname;
                      inherit system configDir;
                      user = user.name;
                    })
                  ];
                  home.stateVersion = lib.mkDefault host.state_version;
                };
              }) (builtins.filter (user: user.home_manager or true) users)
            );
          };
        }
        (import ../modules/nixos/confgen.nix {
          host = hostname;
          inherit system configDir;
        })
      ] ++ modules;
    };

  nixosHosts = lib.mapAttrs (hostname: _: mkSystem { inherit hostname; })
    (lib.filterAttrs (_: h: (h.kind or null) == "nixos") hosts);

  homeHosts = lib.mapAttrs (name: _: mkHome { inherit name; })
    (lib.filterAttrs (_: h: (h.kind or null) == "home") hosts);

  mkHome = { name, modules ? [ ] }:
    let
      host = hosts.${name};
      inherit (host) system;
      username = (builtins.head host.users).name;
    in
    home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { inherit system overlays; };
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ({ lib, pkgs, ... }: {
          nixpkgs.config.allowUnfree = true;
          home.username = username;
          home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
          home.stateVersion = lib.mkDefault host.state_version;
        })
        (import ../modules/home-manager/confgen.nix {
          host = name;
          inherit system configDir;
          user = username;
        })
      ] ++ modules;
    };
}
