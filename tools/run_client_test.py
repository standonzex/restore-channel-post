from pathlib import Path
import json
import os
import secrets
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    token = secrets.token_urlsafe(32)
    env = dict(os.environ, RECOVERY_DEMO_TOKEN=token)
    server = subprocess.Popen([sys.executable, str(root/'server/http_api.py'), '--db', str(Path(tmp)/'demo.sqlite3'),
        '--assets', str(root/'app/Resources/media')], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        line = server.stdout.readline()
        if not line:
            raise RuntimeError('Reference server did not start')
        configuration = json.loads(line)
        test_env = dict(os.environ, RECOVERY_TEST_URL=configuration['url'], RECOVERY_TEST_TOKEN=token)
        subprocess.run([sys.argv[1]], check=True, env=test_env)
    finally:
        server.terminate()
        try: server.wait(timeout=5)
        except subprocess.TimeoutExpired: server.kill(); server.wait()
