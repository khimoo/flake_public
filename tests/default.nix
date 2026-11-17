{ inputs, configurations }:
let
  inherit (inputs.nixpkgs) lib;
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
  # 実在と架空のホスト、config/elements、持ち主の値 owner（TOML の本文）を合わせた設定ディレクトリ。
  configDirWith =
    owner:
    inputs.nixpkgs.legacyPackages.x86_64-linux.runCommand "test-config" { inherit owner; } ''
      mkdir -p "$out/hosts"
      ln -s ${../config/elements} "$out/elements"
      cp ${../config/hosts}/*.toml ${./hosts}/*.toml "$out/hosts/"
      printf '%s' "$owner" > "$out/owner.toml"
    '';
  configDir = configDirWith (builtins.readFile ./owner.toml);
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
          }
          (import ../modules/home-manager/confgen.nix {
            host = "test-darwin";
            user = "test";
            inherit system configDir;
            generatorPkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
          })
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
  rejectsPurpose = rejectsPurposeIn configDir;
  # 持ち主の値を差し替えた設定ディレクトリで、生成が message で止まることを確かめる。
  rejectsPurposeWithOwner = owner: rejectsPurposeIn (configDirWith owner);
  rejectsPurposeIn =
    configDir: name: system: message:
    let
      selected = hostForSystem system name;
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
          if confgen build ${configDir} ${lib.escapeShellArg selected} ${lib.escapeShellArg system} result.nix > log 2>&1; then
            cat log
            exit 1
          fi
          cat log
          grep -F -- ${lib.escapeShellArg message} log
          printf passed > "$out"
        ''
    ) == "passed";
  allAssertions = home: builtins.all (a: a.assertion) home.config.assertions;
  generatedHome =
    host: system:
    (import
      (
        (import ../lib/confgen.nix {
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
          inherit configDir;
        }).generate
          host
          system
      )
      {
        inherit inputs;
        repoRoot = ../.;
      }
    ).homes.test;
  generatedEnvironment =
    host: system: name:
    let
      testPkgs =
        (import inputs.nixpkgs {
          inherit system;
          inherit (configurations) overlays;
          config.allowUnfree = true;
        })
        // {
          writeShellApplication = args: args // { __toString = _: "/shell-app"; };
        };
      args = {
        inherit lib;
        pkgs = testPkgs;
        config = { };
      };
      element = builtins.head (
        builtins.filter (m: (m args)._file == "config/elements/${name}.star")
          (generatedHome host system).imports
      );
      settings = (element args).config.contents;
      packages = (builtins.head (builtins.filter (s: s ? home.packages) settings)).home.packages;
    in
    (builtins.head packages).runtimeEnv;
  neovimFeatures =
    system:
    let
      testPkgs = import inputs.nixpkgs {
        inherit system;
        inherit (configurations) overlays;
        config.allowUnfree = true;
      };
      generated =
        (import
          (
            (import ../lib/confgen.nix {
              pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
              inherit configDir;
            }).generate
              (hostForSystem system "test-neovim-features")
              system
          )
          {
            inherit inputs;
            repoRoot = ../.;
          }
        ).homes.pomu;
      generatedLib = lib // {
        generators = lib.generators // {
          toLua = _: value: builtins.toJSON { inherit (value) features; };
        };
      };
      element = builtins.head (
        builtins.filter (
          m:
          (m {
            config = { };
            lib = generatedLib;
            pkgs = testPkgs;
          })._file == "config/elements/neovim.star"
        ) generated.imports
      );
      settings =
        (element {
          config = { };
          lib = generatedLib;
          pkgs = testPkgs;
        }).config.contents;
      text =
        (builtins.head (builtins.filter (s: s ? xdg.dataFile."nvim/nix/features.lua".text) settings))
        .xdg.dataFile."nvim/nix/features.lua".text;
    in
    (builtins.fromJSON (lib.removePrefix "return " text)).features;
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
    agentSyncText =
      (lib.findFirst (
        p: (p.name or "") == "agent-sync"
      ) (throw "agent-sync is not installed") activationHome.config.home.packages).text;
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
        rejectsPurposeWithOwner
        allAssertions
        neovimFeatures
        generatedEnvironment
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
