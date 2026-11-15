#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python -m pip wheel --no-deps --wheel-dir "$tmp/dist" "$root"
python -m venv "$tmp/env"
"$tmp/env/bin/python" -m pip install --no-deps "$tmp"/dist/*.whl
cp -R "$root/examples" "$root/assets" "$tmp/"
(
    cd "$root"
    python -m particlelab demo > "$tmp/source-demo.json"
    python examples/render_demo.py "$tmp/source-demo.json" --check
    for name in square smoothing backward proposal; do
        python "examples/${name}_audit.py" > "$tmp/source-$name.json"
        python "examples/render_$name.py" "$tmp/source-$name.json" --check
    done
)
cd "$tmp"
"$tmp/env/bin/python" -I - "$root" <<'PY'
import importlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
root = Path(sys.argv[1]).resolve()
modules = ['particlelab'+('.'+p.stem if p.stem != '__init__' else '')
           for p in (root/'particlelab').glob('*.py') if p.stem != '__main__']
for name in modules:
    importlib.import_module(name)
def origins():
    paths = {name: importlib.util.find_spec(name).origin
             for name in modules+['particlelab.__main__']}
    for path in paths.values():
        assert 'site-packages' in path and not Path(path).resolve().is_relative_to(root)
    return paths
origins()
# Existing figure tests import examples as a namespace. Only its copied
# temporary directory is added, after all library modules are loaded.
sys.path.insert(0, str(Path.cwd()))
suite = unittest.defaultTestLoader.discover(str(root/'tests'))
assert unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful()
paths = origins()
sequence = str(root/'examples/sequence.json')
commands = [
    ['filter', sequence, '--particles', '512', '--seed', '0'],
    ['filter', sequence, '--ess-fraction', '0'],
    ['kalman', sequence],
    ['square-reference', str(root/'examples/square.json')],
    ['smooth', sequence, '--particles', '512', '--seed', '0'],
    ['rts', sequence],
    ['backward', sequence, '--particles', '32', '--draws', '512', '--draw-seed', '0'],
    ['filter', sequence, '--particles', '32', '--proposal', 'conditional'],
]
for i, command in enumerate(commands):
    result = subprocess.run([sys.executable, '-I', '-m', 'particlelab', *command],
                            capture_output=True, text=True, check=True)
    json.loads(result.stdout)
    Path('command-'+str(i)+'.json').write_text(result.stdout)
print(json.dumps({'installed_origins': paths, 'documented_input_commands': len(commands)}))
PY
"$tmp/env/bin/python" -I -m particlelab demo > installed-demo.json
cmp source-demo.json installed-demo.json
"$tmp/env/bin/python" -I examples/render_demo.py installed-demo.json --check
for name in square smoothing backward proposal; do
    "$tmp/env/bin/python" -I "examples/${name}_audit.py" > "installed-$name.json"
    cmp "source-$name.json" "installed-$name.json"
    "$tmp/env/bin/python" -I "examples/render_$name.py" "installed-$name.json" --check
done
