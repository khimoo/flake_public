{
  lib,
  dbus,
  fetchFromGitHub,
  installShellFiles,
  libdisplay-info,
  libglvnd,
  libinput,
  libxkbcommon,
  libgbm,
  pango,
  pipewire,
  pkg-config,
  rustPlatform,
  seatd,
  stdenv,
  systemdLibs,
  wayland,
  withDbus ? true,
  withScreencastSupport ? true,
  withSystemd ? true,
}:

# niri-wm/niri#3800（仮想出力と headless backend）の先頭 commit。nixpkgs の niri 26.04 には当たらない。
# 組み立て方は pkgs/by-name/ni/niri/package.nix に合わせる。
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "niri-virtual-outputs";
  version = "26.04-pr3800";

  src = fetchFromGitHub {
    owner = "willybarret";
    repo = "niri";
    rev = "7fd585dd44ed67644977dd9561bb6e8b3837f8f7";
    hash = "sha256-OWF03QF62Q8HJ3fCme3I3GX7dKX9YU+JD7bhTiIzfQ4=";
  };

  cargoHash = "sha256-Yqvambc4F7PdGkGxrxp5xD6PqAEAWmMgqOYZRY+TIBA=";

  outputs = [
    "out"
    "doc"
  ];

  postPatch = ''
    patchShebangs resources/niri-session
    substituteInPlace resources/niri.service \
      --replace-fail 'niri' "$out/bin/niri"
  '';

  nativeBuildInputs = [
    installShellFiles
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    libdisplay-info
    libglvnd # For libEGL
    libinput
    libxkbcommon
    libgbm
    pango
    seatd
    wayland # For libwayland-client
  ]
  ++ lib.optional (withDbus || withScreencastSupport || withSystemd) dbus
  ++ lib.optional withScreencastSupport pipewire
  ++ lib.optional withSystemd systemdLibs; # Includes libudev

  buildFeatures =
    lib.optional withDbus "dbus"
    ++ lib.optional withScreencastSupport "xdp-gnome-screencast"
    ++ lib.optional withSystemd "systemd";
  buildNoDefaultFeatures = true;

  postInstall = ''
    install -Dm0644 README.md resources/default-config.kdl -t $doc/share/doc/niri
    mv docs/wiki $doc/share/doc/niri/wiki

    install -Dm0644 resources/niri.desktop -t $out/share/wayland-sessions
  ''
  + lib.optionalString withDbus ''
    install -Dm0644 resources/niri-portals.conf -t $out/share/xdg-desktop-portal
  ''
  + lib.optionalString withSystemd ''
    install -Dm0755 resources/niri-session -t $out/bin
    install -Dm0644 resources/niri{-shutdown.target,.service} -t $out/lib/systemd/user
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd niri \
      --bash <($out/bin/niri completions bash) \
      --fish <($out/bin/niri completions fish) \
      --nushell <($out/bin/niri completions nushell) \
      --zsh <($out/bin/niri completions zsh)
  '';

  env = {
    # Force linking with libEGL and libwayland-client
    # so they can be discovered by `dlopen()`
    RUSTFLAGS = toString (
      map (arg: "-C link-arg=" + arg) [
        "-Wl,--push-state,--no-as-needed"
        "-lEGL"
        "-lwayland-client"
        "-Wl,--pop-state"
      ]
    );

    NIRI_BUILD_COMMIT = "PR3800-7fd585d";
  };

  checkFlags = [ "--skip=::egl" ];

  passthru.providedSessions = [ "niri" ];

  meta = {
    description = "Scrollable-tiling Wayland compositor with virtual outputs (niri PR #3800)";
    homepage = "https://github.com/niri-wm/niri/pull/3800";
    license = lib.licenses.gpl3Only;
    mainProgram = "niri";
    platforms = lib.platforms.linux;
  };
})
