import json, os, pathlib, queue, stat, subprocess, tempfile, threading, time, unittest

class PluginProtocolTests(unittest.TestCase):
 def setUp(self):
  binary=os.environ.get('ISLAND_PLUGIN_BINARY')
  if not binary:self.skipTest('Compiled local plugin transport is exercised by test-plugin.sh')
  self.tmp=tempfile.TemporaryDirectory(prefix='island-plugin-tests-');self.root=pathlib.Path(self.tmp.name);self.root.chmod(0o700)
  self.live=True
  def pulse():
   while self.live:
    p=self.root/'presence-new';p.write_text(json.dumps({'time':time.time()}));p.replace(self.root/'presence.json');time.sleep(.1)
  self.pulse=threading.Thread(target=pulse,daemon=True);self.pulse.start()
  self.proc=subprocess.Popen([binary,'--directory',str(self.root),'--provider','chatgpt-plugin'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
  self.responses=queue.Queue();self.serial=0
  def reader():
   for line in self.proc.stdout:
    try:self.responses.put(json.loads(line))
    except Exception:self.responses.put({'invalid_output':line})
  threading.Thread(target=reader,daemon=True).start()
 def tearDown(self):
  self.live=False;self.pulse.join(timeout=1)
  if self.proc.poll() is None:
   self.proc.stdin.close()
   try:self.proc.wait(timeout=3)
   except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()
  self.proc.stdout.close();self.proc.stderr.close();self.tmp.cleanup()
 def send(self,method,params=None,id=None):
  if id is None:self.serial+=1;id=self.serial
  self.proc.stdin.write(json.dumps({'jsonrpc':'2.0','id':id,'method':method,'params':params or {}})+'\n');self.proc.stdin.flush();return id
 def receive(self,id,timeout=4):
  end=time.monotonic()+timeout
  while time.monotonic()<end:
   item=self.responses.get(timeout=end-time.monotonic())
   self.assertNotIn('invalid_output',item)
   if item.get('id')==id:return item
  self.fail('No matching response')
 def call(self,name,args=None):return self.receive(self.send('tools/call',{'name':name,'arguments':args or {}}))
 def event(self,kind):
  end=time.monotonic()+3
  while time.monotonic()<end:
   for p in (self.root/'events').glob('*.island-event.json'):
    try:o=json.loads(p.read_text())
    except (OSError,ValueError):continue
    if o.get('kind')==kind:return p,o
   time.sleep(.02)
  self.fail('No event '+kind)
 def test_initialization_and_discovery(self):
  v=self.receive(self.send('initialize',{'protocolVersion':'2025-06-18'}))['result'];self.assertEqual(v['protocolVersion'],'2025-06-18');self.assertIn('tools',v['capabilities'])
  tools=self.receive(self.send('tools/list'))['result']['tools'];self.assertEqual({x['name'] for x in tools},{'report_progress','ask_question','connection_status'});self.assertNotIn('approve',str(tools))
 def test_progress_round_trip(self):
  a={'task_id':'work-1','title':'Building','state':'working','percent':42,'message':'Compiled 42 of 100 items'}
  self.assertTrue(self.call('report_progress',a)['result']['structuredContent']['recorded'])
  p,event=self.event('progress');self.assertEqual(event['percent'],42);self.assertEqual(event['message'],a['message']);self.assertFalse(event['approval'])
  a.update(state='completed',percent=100);self.call('report_progress',a);self.assertEqual(json.loads(p.read_text())['state'],'completed');self.assertEqual(sum(json.loads(f.read_text()).get('kind')=='progress' for f in (self.root/'events').glob('*.island-event.json')),1)
 def test_rejects_invalid_progress(self):
  for extra in [{'percent':True},{'percent':101},{'percent':-1},{'state':'invented'},{'title':''},{'message':123},{'task_id':'../escape'}]:
   a={'task_id':'t','title':'Status','state':'working'};a.update(extra);self.assertTrue(self.call('report_progress',a)['result']['isError'])
 def test_no_invented_percentage(self):
  self.call('report_progress',{'task_id':'t','title':'Working','state':'working'});_,e=self.event('progress');self.assertNotIn('percent',e)
 def test_question_answer_round_trip(self):
  id=self.send('tools/call',{'name':'ask_question','arguments':{'task_id':'t','question':'Which colour?','options':['Blue','Green'],'timeout_seconds':10}})
  p,e=self.event('question');self.assertFalse(e['approval']);self.assertEqual(e['options'],['Blue','Green'])
  answers=self.root/'answers';(answers/(e['id']+'.json')).write_text(json.dumps({'id':e['id'],'nonce':e['nonce'],'answer':'Green'}))
  result=self.receive(id)['result']['structuredContent'];self.assertEqual(result,{'answered':True,'answer':'Green'});self.assertEqual(json.loads(p.read_text())['resolution'],'Answered');self.assertFalse((answers/(e['id']+'.json')).exists())
 def test_wrong_nonce_does_not_answer(self):
  id=self.send('tools/call',{'name':'ask_question','arguments':{'task_id':'t','question':'Continue?','timeout_seconds':10}});p,e=self.event('question')
  a=self.root/'answers'/(e['id']+'.json');a.write_text(json.dumps({'id':e['id'],'nonce':'wrong','answer':'Yes'}));time.sleep(.25);self.assertNotIn('resolution',json.loads(p.read_text()))
  a.write_text(json.dumps({'id':e['id'],'nonce':e['nonce'],'answer':'My own answer'}));self.assertTrue(self.receive(id)['result']['structuredContent']['answered'])
 def test_question_cancel(self):
  id=self.send('tools/call',{'name':'ask_question','arguments':{'task_id':'t','question':'Question','timeout_seconds':10}});p,e=self.event('question')
  self.proc.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/cancelled','params':{'requestId':id}})+'\n');self.proc.stdin.flush()
  result=self.receive(id)['result']['structuredContent'];self.assertFalse(result['answered']);self.assertEqual(result['reason'],'Cancelled');self.assertEqual(json.loads(p.read_text())['state'],'cancelled')
 def test_question_rejects_invalid_choices(self):
  for options in [['Same','Same'],list('1234567'),'wrong',['']]:
   self.assertTrue(self.call('ask_question',{'task_id':'t','question':'Question','options':options})['result']['isError'])
 def test_native_disconnection_fails_closed(self):
  self.live=False;self.pulse.join();(self.root/'presence.json').unlink(missing_ok=True)
  result=self.call('ask_question',{'task_id':'t','question':'Question'})['result'];self.assertTrue(result['isError']);self.assertFalse(result['structuredContent']['answered'])
 def test_files_are_private(self):
  self.call('report_progress',{'task_id':'t','title':'Status','state':'working'});p,e=self.event('progress');self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o600);self.assertEqual(stat.S_IMODE(p.parent.stat().st_mode),0o700)
 def test_json_rpc_errors(self):
  self.assertEqual(self.receive(self.send('missing'))['error']['code'],-32601)
  self.assertEqual(self.call('missing')['error']['code'],-32602)
  self.proc.stdin.write('not json\n');self.proc.stdin.flush();self.assertEqual(self.responses.get(timeout=3)['error']['code'],-32700)
 def test_ping_while_question_waits(self):
  id=self.send('tools/call',{'name':'ask_question','arguments':{'task_id':'t','question':'Question','timeout_seconds':10}});_,e=self.event('question');self.assertEqual(self.receive(self.send('ping'))['result'],{})
  (self.root/'answers'/(e['id']+'.json')).write_text(json.dumps({'id':e['id'],'nonce':e['nonce'],'answer':'Done'}));self.assertTrue(self.receive(id)['result']['structuredContent']['answered'])

if __name__=='__main__':unittest.main()
