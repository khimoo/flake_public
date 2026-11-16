{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) inputs mkTestHome systemAssertionsHold;
  configuredPkgs = import inputs.nixpkgs {
    inherit system;
    inherit (helpers.configurations) overlays;
    config.allowUnfree = true;
  };
  upstream = inputs.llm-agents.packages.${system};
  cache = (import (inputs.llm-agents + "/flake.nix")).nixConfig;
  cacheEnabled =
    config:
    builtins.all (url: builtins.elem url (config.nix.settings.extra-substituters or [ ]))
      cache.extra-substituters
    && builtins.all (key: builtins.elem key (config.nix.settings.extra-trusted-public-keys or [ ]))
      cache.extra-trusted-public-keys;
  desktop = inputs.self.nixosConfigurations.nixos-desktop.config;
  wsl = inputs.self.nixosConfigurations.nixos-work-wsl.config;
  standaloneHome = mkTestHome system [ ../../modules/shared/llm-agents-cache.nix ];
in
{
  llm_agents-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert configuredPkgs.codex.outPath == upstream.codex.outPath;
        assert configuredPkgs.antigravity-cli.outPath == upstream.antigravity-cli.outPath;
        assert configuredPkgs.claude-code.paths == [ upstream.claude-code.outPath ];
        assert cacheEnabled desktop;
        assert cacheEnabled desktop.home-manager.users.pomu;
        assert !(cacheEnabled wsl);
        assert systemAssertionsHold standaloneHome.config;
        assert cacheEnabled standaloneHome.config;
        pkgs.runCommand "llm_agents-contracts" { } ''
          touch "$out"
        ''
      );
    })
    // {
      elements = [
        "llm_agents"
        "claude_code"
        "codex"
        "antigravity_cli"
      ];
    };
}
