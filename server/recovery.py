"""Executable reference for a *proposed* Telegram server change.

Not Telegram's server and not an API endpoint supported by Telegram.
Authentication is supplied by the host: actor_id must come from a verified
session, never from an untrusted restore request body.
"""
from contextlib import contextmanager
import json
import sqlite3
import time


class RecoveryError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


class RecoveryStore:
    def __init__(self, path, *, clock=time.time, retention=48 * 3600):
        if retention <= 0:
            raise ValueError('retention must be positive')
        self.clock, self.retention = clock, retention
        self.db = sqlite3.connect(path, isolation_level=None, timeout=10)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS admins(
                channel INTEGER, actor INTEGER, can_restore INTEGER NOT NULL,
                PRIMARY KEY(channel,actor));
            CREATE TABLE IF NOT EXISTS posts(
                channel INTEGER, id INTEGER, original TEXT NOT NULL,
                deleted_at REAL, expires_at REAL, deletion_event INTEGER,
                PRIMARY KEY(channel,id));
            CREATE TABLE IF NOT EXISTS events(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                channel INTEGER NOT NULL, post INTEGER NOT NULL,
                actor INTEGER NOT NULL, action TEXT NOT NULL, time REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS operations(
                actor INTEGER, request_id TEXT, channel INTEGER NOT NULL,
                post INTEGER NOT NULL, deletion_event INTEGER NOT NULL,
                result TEXT NOT NULL, PRIMARY KEY(actor,request_id));
            CREATE TABLE IF NOT EXISTS outbox(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                channel INTEGER NOT NULL, payload TEXT NOT NULL);
        ''')

    def close(self):
        self.db.close()

    @contextmanager
    def transaction(self):
        self.db.execute('BEGIN IMMEDIATE')
        try:
            yield
            self.db.execute('COMMIT')
        except BaseException:
            self.db.execute('ROLLBACK')
            raise

    def _authorize(self, channel, actor):
        row = self.db.execute('SELECT can_restore FROM admins WHERE channel=? AND actor=?',
                              (channel, actor)).fetchone()
        if not row or not row['can_restore']:
            raise RecoveryError('ADMIN_REQUIRED')

    def grant(self, channel, actor, enabled=True):
        """Test fixture / host integration. Never expose directly to the client."""
        self.db.execute('INSERT OR REPLACE INTO admins VALUES(?,?,?)', (channel, actor, enabled))

    def publish_fixture(self, channel, post, original):
        """Only seeds a local demonstration. Real integration uses canonical storage."""
        if original.get('id') != post or not isinstance(original.get('date'), int):
            raise ValueError('canonical id and timestamp required')
        self.db.execute('INSERT INTO posts(channel,id,original) VALUES(?,?,?)',
                        (channel, post, json.dumps(original, ensure_ascii=False, sort_keys=True)))

    def delete(self, channel, post, actor):
        """Reference interception of the existing delete transaction."""
        with self.transaction():
            self._authorize(channel, actor)
            row = self.db.execute('SELECT * FROM posts WHERE channel=? AND id=?', (channel, post)).fetchone()
            if not row or row['deleted_at'] is not None:
                raise RecoveryError('POST_NOT_AVAILABLE')
            now = self.clock()
            event = self.db.execute("INSERT INTO events(channel,post,actor,action,time) VALUES(?,?,?,'delete',?)",
                                    (channel, post, actor, now)).lastrowid
            self.db.execute('UPDATE posts SET deleted_at=?,expires_at=?,deletion_event=? WHERE channel=? AND id=?',
                            (now, now + self.retention, event, channel, post))
            self._emit(channel, {'kind': 'delete', 'post_id': post, 'event_id': event})
            return {'event_id': event, 'expires_at': now + self.retention}

    def restore(self, channel, post, deletion_event, actor, request_id):
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
            raise RecoveryError('INVALID_REQUEST_ID')
        with self.transaction():
            # Rights are checked even for replayed requests, using current server state.
            self._authorize(channel, actor)
            row = self.db.execute('SELECT * FROM posts WHERE channel=? AND id=?', (channel, post)).fetchone()
            if not row:
                raise RecoveryError('POST_NOT_AVAILABLE')
            # A confirmation for an older deletion must never undo a newer deletion.
            if row['deletion_event'] != deletion_event:
                raise RecoveryError('DELETION_CHANGED')
            previous = self.db.execute('SELECT * FROM operations WHERE actor=? AND request_id=?',
                                       (actor, request_id)).fetchone()
            if previous:
                if (previous['channel'], previous['post'], previous['deletion_event']) != (channel, post, deletion_event):
                    raise RecoveryError('REQUEST_ID_REUSED')
                result = json.loads(previous['result'])
                result['post'] = json.loads(row['original'])
                result['deletion_event'] = deletion_event
                return result
            original = json.loads(row['original'])
            # Other admins / another window may have already restored this generation.
            if row['deleted_at'] is None:
                result = {'status': 'already_restored', 'post': original, 'deletion_event': deletion_event}
            else:
                if self.clock() >= row['expires_at']:
                    raise RecoveryError('RECOVERY_EXPIRED')
                self.db.execute('UPDATE posts SET deleted_at=NULL,expires_at=NULL WHERE channel=? AND id=?',
                                (channel, post))
                self.db.execute("INSERT INTO events(channel,post,actor,action,time) VALUES(?,?,?,'restore',?)",
                                (channel, post, actor, self.clock()))
                # Canonical ID, timestamp, media, discussion links and counters are not rewritten.
                # Production Telegram must supply normal PTS ordering and notification suppression.
                self._emit(channel, {'kind': 'restore', 'post': original, 'deletion_event': deletion_event})
                result = {'status': 'restored', 'post': original, 'deletion_event': deletion_event}
            self.db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?)',
                            (actor, request_id, channel, post, deletion_event, json.dumps({'status': result['status']})))
            return result

    def purge_expired(self):
        """Reference retention worker. Production must also release media references."""
        with self.transaction():
            expired = self.db.execute('SELECT channel,id FROM posts WHERE deleted_at IS NOT NULL AND expires_at<=?',
                                      (self.clock(),)).fetchall()
            for row in expired:
                self.db.execute('DELETE FROM operations WHERE channel=? AND post=?', (row['channel'], row['id']))
                # Do not retain an expired original inside an older recovery update.
                for update in self.db.execute('SELECT id,payload FROM outbox WHERE channel=?', (row['channel'],)).fetchall():
                    payload = json.loads(update['payload'])
                    if payload.get('post', {}).get('id') == row['id'] or payload.get('post_id') == row['id']:
                        self.db.execute('DELETE FROM outbox WHERE id=?', (update['id'],))
                self.db.execute('DELETE FROM posts WHERE channel=? AND id=?', (row['channel'], row['id']))
                self._emit(row['channel'], {'kind': 'expired', 'post_id': row['id']})
            return len(expired)

    def _emit(self, channel, payload):
        self.db.execute('INSERT INTO outbox(channel,payload) VALUES(?,?)', (channel, json.dumps(payload)))

    def visible(self, channel):
        rows = self.db.execute('SELECT original FROM posts WHERE channel=? AND deleted_at IS NULL ORDER BY id',
                               (channel,)).fetchall()
        return [json.loads(row['original']) for row in rows]

    def snapshot(self, channel, actor):
        """A consistent admin view for the executable reference client."""
        with self.transaction():
            self._authorize(channel, actor)
            posts = {r['id']: r for r in self.db.execute('SELECT * FROM posts WHERE channel=?', (channel,))}
            events = []
            now = self.clock()
            for event in self.db.execute('SELECT * FROM events WHERE channel=? ORDER BY id DESC', (channel,)):
                # Channel-level actions have no message body to expire or restore.
                if event['action'] in ('create_channel', 'change_photo'):
                    events.append({'id': event['id'], 'post_id': event['post'],
                                   'action': event['action'], 'time': event['time'],
                                   'status': 'info', 'can_restore': False,
                                   'expires_at': None, 'post': None})
                    continue
                row = posts.get(event['post'])
                latest = bool(row and row['deletion_event'] == event['id'])
                recoverable = bool(event['action'] == 'delete' and latest and row['deleted_at'] is not None
                                   and now < row['expires_at'])
                if row is None or (row['deleted_at'] is not None and now >= row['expires_at']):
                    status = 'expired'
                elif not latest and event['action'] == 'delete':
                    status = 'superseded'
                elif event['action'] == 'restore' or row['deleted_at'] is None:
                    status = 'restored'
                else:
                    status = 'deleted'
                events.append({'id': event['id'], 'post_id': event['post'], 'action': event['action'],
                               'time': event['time'], 'status': status, 'can_restore': recoverable,
                               'expires_at': row['expires_at'] if recoverable else None,
                               'post': json.loads(row['original']) if row and status != 'expired' else None})
            return {'posts': [json.loads(r['original']) for r in sorted(posts.values(), key=lambda r: r['id'])
                              if r['deleted_at'] is None], 'events': events,
                    'version': self.db.execute('SELECT COALESCE(MAX(id),0) FROM outbox').fetchone()[0],
                    'server_time': now, 'retention_seconds': self.retention}
