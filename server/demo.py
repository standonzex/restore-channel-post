"""Run a real transaction on an isolated temporary reference database."""
import tempfile
from pathlib import Path
from recovery import RecoveryStore

with tempfile.TemporaryDirectory() as folder:
    store = RecoveryStore(str(Path(folder) / 'demo.sqlite'))
    try:
        store.grant(100, 1)
        for post_id, timestamp in [(10, 1794816000), (11, 1794902400), (12, 1794988800)]:
            store.publish_fixture(100, post_id, {'id': post_id, 'date': timestamp, 'text': f'Post {post_id}'})
        original = store.visible(100)
        event = store.delete(100, 11, 1)
        print('After deletion:', store.visible(100))
        result = store.restore(100, 11, event['event_id'], 1, 'demo-request')
        print('After restoration:', store.visible(100))
        assert original == store.visible(100)
        print('PASS: all original objects, IDs, timestamps and order preserved.')
    finally:
        store.close()
