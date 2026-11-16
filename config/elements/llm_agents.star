def config():
    return {"nixos_imports": [repoModule("modules/shared/llm-agents-cache.nix")]}

def user_config():
    return {"home_imports": [repoModule("modules/shared/llm-agents-cache.nix")]}
