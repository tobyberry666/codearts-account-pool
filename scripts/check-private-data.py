"""Optional local pre-publication check; never prints private values."""
import argparse
import json
from pathlib import Path
import re
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--private-profile', type=Path)
parser.add_argument('--artifact', action='append', type=Path, default=[])
args = parser.parse_args()
private_values = set()
sensitive = {'api_key', 'cloud_dragon_token', 'access_key_id', 'secret_access_key', 'refresh_token', 'code_verifier', 'd'}

def collect(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in sensitive and isinstance(value, str) and len(value) >= 12:
                private_values.add(value.encode())
            collect(value)
    elif isinstance(obj, list):
        for value in obj:
            collect(value)

if args.private_profile:
    for path in args.private_profile.rglob('*.json'):
        try:
            collect(json.loads(path.read_text(encoding='utf-8-sig')))
        except (ValueError, OSError):
            continue

failures = []
checked = 0
def check(name, data):
    global checked
    checked += 1
    if any(value in data for value in private_values):
        failures.append(name + ': contains a private runtime value')
    if re.search(rb'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', data):
        failures.append(name + ': credential-shaped literal')

for path in args.root.rglob('*'):
    if path.is_file() and not any(part in {'.git', 'dist', 'bin', '__pycache__'} for part in path.relative_to(args.root).parts):
        check(str(path.relative_to(args.root)), path.read_bytes())
for artifact in args.artifact:
    with zipfile.ZipFile(artifact) as archive:
        for name in archive.namelist():
            if name.endswith('/'):
                continue
            if re.search(r'(^|/)(auths|data|backups|\.git)(/|$)|(^|/)(config\.json|connection\.txt|task-proxy\.log)$', name.replace('\\', '/')):
                failures.append(artifact.name + ':' + name + ': forbidden runtime file')
            check(artifact.name + ':' + name, archive.read(name))
if failures:
    print('\n'.join(sorted(set(failures))))
    raise SystemExit(1)
print(f'PASS: {checked} source/archive entries checked; no private runtime values or credential-shaped literals detected.')
