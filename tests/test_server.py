import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from recovery import RecoveryStore, RecoveryError


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = str(Path(self.tmp.name) / 'reference.sqlite')
        self.now = 1000
        self.store = RecoveryStore(self.path, clock=lambda: self.now)
        self.store.grant(10, 1)
        self.original = {'id': 50, 'date': 900, 'text': 'Original', 'kind': 'video_note',
                         'media_id': 'canonical-media-42', 'reactions': {'heart': 7},
                         'discussion': {'peer_id': 11, 'root_id': 91}, 'views': 120}
        self.store.publish_fixture(10, 49, {'id': 49, 'date': 800})
        self.store.publish_fixture(10, 50, self.original)
        self.store.publish_fixture(10, 51, {'id': 51, 'date': 950})
        self.deleted = self.store.delete(10, 50, 1)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def restore(self, actor=1, request='request-1', event=None):
        return self.store.restore(10, 50, event or self.deleted['event_id'], actor, request)

    def assertError(self, code, function):
        with self.assertRaises(RecoveryError) as result:
            function()
        self.assertEqual(result.exception.code, code)

    def test_original_identity_date_media_engagement_and_position(self):
        self.assertEqual([p['id'] for p in self.store.visible(10)], [49, 51])
        self.assertEqual(self.restore()['post'], self.original)
        self.assertEqual([p['id'] for p in self.store.visible(10)], [49, 50, 51])
        self.assertEqual(self.store.visible(10)[1], self.original)

    def test_channel_setup_events_do_not_behave_like_deleted_posts(self):
        for action in ('create_channel', 'change_photo'):
            self.store.db.execute('INSERT INTO events(channel,post,actor,action,time) VALUES(?,?,?,?,?)',
                                  (10, 0, 1, action, self.now - 100))
        snapshot = self.store.snapshot(10, 1)
        setup = [event for event in snapshot['events'] if event['action'] != 'delete']
        self.assertEqual(len(setup), 2)
        self.assertTrue(all(event['status'] == 'info' and event['post'] is None
                            and not event['can_restore'] and event['expires_at'] is None
                            for event in setup))
        deletion = next(event for event in snapshot['events'] if event['action'] == 'delete')
        self.assertTrue(deletion['can_restore'])
        self.assertEqual(self.restore()['post'], self.original)
        self.assertEqual([p['id'] for p in self.store.visible(10)], [49, 50, 51])

    def test_idempotent_retry_emits_once(self):
        first = self.restore()
        self.assertEqual(self.restore(), first)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events WHERE action='restore'").fetchone()[0], 1)
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0], 2)

    def test_two_confirmations_do_not_restore_twice(self):
        self.restore()
        self.assertEqual(self.restore(request='request-2')['status'], 'already_restored')
        self.assertEqual(len(self.store.visible(10)), 3)

    def test_unauthorized(self):
        self.assertError('ADMIN_REQUIRED', lambda: self.restore(actor=2))
        self.assertEqual(len(self.store.visible(10)), 2)

    def test_revoked_permission_including_retry(self):
        self.restore()
        self.store.grant(10, 1, False)
        self.assertError('ADMIN_REQUIRED', self.restore)

    def test_exact_expiration_boundary(self):
        self.now = self.deleted['expires_at']
        self.assertError('RECOVERY_EXPIRED', self.restore)
        self.assertEqual(len(self.store.visible(10)), 2)

    def test_retention_purge_removes_only_expired_deleted_posts(self):
        self.assertEqual(self.store.purge_expired(), 0)
        self.now = self.deleted['expires_at']
        self.assertEqual(self.store.purge_expired(), 1)
        self.assertError('POST_NOT_AVAILABLE', self.restore)
        self.assertEqual([p['id'] for p in self.store.visible(10)], [49, 51])

    def test_purge_clears_previous_restore_payloads(self):
        self.restore()
        self.store.delete(10, 50, 1)
        self.now += 48 * 3600
        self.assertEqual(self.store.purge_expired(), 1)
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM operations').fetchone()[0], 0)
        self.assertFalse(any('canonical-media-42' in row[0] for row in self.store.db.execute('SELECT payload FROM outbox')))

    def test_just_before_expiry(self):
        self.now = self.deleted['expires_at'] - .001
        self.assertEqual(self.restore()['status'], 'restored')

    def test_stale_confirmation_never_undoes_new_deletion(self):
        self.restore()
        self.store.delete(10, 50, 1)
        self.assertError('DELETION_CHANGED', self.restore)
        self.assertEqual(len(self.store.visible(10)), 2)

    def test_cross_channel(self):
        self.assertError('ADMIN_REQUIRED', lambda: self.store.restore(20, 50, self.deleted['event_id'], 1, 'x'))

    def test_request_id_is_bound_to_target(self):
        self.restore()
        deletion = self.store.delete(10, 49, 1)
        self.assertError('REQUEST_ID_REUSED', lambda: self.store.restore(10, 49, deletion['event_id'], 1, 'request-1'))
        self.assertEqual([p['id'] for p in self.store.visible(10)], [50, 51])

    def test_restart(self):
        self.store.close()
        self.store = RecoveryStore(self.path, clock=lambda: self.now)
        self.assertEqual(self.restore()['post'], self.original)

    def test_outbox_failure_rolls_back_restoration(self):
        self.store.db.execute("CREATE TRIGGER fail_update BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'outbox unavailable'); END")
        with self.assertRaises(Exception):
            self.restore()
        self.assertEqual(len(self.store.visible(10)), 2)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events WHERE action='restore'").fetchone()[0], 0)

    def test_concurrent_admins(self):
        self.store.grant(10, 2)
        barrier = threading.Barrier(2)
        results, errors = [], []
        def run(actor):
            store = RecoveryStore(self.path, clock=lambda: self.now)
            try:
                barrier.wait(timeout=5)
                results.append(store.restore(10, 50, self.deleted['event_id'], actor, f'request-{actor}'))
            except Exception as exc:
                errors.append(exc)
            finally:
                store.close()
        threads = [threading.Thread(target=run, args=(actor,)) for actor in (1, 2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join(timeout=10)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(errors, [])
        self.assertEqual(sorted(r['status'] for r in results), ['already_restored', 'restored'])
        self.assertEqual(len(self.store.visible(10)), 3)
