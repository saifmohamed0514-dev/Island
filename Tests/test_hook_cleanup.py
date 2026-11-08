import importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('cleanup',Path(__file__).parents[1]/'scripts/remove-island-hooks.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class HookCleanupTests(unittest.TestCase):
 def test_mixed_handlers_preserve_other_hooks_and_preferences(self):
  source={'permissions':{'defaultMode':'ask'},'hooks':{'Stop':[{'matcher':'*','hooks':[{'type':'command','command':"'/private/IslandBridge' --directory '/private/folder with spaces' --event Stop"},{'type':'command','command':'/other/tool'}]}]}}
  clean,count=module.remove_island_hooks(source)
  self.assertEqual(count,1);self.assertEqual(clean['permissions'],source['permissions']);self.assertEqual(clean['hooks']['Stop'][0]['hooks'],[{'type':'command','command':'/other/tool'}]);self.assertEqual(len(source['hooks']['Stop'][0]['hooks']),2)
 def test_all_island_empty_and_idempotent(self):
  source={'hooks':{'Stop':[{'hooks':[{'command':'/private/IslandBridge --directory /private/path'}]}]}}
  clean,count=module.remove_island_hooks(source);self.assertEqual((clean,count),({'hooks':{}},1));self.assertEqual(module.remove_island_hooks(clean),(clean,0))
 def test_plain_cursor_handlers(self):
  clean,count=module.remove_island_hooks({'version':1,'hooks':{'beforeShellExecution':[{'command':'/private/IslandBridge --directory /private/path'},{'command':'/other/tool'}]}})
  self.assertEqual(count,1);self.assertEqual(clean['version'],1);self.assertEqual(clean['hooks']['beforeShellExecution'],[{'command':'/other/tool'}])
 def test_similar_names_and_malformed_commands_untouched(self):
  for command in ['/tmp/MyIslandBridge --directory /tmp','echo IslandBridge --directory /tmp',"'unterminated",'/tmp/IslandBridge']:
   source={'hooks':{'Stop':[{'command':command}]}};self.assertEqual(module.remove_island_hooks(source),(source,0))
