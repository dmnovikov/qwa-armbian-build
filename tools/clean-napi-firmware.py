#!/usr/bin/env python3
"""Keep configured firmware in an Armbian image."""

import fnmatch
import os
from pathlib import Path
import sys


def clean(root, apply, patterns):
    root = root.resolve(strict=True)
    if root == Path('/') or not (root / 'etc/armbian-release').is_file():
        raise ValueError('Expected an Armbian image root directory.')
    for pattern in patterns:
        if not pattern or pattern.startswith('/') or '..' in pattern.split('/'):
            raise ValueError(f'Invalid firmware pattern: {pattern}')

    firmware = root / 'usr/lib/firmware'
    if not firmware.exists():
        firmware = root / 'lib/firmware'
    resolved = firmware.resolve()
    if not resolved.is_relative_to(root) or firmware.is_symlink():
        raise ValueError('Firmware directory escapes the image or is a symlink.')
    firmware = resolved
    files = {}
    directories = []
    for parent, dirs, names in os.walk(firmware, followlinks=False):
        parent = Path(parent)
        for name in list(dirs):
            path = parent / name
            if path.is_symlink():
                names.append(name)
                dirs.remove(name)
            else:
                directories.append(path)
        for name in names:
            path = parent / name
            files[path.relative_to(firmware).as_posix()] = path

    keep = {
        name for name, path in files.items()
        if any(fnmatch.fnmatchcase(name, p) or
               (path.is_symlink() and p.startswith(name + '/')) for p in patterns)
    }
    pending = list(keep)
    while pending:
        path = files[pending.pop()]
        if not path.is_symlink():
            continue
        target = path.resolve()
        if not target.is_relative_to(firmware):
            raise ValueError(f'Firmware symlink escapes its directory: {path}')
        name = target.relative_to(firmware).as_posix()
        targets = [name] if not target.is_dir() else [n for n in files if n.startswith(name + '/')]
        for name in targets:
            if name in files and name not in keep:
                keep.add(name)
                pending.append(name)

    remove = set(files) - keep
    size = sum(files[name].lstat().st_size for name in remove)
    print(f'Firmware: keep {len(keep)} files; remove {len(remove)} files ({size / 1048576:.1f} MiB).')
    if not apply:
        return

    config_dir = root / 'etc/dpkg/dpkg.cfg.d'
    if not config_dir.resolve().is_relative_to(root):
        raise ValueError('Dpkg configuration directory escapes the image.')
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / '98-napi-firmware'
    if config.is_symlink():
        raise ValueError('Dpkg configuration file is a symlink.')
    # Keep existing symlink targets during package updates.
    includes = patterns + sorted(keep)
    lines = []
    for prefix in ['/usr/lib/firmware', '/lib/firmware']:
        lines.append(f'path-exclude={prefix}/*')
        lines.extend(f'path-include={prefix}/{pattern}' for pattern in includes)
    config.write_text('\n'.join(lines) + '\n')
    for name in sorted(remove):
        files[name].unlink()
    for path in sorted(directories, key=lambda p: len(p.parts), reverse=True):
        if not any(path.iterdir()):
            path.rmdir()


if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[2] not in ('--apply', '--dry-run'):
        sys.exit('Usage: clean-napi-firmware.py ROOTFS --apply|--dry-run [PATTERN ...]')
    clean(Path(sys.argv[1]), sys.argv[2] == '--apply', sys.argv[3:])
