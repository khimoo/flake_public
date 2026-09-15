# Sony Digital Paper / Fujitsu Quaderno を Digital Paper App なしで操作する CLI。
#
# PyPI の最新版 (0.1.19, 2025-10-14) を使わず GitHub の master に固定している。
# Quaderno Gen2 の登録は 0.1.19 では約半分の確率で HTTP 403
# "Bad parameters for registration process." に落ちる。Diffie-Hellman の公開値 yb を
# 固定長 256 バイトへ詰め直したせいで、Java 側が付ける符号バイトの分だけ HMAC の
# 入力がずれるのが原因で、commit 7a0ef077 (2026-07-12) が直している。
# この修正を含むリリースはまだ PyPI に出ていない。
#
# 削除条件: 修正を含むリリースが PyPI に出たら rev 固定をやめる。
#           nixpkgs に dpt-rp1-py が入ったらこのディレクトリごと削除する。
# 設計判断: docs/architecture/quaderno.md
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication {
  pname = "dpt-rp1-py";
  version = "0.1.19-unstable-2026-07-13";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "janten";
    repo = "dpt-rp1-py";
    rev = "9dda9d9a16c20477bd19374866e2095705765f96";
    sha256 = "0fyl27kli11yyk3jlbwik06gknrdqs5pd5nxmj2nz8l46gs48gka";
  };

  propagatedBuildInputs = with python3Packages; [
    httpsig
    requests
    pbkdf2
    urllib3
    pyyaml
    anytree
    fusepy
    zeroconf
    tqdm
    setuptools
  ];

  # upstream にテストが無い。pythonImportsCheck が実質の検査になる。
  # dptrp1/__init__.py は空なので、"dptrp1" だけでは依存の欠落を検出できない。
  # 本体を持つ "dptrp1.dptrp1" を import させて意味のある検査にする。
  doCheck = false;
  pythonImportsCheck = [ "dptrp1.dptrp1" ];

  meta = {
    description = "Sony DPT-RP1 / Fujitsu Quaderno を操作する CLI";
    homepage = "https://github.com/janten/dpt-rp1-py";
    license = lib.licenses.mit;
    mainProgram = "dptrp1";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
  };
}
