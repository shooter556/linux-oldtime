#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output DIR [-g|--geometry C,H,S] [-f|--force]"
    echo
    echo "Build two 1.44M Linux 0.11 install floppies (raw, dd offsets):"
    echo "  install.flp  guest script /tmp/inst (from inst.sh.in), bootstrap tools and"
    echo "               the whole root tree (rootimage-0.11 + fdisk/mkfs/mount/umount/mknod)"
    echo "               as one compressed tar, so the guest only needs 'tar xf'"
    echo "               (0.11 lacks lstat, which 'tar c' needs)"
    echo "  pkg.flp      gcc, headers, make and other utilities as one compressed tar"
    echo "Sources: an oldlinux-files tree."
    echo
    echo "  -s, --source DIR      oldlinux-files tree (default: \$OLDLINUX)"
    echo "                        https://github.com/oldlinux-web/oldlinux-files"
    echo "  -o, --output DIR      directory to write install.flp and pkg.flp into"
    echo "  -g, --geometry C,H,S  hard disk geometry baked into the script (default: 128,16,63)"
    echo "  -f, --force           overwrite existing images"
    echo "  -h, --help            show this help"
    exit 1
}

OUT= FORCE=0 GEOM=128,16,63
[ $# -ge 1 ] || usage
while [ $# -gt 0 ]; do
    case "$1" in
        -s|--source) SRC=${2:?}; shift 2 ;;
        -o|--output) OUT=${2:?}; shift 2 ;;
        -g|--geometry) GEOM=${2:?}; shift 2 ;;
        -f|--force) FORCE=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$OUT" ] || usage
