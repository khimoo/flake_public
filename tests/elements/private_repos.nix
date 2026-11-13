{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    home
    activationHome
    users
    mkTestHome
    rejectsPurpose
    activationDepsExist
    hasLauncher
    commandText
    snippet
    mockPaths
    ;
in
{
  private_repos-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert activationDepsExist activationHome.config.home.activation;
        assert lib.hasInfix "/home/bob/sagyo/flake_public"
          (lib.findFirst (
            p: (p.name or "") == "pull-repos"
          ) (throw "pull-repos is not installed") users.bob.home.packages).text;
        assert !(hasLauncher users.bob "clone-repos");
        assert hasLauncher users.alice "clone-repos";
        assert rejectsPurpose "test-duplicate-clone" "x86_64-linux"
          "private_repos: duplicate clone destination";
        assert rejectsPurpose "test-outside-clone" "x86_64-linux"
          "personal_files: destinations must live below";
        pkgs.runCommand "private_repos-contracts" { } ''
          echo "private_repos contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "agent_compression"
        "agent_links"
        "agent_sync"
        "codex_policy"
        "checkout"
        "personal_files"
        "private_repos"
        "secrets"
      ];
    };

  activation =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "activation-contracts"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.bash
            ];
            cloneScript = commandText "clone-repos";
            secretsScript = snippet "secrets";
            emptySecretsScript = mockPaths (mkTestHome "x86_64-linux" [ ]).config.home.activation.secrets.data;
            passAsFile = [
              "cloneScript"
              "secretsScript"
              "emptySecretsScript"
            ];
          }
          ''
            python ${../activation.py}
            touch "$out"
          ''
      );
    })
    // {
      elements = [
        "private_repos"
        "secrets"
      ];
    };
  # private repo を持たないユーザーでも pull-repos のビルド（shellcheck）が通ること。
  # standalone の Home Manager は評価しかしないので、ここでビルドしないと見つからない。
  pull-repos =
    (lib.lazyDerivation {
      derivation = (
        lib.findFirst (
          p: (p.name or "") == "pull-repos"
        ) (throw "pull-repos is not installed") home.config.home.packages
      );
    })
    // {
      elements = [ "private_repos" ];
    };
  # clone-repos の shellcheck。本文の動作は activation の check が偽の git で確かめる。
  clone-repos =
    (lib.lazyDerivation {
      derivation = (
        lib.findFirst (
          p: (p.name or "") == "clone-repos"
        ) (throw "clone-repos is not installed") activationHome.config.home.packages
      );
    })
    // {
      elements = [ "private_repos" ];
    };
}
