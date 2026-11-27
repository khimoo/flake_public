{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nirinit";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "amaanq";
    repo = "nirinit";
    rev = "bf634224bc897a46f8e737edf605ee9ca742673b";
    hash = "sha256-1+FMb6DixJUa4k7F8e0Sn8zZC+9bJCv7C/Ph7B/e93c=";
  };
  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

  meta = {
    description = "Window layout session manager for Niri";
    homepage = "https://github.com/amaanq/nirinit";
    license = lib.licenses.mpl20;
    mainProgram = "nirinit";
    platforms = lib.platforms.linux;
  };
})
