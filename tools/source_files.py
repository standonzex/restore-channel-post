"""Single allowlist for source archives and the publication checkout."""
import os
from pathlib import Path

ROOTS={'app','server','tests','tools','ios','module','ios-demo','.github','submission'}
EXCLUDED={'.git','.build','.swiftpm','__pycache__','dist','release','.venv','node_modules'}

def source_files(root):
    root=Path(root)
    paths=[]
    for current,directories,files in os.walk(root):
        relative=Path(current).relative_to(root)
        if relative==Path('.'):
            directories[:]=[d for d in directories if d in ROOTS]
        else:
            directories[:]=[d for d in directories if d not in EXCLUDED and not d.startswith('.')]
        for name in files:
            path=Path(current)/name
            item=path.relative_to(root)
            if path.is_symlink() or name.startswith('.') and name!='.gitignore': continue
            if len(item.parts)==1 and path.suffix not in {'.md','.sh','.command','.txt'} and name!='.gitignore': continue
            if path.suffix in {'.zip','.sha256','.sqlite','.sqlite3','.pyc','.bundle'}: continue
            paths.append(path)
    return sorted(paths)
