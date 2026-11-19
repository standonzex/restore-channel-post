import concurrent.futures
from http.client import HTTPConnection
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from http_api import DemoServer, CHANNEL, ACTOR

class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root/'demo-circle.mov').write_bytes(b'0123456789')
        self.server = DemoServer(self.root/'demo.sqlite3', 'test-secret', self.root)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(timeout=5)
        self.tmp.cleanup()
    def request(self, path='/api/state', body=None, headers=None):
        conn = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        request_headers = {'Authorization':'Bearer test-secret', 'Content-Type':'application/json'}
        request_headers.update(headers or {})
        conn.request('POST' if body is not None else 'GET', path, json.dumps(body) if body is not None else None, request_headers)
        response = conn.getresponse()
        status, data = response.status, response.read()
        conn.close()
        return status, json.loads(data)
    def test_native_client_flow(self):
        status, before = self.request()
        self.assertEqual(status, 200)
        post = before['posts'][0]
        status, deletion = self.request('/api/delete', {'post_id':post['id']})
        self.assertEqual(status, 200)
        _, removed = self.request()
        self.assertEqual(len(removed['posts']), 3)
        self.assertTrue(removed['events'][0]['can_restore'])
        body = {'post_id':post['id'], 'deletion_event':deletion['event_id'], 'request_id':'retry-same'}
        status, restored = self.request('/api/restore', body)
        self.assertEqual(status, 200)
        self.assertEqual(restored['post'], post)
        self.assertEqual(self.request('/api/restore', body)[1], restored)
        _, after = self.request()
        self.assertEqual(after['posts'], before['posts'])
        self.assertFalse(any(e['can_restore'] for e in after['events']))
    def test_no_credentials(self):
        self.assertEqual(self.request(headers={'Authorization':''})[0], 401)
    def test_browser_origin_is_rejected(self):
        self.assertEqual(self.request(headers={'Origin':'https://example.com'})[0], 403)
    def test_host_rebinding_is_rejected(self):
        self.assertEqual(self.request(headers={'Host':'example.com'})[0], 403)
    def test_actor_cannot_be_supplied(self):
        self.assertEqual(self.request('/api/delete', {'post_id':101, 'actor':1})[0], 400)
    def test_restore_body_cannot_override_original_date(self):
        self.assertEqual(self.request('/api/restore', {'post_id':101, 'deletion_event':1, 'request_id':'x', 'date':0})[0], 400)
    def test_invalid_ids(self):
        for value in (True, -1, 0, '101', 2**54):
            self.assertEqual(self.request('/api/delete', {'post_id':value})[0], 400)
    def test_permission_failure_has_json(self):
        with self.server.store() as store:
            store.grant(CHANNEL, ACTOR, False)
        self.assertEqual(self.request(), (403, {'error':'ADMIN_REQUIRED'}))
    def test_reset_requires_explicit_confirmation(self):
        self.assertEqual(self.request('/api/reset', {'confirmation':'yes'})[0], 400)
        self.request('/api/delete', {'post_id':101})
        self.assertEqual(self.request('/api/reset', {'confirmation':'RESET_DEMO'})[0], 200)
        _, state = self.request()
        self.assertEqual(len(state['posts']), 4)
        self.assertEqual(state['events'], [])
    def test_old_confirmation_after_reset_is_rejected(self):
        _, deletion = self.request('/api/delete', {'post_id':101})
        self.request('/api/reset', {'confirmation':'RESET_DEMO'})
        status, response = self.request('/api/restore', {'post_id':101, 'deletion_event':deletion['event_id'], 'request_id':'old'})
        self.assertEqual((status, response['error']), (409, 'DELETION_CHANGED'))

    def _purge_whole_channel(self):
        with self.server.store() as store:
            for post in store.visible(CHANNEL):
                store.delete(CHANNEL, post['id'], ACTOR)
            store.db.execute('UPDATE posts SET expires_at=0')
            self.assertEqual(store.purge_expired(), 4)

    def _restart_view(self):
        restarted = DemoServer(self.root/'demo.sqlite3', 'test-secret', self.root)
        try:
            with restarted.store() as store:
                return store.snapshot(CHANNEL, ACTOR)
        finally:
            restarted.server_close()

    def test_startup_never_resurrects_purged_posts(self):
        self._purge_whole_channel()
        state = self._restart_view()
        self.assertEqual(state['posts'], [])
        self.assertEqual(len(state['events']), 4)
        self.assertFalse(any(e['can_restore'] for e in state['events']))

    def test_empty_legacy_database_with_audit_history_is_not_reseeded(self):
        self._purge_whole_channel()
        with self.server.store() as store:
            store.db.execute('DROP TABLE demo_metadata')
        self.assertEqual(self._restart_view()['posts'], [])

    def test_explicit_reset_can_reinitialize_empty_channel(self):
        self._purge_whole_channel()
        self.assertEqual(self.request('/api/reset', {'confirmation':'RESET_DEMO'})[0], 200)
        state = self._restart_view()
        self.assertEqual(len(state['posts']), 4)
        self.assertEqual(state['events'], [])
    def test_concurrent_requests_do_not_duplicate_posts(self):
        _, deletion = self.request('/api/delete', {'post_id':101})
        def restore(i):
            return self.request('/api/restore', {'post_id':101, 'deletion_event':deletion['event_id'], 'request_id':str(i)})
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(restore, range(4)))
        self.assertTrue(all(s==200 for s,_ in results))
        self.assertEqual(sum(r['status']=='restored' for _,r in results), 1)
        self.assertEqual(len(self.request()[1]['posts']), 4)
    def test_video_byte_range(self):
        conn=HTTPConnection('127.0.0.1', self.server.server_port)
        conn.request('GET','/assets/demo-circle.mov',headers={'Range':'bytes=2-5'})
        response=conn.getresponse()
        self.assertEqual(response.status,206)
        self.assertEqual(response.getheader('Content-Range'),'bytes 2-5/10')
        self.assertEqual(response.read(),b'2345'); conn.close()
    def test_asset_traversal_is_not_served(self):
        self.assertEqual(self.request('/assets/../recovery.py')[0],404)


    def test_empty_channel_composer_and_circle_recovery(self):
        self.assertEqual(self.request('/api/demo/empty', {'confirmation':'EMPTY_DEMO'})[0], 200)
        self.assertEqual(self.request()[1]['posts'], [])
        _, text = self.request('/api/demo/publish', {'kind':'text','text':'первая запись 🤍','request_id':'text-1'})
        _, video = self.request('/api/demo/publish', {'kind':'video_note','text':'','request_id':'video-1'})
        circle = video['post']
        self.assertEqual(circle['asset'], 'demo-circle.mov')
        self.assertEqual(self.request()[1]['posts'], [text['post'], circle])
        _, deletion = self.request('/api/delete', {'post_id':circle['id']})
        self.assertEqual(self.request()[1]['posts'], [text['post']])
        status, restored = self.request('/api/restore', {'post_id':circle['id'], 'deletion_event':deletion['event_id'], 'request_id':'restore-created'})
        self.assertEqual(status, 200)
        self.assertEqual(restored['post'], circle)
        self.assertEqual(self.request()[1]['posts'], [text['post'], circle])

    def test_publish_retry_is_idempotent_and_does_not_undo_deletion(self):
        body = {'kind':'text','text':'new post','request_id':'one-send'}
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            replies = list(pool.map(lambda _: self.request('/api/demo/publish', body), range(4)))
        self.assertTrue(all(s == 200 for s, _ in replies))
        self.assertTrue(all(reply == replies[0][1] for _, reply in replies))
        self.assertEqual(len(self.request()[1]['posts']), 5)
        post = replies[0][1]['post']
        self.request('/api/delete', {'post_id':post['id']})
        self.assertEqual(self.request('/api/demo/publish', body), replies[0])
        self.assertFalse(any(p['id'] == post['id'] for p in self.request()[1]['posts']))
        self.assertEqual(self.request('/api/demo/publish', dict(body, text='different'))[1]['error'], 'REQUEST_ID_REUSED')

    def test_publish_validation_and_current_rights(self):
        for body in ({'kind':'text','text':' ','request_id':'a'}, {'kind':'photo','text':'x','request_id':'a'},
                     {'kind':'text','text':7,'request_id':'a'}, {'kind':'text','text':'x','request_id':True},
                     {'kind':'text','text':'x','request_id':'a','date':1}):
            self.assertEqual(self.request('/api/demo/publish', body)[0], 400)
        with self.server.store() as store:
            store.grant(CHANNEL, ACTOR, False)
        self.assertEqual(self.request('/api/demo/publish', {'kind':'text','text':'x','request_id':'a'})[0], 403)
        self.assertEqual(self.request('/api/demo/empty', {'confirmation':'EMPTY_DEMO'})[0], 403)

    def test_empty_channel_persists_and_post_ids_are_not_reused(self):
        self.assertEqual(self.request('/api/demo/empty', {'confirmation':'yes'})[0], 400)
        self.request('/api/demo/empty', {'confirmation':'EMPTY_DEMO'})
        self.assertEqual(self._restart_view()['posts'], [])
        _, first = self.request('/api/demo/publish', {'kind':'text','text':'first','request_id':'a'})
        self.request('/api/demo/empty', {'confirmation':'EMPTY_DEMO'})
        _, second = self.request('/api/demo/publish', {'kind':'text','text':'second','request_id':'b'})
        self.assertGreater(second['post']['id'], first['post']['id'])
        self.assertEqual(self._restart_view()['posts'], [second['post']])


    def test_fresh_iphone_channel_starts_empty_without_reseeding_on_restart(self):
        path = self.root/'fresh-iphone.sqlite3'
        fresh = DemoServer(path, 'test-secret', self.root, start_empty=True)
        try:
            with fresh.store() as store:
                state = store.snapshot(CHANNEL, ACTOR)
                self.assertEqual(state['posts'], [])
                self.assertEqual(state['events'], [])
        finally:
            fresh.server_close()
        restarted = DemoServer(path, 'test-secret', self.root)
        try:
            with restarted.store() as store:
                self.assertEqual(store.snapshot(CHANNEL, ACTOR)['posts'], [])
        finally:
            restarted.server_close()
