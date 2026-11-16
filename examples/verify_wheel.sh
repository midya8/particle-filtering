#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python -m pip wheel --no-deps --wheel-dir "$tmp/dist" "$root"
python -m venv "$tmp/env"
"$tmp/env/bin/python" -m pip install --no-deps "$tmp"/dist/*.whl
cp -R "$root/examples" "$root/assets" "$root/tests" "$tmp/"
(
    cd "$root"
    python -m particlelab demo > "$tmp/source-demo.json"
    python examples/render_demo.py "$tmp/source-demo.json" --check
    python - "$tmp" <<'SOURCE'
import json,subprocess,sys
from pathlib import Path
sequence='examples/sequence.json'
commands = [
    ['filter', sequence, '--particles', '512', '--seed', '0'],
    ['filter', sequence, '--ess-fraction', '0'],
    ['kalman', sequence],
    ['square-reference', 'examples/square.json'],
    ['smooth', sequence, '--particles', '512', '--seed', '0'],
    ['rts', sequence],
    ['backward', sequence, '--particles', '32', '--draws', '512', '--draw-seed', '0'],
    ['filter', sequence, '--particles', '32', '--proposal', 'conditional'],
]
Path(sys.argv[1],'command-table.json').write_text(json.dumps(commands))
for i,command in enumerate(commands):
    text=subprocess.check_output([sys.executable,'-m','particlelab',*command],text=True)
    json.loads(text)
    Path(sys.argv[1],f'source-command-{i}.json').write_text(text)
SOURCE
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
        assert 'site-packages' in path and Path(path).resolve().is_relative_to(Path(sys.prefix).resolve()) and not Path(path).resolve().is_relative_to(root)
    return paths
origins()
# Existing figure tests import examples as a namespace. Only its copied
# temporary directory is added, after all library modules are loaded.
sys.path.insert(0, str(Path.cwd()))
suite = unittest.defaultTestLoader.discover(str(Path.cwd()/'tests'))
result = unittest.TextTestRunner(verbosity=2).run(suite)
assert result.testsRun > 0 and result.wasSuccessful()
result_count = result.testsRun
paths = origins()
sequence = 'examples/sequence.json'
commands = json.loads(Path('command-table.json').read_text())
for i, command in enumerate(commands):
    result = subprocess.run([sys.executable, '-I', '-m', 'particlelab', *command],
                            capture_output=True, text=True, check=True)
    expected = json.loads(Path('source-command-'+str(i)+'.json').read_text())
    assert json.loads(result.stdout) == expected, command
    Path('command-'+str(i)+'.json').write_text(result.stdout)
origins()
print(json.dumps({'tests': result_count, 'installed_origins': paths, 'checked_before_and_after': True, 'complete_input_command_reports': len(commands)}))
PY
"$tmp/env/bin/python" -I -m particlelab demo > installed-demo.json
cmp source-demo.json installed-demo.json
"$tmp/env/bin/python" -I examples/render_demo.py installed-demo.json --check
for name in square smoothing backward proposal; do
    "$tmp/env/bin/python" -I "examples/${name}_audit.py" > "installed-$name.json"
    cmp "source-$name.json" "installed-$name.json"
    "$tmp/env/bin/python" -I "examples/render_$name.py" "installed-$name.json" --check
done
