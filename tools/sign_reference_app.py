"""Ad-hoc sign only this project's generated app; leave security attributes alone."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
if not app.is_relative_to(root/'dist') or app.suffix != '.app':
    raise SystemExit('Only generated apps under this project dist/ can be signed')

def clear_finder_metadata():
    # iCloud/File Provider may reattach these while a build is being written.
    # Do not clear quarantine, provenance or other unrelated attributes.
    for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
        subprocess.run(['xattr', '-dr', attribute, str(app)], capture_output=True)

for attempt in range(3):
    clear_finder_metadata()
    result = subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], capture_output=True, text=True)
    if result.returncode == 0:
        clear_finder_metadata()
        verification = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
        if verification.returncode == 0:
            print('Ad-hoc signature verified:', app)
            break
        result = verification
    if 'resource fork, Finder information' not in result.stderr or attempt == 2:
        raise SystemExit(result.stderr or 'Reference app signing failed')
