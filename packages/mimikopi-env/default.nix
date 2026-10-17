# 耳コピ（楽曲の自動採譜）のスキルが使う ML モデルを、uv が取得する Python と manylinux wheel で動かす環境。
# uv-mode と同じ仕組みだが、ROCm 版の PyTorch が要るライブラリを足し、データを dataDir の subvol に寄せる。
# 影響を耳コピだけに閉じるため uv-mode には混ぜない。設計判断: docs/architecture/mimikopi-env.md
{ lib, buildFHSEnv, writeShellScript, dataDir, hsaOverrideGfxVersion ? null }:

buildFHSEnv {
  name = "mimikopi-env";
  targetPkgs = pkgs: with pkgs; [
    uv
    zlib
    stdenv.cc.cc.lib
    # ROCm 版の torch が import 時に読む。
    zstd
    libdrm
    numactl
    elfutils
    xz
    bzip2
    ffmpeg
    util-linux
  ];
  runScript = writeShellScript "mimikopi-env-run" ''
    # dataDir の subvol は nofail でマウントする。マウントに失敗したまま続けると、ルート側の
    # 同じパスへ数十 GB を書き込んでルートを埋めるので、ここで止める。
    if ! mountpoint -q ${lib.escapeShellArg dataDir}; then
      echo "mimikopi-env: ${dataDir} がマウントされていません。手順: docs/howtouse/cli-tools/mimikopi-env.md" >&2
      exit 1
    fi
    export UV_PYTHON_PREFERENCE=only-managed
    # uv はキャッシュから環境へハードリンクで展開する。同じファイルシステムに置くと、
    # 同じ版の torch を複数のモデルの環境で共有できる。
    export UV_CACHE_DIR=${lib.escapeShellArg "${dataDir}/uv-cache"}
    export UV_PYTHON_INSTALL_DIR=${lib.escapeShellArg "${dataDir}/python"}
    export HF_HOME=${lib.escapeShellArg "${dataDir}/huggingface"}
    export TORCH_HOME=${lib.escapeShellArg "${dataDir}/torch"}
    export MIMIKOPI_DATA_DIR=${lib.escapeShellArg dataDir}
    ${lib.optionalString (hsaOverrideGfxVersion != null)
      "export HSA_OVERRIDE_GFX_VERSION=${lib.escapeShellArg hsaOverrideGfxVersion}"}
    if [ "$#" -eq 0 ]; then exec bash; fi
    exec "$@"
  '';
}
