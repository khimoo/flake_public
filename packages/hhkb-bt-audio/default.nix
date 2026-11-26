{
  lib,
  fetchgit,
  rustPlatform,
  clang,
  pkg-config,
  systemdLibs,
  elfutils,
  zlib,
  libbpf,
  linuxHeaders,
  python3,
}:

rustPlatform.buildRustPackage {
  pname = "hhkb-bt-audio";
  version = "2.3.0-20260703";

  src = fetchgit {
    url = "https://gitlab.freedesktop.org/libevdev/udev-hid-bpf.git";
    rev = "bbaad639d4b2efe2a909e8b7c594b91e87704ab8";
    hash = "sha256-YvAuFAuwFSZQfZYJS9mc0aPa9tFIJxVc/UjaOAJ+qh8=";
  };

  cargoDepsName = "udev-hid-bpf";
  cargoHash = "sha256-Jje8326ESCBI/vnyv6HIKu7R2hfG7uE0d/orx15yQ/Q=";

  nativeBuildInputs = [ clang.cc pkg-config python3 ];
  buildInputs = [ systemdLibs elfutils zlib ];

  env.MESON_BUILD = "1";

  preBuild = ''
    export MESON_BINDIR="$out/bin"
    export BPF_LOOKUP_DIRS="$out/lib/firmware/hid/bpf"
  '';

  postBuild = ''
    clang -target bpf -O2 -g -fms-extensions -Wno-microsoft-anon-tag \
      -Isrc/bpf -I${./.} -I${lib.getDev libbpf}/include \
      -idirafter ${linuxHeaders}/include \
      -c ${./hhkb-bt-audio.bpf.c} -o hhkb-bt-audio.bpf.o
  '';

  checkPhase = ''
    runHook preCheck
    HHKB_AUDIO_HEADER=${./.}/descriptor.h \
      HHKB_AUDIO_DESCRIPTOR=${../../tests/fixtures/hhkb-bt-report-descriptor.hex} \
      python ${../../tests/hhkb-bt-audio.py}
    runHook postCheck
  '';

  postInstall = ''
    install -Dm0644 hhkb-bt-audio.bpf.o "$out/lib/firmware/hid/bpf/hhkb-bt-audio.bpf.o"
    mkdir -p "$out/lib/udev/rules.d"
    cat > "$out/lib/udev/rules.d/81-hhkb-bt-audio.rules" <<EOF
    ACTION=="add", SUBSYSTEM=="hid", KERNEL=="0005:04FE:0202.*", IMPORT{program}="$out/bin/udev-hid-bpf add \$sys\$devpath $out/lib/firmware/hid/bpf/hhkb-bt-audio.bpf.o"
    ACTION=="remove", SUBSYSTEM=="hid", KERNEL=="0005:04FE:0202.*", RUN{program}+="$out/bin/udev-hid-bpf remove \$sys\$devpath"
    EOF
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/udev-hid-bpf" inspect "$out/lib/firmware/hid/bpf/hhkb-bt-audio.bpf.o"
    runHook postInstallCheck
  '';

  meta = {
    description = "HHKB Professional BT volume-key HID compatibility fix";
    homepage = "https://gitlab.freedesktop.org/libevdev/udev-hid-bpf";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
