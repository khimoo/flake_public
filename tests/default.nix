{ inputs, configurations }:
let
  inherit (inputs.nixpkgs) lib;
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
  configDir = inputs.nixpkgs.legacyPackages.x86_64-linux.runCommand "test-config" { } ''
    mkdir -p "$out/hosts" "$out/users"
    ln -s ${../config/elements} "$out/elements"
    cp ${../config/hosts}/*.toml ${./hosts}/*.toml "$out/hosts/"
    cp ${../config/users}/*.toml ${./users}/*.toml "$out/users/"
  '';
  configurations = import ../lib/configurations.nix { inherit inputs configDir; };
  fixture = configurations.mkSystem {
    hostname = "test-agents-users";
    modules = [ ../examples/new-host.nix ];
  };
  users = fixture.config.home-manager.users;
  nixosHost =
    hostname:
    (configurations.mkSystem {
      inherit hostname;
      modules = [ ../examples/new-host.nix ];
    }).config;
  laptop = nixosHost "test-remote-build";
  agentHost = nixosHost;
  xsavedHost = nixosHost "test-xsaved";
  codexConfig = host: builtins.fromTOML host.environment.etc."codex/config.toml".text;
  systemAssertionsHold = config: builtins.all (a: a.assertion) config.assertions;
  hostForSystem =
    system: name:
    if lib.hasSuffix "-darwin" system && builtins.pathExists (./hosts + "/${name}-darwin.toml") then
      "${name}-darwin"
    else
      name;
  mkTestHome =
    system: modules:
    if lib.hasSuffix "-darwin" system then
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          inherit system;
          inherit (configurations) overlays;
        };
        extraSpecialArgs = { inherit inputs; };
        modules = [
          {
            home.username = "test";
            home.homeDirectory = "/Users/test";
            home.stateVersion = configurations.hosts.test-darwin.state_version;
            nixpkgs.config.allowUnfree = true;
          }
          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            import ../lib/confgen-bridge.nix {
              inherit lib pkgs inputs;
              class = "home";
              # Linux の検査では生成器だけ Linux で動かし、Darwin のパッケージは評価にとどめる。
              result =
                (import ../lib/confgen.nix {
                  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
                  inherit configDir;
                }).read
                  "test-darwin"
                  system
                  "test";
              special = resolve: {
                "$outOfStoreLink" = v: config.lib.file.mkOutOfStoreSymlink (builtins.head v);
                "$activation" = v: lib.hm.dag.entryAfter (builtins.elemAt v 0) (resolve (builtins.elemAt v 1));
                "$gvariantTuple" = v: lib.hm.gvariant.mkTuple (builtins.head v);
              };
            }
          )
        ]
        ++ modules;
      }
    else
      configurations.mkHome {
        name = "test";
        inherit modules;
      };
  purposeHome =
    system: name:
    configurations.mkHome {
      name = hostForSystem system name;
    };
  rejectsPurpose =
    name: system: message:
    let
      selected = hostForSystem system name;
      username = (builtins.head (configurations.hosts.${selected}.users or [ { name = "test"; } ])).name;
    in
    builtins.readFile (
      inputs.nixpkgs.legacyPackages.x86_64-linux.runCommand "reject-${name}-${system}"
        {
          nativeBuildInputs = [
            (import ../lib/confgen.nix {
              pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
              inherit configDir;
            }).package
          ];
        }
        ''
          if confgen build ${configDir} ${lib.escapeShellArg selected} ${lib.escapeShellArg system} ${lib.escapeShellArg username} result.json > log 2>&1; then
            cat log
            exit 1
          fi
          cat log
          grep -F -- ${lib.escapeShellArg message} log
          printf passed > "$out"
        ''
    ) == "passed";
  allAssertions = home: builtins.all (a: a.assertion) home.config.assertions;
  # confgen が作る Neovim の機能の一覧。confgen 自体は Linux で build する。
  neovimFeatures =
    system:
    let
      result =
        (import ../lib/confgen.nix {
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
          inherit configDir;
        }).read
          "test-neovim-features"
          system
          "pomu";
      featuresLua = lib.findFirst (
        s:
        s.path == [
          "xdg"
          "dataFile"
          "nvim/nix/features.lua"
          "text"
        ]
      ) null result.elements.neovim.home;
    in
    (lib.elemAt featuresLua.value."$concat" 1)."$lua".features;
  # activation の after / before が存在しないノードを指しても、Home Manager はエラーにせず順序も保証しない。
  activationDepsExist =
    activation:
    builtins.all (entry: builtins.all (dep: activation ? ${dep}) (entry.after ++ entry.before)) (
      builtins.attrValues activation
    );
  hasLauncher = user: name: builtins.any (p: (p.name or "") == name) user.home.packages;
in
lib.genAttrs systems (
  system:
  let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    home = mkTestHome system [ ];
    activationHome = configurations.mkHome {
      name = "test-agents";
    };
    agentSyncSpec =
      let
        result =
          (import ../lib/confgen.nix {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            inherit configDir;
          }).read
            "test-agents"
            "x86_64-linux"
            "test";
        packages = lib.findFirst (
          s:
          s.path == [
            "home"
            "packages"
          ]
        ) null result.elements.agent_sync.home;
      in
      (builtins.head packages.value)."$shellAppEnv";
    agentSyncText =
      let
        resolveEnv =
          value:
          if builtins.isString value then
            value
          else
            let
              spec = value."$exe";
              package = lib.getAttrFromPath (lib.splitString "." (builtins.elemAt spec 0)) activationHome.pkgs;
            in
            "${package}/bin/${builtins.elemAt spec 1}";
      in
      lib.concatStrings (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (resolveEnv value)}\n") (
          builtins.elemAt agentSyncSpec 2
        )
      )
      + builtins.readFile (../. + "/${builtins.head (builtins.elemAt agentSyncSpec 3)."$repoText"}");
    # These are shell-source tests using fake tools, not builds of the target
    # platform packages. Discard context only for these mocked script strings.
    mockPaths =
      text:
      builtins.unsafeDiscardStringContext (
        builtins.replaceStrings
          [
            "/home/test"
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.git)
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.sops)
          ]
          [ "@test-home@" "@tools@" "@tools@" ]
          text
      );
    snippet = name: mockPaths activationHome.config.home.activation.${name}.data;
    # コマンドの本文。道具は PATH から呼ぶので、テストが偽の道具を PATH の先頭に置く。
    commandText =
      name:
      if name == "agent-sync" then
        mockPaths agentSyncText
      else
        mockPaths
          (lib.findFirst (
            p: (p.name or "") == name
          ) (throw "${name} is not installed") activationHome.config.home.packages).text;
    helpers = {
      inherit
        inputs
        configDir
        configurations
        home
        activationHome
        users
        nixosHost
        laptop
        agentHost
        xsavedHost
        codexConfig
        systemAssertionsHold
        mkTestHome
        purposeHome
        rejectsPurpose
        allAssertions
        neovimFeatures
        activationDepsExist
        hasLauncher
        commandText
        snippet
        mockPaths
        ;
    };
    args = {
      inherit
        lib
        pkgs
        system
        helpers
        ;
    };
    elementFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
      builtins.readDir ./elements
    );
  in
  lib.foldl' (
    checks: file: checks // import (./elements + "/${file}") args
  ) (import ./hosts.nix args) (builtins.attrNames elementFiles)
)
