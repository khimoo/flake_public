inputs: final: prev: {
  inherit (inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system})
    claude-code
    codex
    antigravity-cli
    hermes-agent
    hermes-desktop
    ;
}
