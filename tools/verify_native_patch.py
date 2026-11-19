"""Apply the native patch to clean pinned files and parse every changed Swift file.

This deliberately does NOT claim type-checking, linking or running Telegram.
No files in the supplied checkout or its Git index are modified.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

BASE = '24638bc69bd083981b178dd1e7f921eebbf7fc46'
root = Path(__file__).resolve().parents[1]
checkout = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else None
if checkout is None:
    raise SystemExit('Usage: python3 tools/verify_native_patch.py /path/to/Telegram-iOS')
patch = root/'ios/channel-post-recovery.patch'
subprocess.run(['git', 'cat-file', '-e', BASE+'^{commit}'], cwd=checkout, check=True)
env = dict(os.environ)
if 'DEVELOPER_DIR' not in env and Path('/Applications/Xcode.app/Contents/Developer').is_dir():
    env['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
chunks = patch.read_text().split('diff --git ')[1:]
with tempfile.TemporaryDirectory(prefix='native-recovery-patch-') as directory:
    stage = Path(directory)
    subprocess.run(['git', 'init', '-q', directory], check=True)
    paths = []
    for chunk in chunks:
        item = Path(chunk.splitlines()[0].split(' b/', 1)[1])
        if item.is_absolute() or '..' in item.parts or item.parts[0] != 'submodules':
            raise SystemExit('Unexpected patch path')
        paths.append(item)
        if '\nnew file mode ' in chunk:
            continue
        data = subprocess.check_output(['git', 'show', f'{BASE}:{item.as_posix()}'], cwd=checkout)
        target = stage/item
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=stage, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=stage, check=True)
    # The package also supplies complete UI files for review. They must describe
    # the same implementation as the patch, not an older confirmation/button flow.
    for item in paths:
        if item.suffix != '.swift':
            continue
        if 'ChatRecentActionsController' in item.parts:
            supplied = root/'ios/Sources'/item.name
        elif 'ChannelRecoveryKit' in item.parts:
            supplied = root/'module/Sources/ChannelRecoveryKit'/item.name
        else:
            continue
        if supplied.read_bytes() != (stage/item).read_bytes():
            raise SystemExit(f'Patch/source drift: {supplied.relative_to(root)}')
    swift = [str(stage/item) for item in paths if item.suffix == '.swift']
    subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', *swift], env=env, check=True)
    subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=stage, check=True)
print(f'Clean pinned-base patch application and {len(swift)} Swift syntax checks passed.')
print('Complete native files and shared coordinator match the reconstructed patch.')
print('Full Telegram target build, server transport and runtime verification remain separate requirements.')
