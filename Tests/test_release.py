import base64, importlib.util, json, os, plistlib, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).parents[1]
s=importlib.util.spec_from_file_location('release',ROOT/'scripts/prepare-release.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ReleaseTests(unittest.TestCase):
 def test_unconfigured_app_is_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);app=root/'Island.app';(app/'Contents').mkdir(parents=True)
   (app/'Contents/Info.plist').write_bytes(plistlib.dumps({}))
   with self.assertRaises(ValueError):m.prepare(app,root/'Island.zip',root/'appcast.xml',Path('/missing'))
 def test_real_signature_and_tamper_rejection(self):
  sign=os.environ.get('ISLAND_SPARKLE_SIGN_TOOL')
  if not sign:self.skipTest('Set ISLAND_SPARKLE_SIGN_TOOL for real Sparkle signing check.')
  with tempfile.TemporaryDirectory() as d:
   root=Path(d); fixture=root/'fixture.swift'
   fixture.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let exported = key.rawRepresentation
let object = ["public": key.publicKey.rawRepresentation.base64EncodedString(), "private": exported.base64EncodedString()]
print(String(data: try JSONEncoder().encode(object), encoding: .utf8)!)
''')
   keys=json.loads(subprocess.check_output(['/usr/bin/xcrun','swift',str(fixture)],text=True))
   app=root/'Island.app';(app/'Contents').mkdir(parents=True)
   (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'SUFeedURL':'https://github.com/example/Island/releases/latest/download/appcast.xml','SUPublicEDKey':keys['public'],'CFBundleShortVersionString':'2.0.1','CFBundleVersion':'201'}))
   archive=root/'Island.zip';archive.write_bytes(b'test-archive')
   old=os.environ.get('SPARKLE_PRIVATE_KEY');os.environ['SPARKLE_PRIVATE_KEY']=keys['private']
   try:
    m.prepare(app,archive,root/'appcast.xml',Path(sign))
    self.assertIn('/v2.0.1/Island.zip',(root/'appcast.xml').read_text())
    # Archive signature must fail after modification.
    keyfile=root/'key';keyfile.write_text(keys['private']);keyfile.chmod(0o600)
    output=subprocess.check_output([sign,'--ed-key-file',str(keyfile),str(archive)],text=True)
    signature=m.re.search(r'sparkle:edSignature="([^"]+)"',output)[1]
    archive.write_bytes(b'tampered-archive')
    check=subprocess.run(['/usr/bin/xcrun','swift',str(ROOT/'scripts/VerifyUpdate.swift'),str(archive),keys['public'],signature],capture_output=True)
    self.assertNotEqual(check.returncode,0)
    # Valid archive signature paired with a different app public key must fail too.
    archive.write_bytes(b'test-archive')
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes()); info['SUPublicEDKey']=base64.b64encode(bytes(32)).decode();(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    with self.assertRaises(subprocess.CalledProcessError):m.prepare(app,archive,root/'bad.xml',Path(sign))
   finally:
    if old is None:os.environ.pop('SPARKLE_PRIVATE_KEY',None)
    else:os.environ['SPARKLE_PRIVATE_KEY']=old
