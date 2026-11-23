"""Make the tiny RPC tool use the same interpreter and imports as the Nix Hermes CLI."""
import ast
from pathlib import Path
import sys

wrapped, rpc, output = map(Path, sys.argv[1:])
source = wrapped.read_text(encoding='utf-8')
shebang = source.splitlines()[0]
if not shebang.startswith('#!/nix/store/') or '/bin/python' not in shebang:
    raise SystemExit('Hermes の Python ラッパーの形式が変わりました')
# wrapPython embeds the site-packages list as the second operand of functools.reduce.
paths = None
for node in ast.walk(ast.parse(source)):
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name) and node.func.value.id == 'functools'
            and node.func.attr == 'reduce' and len(node.args) >= 2 and isinstance(node.args[1], ast.List)):
        candidate = ast.literal_eval(node.args[1])
        if candidate and all(isinstance(p, str) and p.startswith('/nix/store/') for p in candidate):
            paths = candidate
            break
if paths is None:
    raise SystemExit('Hermes の Python 依存パスを特定できません')
output.write_text(shebang + '\nimport runpy, site\nfor path in ' + repr(paths) + ':\n    site.addsitedir(path)\nrunpy.run_path(' + repr(str(rpc)) + ', run_name="__main__")\n', encoding='utf-8')
output.chmod(0o755)
