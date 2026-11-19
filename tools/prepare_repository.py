"""Prepare an isolated local Git checkout for review. Does not publish anything."""
from pathlib import Path
import shutil
import subprocess
from source_files import source_files

root=Path(__file__).resolve().parents[1]
destination=root/'release/publication/RestoreChannelPost'
if destination.exists():
    raise SystemExit('Publication checkout already exists. Review it before replacing anything.')
destination.mkdir(parents=True)
for source in source_files(root):
    target=destination/source.relative_to(root)
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
shutil.copyfile(destination/'README.md',destination/'README-RU.md')
shutil.copyfile(destination/'README-EN.md',destination/'README.md')
subprocess.run(['git','init','-b','codex/restore-channel-post'],cwd=destination,check=True,capture_output=True)
subprocess.run(['git','add','--all'],cwd=destination,check=True)
subprocess.run(['git','-c','user.name=Codex','-c','user.email=codex@openai.com','commit','-m','Add recoverable channel post reference implementation and integration module'],cwd=destination,check=True,capture_output=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=destination,text=True).strip()
files=subprocess.check_output(['git','ls-files'],cwd=destination,text=True).splitlines()
assert not any('/.build/' in f or f.endswith('.sqlite3') or f=='.env' for f in files)
bundle=root/'release/RestoreChannelPost-1.1.bundle'
subprocess.run(['git','bundle','create',str(bundle),'--all'],cwd=destination,check=True)
(root/'release/PUBLICATION-REVIEW.md').write_text(f'''# Prepared publication checkout

Suggested repository name: `restore-channel-post`.
Local path: `{destination}`.
Branch: `codex/restore-channel-post`.
Commit: `{commit}`.
Tracked files: {len(files)}.

No remote is configured; nothing has been published. The checkout contains only this proposal's allowlisted code, fixtures, documentation and CI. It excludes Again, credentials, local databases, generated build caches and application state.

Read README.md, SUBMISSION.md, QA-REPORT.md and INTEGRATION.md before publication. iOS simulator and full Telegram iOS checks remain explicitly marked as unverified until actually run. The public server contract still requires Telegram's support.

The included GitHub workflow verifies the Mac implementation and attempts the standalone iPhone simulator build. Its jobs have not run on GitHub yet. Public publication will expose the listed source files and start that workflow. Choose the GitHub account and confirm repository visibility before publishing.
''')
print('Prepared local checkout:',destination)
print('Commit:',commit)
print('Files:',len(files))
print('Git bundle:',bundle)
