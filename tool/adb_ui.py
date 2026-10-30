#!/usr/bin/env python3
"""Tap/assert UI elements by label instead of guessing coordinates.

  ./tool/adb_ui.py tap "Set Description"
  ./tool/adb_ui.py tap-regex "Add .*"
  ./tool/adb_ui.py list
  ./tool/adb_ui.py screenshot /tmp/name.png
"""
import os
import re
import subprocess
import sys

# Wireless debugging picks a new port on every reboot, so the serial comes from
# the environment; the fallback is the phone as it usually answers.
DEVICE = os.environ.get('ADB_DEV', '172.16.23.241:5555')


def adb(*args, binary=False):
    out = subprocess.run(['adb', '-s', DEVICE, *args], capture_output=True)
    return out.stdout if binary else out.stdout.decode('utf-8', 'replace')


def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/ui.xml')
    xml = adb('shell', 'cat', '/sdcard/ui.xml')
    out = []
    for m in re.finditer(r'<node[^>]*>', xml):
        tag = m.group(0)

        def attr(name):
            a = re.search(rf'{name}="([^"]*)"', tag)
            return a.group(1) if a else ''

        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        label = (attr('content-desc') or attr('text')).replace('&#10;', ' | ')
        out.append({
            'label': label,
            'clickable': attr('clickable') == 'true',
            'center': ((x1 + x2) // 2, (y1 + y2) // 2),
        })
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'list'
    if cmd == 'list':
        for n in nodes():
            if n['label'] or n['clickable']:
                print(f"{n['label'][:50]!r:54} click={n['clickable']!s:5} {n['center']}")
        return
    if cmd == 'screenshot':
        open(sys.argv[2], 'wb').write(adb('exec-out', 'screencap', '-p', binary=True))
        return
    if cmd in ('tap', 'tap-regex', 'expect'):
        pattern = sys.argv[2]
        match = None
        for n in nodes():
            hit = (n['label'] == pattern if cmd == 'tap'
                   else re.fullmatch(pattern, n['label']))
            if hit:
                match = n
                break
        if not match:
            print(f'NOT FOUND: {pattern}')
            sys.exit(1)
        print(f"{cmd} {match['label'][:40]!r} at {match['center']}")
        if cmd != 'expect':
            adb('shell', 'input', 'tap', str(match['center'][0]), str(match['center'][1]))
        return
    print(__doc__)
    sys.exit(2)


if __name__ == '__main__':
    main()
