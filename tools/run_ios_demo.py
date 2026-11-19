"""Start the reference service and launch only our own app on a selected simulator."""
from pathlib import Path
import json
import os
import secrets
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
udid = sys.argv[1] if len(sys.argv)>1 else 'booted'
capture_args = sys.argv[2:]
if capture_args not in ([], ['--capture-canvas']):
    raise SystemExit('Usage: run-ios-demo.sh [simulator-udid] [--capture-canvas]')
env = dict(os.environ)
if 'DEVELOPER_DIR' not in env and Path('/Applications/Xcode.app/Contents/Developer').is_dir():
    env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
app = root/'dist/ios-simulator/RestoreChannelPost.app'
if not (app/'RestoreChannelPost').is_file():
    raise SystemExit('Build the iOS reference app first: ./build-ios-demo.sh')
# Persistent synthetic iOS dataset, separate from the Mac demo and all live accounts.
support=Path.home()/'Library/Application Support/ChannelRecoveryReference'
support.mkdir(parents=True,exist_ok=True)
server_env=dict(env, RECOVERY_DEMO_TOKEN=secrets.token_urlsafe(32))
server=subprocess.Popen([sys.executable,str(root/'server/http_api.py'),'--db',str(support/'ios-demo.sqlite3'),
    '--start-empty','--assets',str(root/'app/Resources/media')],stdout=subprocess.PIPE,text=True,env=server_env)
try:
    line=server.stdout.readline()
    if not line: raise RuntimeError('Reference server failed to start')
    config=json.loads(line)
    launch_env=dict(env,SIMCTL_CHILD_RECOVERY_REFERENCE_URL=config['url'],SIMCTL_CHILD_RECOVERY_REFERENCE_TOKEN=config['token'])
    subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True,env=env)
    subprocess.run(['xcrun','simctl','launch','--terminate-running-process',udid,'local.again.channelrecovery.iosreference',*capture_args],check=True,env=launch_env)
    print('Reference server is running. Keep this terminal open; press Ctrl+C after testing.')
    server.wait()
except KeyboardInterrupt:
    pass
finally:
    server.terminate()
    try: server.wait(timeout=5)
    except subprocess.TimeoutExpired: server.kill(); server.wait()
