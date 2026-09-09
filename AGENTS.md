# Repository instructions

## Scope and workflow

This repository manages NixOS hosts, Home Manager environments and live editor/terminal configuration.
Read [README](README.md) and the relevant [architecture](docs/architecture/README.md) / [usage](docs/howtouse/README.md) documents before changing a feature.

- Investigation and review do not authorize edits. An explicit implementation request authorizes the necessary edits and verification; do not ask again for each file.
- Preserve unrelated user changes. Diagnose failures before replacing an approach; distinguish evaluation, build, activation and runtime failures.
- Do not run `nixos-rebuild`, `home-manager switch`, or another generation-switch command. Prepare and verify changes; the user applies them.
- `nix eval`, `nix build`, and `nix flake check` are allowed for verification. They can fetch/build store dependencies even during evaluation; they do not switch generations.
- Never put plaintext secrets in this repository, tool output or conversation. Never use `sudo -S` to pass a password. For an authorized operation requiring root without switching generations, explain the operation and use `pkexec` where available; respect the execution environment's approval policy.

## Configuration boundaries

- `flake.nix` selects hosts and standalone environments; `lib/configurations.nix` assembles them.
- `hosts/` owns hardware and machine policy. `modules/nixos/` owns OS mechanisms.
- `modules/home-manager/` owns user mechanisms. `local.profile` is the typed interface, defined in `modules/home-manager/profile.nix`.
- Personal Git identity, mutable checkout paths, secrets and optional workflows belong in that user's home module or `profiles/home/`. Never pass one user's profile to all Home Manager users.
- Use typed options, `mkEnableOption`, `mkIf`, `mkDefault` and assertions for settings that users may change. Feature toggles are normal Nix composition; do not replace them merely to follow generic coupling rankings.
- Keep imports static. Conditions depending on `config` belong in `mkIf`; avoid `optionalAttrs config...` when it determines module structure.
- Keep package provenance and compatibility patches in `overlays/` or `packages/`; document evidence and removal conditions.
- Activation code must specify supported platforms, dry-run behavior, idempotence and recovery after interruption. Failure must not leave a partial result that is mistaken for completion.
- Live symlinks for Neovim, terminals and Claude settings intentionally bypass generation rollback. Changes to their source files may affect running user workflows immediately.

## Verification

Run `bash scripts/check.sh` after configuration changes. It checks the current-system flake outputs, every standalone Home Manager generation, Linux/Darwin module contracts, local documentation links and whitespace, then builds native checks. See [validation](docs/howtouse/validation.md) for scope and commands.

- For a regression, add a focused check at the boundary that failed (platform support, user isolation, activation failure), not a test that simply repeats implementation details.
- For package changes, build the changed package and run its existing install checks.
- For editor changes, check the affected Lua/configuration and document any runtime checks the user must perform.
- Report precisely what passed and what requires a real host or manual activation. Never describe evaluation success as proof that macOS activation works.
- For unfamiliar upstream behavior, consult official documentation or upstream source and record the relevant version/revision. Separate observed facts from hypotheses.

## Documentation

The repository owns its documentation rules; do not depend on a private agent memory file.

- Usage and procedures: `docs/howtouse/`. Rationale and tradeoffs: `docs/architecture/`.
- Neovim-specific keys/plugins: `modules/home-manager/dev/neovim/config/docs/`.
- Update the affected usage and architecture documents with an implementation change, plus index entries when files are added or removed. Add reciprocal links when a pair exists.
- Configuration is the source of truth for behavior. Detailed feature docs describe it; indexes link to details rather than copying full tables.
- Use local file links for implementation references. Keep commands and examples aligned with the current typed interface.
- Mark proposals as unimplemented. Record evidence, uncertainty, and conditions for revisiting a decision.

`AGENTS.md` is the common instruction source. `CLAUDE.md` imports it; do not maintain a second copy of these rules.
