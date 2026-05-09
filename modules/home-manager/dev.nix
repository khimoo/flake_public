{ kiro, settings, config, pkgs, lib, ... }:

let
  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
  ];

  rustowlVersion = "1.0.0-rc.1";
  rustowlArchive = pkgs.fetchurl {
    url = "https://github.com/cordx56/rustowl/releases/download/v${rustowlVersion}/rustowl-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-ir1fQfMEZg4xdNUrf2bgxziFtzm+xPZQv1IDIHbIOKM=";
  };

in {
  home.packages = with pkgs; [
    vscode
    jetbrains.idea
    tree
    ffmpeg
    claude-code
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    kiro.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.antigravity-fhs
  ] ++ map (s: s.pkg) lspServers;

  home.sessionPath = [ "$HOME/.local/bin" ];

  home.sessionVariables = {
    NEOVIM_LSP_SERVERS = builtins.concatStringsSep "," (map (s: s.lsp) lspServers);
    CODELLDB_PATH = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
    withNodeJs = true;
    extraPackages = with pkgs; [
      deno
      ripgrep
      nil
      nixfmt-rfc-style
      vscode-extensions.vadimcn.vscode-lldb
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.xclip
    ];
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];
  };

  # [impure] rustowl のプリビルドバイナリを ~/.local/ にインストール
  # rustowl は特定の nightly Rust sysroot を必要とし、nixpkgs でのパッケージングが困難なため
  # GitHub Releases のプリビルドバイナリ（sysroot 同梱）を Nix store 外に展開する。
  # v1.0.0-rc.1 以降は `rustowl toolchain install` でランタイムに sysroot をダウンロードする。
  # プロジェクトごとの Rust ツールチェーンは各 devShell の rust-overlay が PATH で上書きするため影響しない。
  # NixOS では動的リンカのパスが標準 Linux と異なるため、patchelf で修正が必要。
  home.activation.rustowl = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    RUSTOWL_DIR="$HOME/.local/share/rustowl"
    RUSTOWL_BIN="$HOME/.local/bin/rustowl"
    SYSROOT="$RUSTOWL_DIR/sysroot/1.89.0-x86_64-unknown-linux-gnu"
    INTERP="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
    NIX_RPATH="${lib.makeLibraryPath [ pkgs.zlib pkgs.stdenv.cc.cc.lib ]}"

    if [ ! -x "$RUSTOWL_BIN" ] || [ "$("$RUSTOWL_BIN" --version 2>/dev/null)" != "RustOwl v${rustowlVersion}" ]; then
      $DRY_RUN_CMD mkdir -p "$RUSTOWL_DIR" "$HOME/.local/bin"
      $DRY_RUN_CMD ${pkgs.gzip}/bin/gzip -dc ${rustowlArchive} | $DRY_RUN_CMD ${pkgs.gnutar}/bin/tar xf - -C "$RUSTOWL_DIR"
      # rustowl 本体を先に patchelf（toolchain install の実行に必要）
      $DRY_RUN_CMD ${pkgs.patchelf}/bin/patchelf \
        --set-interpreter "$INTERP" \
        --set-rpath "$NIX_RPATH" \
        "$RUSTOWL_DIR/rustowl"
      # sysroot をダウンロード
      $DRY_RUN_CMD "$RUSTOWL_DIR/rustowl" toolchain install
      # sysroot 内の ELF バイナリに patchelf
      SYSROOT_LIB="$SYSROOT/lib"
      for bin in "$SYSROOT/bin/rustowlc" "$SYSROOT/bin/rustc" "$SYSROOT/bin/rustdoc" \
                 "$SYSROOT/bin/cargo" "$SYSROOT/libexec/rust-analyzer-proc-macro-srv"; do
        [ -f "$bin" ] && [ ! -L "$bin" ] && \
          $DRY_RUN_CMD ${pkgs.patchelf}/bin/patchelf \
            --set-interpreter "$INTERP" \
            --set-rpath "$SYSROOT_LIB:$NIX_RPATH" \
            "$bin"
      done
      # sysroot の共有ライブラリも rpath 修正（librustc_driver が libz 等を必要とする）
      for so in "$SYSROOT_LIB"/*.so*; do
        [ -f "$so" ] && [ ! -L "$so" ] && \
          $DRY_RUN_CMD ${pkgs.patchelf}/bin/patchelf --set-rpath "$SYSROOT_LIB:$NIX_RPATH" "$so" 2>/dev/null || true
      done
      $DRY_RUN_CMD ln -sf "$RUSTOWL_DIR/rustowl" "$RUSTOWL_BIN"
    fi
  '';

  # mkOutOfStoreSymlinkを使えばrebuild不要で即反映できるが、絶対パスのハードコードが必要になるため使用しない
  xdg.configFile."nvim" = {
    source = ../../dotfiles/nvim;
    recursive = true;
  };
}
