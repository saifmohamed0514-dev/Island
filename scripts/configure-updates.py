#!/usr/bin/env python3
"""Configure only a user-owned GitHub release feed; never create a private key here."""
import argparse, base64, plistlib, re
from pathlib import Path

def configure(repository, public_key, root):
    repository = repository.removeprefix('https://github.com/').removesuffix('.git').strip('/')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Use OWNER/REPOSITORY or its github.com URL.')
    if repository.lower() == 'theboredteam/boring.notch':
        raise ValueError('Use your own Island repository, not the upstream project.')
    try: key = base64.b64decode(public_key, validate=True)
    except Exception as exc: raise ValueError('Public key must be base64.') from exc
    if len(key) != 32: raise ValueError('Sparkle public key must decode to 32 bytes.')
    path = root / 'boringNotch/Info.plist'
    data = plistlib.loads(path.read_bytes())
    data['SUFeedURL'] = f'https://github.com/{repository}/releases/latest/download/appcast.xml'
    data['SUPublicEDKey'] = public_key
    path.write_bytes(plistlib.dumps(data))
    return repository

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('repository'); p.add_argument('public_key')
    a = p.parse_args()
    try: repo = configure(a.repository, a.public_key, Path(__file__).resolve().parents[1])
    except ValueError as e: p.error(str(e))
    print(f'Configured {repo}. Rebuild Island before distributing it. No publishing occurred.')
