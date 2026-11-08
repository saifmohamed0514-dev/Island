#!/usr/bin/env python3
"""Create a signed Sparkle appcast for a ZIP. Does not upload or publish anything."""
import argparse, base64, datetime, html, os, plistlib, re, subprocess, tempfile
from pathlib import Path
from xml.sax.saxutils import escape

def prepare(app, archive, output, sign_tool):
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    feed = info.get('SUFeedURL', '')
    match = re.fullmatch(r'https://github.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/releases/latest/download/appcast.xml',feed)
    if not match or not info.get('SUPublicEDKey'): raise ValueError('Configure your update feed and public key, then rebuild first.')
    secret = os.environ.get('SPARKLE_PRIVATE_KEY','').strip()
    if secret:
        # CI can use an owner-only temporary file; never place a key in argv.
        with tempfile.NamedTemporaryFile(mode='w') as key:
            os.chmod(key.name,0o600);key.write(secret);key.flush()
            signed=subprocess.check_output([str(sign_tool),'--ed-key-file',key.name,str(archive)],text=True)
    else:
        # Local publishing uses the Sparkle key already stored in Keychain.
        account=info.get('IslandUpdateKeyAccount','Island-org.islandapp.Island')
        signed=subprocess.check_output([str(sign_tool),'--account',account,str(archive)],text=True)

    signature = re.search(r'sparkle:edSignature="([^"]+)"',signed)
    if not signature: raise ValueError('Sparkle did not return an archive signature.')
    subprocess.run(['/usr/bin/xcrun', 'swift', str(Path(__file__).with_name('VerifyUpdate.swift')), str(archive), info['SUPublicEDKey'], signature[1]], check=True)
    version = str(info['CFBundleShortVersionString']); build = str(info['CFBundleVersion'])
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}',version) or not build.isdigit(): raise ValueError('Use numeric app version and build number.')
    tag = 'v'+version
    url = f'https://github.com/{match[1]}/releases/download/{tag}/Island.zip'
    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Island Updates</title><link>{escape(feed)}</link><description>Signed Island releases</description><language>en</language>
<item><title>Island {escape(version)}</title><sparkle:version>{escape(build)}</sparkle:version><sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
<enclosure url="{escape(url)}" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature[1]}"/>
</item></channel></rss>
'''
    output.write_text(xml)
    print(f'Created {output.name}. Nothing uploaded. Release tag must be {tag}.')

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app',required=True,type=Path);p.add_argument('--archive',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--sign-tool',required=True,type=Path)
    a=p.parse_args()
    try: prepare(a.app,a.archive,a.output,a.sign_tool)
    except (ValueError,subprocess.CalledProcessError) as e: p.error(str(e))
