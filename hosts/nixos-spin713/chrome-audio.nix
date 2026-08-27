# chrome-device.nix
{ config, pkgs, lib, ... }:

let
  cb-ucm-conf = with pkgs;
    alsa-ucm-conf.overrideAttrs {
      wttsrc = fetchFromGitHub {
        owner = "WeirdTreeThing";
        repo = "alsa-ucm-conf-cros";
        rev = "7b1470d9261674f7eeb29d18eb9b5375bde80ebb";
        hash = "sha256-coYSt+Jhbeb/wBvtFTOApxNI89Dw2/wI4r1iOKZUplE=";
      };
      unpackPhase = ''
        runHook preUnpack
        tar xf "$src"
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/alsa
        cp -r alsa-ucm*/ucm2 $out/share/alsa
        runHook postInstall
      '';
    };
in {
  boot = {
    extraModprobeConfig = ''
      options snd-intel-dspcfg dsp_driver=4
    '';
  };
  services.keyd = {
    enable = true;
    keyboards.internal = {
      ids = [
        "k:0001:0001"
        "k:18d1:5044"
        "k:18d1:5052"
        "k:0000:0000"
        "k:18d1:5050"
        "k:18d1:504c"
        "k:18d1:503c"
        "k:18d1:5030"
        "k:18d1:503d"
        "k:18d1:505b"
        "k:18d1:5057"
        "k:18d1:502b"
        "k:18d1:5061"
      ];
      settings = {
        main = {
          leftcontrol = "leftmeta";
          leftmeta = "leftcontrol";
          f1 = "back";
          f2 = "forward";
          f3 = "refresh";
          f4 = "f11";
          f5 = "scale";
          f6 = "brightnessdown";
          f7 = "brightnessup";
          f8 = "mute";
          f9 = "volumedown";
          f10 = "volumeup";
          back = "back";
          forward = "forward";
          refresh = "refresh";
          zoom = "f11";
          scale = "scale";
          brightnessdown = "brightnessdown";
          brightnessup = "brightnessup";
          mute = "mute";
          volumedown = "volumedown";
          volumeup = "volumeup";
          sleep = "coffee";
        };
        meta = {
          f1 = "f1";
          f2 = "f2";
          f3 = "f3";
          f4 = "f4";
          f5 = "f5";
          f6 = "f6";
          f7 = "f7";
          f8 = "f8";
          f9 = "f9";
          f10 = "f10";
          back = "f1";
          forward = "f2";
          refresh = "f3";
          zoom = "f4";
          scale = "f5";
          brightnessdown = "f6";
          brightnessup = "f7";
          mute = "f8";
          volumedown = "f9";
          volumeup = "f10";
          sleep = "f12";
        };
        alt = {
          backspace = "delete";
          # meta = "capslock";
          brightnessdown = "kbdillumdown";
          brightnessup = "kbdillumup";
          f6 = "kbdillumdown";
          f7 = "kbdillumup";
        };
        control = {
          f5 = "print";
          scale = "print";
        };
        controlalt = { backspace = "C-A-delete"; };
      };
    };
  };
  # タイピング中はタッチパッドを無効化
  environment.etc."libinput/local-overrides.quirks".text = pkgs.lib.mkForce ''
    [Serial Keyboards]
    MatchUdevType=keyboard
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
  '';

  # add your audio setup modprobes here

  environment = {
    systemPackages = with pkgs; [ sof-firmware alsa-utils ];
    sessionVariables.ALSA_CONFIG_UCM2 = "${cb-ucm-conf}/share/alsa/ucm2";
    # AUDIO SETUP FOR < 23.11 AND UNSTABLE
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  # AUDIO SETUP FOR > 24.05
  services.pipewire.wireplumber.configPackages = [
    (pkgs.writeTextDir "share/wireplumber/main.lua.d/51-avs-dmic.lua" ''
      rule = {
        matches = {
          {
            { "node.nick", "equals", "Internal Microphone" },
          },
        },
        apply_properties = {
          ["audio.format"] = "S16LE",
        },
      }

      table.insert(alsa_monitor.rules, rule)
    '')
  ];

  system.replaceDependencies.replacements = [({
    original = pkgs.alsa-ucm-conf;
    replacement = cb-ucm-conf;
  })];
}
