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
    activationDepsExist
    hasLauncher
    ;
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  spin713User = inputs.self.nixosConfigurations.nixos-spin713.config.home-manager.users.pomu;
  wslUser = inputs.self.nixosConfigurations.nixos-work-wsl.config.home-manager.users.nixos;
  findPkg =
    user: name:
    lib.findFirst (p: (p.name or "") == name) (throw "${name} is not installed") user.home.packages;
in
{
  dotfiles-mode-script =
    (lib.lazyDerivation {
      derivation = pkgs.runCommand "dotfiles-mode-script" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        DOTFILES_MODE_SCRIPT=${../../modules/home-manager/dev/dotfiles-mode.py} python ${../dotfiles-mode.py}
        touch "$out"
      '';
    })
    // {
      elements = [ "dotfiles_mode" ];
    };

  dotfiles-mode-contracts =
    (lib.lazyDerivation {
      derivation =
        if system != "x86_64-linux" then
          pkgs.runCommand "dotfiles-mode-contracts-skipped" { } "touch $out"
        else
          let
            desktopBin = findPkg desktopUser "dotfiles-mode";
            spin713Bin = findPkg spin713User "dotfiles-mode";
            wslBin = findPkg wslUser "dotfiles-mode";
          in
          assert activationDepsExist desktopUser.home.activation;
          assert activationDepsExist spin713User.home.activation;
          assert activationDepsExist wslUser.home.activation;
          assert desktopUser.home.activation ? dotfilesMode;
          assert spin713User.home.activation ? dotfilesMode;
          assert wslUser.home.activation ? dotfilesMode;
          assert hasLauncher desktopUser "dotfiles-mode";
          assert hasLauncher spin713User "dotfiles-mode";
          assert hasLauncher wslUser "dotfiles-mode";
          pkgs.runCommand "dotfiles-mode-contracts" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            check_link() {
              actual=$(readlink "$1")
              if [ "$actual" != "$2" ]; then
                echo "expected $1 -> $2, got $actual" >&2
                exit 1
              fi
            }
            check_link ${desktopUser.xdg.configFile."niri/config.kdl".source} /home/pomu/.local/state/dotfiles-mode/links/niri
            check_link ${desktopUser.xdg.configFile."quickshell/hub".source} /home/pomu/.local/state/dotfiles-mode/links/quickshell
            check_link ${desktopUser.xdg.configFile."kanshi".source} /home/pomu/.local/state/dotfiles-mode/links/kanshi
            check_link ${desktopUser.xdg.configFile."kitty/kitty.conf".source} /home/pomu/.local/state/dotfiles-mode/links/kitty
            check_link ${desktopUser.xdg.configFile."nvim".source} /home/pomu/.local/state/dotfiles-mode/links/nvim
            check_link ${spin713User.xdg.configFile."niri/config.kdl".source} /home/pomu/.local/state/dotfiles-mode/links/niri
            check_link ${wslUser.xdg.configFile."kitty/kitty.conf".source} /home/nixos/.local/state/dotfiles-mode/links/kitty
            check_link ${wslUser.xdg.configFile."nvim".source} /home/nixos/.local/state/dotfiles-mode/links/nvim

            python3 - ${desktopBin}/bin/dotfiles-mode ${spin713Bin}/bin/dotfiles-mode ${wslBin}/bin/dotfiles-mode <<'PY'
            import json
            import os
            import re
            import subprocess
            import sys

            def inspect_bin(bin_path, expected_names):
                out = subprocess.check_output([bin_path, "--status-json"], text=True)
                payload = json.loads(out)
                names = [i["name"] for i in payload["items"]]
                assert names == expected_names, f"{bin_path}: expected {expected_names}, got {names}"
                wrapper = open(bin_path, encoding="utf-8").read()
                m = re.search(r"DOTFILES_MODE_MANIFEST=['\"]?(/nix/store/[^\s'\"]+)", wrapper)
                assert m, f"manifest path not found in {bin_path}"
                manifest = json.load(open(m.group(1), encoding="utf-8"))
                for item in manifest["items"]:
                    assert os.path.exists(item["store"]), f"missing store path in closure: {item['store']}"

            inspect_bin(sys.argv[1], ["niri", "quickshell", "kanshi", "kitty", "nvim"])
            inspect_bin(sys.argv[2], ["niri", "quickshell", "kanshi", "kitty", "nvim"])
            inspect_bin(sys.argv[3], ["kitty", "nvim"])
            PY
            touch "$out"
          '';
    })
    // {
      elements = [
        "dotfiles_mode"
        "neovim"
        "niri_config"
        "kitty"
        "quickshell_hub"
        "display_layout"
      ];
      hosts = [
        "nixos-desktop"
        "nixos-spin713"
        "nixos-work-wsl"
      ];
    };
}
