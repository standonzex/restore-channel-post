"""Loopback-only reference API for the native feature demo; no Telegram access."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import threading
import time
from urllib.parse import urlsplit
from recovery import RecoveryStore, RecoveryError

CHANNEL = 100
ACTOR = 1  # Bound to the local demo session, never read from request JSON.


def seed(store, *, reset=False, start_empty=False):
    with store.transaction():
        # An empty channel is a valid persisted state after retention cleanup.
        # Startup must never resurrect deleted posts merely because it is empty.
        store.db.execute('CREATE TABLE IF NOT EXISTS demo_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)')
        store.db.execute('CREATE TABLE IF NOT EXISTS demo_publications(request_id TEXT PRIMARY KEY, post_id INTEGER NOT NULL, fingerprint TEXT NOT NULL)')
        if reset:
            for table in ('operations', 'outbox', 'events', 'posts', 'admins', 'demo_publications'):
                store.db.execute(f'DELETE FROM {table}')
            store.db.execute('DELETE FROM demo_metadata')
        initialized = store.db.execute("SELECT 1 FROM demo_metadata WHERE key='initialized'").fetchone()
        # Older databases have no marker; audit history also proves initialization.
        existing = store.db.execute('SELECT 1 FROM posts LIMIT 1').fetchone() or store.db.execute('SELECT 1 FROM events LIMIT 1').fetchone()
        store.db.execute("INSERT OR REPLACE INTO demo_metadata VALUES('initialized','1')")
        if initialized or existing:
            return
        store.grant(CHANNEL, ACTOR)
        if start_empty:
            return
        samples = [
            (101, 1648981800, 'text', 'моя первая запись здесь. пусть останется. 🤍', 128, 24, None),
            (102, 1794897000, 'photo', 'серебро на веках, ночь за окном.', 86, 12, 'demo-photo.png'),
            (103, 1794986100, 'video_note', 'пару слов перед сном 🌙', 54, 8, 'demo-circle.mov'),
            (104, 1795075200, 'text', 'кое-что хочется сохранить навсегда. ✨', 42, 6, None),
        ]
        for post_id, date, kind, text, reactions, comments, asset in samples:
            store.publish_fixture(CHANNEL, post_id, {'id': post_id, 'date': date, 'kind': kind,
                'text': text, 'reactions': reactions, 'comments': comments, 'asset': asset})



def publish_demo(store, kind, text, request_id):
    """Reference-host composer only; not a proposed Telegram publish API."""
    if kind not in ('text', 'video_note') or not isinstance(text, str) or len(text) > 2000:
        raise ValueError()
    text = text.strip()
    if kind == 'text' and not text:
        raise ValueError()
    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
        raise ValueError()
    fingerprint = hashlib.sha256(json.dumps([kind, text], ensure_ascii=False).encode()).hexdigest()
    with store.transaction():
        store._authorize(CHANNEL, ACTOR)
        previous = store.db.execute('SELECT * FROM demo_publications WHERE request_id=?', (request_id,)).fetchone()
        if previous:
            if previous['fingerprint'] != fingerprint:
                raise RecoveryError('REQUEST_ID_REUSED')
            row = store.db.execute('SELECT original FROM posts WHERE channel=? AND id=?', (CHANNEL, previous['post_id'])).fetchone()
            if not row:
                raise RecoveryError('POST_NOT_AVAILABLE')
            return {'post': json.loads(row['original'])}
        last = store.db.execute("SELECT value FROM demo_metadata WHERE key='last_published_id'").fetchone()
        maximum = store.db.execute('SELECT COALESCE(MAX(id),100) FROM posts WHERE channel=?', (CHANNEL,)).fetchone()[0]
        post_id = max(int(last[0]) if last else 100, maximum) + 1
        store.db.execute("INSERT OR REPLACE INTO demo_metadata VALUES('last_published_id',?)", (str(post_id),))
        post = {'id': post_id, 'date': int(store.clock()), 'kind': kind, 'text': text,
                'reactions': 0, 'comments': 0, 'asset': 'demo-circle.mov' if kind == 'video_note' else None}
        store.publish_fixture(CHANNEL, post_id, post)
        store.db.execute('INSERT INTO demo_publications VALUES(?,?,?)', (request_id, post_id, fingerprint))
        store._emit(CHANNEL, {'kind': 'publish', 'post': post})
        return {'post': post}


def empty_demo(store):
    """Explicit reset of synthetic content; retain the initialization marker and rights."""
    with store.transaction():
        store._authorize(CHANNEL, ACTOR)
        for table in ('operations', 'outbox', 'events', 'posts', 'demo_publications'):
            store.db.execute(f'DELETE FROM {table}')
        store.db.execute("INSERT OR REPLACE INTO demo_metadata VALUES('initialized','1')")
    return {'status': 'empty'}

class DemoServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, db_path, token, assets, port=0, *, start_empty=False):
        self.db_path, self.token, self.assets = str(db_path), token, Path(assets)
        self.session_lock = threading.Lock()
        self.last_purge = 0
        super().__init__(('127.0.0.1', port), Handler)
        with self.store() as store:
            seed(store, start_empty=start_empty)

    def service_actions(self):
        if time.monotonic() - self.last_purge >= 30:
            with self.store() as store:
                store.purge_expired()
            self.last_purge = time.monotonic()

    def store(self):
        from contextlib import contextmanager
        @contextmanager
        def connection():
            store = RecoveryStore(self.db_path)
            try:
                yield store
            finally:
                store.close()
        return connection()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *_):
        pass

    def respond(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        self.wfile.write(data)

    def authorized(self):
        # No CORS. Native URLSession needs no Origin. Reject browser-origin requests.
        if self.headers.get('Origin'):
            self.respond(403, {'error': 'ORIGIN_REJECTED'})
            return False
        expected_host = f'127.0.0.1:{self.server.server_port}'
        if self.headers.get('Host') != expected_host:
            self.respond(403, {'error': 'HOST_REJECTED'})
            return False
        supplied = self.headers.get('Authorization', '')
        if not secrets.compare_digest(supplied, 'Bearer ' + self.server.token):
            self.respond(401, {'error': 'UNAUTHORIZED'})
            return False
        return True

    def do_GET(self):
        path = urlsplit(self.path).path
        # Media is synthetic, fixed and loopback-only. AVPlayer cannot set the bearer header.
        if path.startswith('/assets/'):
            self.asset(path.removeprefix('/assets/'))
            return
        if not self.authorized():
            return
        if path != '/api/state':
            self.respond(404, {'error': 'NOT_FOUND'})
            return
        try:
            with self.server.store() as store:
                self.respond(200, store.snapshot(CHANNEL, ACTOR))
        except RecoveryError as error:
            self.respond(403, {'error': error.code})

    def do_POST(self):
        if not self.authorized():
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096:
                raise ValueError()
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError()
            path = urlsplit(self.path).path
            with self.server.session_lock, self.server.store() as store:
                if path == '/api/delete':
                    self.validate_keys(body, {'post_id'})
                    result = store.delete(CHANNEL, self.integer(body['post_id']), ACTOR)
                elif path == '/api/restore':
                    self.validate_keys(body, {'post_id', 'deletion_event', 'request_id'})
                    result = store.restore(CHANNEL, self.integer(body['post_id']),
                        self.integer(body['deletion_event']), ACTOR, body['request_id'])
                elif path == '/api/demo/publish':
                    self.validate_keys(body, {'kind', 'text', 'request_id'})
                    result = publish_demo(store, body['kind'], body['text'], body['request_id'])
                elif path == '/api/demo/empty':
                    self.validate_keys(body, {'confirmation'})
                    if body['confirmation'] != 'EMPTY_DEMO':
                        raise ValueError()
                    result = empty_demo(store)
                elif path == '/api/reset':
                    self.validate_keys(body, {'confirmation'})
                    if body['confirmation'] != 'RESET_DEMO':
                        raise ValueError()
                    seed(store, reset=True)
                    result = {'status': 'reset'}
                else:
                    self.respond(404, {'error': 'NOT_FOUND'})
                    return
                self.respond(200, result)
        except (ValueError, TypeError, KeyError, json.JSONDecodeError):
            self.respond(400, {'error': 'INVALID_REQUEST'})
        except RecoveryError as error:
            status = 403 if error.code == 'ADMIN_REQUIRED' else 409
            self.respond(status, {'error': error.code})
        except Exception:
            self.respond(500, {'error': 'SERVER_ERROR'})

    @staticmethod
    def integer(value):
        if type(value) is not int or value <= 0 or value > 2**53:
            raise ValueError()
        return value

    @staticmethod
    def validate_keys(body, keys):
        if set(body) != keys:
            raise ValueError()

    def asset(self, name):
        if name not in ('demo-photo.png', 'demo-circle.mov'):
            self.respond(404, {'error': 'NOT_FOUND'})
            return
        file = self.server.assets / name
        if not file.is_file():
            self.respond(404, {'error': 'NOT_FOUND'})
            return
        data = file.read_bytes()
        start, end, status = 0, len(data)-1, 200
        header = self.headers.get('Range')
        if header:
            try:
                if not header.startswith('bytes=') or ',' in header:
                    raise ValueError()
                left, right = header[6:].split('-', 1)
                if left:
                    start = int(left)
                    end = int(right) if right else end
                else:
                    start = max(0, len(data)-int(right))
                if start < 0 or start >= len(data) or end < start:
                    raise ValueError()
                end = min(end, len(data)-1)
                status = 206
            except (ValueError, TypeError):
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{len(data)}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
        part = data[start:end+1]
        self.send_response(status)
        self.send_header('Content-Type', 'image/png' if name.endswith('.png') else 'video/quicktime')
        self.send_header('Content-Length', str(len(part)))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Cache-Control', 'no-store')
        if status == 206:
            self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
        self.end_headers()
        self.wfile.write(part)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--assets', required=True)
    parser.add_argument('--start-empty', action='store_true', help='Start a fresh synthetic database with an empty channel; never clears existing state')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--parent-pid', type=int)
    args = parser.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    token = os.environ.get('RECOVERY_DEMO_TOKEN') or secrets.token_urlsafe(32)
    server = DemoServer(args.db, token, args.assets, args.port, start_empty=args.start_empty)
    print(json.dumps({'url': f'http://127.0.0.1:{server.server_port}', 'token': token}), flush=True)
    if args.parent_pid:
        def watch_parent():
            while True:
                time.sleep(2)
                try:
                    os.kill(args.parent_pid, 0)
                except ProcessLookupError:
                    server.shutdown()
                    return
        threading.Thread(target=watch_parent, daemon=True).start()
    try:
        server.serve_forever(poll_interval=.2)
    finally:
        server.server_close()

if __name__ == '__main__':
    main()
