{
  config,
  pkgs,
  lib,
  ...
}:

let
  supported = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  rustowlVersion = "1.0.0-rc.1";
  rustowlArchive = pkgs.fetchurl {
    url = "https://github.com/cordx56/rustowl/releases/download/v${rustowlVersion}/rustowl-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-ir1fQfMEZg4xdNUrf2bgxziFtzm+xPZQv1IDIHbIOKM=";
  };
in
{
  options.local.rustowl.enable = lib.mkOption {
    type = lib.types.bool;
    default = supported;
    description = "Install the pinned RustOwl binary and sysroot (x86_64-linux only).";
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !config.local.rustowl.enable || supported;
          message = "local.rustowl supports x86_64-linux only.";
        }
      ];
    }
    (lib.mkIf (config.local.rustowl.enable && supported) {
      home.sessionPath = [ "$HOME/.local/bin" ];

      # [impure] rustowl のプリビルドバイナリを ~/.local/ にインストール
      # rustowl は特定の nightly Rust sysroot を必要とし、nixpkgs でのパッケージングが困難なため
      # GitHub Releases のプリビルドバイナリ（sysroot 同梱）を Nix store 外に展開する。
      # v1.0.0-rc.1 以降は `rustowl toolchain install` でランタイムに sysroot をダウンロードする。
      # プロジェクトごとの Rust ツールチェーンは各 devShell の rust-overlay が PATH で上書きするため影響しない。
      # NixOS では動的リンカのパスが標準 Linux と異なるため、patchelf で修正が必要。
      home.activation.rustowl = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          echo "rustowl: (dry-run) install/repair RustOwl v${rustowlVersion}" >&2
        else
        RUSTOWL_DIR="$HOME/.local/share/rustowl"
        RUSTOWL_BIN="$HOME/.local/bin/rustowl"
        SYSROOT="$RUSTOWL_DIR/sysroot/1.89.0-x86_64-unknown-linux-gnu"
        INTERP="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
        NIX_RPATH="${
          lib.makeLibraryPath [
            pkgs.zlib
            pkgs.stdenv.cc.cc.lib
          ]
        }"

        # The marker is written only after the complete sysroot has been patched.
        # Include store paths so a new toolchain generation refreshes rpaths after GC.
        EXPECTED="${rustowlVersion}:$INTERP:$NIX_RPATH"
        if [ ! -x "$RUSTOWL_BIN" ] || [ ! -x "$SYSROOT/bin/rustowlc" ] || \
           [ "$(cat "$RUSTOWL_DIR/.complete" 2>/dev/null || :)" != "$EXPECTED" ] || \
           [ "$("$RUSTOWL_BIN" --version 2>/dev/null)" != "RustOwl v${rustowlVersion}" ]; then
          $DRY_RUN_CMD mkdir -p "$RUSTOWL_DIR" "$HOME/.local/bin"
          rm -f "$RUSTOWL_DIR/.complete"
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
            if [ -f "$so" ] && [ ! -L "$so" ]; then
              ${pkgs.patchelf}/bin/patchelf --set-rpath "$SYSROOT_LIB:$NIX_RPATH" "$so"
            fi
          done
          test -x "$SYSROOT/bin/rustowlc"
          $DRY_RUN_CMD ln -sf "$RUSTOWL_DIR/rustowl" "$RUSTOWL_BIN"
          printf '%s' "$EXPECTED" > "$RUSTOWL_DIR/.complete"
        fi
        fi
      '';
    })
  ];
}
