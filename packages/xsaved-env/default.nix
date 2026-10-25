# X のいいねとブックマークの保存と意味検索（xsaved）を、uv が取得する Python と manylinux wheel で動かす環境。
# mimikopi-env と同じ形で、ROCm 版の PyTorch が読むライブラリを足し、データを dataDir の subvol に寄せる。
# 耳コピの環境と分けたので、同じ版の torch でもキャッシュを共有しない。設計判断: docs/architecture/xsaved.md
{
  lib,
  buildFHSEnv,
  writeShellScript,
  gallery-dl,
  dataDir,
  database,
  # dataDir が nofail でマウントする subvol のときだけ、マウントを確かめる。
  checkMount ? true,
  # GPU を使う計算を、ほかの実行と順番にするためのロックファイル（ホストで共有する）。
  gpuLock ? null,
  hsaOverrideGfxVersion ? null,
}:

buildFHSEnv {
  name = "xsaved-env";
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
  runScript = writeShellScript "xsaved-env-run" ''
    ${lib.optionalString checkMount ''
      # dataDir の subvol は nofail でマウントする。マウントに失敗したまま続けると、ルート側の
      # 同じパスへ torch とメディアを書き込んでルートを埋めるので、ここで止める。
      if ! mountpoint -q ${lib.escapeShellArg dataDir}; then
        echo "xsaved-env: ${dataDir} がマウントされていません。手順: docs/howtouse/xsaved.md" >&2
        exit 1
      fi
    ''}
    export UV_PYTHON_PREFERENCE=only-managed
    export UV_CACHE_DIR=${lib.escapeShellArg "${dataDir}/uv-cache"}
    export UV_PYTHON_INSTALL_DIR=${lib.escapeShellArg "${dataDir}/python"}
    export UV_PROJECT_ENVIRONMENT=${lib.escapeShellArg "${dataDir}/venv"}
    # uv が取得する Python の OpenSSL は CA 証明書を /etc/ssl/cert.pem で探すが、NixOS にはない。
    # 渡さないと、urllib のような標準ライブラリの HTTPS が証明書を検証できずに失敗する。
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
    export HF_HOME=${lib.escapeShellArg "${dataDir}/huggingface"}
    export XSAVED_DATA_DIR=${lib.escapeShellArg "${dataDir}/tweets"}
    export XSAVED_DATABASE_URL=${lib.escapeShellArg "host=/run/postgresql dbname=${database}"}
    export XSAVED_GALLERY_DL=${lib.escapeShellArg (lib.getExe gallery-dl)}
    ${lib.optionalString (gpuLock != null) "export XSAVED_GPU_LOCK=${lib.escapeShellArg gpuLock}"}
    # アカウント名は公開リポジトリに書かないので、データディレクトリのファイルから読む。
    if [ -z "''${XSAVED_X_USER:-}" ] && [ -r ${lib.escapeShellArg "${dataDir}/x-user"} ]; then
      XSAVED_X_USER=$(< ${lib.escapeShellArg "${dataDir}/x-user"})
      export XSAVED_X_USER
    fi
    ${lib.optionalString (
      hsaOverrideGfxVersion != null
    ) "export HSA_OVERRIDE_GFX_VERSION=${lib.escapeShellArg hsaOverrideGfxVersion}"}
    if [ "$#" -eq 0 ]; then exec bash; fi
    exec "$@"
  '';
}
