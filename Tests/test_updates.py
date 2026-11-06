import unittest, importlib.util, tempfile, plistlib, base64
from pathlib import Path
s=importlib.util.spec_from_file_location('configuration',Path(__file__).parents[1]/'scripts/configure-updates.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ConfigurationTests(unittest.TestCase):
 def test_valid_feed(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d); (root/'IslandCore').mkdir(); p=root/'IslandCore/Info.plist'; p.write_bytes(plistlib.dumps({}))
   m.configure('https://github.com/example/island',base64.b64encode(bytes(32)).decode(),root)
   self.assertEqual(plistlib.loads(p.read_bytes())['SUFeedURL'],'https://github.com/example/island/releases/latest/download/appcast.xml')
 def test_rejects_wrong_repository(self):
  for repo in ['TheBoredTeam/boring.notch','https://evil.example/user/repo','owner/repo/extra','owner/repo?x=1','../file']:
   with self.assertRaises(ValueError): m.configure(repo,base64.b64encode(bytes(32)).decode(),Path('/missing'))
 def test_rejects_invalid_keys(self):
  for key in ['bad',base64.b64encode(bytes(31)).decode()]:
   with self.assertRaises(ValueError): m.configure('example/island',key,Path('/missing'))
 def test_release_has_no_upstream_feed(self):
  d=plistlib.loads((Path(__file__).parents[1]/'IslandCore/Info.plist').read_bytes())
  self.assertNotIn('TheBoredTeam',d.get('SUFeedURL',''))
