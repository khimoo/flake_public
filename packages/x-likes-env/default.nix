# X のいいねの保存と意味検索（x-likes-archive）を、uv が取得する Python と manylinux wheel で動かす環境。
# mimikopi-env と同じ形で、ROCm 版の PyTorch が読むライブラリを足し、データを dataDir の subvol に寄せる。
# 耳コピの環境と分けたので、同じ版の torch でもキャッシュを共有しない。設計判断: docs/architecture/x-likes.md
{
  lib,
  buildFHSEnv,
  writeShellScript,
  gallery-dl,
  dataDir,
  database,
  hsaOverrideGfxVersion ? null,
}:

buildFHSEnv {
  name = "x-likes-env";
  targetPkgs =
    pkgs: with pkgs; [
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
      util-linux
    ];
  runScript = writeShellScript "x-likes-env-run" ''
    # dataDir の subvol は nofail でマウントする。マウントに失敗したまま続けると、ルート側の
    # 同じパスへ torch とメディアを書き込んでルートを埋めるので、ここで止める。
    if ! mountpoint -q ${lib.escapeShellArg dataDir}; then
      echo "x-likes-env: ${dataDir} がマウントされていません。手順: docs/howtouse/x-likes.md" >&2
      exit 1
    fi
    export UV_PYTHON_PREFERENCE=only-managed
    export UV_CACHE_DIR=${lib.escapeShellArg "${dataDir}/uv-cache"}
    export UV_PYTHON_INSTALL_DIR=${lib.escapeShellArg "${dataDir}/python"}
    export UV_PROJECT_ENVIRONMENT=${lib.escapeShellArg "${dataDir}/venv"}
    export HF_HOME=${lib.escapeShellArg "${dataDir}/huggingface"}
    export XLIKES_DATA_DIR=${lib.escapeShellArg "${dataDir}/tweets"}
    export XLIKES_DATABASE_URL=${lib.escapeShellArg "host=/run/postgresql dbname=${database}"}
    export XLIKES_GALLERY_DL=${lib.escapeShellArg (lib.getExe gallery-dl)}
    # アカウント名は公開リポジトリに書かないので、データディレクトリのファイルから読む。
    if [ -z "''${XLIKES_X_USER:-}" ] && [ -r ${lib.escapeShellArg "${dataDir}/x-user"} ]; then
      XLIKES_X_USER=$(< ${lib.escapeShellArg "${dataDir}/x-user"})
      export XLIKES_X_USER
    fi
    ${lib.optionalString (
      hsaOverrideGfxVersion != null
    ) "export HSA_OVERRIDE_GFX_VERSION=${lib.escapeShellArg hsaOverrideGfxVersion}"}
    if [ "$#" -eq 0 ]; then exec bash; fi
    exec "$@"
  '';
}
