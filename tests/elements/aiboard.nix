{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    inputs
    purposeHome
    generatedEnvironment
    ;
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  profiles = [
    "aiboard-astra"
    "aiboard-gemini-argon"
    "aiboard-gemini-hydrogen"
    "aiboard-gemini-neon"
    "aiboard-opus"
    "aiboard-sol"
    "aiboard-vertex-argon"
    "aiboard-vertex-hydrogen"
    "aiboard-vertex-neon"
  ];
  pyYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
in
{
  aiboard-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert
          system != "x86_64-linux"
          || (
            let
              env = generatedEnvironment "test-aiboard-client" system "use_aiboard";
              clientHome = (purposeHome system "test-aiboard-client").config;
              webSvc = desktopUser.systemd.user.services.aiboard-web;
            in
            # サーバ側（nixos-desktop の pomu）
            builtins.any (p: (p.pname or "") == "aiboard") desktopUser.home.packages
            && desktopUser.home.file ? ".hermes/skills/aiboard/SKILL.md"
            && desktopUser.home.file ? ".gemini/config/skills/aiboard-observer/SKILL.md"
            && builtins.all (
              name:
              desktopUser.home.file ? ".hermes/profiles/${name}/SOUL.md"
              && desktopUser.home.file ? ".hermes/profiles/${name}/.no-bundled-skills"
            ) profiles
            && desktopUser.home.activation ? aiboardProfiles
            && lib.hasInfix "/home/pomu/.config/aiboard/vertex-provider.yaml"
              desktopUser.home.activation.secrets.data
            && webSvc.Install.WantedBy == [ "default.target" ]
            && lib.hasInfix "--port 15280" (builtins.concatStringsSep " " webSvc.Service.ExecStart)
            && lib.any (lib.hasPrefix "PATH=") webSvc.Service.Environment
            # クライアント側（use_aiboard）
            && env == {
              AIBOARD_SERVER = "desktop-ts";
              AIBOARD_SERVER_PORT = "15280";
              AIBOARD_LOCAL_PORT = "25280";
            }
            && clientHome.home.file ? ".gemini/config/skills/aiboard-observer/SKILL.md"
            && !(clientHome.systemd.user.services ? aiboard-web)
            && !(clientHome.home.activation ? aiboardProfiles)
          );
        pkgs.runCommand "aiboard-contracts"
          {
            nativeBuildInputs = [ pyYaml ];
          }
          ''
            python3 - <<'PY'
            import json, os, stat, subprocess, tempfile, yaml
            from pathlib import Path

            script = "${../../modules/home-manager/aiboard/sync-profiles.py}"
            with tempfile.TemporaryDirectory() as td:
                home = Path(td) / "home"
                home.mkdir()
                manifest = {
                    "aiboard-sol": {
                        "config": {
                            "model": {"default": "gpt-6.2-sol", "provider": "openai-codex"},
                            "skills": {"write_approval": True},
                            "memory": {"memory_enabled": False},
                        },
                        "uses_vertex_secret": False,
                    },
                    "aiboard-vertex-neon": {
                        "config": {
                            "model": {"default": "google/gemini-4-neon", "provider": "custom:vertexcloud"},
                            "skills": {"write_approval": True},
                            "memory": {"memory_enabled": False},
                        },
                        "uses_vertex_secret": True,
                    },
                    "aiboard-symlink": {
                        "config": {"model": {"default": "x"}},
                        "uses_vertex_secret": False,
                    },
                }
                mpath = Path(td) / "manifest.json"
                mpath.write_text(json.dumps(manifest), encoding="utf-8")
                vpath = Path(td) / "vertex.yaml"
                vpath.write_text(
                    "vertex:\n  region: global\n  project_id: dummy-proj\nproviders:\n  vertexcloud:\n    name: Dummy\n",
                    encoding="utf-8",
                )
                # Pre-existing runtime keys must be preserved; symlinks must not be overwritten.
                sol_dir = home / ".hermes" / "profiles" / "aiboard-sol"
                sol_dir.mkdir(parents=True)
                (sol_dir / "config.yaml").write_text("_config_version: 99\ncustom_runtime: keep\n", encoding="utf-8")
                sym_dir = home / ".hermes" / "profiles" / "aiboard-symlink"
                sym_dir.mkdir(parents=True)
                sym_target = Path(td) / "untouched.yaml"
                sym_target.write_text("original: true\n", encoding="utf-8")
                (sym_dir / "config.yaml").symlink_to(sym_target)

                # Dry-run writes nothing
                r = subprocess.run(
                    ["python3", script, "--home", str(home), "--manifest", str(mpath), "--vertex-secret", str(vpath)],
                    env={**os.environ, "DRY_RUN_CMD": "echo"},
                    capture_output=True, text=True, check=True,
                )
                assert not (home / ".hermes" / "profiles" / "aiboard-vertex-neon" / "config.yaml").exists()

                # Real run merges and sets permissions
                subprocess.run(
                    ["python3", script, "--home", str(home), "--manifest", str(mpath), "--vertex-secret", str(vpath)],
                    check=True,
                )
                sol_cfg = yaml.safe_load((sol_dir / "config.yaml").read_text(encoding="utf-8"))
                assert sol_cfg["_config_version"] == 99
                assert sol_cfg["custom_runtime"] == "keep"
                assert sol_cfg["model"]["default"] == "gpt-6.2-sol"
                assert sol_cfg["skills"]["external_dirs"] == [str(home / ".hermes" / "skills")]
                assert stat.S_IMODE((sol_dir / "config.yaml").stat().st_mode) == 0o644

                v_cfg_path = home / ".hermes" / "profiles" / "aiboard-vertex-neon" / "config.yaml"
                v_cfg = yaml.safe_load(v_cfg_path.read_text(encoding="utf-8"))
                assert v_cfg["vertex"]["project_id"] == "dummy-proj"
                assert v_cfg["providers"]["vertexcloud"]["name"] == "Dummy"
                assert v_cfg["_config_version"] == 52
                assert stat.S_IMODE(v_cfg_path.stat().st_mode) == 0o600

                # Symlink untouched
                assert (sym_dir / "config.yaml").is_symlink()
                assert sym_target.read_text(encoding="utf-8") == "original: true\n"

                # Idempotent re-run
                before = v_cfg_path.read_text(encoding="utf-8")
                subprocess.run(
                    ["python3", script, "--home", str(home), "--manifest", str(mpath), "--vertex-secret", str(vpath)],
                    check=True,
                )
                assert v_cfg_path.read_text(encoding="utf-8") == before
            PY
            echo "aiboard contracts passed" > "$out"
          ''
      );
    })
    // {
      elements = [
        "connect_ssh"
        "find_home_server"
        "hermes_agent"
        "secrets"
        "serve_aiboard"
        "use_aiboard"
      ];
      hosts = [
        "nixos-desktop"
      ];
    };
}