[ -d "$SRC/Linux-0.11" ] || { echo "[ERROR] not an oldlinux-files tree: '$SRC' (use -s)" >&2; exit 1; }
[ -d "$OUT" ] || { echo "[ERROR] no such directory: $OUT" >&2; exit 1; }
IFS=, read -r C H S <<< "$GEOM"
[[ "$C,$H,$S" =~ ^[0-9]+,[0-9]+,[0-9]+$ ]] || { echo "[ERROR] bad geometry '$GEOM' (want C,H,S)" >&2; exit 1; }
LAST=$((C * H * S - 1))
for f in install.flp pkg.flp; do
    [ ! -e "$OUT/$f" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT/$f exists (use -f)" >&2; exit 1; }
done
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/pkg/usr/bin" "$W/pkg/usr/include" "$W/pkg/usr/local/bin" "$W/pkg/usr/local/lib"

minixcat() {
    python3 -I - "$1" "$2" <<'PYEOF'
import sys, struct
img = open(sys.argv[1], 'rb').read()
B = lambda n: img[n*1024:(n+1)*1024]
ni, nz, im, zm = struct.unpack('<HHHH', B(1)[:8]); it = 2 + im + zm
def inode(n):
    n -= 1; b = B(it + n // 32); o = (n % 32) * 32
    m, u, s = struct.unpack('<HHI', b[o:o+8]); return s, struct.unpack('<9H', b[o+14:o+32])
def data(s, z):
    zs = list(z[:7]) + (list(struct.unpack('<512H', B(z[7]))) if z[7] else [])
    return b''.join(B(q) if q else b'\0'*1024 for q in zs[:(s+1023)//1024])[:s]
ino = 1
for p in sys.argv[2].strip('/').split('/'):
    d = data(*inode(ino))
    ino = next(struct.unpack('<H', d[i:i+2])[0] for i in range(0, len(d), 16)
               if struct.unpack('<H', d[i:i+2])[0] and d[i+2:i+16].rstrip(b'\0').decode() == p)
sys.stdout.buffer.write(data(*inode(ino)))
PYEOF
}

# Root tree tar: the minix root image as-is (device nodes included), /etc/rc and
# /etc/mtab pointed at /dev/hd1, plus the bootstrap tools in /bin and an empty /mnt.
# tar and compress are left out: the guest runs them while extracting.
mktree() {
    python3 -I - "$@" <<'PYEOF'
import sys, struct, tarfile, io, os
img_path, out, extra = sys.argv[1], sys.argv[2], sys.argv[3]
img = open(img_path, 'rb').read()
B = lambda n: img[n*1024:(n+1)*1024]
ni, nz, im, zm = struct.unpack('<HHHH', B(1)[:8]); it = 2 + im + zm
def inode(n):
    n -= 1; b = B(it + n // 32); o = (n % 32) * 32
    m, u, s, t, g = struct.unpack('<HHIIB', b[o:o+13])
    return m, u, s, t, g, struct.unpack('<9H', b[o+14:o+32])
def data(s, z):
    zs = list(z[:7]) + (list(struct.unpack('<512H', B(z[7]))) if z[7] else [])
    return b''.join(B(q) if q else b'\0'*1024 for q in zs[:(s+1023)//1024])[:s]
tf = tarfile.open(out, 'w', format=tarfile.GNU_FORMAT)
def add(name, mode, uid, gid, mtime, kind, body=b'', dev=(0, 0)):
    ti = tarfile.TarInfo(name); ti.mode = mode & 0o7777; ti.uid = uid; ti.gid = gid
    ti.uname = ti.gname = ''; ti.mtime = mtime; ti.type = kind
    if kind in (tarfile.CHRTYPE, tarfile.BLKTYPE): ti.devmajor, ti.devminor = dev
    if kind == tarfile.REGTYPE: ti.size = len(body); tf.addfile(ti, io.BytesIO(body))
    else: tf.addfile(ti)
def walk(ino, path):
    m, u, s, t, g, z = inode(ino); d = data(s, z)
    for i in range(0, len(d), 16):
        n = struct.unpack('<H', d[i:i+2])[0]; nm = d[i+2:i+16].rstrip(b'\0').decode()
        if not n or nm in ('.', '..'): continue
        mm, uu, ss, tt, gg, zz = inode(n); p = path + nm; f = mm & 0o170000
        if f == 0o040000:
            add(p, mm, uu, gg, tt, tarfile.DIRTYPE); walk(n, p + '/')
        elif f in (0o020000, 0o060000):
            add(p, mm, uu, gg, tt, tarfile.CHRTYPE if f == 0o020000 else tarfile.BLKTYPE,
                dev=(zz[0] >> 8, zz[0] & 255))
        else:
            body = data(ss, zz)
            if p in ('etc/rc', 'etc/mtab'):
                body = body.replace(b'/dev/fd1', b'/dev/hd1')
            add(p, mm, uu, gg, tt, tarfile.REGTYPE, body)
walk(1, '')
now = int(os.path.getmtime(extra))
add('mnt', 0o755, 0, 0, now, tarfile.DIRTYPE)
for f in sorted(os.listdir(extra)):
    add('bin/' + f, 0o755, 0, 0, now, tarfile.REGTYPE, open(os.path.join(extra, f), 'rb').read())
tf.close()
PYEOF
}

R11=$SRC/images/rootimage-0.11-20040305
for p in bin/mkfs bin/mount bin/umount bin/mknod usr/bin/tar usr/bin/compress; do
    minixcat "$R11" "/$p" > "$W/bin/$(basename $p)"
done
gzip -dc "$SRC/bin-src/fdisk-0.91.tar.Z" | tar xOf - fdisk/fdisk > "$W/bin/fdisk"
gzip -dc "$SRC/Linux-0.11/images/rootimage-0.11.Z" > "$W/root.img"

mkdir "$W/extra"
cp "$W/bin/fdisk" "$W/bin/mkfs" "$W/bin/mount" "$W/bin/umount" "$W/bin/mknod" "$W/extra/"
mktree "$W/root.img" "$W/tree.tar" "$W/extra"
printf '\001\003' > "$W/rootdev"

B11=$SRC/Linux-0.11/binaries
B12=$SRC/Linux-0.12/binaries
mkdir "$W/x"
gzip -dc "$B12/usr.bin/fileutil.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$B12/usr.bin/utils.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$B12/compilers/as86.tar.Z" | tar xf - -C "$W/x" 2>/dev/null
gzip -dc "$B11/compilers/gccbin.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$SRC/libs/libc/libc-0.1x/include-0.11.tar.Z" | tar xf - -C "$W/x"
chmod -R u+rwX "$W/x"
for f in make egrep kermit em expand unexpand split tac as86 ld86; do
    cp -p "$W/x/usr/bin/$f" "$W/pkg/usr/bin/"
done
mv "$W/x/gccbin/gcc" "$W/pkg/usr/local/bin/"
mv "$W/x/gccbin/"* "$W/pkg/usr/local/lib/"
cp -rp "$W/x/include-0.12/." "$W/pkg/usr/include/"
tar xf "$SRC/kernel/0.1x/linux-0.11.tar" -C "$W/pkg/usr/include" --strip-components=2 linux-0.11/include/utime.h
tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W/pkg" usr

for f in fdisk mkfs mount tar; do compress -c "$W/bin/$f" > "$W/$f.Z"; done
compress -c "$W/tree.tar" > "$W/tree.tar.Z"
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=4
POS=$SCRIPT_N
declare -A O N
for f in compress:bin/compress fdisk:fdisk.Z mkfs:mkfs.Z mount:mount.Z tar:tar.Z rootdev:rootdev tree:tree.tar.Z; do
    k=${f%%:*}; O[$k]=$POS; N[$k]=$(blocks "$W/${f#*:}"); POS=$((POS + N[$k]))
done
[ $POS -le 1440 ] || { echo "[ERROR] install.flp needs $POS blocks > 1440" >&2; exit 1; }
PKG_N=$(blocks "$W/pkg.tar.Z")
[ $PKG_N -le 1440 ] || { echo "[ERROR] pkg.flp needs $PKG_N blocks > 1440" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/" \
    -e "s/@H@/$H/g; s/@S@/$S/g; s/@C@/$C/g; s/@LAST@/$LAST/g" \
    -e "s/@COMPRESS_O@/${O[compress]}/; s/@COMPRESS_N@/${N[compress]}/" \
    -e "s/@FDISK_O@/${O[fdisk]}/; s/@FDISK_N@/${N[fdisk]}/" \
    -e "s/@MKFS_O@/${O[mkfs]}/; s/@MKFS_N@/${N[mkfs]}/" \
    -e "s/@MOUNT_O@/${O[mount]}/; s/@MOUNT_N@/${N[mount]}/" \
    -e "s/@TAR_O@/${O[tar]}/; s/@TAR_N@/${N[tar]}/" \
    -e "s/@ROOTDEV_O@/${O[rootdev]}/" \
    -e "s/@TREE_O@/${O[tree]}/; s/@TREE_N@/${N[tree]}/" \
    -e "s/@PKG_N@/$PKG_N/" \
    "$HERE/inst.sh.in" > "$W/inst"
! grep -n '@[A-Z_]*@' "$W/inst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/inst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

I=$OUT/install.flp P=$OUT/pkg.flp
dd if=/dev/zero of="$I" bs=1024 count=1440 status=none
put() { dd if="$1" of="$I" bs=1024 seek="$2" conv=notrunc status=none; }
put "$W/inst" 0
put "$W/bin/compress" "${O[compress]}"
for k in fdisk mkfs mount tar; do put "$W/$k.Z" "${O[$k]}"; done
put "$W/rootdev" "${O[rootdev]}"
put "$W/tree.tar.Z" "${O[tree]}"
dd if=/dev/zero of="$P" bs=1024 count=1440 status=none
dd if="$W/pkg.tar.Z" of="$P" bs=1024 conv=notrunc status=none

echo "install.flp:"
printf '  %-9s %5s %5s\n' item skip count script 0 $SCRIPT_N
for k in compress fdisk mkfs mount tar rootdev tree; do printf '  %-9s %5s %5s\n' $k ${O[$k]} ${N[$k]}; done
echo "  used $POS / 1440 blocks -> $I"
echo "pkg.flp:"
printf '  %-9s %5s %5s\n' pkg 0 $PKG_N
echo "  used $PKG_N / 1440 blocks -> $P"
echo "geometry C,H,S = $C,$H,$S, hd1 = sectors $S..$LAST"
