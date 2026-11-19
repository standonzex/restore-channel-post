"""Package source and the locally built app without state, tokens or dependencies."""
from pathlib import Path
import hashlib
import platform
import shutil
import zipfile
from source_files import source_files

root = Path(__file__).resolve().parents[1]
release = root/'release'
release.mkdir(exist_ok=True)
version=(root/'VERSION.txt').read_text().strip()
source_archive = release/f'RestoreChannelPost-Source-{version}.zip'
app_archive = release/f'RestoreChannelPost-Mac-{platform.machine()}-{version}.zip'
source_paths=source_files(root)
with zipfile.ZipFile(source_archive,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in source_paths:
        archive.write(path, arcname=Path('RestoreChannelPost')/path.relative_to(root))
app=root/'dist/Restore Channel Post.app'
if not (app/'Contents/MacOS/RestoreChannelPost').is_file():
    raise SystemExit('Build the native app first: ./build.sh')
with zipfile.ZipFile(app_archive,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file(): archive.write(path, arcname=Path(app.name)/path.relative_to(app))
for path in (source_archive,app_archive):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        assert not any('.env' in name or '.sqlite' in name or '__pycache__' in name or '/.git/' in name for name in archive.namelist())
checksums=''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in (source_archive,app_archive))
(release/'SHA256SUMS.txt').write_text(checksums)
# Preserve the previously shared path, now with the current full source package.
shutil.copyfile(source_archive, root/'restore-channel-post-source.zip')
(root/'restore-channel-post-source.sha256').write_text(hashlib.sha256(source_archive.read_bytes()).hexdigest()+'  restore-channel-post-source.zip\n')
print(f'Source: {source_archive}')
print(f'Mac app: {app_archive}')
print(f'{len(source_paths)} source/resource files; archive integrity and exclusions verified')
