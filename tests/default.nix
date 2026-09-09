{ inputs, configurations }:
let
  inherit (inputs.nixpkgs) lib;
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
  fixture = configurations.mkSystem {
    hostname = "example";
    system = "x86_64-linux";
    timezone = "Asia/Tokyo";
    stateVersion = "25.11";
    hostModule = ../examples/new-host.nix;
    users = [
      {
        username = "alice";
        homeModules = [
          {
            local.profile = {
              gitUsername = "Alice";
              gitUserEmail = "alice@example.org";
              claudeConfigRoot = "/home/alice/claude-config";
              claudeConfigRepo = "git@example.org:alice/config.git";
              lanSsh = true;
            };
          }
        ];
      }
      { username = "bob"; }
      {
        username = "unmanaged";
        manageHome = false;
      }
    ];
  };
  users = fixture.config.home-manager.users;
  mkTestHome =
    system: modules:
    configurations.mkHome {
      username = "test";
      inherit system modules;
      stateVersion = "25.11";
    };
  allAssertions = home: builtins.all (a: a.assertion) home.config.assertions;
in
lib.genAttrs systems (
  system:
  let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    home = mkTestHome system [ ];
    activationHome = mkTestHome "x86_64-linux" [
      {
        local.profile = {
          claudeConfigRoot = "/home/test/config";
          claudeConfigRepo = "git@example.org:test/config.git";
        };
      }
    ];
    # These are shell-source tests using fake tools, not builds of the target
    # platform packages. Discard context only for these mocked script strings.
    snippet =
      name:
      builtins.unsafeDiscardStringContext (
        builtins.replaceStrings
          [
            "/home/test"
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.git)
            (toString inputs.nixpkgs.legacyPackages.x86_64-linux.sops)
          ]
          [ "@test-home@" "@tools@" "@tools@" ]
          activationHome.config.home.activation.${name}.data
      );
    rejects =
      module:
      let
        result = builtins.tryEval (allAssertions (mkTestHome system [ module ]));
      in
      !result.success || !result.value;
    # Force the typed option directly: an invalid option value must fail evaluation.
    badType =
      builtins.tryEval
        (mkTestHome system [ { local.profile.features.gui = "yes"; } ]).config.local.profile.features.gui;
    unknownFeature =
      builtins.tryEval
        (mkTestHome system [ { local.profile.features.typo = true; } ]).config.local.profile.features.gui;
    contracts =
      assert allAssertions home;
      assert users.alice.local.profile.gitUsername == "Alice";
      assert users.bob.local.profile.gitUsername == null;
      assert users.bob.local.profile.gitUserEmail == null;
      assert users.bob.local.profile.privateRepos == [ ];
      assert users.bob.local.profile.sshKeys == [ ];
      assert users.bob.local.profile.claudeConfigRoot == null;
      assert users.bob.local.profile.flakeRoot == "/home/bob/sagyo/flake_public";
      assert !(users.bob.home.activation ? sshKeys);
      assert !(users.bob.home.activation ? privateRepos);
      assert !(users ? unmanaged);
      assert builtins.length users.alice.local.profile.sshKeys == 2;
      assert !(home.config.home.activation ? rustowl);
      assert (builtins.any (p: (p.pname or "") == "rustowl") home.config.home.packages) == (system == "x86_64-linux");
      assert (mkTestHome system [{ local.rustowl.enable = false; }]).config.xdg.dataFile."nvim/nix/rustowl.lua".text == "return nil";
      assert !(builtins.any (p: (p.pname or "") == "vscode") home.config.home.packages);
      assert rejects { local.profile.claudeConfigRepo = "git@example.org:test/config.git"; };
      assert rejects { local.profile.claudeConfigRoot = "/home/another-user/config"; };
      assert rejects { local.profile.features.zettelkastenSync = true; };
      assert rejects { local.profile.features.gnome = true; };
      assert rejects {
        local.profile.privateRepos = [
          {
            url = "one";
            dest = "/home/test/repo";
          }
          {
            url = "two";
            dest = "/home/test/repo";
          }
        ];
      };
      assert system == "x86_64-linux" || rejects { local.rustowl.enable = true; };
      assert !badType.success;
      assert !unknownFeature.success;
      "module contracts passed";
  in
  {
    module-contracts = pkgs.runCommand "module-contracts" { } ''
      echo ${lib.escapeShellArg contracts} > "$out"
    '';
    docs = pkgs.runCommand "documentation-links" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python ${../scripts/check-docs.py} ${../.}
      touch "$out"
    '';
    activation =
      pkgs.runCommand "activation-contracts"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.bash
          ];
          cloneScript = snippet "privateRepos";
          keysScript = snippet "sshKeys";
          passAsFile = [
            "cloneScript"
            "keysScript"
          ];
        }
        ''
          python ${./activation.py}
          touch "$out"
        '';
  }
)
