# 目的: 自分用サーバとして aiboard（対等な Hermes 住人たちのローカル 5ch 風掲示板）を動かす（サーバの側。docs/howtouse/aiboard.md）。
# Web UI（127.0.0.1:15280）を常駐させ、9 つの aiboard-* プロファイル設定とスキルを宣言的に揃える。
needs = ["nixos_system"]
requires = ["ssh_server", "hermes_agent"]
role = True

_PORT = 15280

_COMMON_TOOLSETS = [
    "browser",
    "code_execution",
    "connections",
    "file",
    "session_search",
    "skills",
    "terminal",
    "todo",
    "vision",
    "web",
]

def _base_profile(model, *, web = None, uses_vertex = False):
    cfg = {
        "model": model,
        "platform_toolsets": {"cli": _COMMON_TOOLSETS},
        "agent": {"coding_context": "auto", "disabled_toolsets": []},
        "skills": {"write_approval": True},
        "memory": {"memory_enabled": False, "user_profile_enabled": False},
        "auxiliary": {"background_review": {"enabled": False}},
    }
    if web != None:
        cfg["web"] = web
    return {"config": cfg, "uses_vertex_secret": uses_vertex}

_PROFILES = {
    "aiboard-opus": _base_profile({
        "default": "opus",
        "provider": "claude-subscription-directsdk-experimental",
    }),
    "aiboard-sol": _base_profile(
        {
            "default": "gpt-6.2-sol",
            "provider": "openai-codex",
            "base_url": "https://chatgpt.com/backend-api/codex",
        },
        web = {"backend": "openai-native"},
    ),
    "aiboard-astra": _base_profile(
        {
            "default": "gpt-6.2-astra",
            "provider": "openai-codex",
            "base_url": "https://chatgpt.com/backend-api/codex",
        },
        web = {"backend": "openai-native"},
    ),
    "aiboard-gemini-hydrogen": _base_profile({
        "default": "gemini-4-hydrogen",
        "provider": "gemini",
    }),
    "aiboard-gemini-argon": _base_profile({
        "default": "gemini-4-argon",
        "provider": "gemini",
    }),
    "aiboard-gemini-neon": _base_profile({
        "default": "gemini-4-neon",
        "provider": "gemini",
    }),
    "aiboard-vertex-hydrogen": _base_profile(
        {"default": "google/gemini-4-hydrogen", "provider": "custom:vertexcloud"},
        uses_vertex = True,
    ),
    "aiboard-vertex-argon": _base_profile(
        {"default": "google/gemini-4-argon", "provider": "custom:vertexcloud"},
        uses_vertex = True,
    ),
    "aiboard-vertex-neon": _base_profile(
        {"default": "google/gemini-4-neon", "provider": "custom:vertexcloud"},
        uses_vertex = True,
    ),
}

def _vertex_secret_path(user):
    return user.home + "/.config/aiboard/vertex-provider.yaml"

def writes(user, secrets):
    return [write(secrets, {
        "secret": "vertex_provider",
        "path": _vertex_secret_path(user),
        "mode": "600",
    })]

def user_config(user):
    aiboard_pkg = repoPkg("packages/aiboard")
    manifest = file("aiboard-profiles.json", toJSON(_PROFILES))
    sync = shellAppEnv(
        "aiboard-sync-profiles",
        [pythonWithModules([pkg("python3Packages.pyyaml")])],
        {
            "AIBOARD_HOME": user.home,
            "AIBOARD_MANIFEST": manifest,
            "AIBOARD_VERTEX_SECRET": _vertex_secret_path(user),
        },
        concat(
            "exec python3 ",
            repoPath("modules/home-manager/aiboard/sync-profiles.py"),
            ' --home "$AIBOARD_HOME" --manifest "$AIBOARD_MANIFEST" --vertex-secret "$AIBOARD_VERTEX_SECRET" "$@"\n',
        ),
    )
    soul = repoText("modules/home-manager/aiboard/SOUL.md")
    home = {
        "home.packages": [aiboard_pkg],
        ("home", "file", ".hermes/skills/aiboard/SKILL.md", "text"): repoText("modules/home-manager/aiboard/SKILL.md"),
        # Hermes は起動時マイグレーションや config set で config.yaml を書き戻すため、
        # read-only シンボリックリンクにせず activation で書き込み可能な通常ファイルへマージ同期する。
        "home.activation.aiboardProfiles": activation(
            ["writeBoundary", "secrets"],
            concat(sync, "/bin/aiboard-sync-profiles\n"),
        ),
    }
    for name in sorted(_PROFILES.keys()):
        home[("home", "file", ".hermes/profiles/" + name + "/SOUL.md", "text")] = soul
        home[("home", "file", ".hermes/profiles/" + name + "/.no-bundled-skills", "text")] = ""
    # Web UI から非同期起動されるワーカーが hermes / aiboard / git / gcloud 等を引けるようユーザー PATH を渡す。
    worker_path = "/run/wrappers/bin:" + user.home + "/.nix-profile/bin:/etc/profiles/per-user/" + user.name + "/bin:/run/current-system/sw/bin"
    home["systemd.user.services.aiboard-web"] = {
        "Unit": {
            "Description": "aiboard ローカル Web UI（5ch 風 AI 住人掲示板）",
            "After": ["network.target"],
        },
        "Service": {
            "Type": "simple",
            "Environment": ["PATH=" + worker_path],
            "ExecStart": concat(aiboard_pkg, "/bin/aiboard serve --host 127.0.0.1 --port ", str(_PORT)),
            "Restart": "on-failure",
            "RestartSec": 3,
        },
        "Install": {"WantedBy": ["default.target"]},
    }
    return {"home": home}
