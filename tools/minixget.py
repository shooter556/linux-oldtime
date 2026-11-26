#!/usr/bin/env python3
"""Extract a Minix v1 filesystem (Linux 0.1x/0.9x hard disk or floppy) into a host directory.

Keeps modes, mtimes and hard links. Device nodes and FIFOs are skipped. Absolute symlink
targets are rewritten to point inside OUTDIR, so the host resolves them within the tree
(as l01run.py does with L01ROOT).
"""
import argparse, os, struct, sys

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('-i', '--image', required=True, help='disk or floppy image')
ap.add_argument('-p', '--partition', type=int, default=0, help='MBR partition 1-4 (0 = whole image is the fs, default)')
ap.add_argument('-o', '--output', required=True, help='new directory to extract into')
if len(sys.argv) == 1:
    ap.print_help(); sys.exit(0)
a = ap.parse_args()

f = open(a.image, 'rb')
base = 0
if a.partition:
    f.seek(0x1be + 16 * (a.partition - 1)); base = struct.unpack('<I', f.read(16)[8:12])[0] * 512
def blk(n, cnt=1):
    f.seek(base + n * 1024); return f.read(1024 * cnt)

ninodes, nzones, imap, zmap, firstdata, logzone, maxsize, magic = struct.unpack('<HHHHHHIH', blk(1)[:18])
if magic not in (0x137f, 0x138f) or logzone:
    sys.exit('not a Minix v1 fs with 1K zones (magic %#x, log_zone_size %d)' % (magic, logzone))
NAMELEN = 14 if magic == 0x137f else 30
itab = 2 + imap + zmap

def inode(n):
    off = (n - 1) * 32
    b = blk(itab + off // 1024)[off % 1024:off % 1024 + 32]
    mode, uid, size, mtime, gid, nlinks = struct.unpack('<HHIIBB', b[:14])
    return mode, size, mtime, struct.unpack('<9H', b[14:32])

def data(ino):
    mode, size, mtime, z = inode(ino)
    zones = list(z[:7])
    if z[7]: zones += [x for x in struct.unpack('<512H', blk(z[7]))]
    if z[8]:
        for ind in struct.unpack('<512H', blk(z[8])):
            if ind: zones += list(struct.unpack('<512H', blk(ind)))
    out = bytearray()
    for zn in zones:
        if len(out) >= size: break
        out += blk(zn) if zn else bytes(1024)
    return bytes(out[:size])

if os.path.exists(a.output): sys.exit(a.output + ' already exists')
OUT = os.path.abspath(a.output)
seen = {}; dirs = []
def walk(ino, path):
    raw = data(ino); step = NAMELEN + 2
    for i in range(0, len(raw), step):
        n = struct.unpack('<H', raw[i:i + 2])[0]
        name = raw[i + 2:i + step].split(b'\0')[0].decode('latin-1')
        if not n or name in ('.', '..'): continue
        p = os.path.join(path, name)
        mode, size, mtime, _ = inode(n)
        t = mode & 0o170000
        if t == 0o040000:
            os.mkdir(p); dirs.append((p, mode, mtime)); walk(n, p)
        elif n in seen:
            os.link(seen[n], p)
        elif t == 0o100000:
            open(p, 'wb').write(data(n)); os.chmod(p, mode & 0o7777); os.utime(p, (mtime, mtime)); seen[n] = p
        elif t == 0o120000:
            tgt = data(n).decode('latin-1')
            os.symlink(OUT + tgt if tgt.startswith('/') else tgt, p)
        else:
            print('skip %s (mode %o)' % (p[len(OUT):], mode), file=sys.stderr)

os.mkdir(OUT)
walk(1, OUT)
for p, mode, mtime in reversed(dirs):
    os.chmod(p, mode & 0o7777 | 0o700); os.utime(p, (mtime, mtime))
