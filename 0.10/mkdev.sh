#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy that bootstraps a C development environment on a"
    echo "Linux 0.10 hard-disk system: the guest script /tmp/dinst (from dinst.sh.in),"
    echo "compress and tar.Z (from rootimage-0.11), and a compressed tar holding"
    echo "  usr/local/bin/gcc, usr/local/lib/gcc-* etc.  0.10 gccbin (gcc 1.40, libc)"
    echo "  usr/include                                  include-0.11"
    echo "  usr/bin/make, as86, ld86                     0.12 binaries"
    echo "  usr/bin/pmake, usr/share/mk                  0.10 pmake (BSD make)"
    echo "Sources: an oldlinux-files tree."
    echo
    echo "  -s, --source DIR   oldlinux-files tree (default: \$OLDLINUX)"
    echo "                     https://github.com/oldlinux-web/oldlinux-files"
    echo "  -o, --output FILE  floppy image to write"
    echo "  -f, --force        overwrite FILE if it exists"
    echo "  -h, --help         show this help"
    exit 1
}

OUT= FORCE=0
[ $# -ge 1 ] || usage
while [ $# -gt 0 ]; do
    case "$1" in
        -s|--source) SRC=${2:?}; shift 2 ;;
        -o|--output) OUT=${2:?}; shift 2 ;;
        -f|--force) FORCE=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$OUT" ] || usage
[ -d "$SRC/Linux-0.10" ] || { echo "[ERROR] not an oldlinux-files tree: '$SRC' (use -s)" >&2; exit 1; }
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# print one file from a Minix v1 image
minixcat() {
python3 -I - "$1" "$2" <<'EOF'
import struct, sys
img = open(sys.argv[1], 'rb').read()
B = lambda n: img[n*1024:(n+1)*1024]
ni, nz, im, zm = struct.unpack('<HHHH', B(1)[:8]); it = 2 + im + zm
def inode(n):
    o = it*1024 + (n-1)*32
    m, u, s = struct.unpack('<HHI', img[o:o+8])
    return s, struct.unpack('<9H', img[o+14:o+32])
def data(n):
    s, z = inode(n)
    zs = list(z[:7]) + (list(struct.unpack('<512H', B(z[7]))) if z[7] else [])
    return b''.join(B(q) if q else b'\0'*1024 for q in zs[:(s+1023)//1024])[:s]
ino = 1
for part in sys.argv[2].strip('/').split('/'):
    d = data(ino)
    ino = next(struct.unpack('<H', d[i:i+2])[0] for i in range(0, len(d), 16)
               if d[i+2:i+16].rstrip(b'\0').decode() == part)
sys.stdout.buffer.write(data(ino))
EOF
}

R11=$SRC/images/rootimage-0.11-20040305
minixcat "$R11" /usr/bin/compress > "$W/compress"
minixcat "$R11" /usr/bin/tar > "$W/tar"

P=$W/pkg
mkdir -p "$P/usr/local/bin" "$P/usr/local/lib" "$P/usr/include" "$P/usr/bin" "$W/x"
gzip -dc "$SRC/Linux-0.10/binaries/compilers/gccbin.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$SRC/libs/libc/libc-0.1x/include-0.11.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$SRC/Linux-0.12/binaries/usr.bin/utils.tar.Z" | tar xf - -C "$W/x" usr/bin/make
gzip -dc "$SRC/Linux-0.12/binaries/compilers/as86.tar.Z" | tar xf - -C "$W/x" 2>/dev/null
gzip -dc "$SRC/Linux-0.10/binaries/usr.bin/pmake/pm_supp.tar.Z" | tar xf - -C "$P"
gzip -dc "$SRC/Linux-0.10/binaries/usr.bin/pmake/pmake.Z" > "$P/usr/bin/pmake"
chmod -R u+rwX "$W/x"
mv "$W/x/gccbin/gcc" "$P/usr/local/bin/"
mv "$W/x/gccbin/"* "$P/usr/local/lib/"
cp -rp "$W/x/include-0.12/." "$P/usr/include/"
tar xzf "$SRC/kernel/0.1x/linux-0.10.tar.gz" -C "$P/usr/include" --strip-components=2 linux-0.10/include/utime.h
mv "$W/x/usr/bin/make" "$W/x/usr/bin/as86" "$W/x/usr/bin/ld86" "$P/usr/bin/"
chmod 755 "$P/usr/bin/"* "$P/usr/local/bin/gcc" "$P/usr/local/lib/gcc-"*

tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$P" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"
compress -c "$W/tar" > "$W/tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=3
COMPRESS_O=$SCRIPT_N COMPRESS_N=$(blocks "$W/compress")
TAR_O=$((COMPRESS_O + COMPRESS_N)) TAR_N=$(blocks "$W/tar.Z")
PKG_O=$((TAR_O + TAR_N)) PKG_N=$(blocks "$W/pkg.tar.Z")
[ $((PKG_O + PKG_N)) -le 1440 ] || { echo "[ERROR] too big: $((PKG_O + PKG_N)) blocks" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@COMPRESS_O@/$COMPRESS_O/; s/@COMPRESS_N@/$COMPRESS_N/" \
    -e "s/@TAR_O@/$TAR_O/; s/@TAR_N@/$TAR_N/; s/@PKG_O@/$PKG_O/; s/@PKG_N@/$PKG_N/" \
    "$HERE/dinst.sh.in" > "$W/dinst"
! grep -n '@[A-Z_]*@' "$W/dinst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/dinst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/dinst" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/compress" of="$OUT" bs=1024 seek=$COMPRESS_O conv=notrunc status=none
dd if="$W/tar.Z" of="$OUT" bs=1024 seek=$TAR_O conv=notrunc status=none
dd if="$W/pkg.tar.Z" of="$OUT" bs=1024 seek=$PKG_O conv=notrunc status=none
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N compress $COMPRESS_O $COMPRESS_N \
    tar $TAR_O $TAR_N pkg $PKG_O $PKG_N
echo "used $((PKG_O + PKG_N)) / 1440 blocks -> $OUT"
