# Public Home Manager interface. Personal values belong to profiles/home or a user's homeFile.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.local.profile;
  absolutePath = types.strMatching "/.*";
  # Launcher name suffix and file stem; keeps generated paths and executables free of shell metacharacters.
  profileName = types.strMatching "[A-Za-z0-9_-]+";
  unique = xs: lib.unique xs == xs;
  optionalPath =
    description:
    mkOption {
      type = types.nullOr absolutePath;
      default = null;
      inherit description;
    };
  optionalUrl =
    description:
    mkOption {
      type = types.nullOr types.str;
      default = null;
      inherit description;
    };
  pairs = [
    {
      root = cfg.zettelkastenRoot;
      repo = cfg.zettelkastenRepoUrl;
    }
    {
      root = cfg.agentConfigRoot;
      repo = cfg.agentConfigRepo;
    }
    {
      root = cfg.vaultSkeletonRepo;
      repo = cfg.vaultSkeletonRepoUrl;
    }
    {
      root = cfg.llmWikisRoot;
      repo = cfg.llmWikisRepoUrl;
    }
  ];
  inHome = path: path == null || lib.hasPrefix "${config.home.homeDirectory}/" path;
in
{
  options.local.profile = {
    flakeRoot = mkOption {
      type = absolutePath;
      default = "${config.home.homeDirectory}/sagyo/flake_public";
      description = "Live checkout used by Neovim and terminal configuration symlinks.";
    };
    gitUsername = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Git author name. Null leaves the identity to the user.";
    };
    gitUserEmail = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Git author email. Null leaves the identity to the user.";
    };
    standalone = mkOption {
      type = types.bool;
      default = true;
      description = "Whether Home Manager owns its nixpkgs configuration; set by the host factory.";
    };
    features = lib.genAttrs [
      "gui"
      "gnome"
      "ime"
      "audio"
      "referenceSync"
      "zettelkastenSync"
      "obsidian"
    ] (name: lib.mkEnableOption "${name} in this user's environment");
    zettelkastenRoot = optionalPath "User's vault checkout.";
    zettelkastenRepoUrl = optionalUrl "Vault clone URL; null means manual clone.";
    agentConfigRoot = optionalPath "User's agent (Claude Code / Codex) configuration checkout.";
    agentConfigRepo = optionalUrl "Agent configuration clone URL; null means manual clone.";
    agentProfiles = mkOption {
      type = types.submodule {
        options = {
          claude = mkOption {
            type = types.listOf profileName;
            default = [ ];
            description = "Claude Code profile names; each needs <agentConfigRoot>/claude/profiles/<name>.json and yields a `claude-<name>` launcher.";
          };
          codex = mkOption {
            type = types.listOf profileName;
            default = [ ];
            description = "Codex profile names; each needs <agentConfigRoot>/codex/<name>.config.toml and yields a `codex-<name>` launcher.";
          };
        };
      };
      default = { };
      description = "Per-model launcher profiles read from the agent configuration checkout.";
    };
    vaultSkeletonRepo = optionalPath "Workflow checkout used by mirror-vault.";
    vaultSkeletonRepoUrl = optionalUrl "Workflow clone URL; null means manual clone.";
    llmWikisRoot = optionalPath "User's LLM Wiki checkout.";
    llmWikisRepoUrl = optionalUrl "LLM Wiki clone URL; null means manual clone.";
    lanSsh = lib.mkEnableOption "distribution of the shared LAN SSH key to this user";
    privateRepos = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            url = mkOption {
              type = types.str;
              description = "Clone URL.";
            };
            dest = mkOption {
              type = absolutePath;
              description = "Clone destination in this user's home.";
            };
          };
        }
      );
      default = [ ];
      description = "Additional repositories to clone; named checkout options also contribute here.";
    };
    sshKeys = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            secret = mkOption {
              type = types.strMatching "[A-Za-z0-9_-]+";
              description = "Sops secret key.";
            };
            name = mkOption {
              type = types.strMatching "[A-Za-z0-9_][A-Za-z0-9_.-]*";
              description = "Filename below ~/.ssh.";
            };
          };
        }
      );
      default = [ ];
      description = "SSH keys to restore; GitHub and LAN requirements are added automatically.";
    };
  };

  config = {
    local.profile.privateRepos = map (p: {
      url = p.repo;
      dest = p.root;
    }) (builtins.filter (p: p.root != null && p.repo != null) pairs);
    local.profile.sshKeys =
      lib.optional (cfg.privateRepos != [ ]) {
        secret = "git_ssh_key";
        name = "id_github";
      }
      ++ lib.optional cfg.lanSsh {
        secret = "lan_ssh_key";
        name = "id_lan";
      };
    assertions = [
      {
        assertion = builtins.all (p: p.repo == null || p.root != null) pairs;
        message = "local.profile: a clone URL requires its corresponding checkout path.";
      }
      {
        assertion =
          (cfg.agentProfiles.claude == [ ] && cfg.agentProfiles.codex == [ ]) || cfg.agentConfigRoot != null;
        message = "local.profile: agentProfiles require agentConfigRoot.";
      }
      {
        assertion = unique cfg.agentProfiles.claude && unique cfg.agentProfiles.codex;
        message = "local.profile: agentProfiles names must be unique per harness.";
      }
      {
        assertion = builtins.all inHome (
          [
            cfg.zettelkastenRoot
            cfg.agentConfigRoot
            cfg.vaultSkeletonRepo
            cfg.llmWikisRoot
          ]
          ++ map (r: r.dest) cfg.privateRepos
        );
        message = "local.profile: mutable checkouts must belong to this user's home directory.";
      }
      {
        assertion =
          !(cfg.features.zettelkastenSync || cfg.features.referenceSync || cfg.features.obsidian)
          || cfg.zettelkastenRoot != null;
        message = "local.profile: vault features require zettelkastenRoot.";
      }
      {
        assertion = !(cfg.features.gnome || cfg.features.ime) || cfg.features.gui;
        message = "local.profile: gnome and ime require gui.";
      }
      {
        assertion =
          pkgs.stdenv.isLinux
          || !(
            cfg.features.gui
            || cfg.features.audio
            || cfg.features.zettelkastenSync
            || cfg.features.referenceSync
            || cfg.features.obsidian
          );
        message = "local.profile: the desktop, audio and vault profiles currently support Linux only.";
      }
      {
        assertion =
          builtins.length (lib.unique (map (r: r.dest) cfg.privateRepos)) == builtins.length cfg.privateRepos;
        message = "local.profile: duplicate clone destination.";
      }
      {
        assertion =
          builtins.length (lib.unique (map (k: k.name) cfg.sshKeys)) == builtins.length cfg.sshKeys;
        message = "local.profile: duplicate SSH key filename.";
      }
    ];
  };
}
