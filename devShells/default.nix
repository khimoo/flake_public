{ pkgs }:
let
  inherit (pkgs) lib;

  # Rust 共通 toolchain (nixpkgs の stable rustc)。
  # rust-analyzer も同じく nixpkgs のもの。バージョン整合は厳密ではないが、
  # 同一 channel 内で重大な不整合は出にくい。
  # std へジャンプ可能にするため RUST_SRC_PATH を rustPlatform.rustLibSrc に
  # 向ける (各 shell の env 側で設定)。
  rustTools = with pkgs; [
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy
  ];

  # Bevy / wgpu / winit / egui が link or dlopen で必要とする native lib 群。
  # LD_LIBRARY_PATH を介して runtime にも見えるようにしておく
  # (wgpu の vulkan-loader, winit の libwayland など)。
  bevyNativeLibs = with pkgs; [
    alsa-lib
    udev
    vulkan-loader
    vulkan-headers
    vulkan-tools
    vulkan-validation-layers
    libxkbcommon
    wayland
    wayland-protocols
    libGL
    libdrm
    libgbm
    mesa
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
    xorg.libXinerama
    xorg.libxcb
    xwayland
  ];

  # Python: FastAPI + 科学/地理スタック。
  # geopandas が動くために GDAL/GEOS/PROJ を system 側で揃える必要がある。
  pythonScientificEnv = pkgs.python312.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    pyyaml
    numpy
    scipy
    pandas
    scikit-learn
    joblib
    requests
    httpx
    geopandas
    shapely
    matplotlib
    beautifulsoup4
    pytest
    pytest-asyncio
    debugpy
    black
    mypy
    isort
  ]);
in
{
  # Bevy / wgpu / winit を含む Rust プロジェクト用。
  rust-bevy = pkgs.mkShell {
    buildInputs = rustTools ++ [ pkgs.pkg-config ] ++ bevyNativeLibs;
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
    shellHook = ''
      export LD_LIBRARY_PATH="${lib.makeLibraryPath bevyNativeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    '';
  };

  # ネイティブ GUI ライブラリが不要な、定義ジャンプ + ビルド用の最小 Rust。
  # 競プロ的なコード, 上流リポジトリのコードリーディング等に。
  rust-min = pkgs.mkShell {
    buildInputs = rustTools ++ [ pkgs.pkg-config ];
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  # FastAPI / scikit-learn / geopandas を含む Python 研究/バックエンド用。
  py-sci = pkgs.mkShell {
    buildInputs = with pkgs; [
      pythonScientificEnv
      pyright
      uv
      just
      gdal
      geos
      proj
    ];
    shellHook = ''
      export PYTHONPATH="$PWD:$PYTHONPATH"
    '';
  };

  # Node / TypeScript web (拡張機能, SPA など)。
  # 個別プロジェクトの devDependencies は通常 `npm install` で十分なので、
  # ここでは LSP/formatter/linter のグローバル提供までに留める。
  ts-web = pkgs.mkShell {
    buildInputs = with pkgs; [
      nodejs_22
      pnpm
      yarn
      typescript
      nodePackages.typescript-language-server
      nodePackages.prettier
      nodePackages.eslint
    ];
  };
}
