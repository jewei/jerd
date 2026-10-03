#!/usr/bin/env python3
"""Capture native views with memory-only fixtures after a Debug Xcode build.

No app startup, service methods, updater, or system setup is invoked.
Output stays in .build/ui-review. Requires a macOS graphical session.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
work = root / '.build/ui-review'
products = root / '.build/xcode/Build/Products/Debug'
work.mkdir(parents=True, exist_ok=True)
app = work / 'Jerd UI Review.app'
resources = app / 'Contents/Resources'
executable = app / 'Contents/MacOS/UIReview'
resources.mkdir(parents=True, exist_ok=True)
executable.parent.mkdir(parents=True, exist_ok=True)
for path in (products / 'Jerd.app/Contents/Resources').iterdir():
    if path.suffix in ('.png', '.icns', '.car'):
        shutil.copy2(path, resources / path.name)
info = plistlib.loads((products / 'Jerd.app/Contents/Info.plist').read_bytes())
info.update(CFBundleIdentifier='dev.jerd.ui-review', CFBundleExecutable='UIReview', CFBundleName='Jerd UI Review')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
# Keep production workspace code, but replace the application entry point.
entry = work / 'JerdApp.swift'
entry.write_text((root / 'Sources/Jerd/Application/JerdApp.swift').read_text().replace('@main\n', '', 1))
sources = [str(p) for p in (root / 'Sources/Jerd').rglob('*.swift') if p.name != 'JerdApp.swift']
subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-I', str(products),
                '-I', str(root / 'Packages/JerdCore/Sources/CArchive'), '-F', str(products),
                *sources, str(entry), str(root / 'Scripts/Checks/capture-ui.swift'),
                str(products / 'JerdCore.o'), '-framework', 'Sparkle', '-larchive',
                '-Xlinker', '-rpath', '-Xlinker', str(products), '-o', str(executable)], check=True)
subprocess.run([str(executable), str(work / 'screenshots-final'), *sys.argv[1:]], check=True)
