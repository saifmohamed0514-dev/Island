import json, os, pathlib, subprocess, tempfile, time, unittest

class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.executable = os.environ.get('ISLAND_BRIDGE_TEST_BINARY')
        if not cls.executable:
            raise unittest.SkipTest('Run scripts/test-bridge.sh for production hook transport checks')

    def invoke(self, provider, event, answer=None, mutate=None, payload=None):
        with tempfile.TemporaryDirectory(prefix='island-bridge-fixture-') as root:
            process = subprocess.Popen([self.executable, '--provider', provider, '--event', event,
                                        '--directory', root, '--timeout', '0.8'],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            process.stdin.write(json.dumps(payload or {'session_id':'fixture','tool_name':'Shell',
                'tool_input':{'command':'fixture only; never executed'}}).encode())
            process.stdin.close()
            try:
                deadline = time.monotonic()+5
                files = []
                while time.monotonic() < deadline and not files:
                    files = list(pathlib.Path(root).glob('events/*.island-event.json'))
                    time.sleep(.02)
                self.assertEqual(len(files),1)
                record = json.loads(files[0].read_text())
                self.assertEqual(files[0].stat().st_mode & 0o777,0o600)
                self.assertEqual(files[0].parent.stat().st_mode & 0o777,0o700)
                if answer is not None:
                    decision = {'id':record['id'],'nonce':record['nonce'],'allow':answer}
                    if mutate: mutate(decision)
                    pathlib.Path(root,'decisions',record['id']+'.json').write_text(json.dumps(decision))
                process.wait(timeout=5)
                output = json.loads(process.stdout.read())
                self.assertEqual(process.returncode,0)
                self.assertEqual(process.stderr.read(),b'')
                final = json.loads(files[0].read_text())
                return output, final
            finally:
                if process.poll() is None: process.kill(); process.wait()
                process.stdout.close(); process.stderr.close()

    def test_claude_allow_once(self):
        result, final = self.invoke('claude','PermissionRequest',True)
        decision=result['hookSpecificOutput']['decision']
        self.assertEqual(decision,{'behavior':'allow'})
        self.assertEqual(final['resolution'],'Allowed once')
        self.assertFalse(final['approval'])

    def test_claude_deny(self):
        result,_=self.invoke('claude','PermissionRequest',False)
        self.assertEqual(result['hookSpecificOutput']['decision']['behavior'],'deny')

    def test_claude_timeout_preserves_client_prompt(self):
        result,final=self.invoke('claude','PermissionRequest')
        self.assertEqual(result,{})
        self.assertEqual(final['resolution'],'Review in original client')

    def test_cursor_allow_and_timeout(self):
        result,_=self.invoke('cursor','beforeShellExecution',True)
        self.assertEqual(result['permission'],'allow')
        result,_=self.invoke('cursor','beforeShellExecution')
        self.assertEqual(result['permission'],'deny')

    def test_wrong_nonce_rejected(self):
        result,_=self.invoke('cursor','beforeShellExecution',True,lambda d:d.update(nonce='wrong'))
        self.assertEqual(result['permission'],'deny')

    def test_numeric_boolean_rejected(self):
        result,_=self.invoke('cursor','beforeShellExecution',1)
        self.assertEqual(result['permission'],'deny')

    def test_notice_no_permission(self):
        result,record=self.invoke('relay','Notification',payload={'title':'Fixture','body':'A local test'})
        self.assertEqual(result,{})
        self.assertEqual(record['title'],'Fixture')
        self.assertFalse(record['approval'])

    def test_oversized_request_cannot_be_approved(self):
        result,record=self.invoke('cursor','beforeShellExecution',payload={'command':'x'*66000})
        self.assertEqual(result['permission'],'deny')
        self.assertFalse(record['approval'])

if __name__=='__main__': unittest.main()
