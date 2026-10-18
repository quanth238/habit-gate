#!/usr/bin/env python3
"""Check installed identity, native protocol and permissions without reading the API key."""
import base64, hashlib, json, pathlib, struct, subprocess

app=pathlib.Path('/Applications/Habit Gate.app')
support=pathlib.Path.home()/'Library/Application Support/HabitGate'
manifest=json.loads((support/'ChromeExtension/manifest.json').read_text())
digest=hashlib.sha256(base64.b64decode(manifest['key'])).hexdigest()[:32]
identity=''.join(chr(97+int(char,16)) for char in digest)
assert identity==(app/'Contents/Resources/extension-id.txt').read_text().strip()
hostfile=pathlib.Path.home()/'Library/Application Support/Google/Chrome/NativeMessagingHosts/me.habitgate.bridge.json'
host=json.loads(hostfile.read_text())
assert host['allowed_origins']==[f'chrome-extension://{identity}/']
assert host['path']==str(app/'Contents/MacOS/HabitGateBridge')
assert hostfile.stat().st_mode & 0o777 == 0o600
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
bridge=str(app/'Contents/MacOS/HabitGateBridge')
origin=f'chrome-extension://{identity}/'
body=json.dumps({'command':'getState'}).encode()
response=subprocess.run([bridge,origin],input=struct.pack('<I',len(body))+body,capture_output=True,timeout=10,check=True).stdout
length=struct.unpack('<I',response[:4])[0]
assert length==len(response[4:])
data=json.loads(response[4:])
assert set(data)=={'snapshot','configured','hostAvailable'}
assert data['snapshot']['version']==1
assert 'apiKey' not in data['snapshot'] and 'key' not in data['snapshot']
assert subprocess.run([bridge,'chrome-extension://unauthorized/'],input=b'',capture_output=True,timeout=5).returncode!=0
assert subprocess.run([bridge,origin],input=struct.pack('<I',65537),capture_output=True,timeout=5).returncode!=0
print('PASS: installed signature, fixed extension ID, owner-only host registration, native framing, origin rejection and oversized-message rejection.')
print('This checks the native protocol directly. It does not establish that Chrome has loaded the extension.')
