{ lib, buildGoModule, pkg-config, SDL3, freetype, fontconfig }:

buildGoModule rec {
  pname = "ng";
  version = "unstable-2026-11-19";

  # 上流の Go module には外部依存がない。rev を固定してソースを取得する。
  src = builtins.fetchGit {
    url = "https://github.com/Shougo/ng.git";
    rev = "9bf3ff48f89a8a097a9fd84cce90ae63fb552224";
  };

  subPackages = [ "cmd/ng" ];
  vendorHash = null;
  env.CGO_ENABLED = "1";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ SDL3 freetype fontconfig ];
  ldflags = [ "-X main.version=${version}" ];

  postInstall = ''
    install -Dm644 assets/ng.desktop "$out/share/applications/ng.desktop"
    mkdir -p "$out/share/icons"
    cp -r assets/icons/hicolor "$out/share/icons/"
  '';

  meta = {
    description = "Minimal GUI client for Neovim";
    homepage = "https://github.com/Shougo/ng";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ng";
  };
}
