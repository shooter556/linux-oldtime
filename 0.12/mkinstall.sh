#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a single 1.44M Linux 0.12 install floppy (raw, dd offsets) holding"
    echo "the guest script /tmp/inst (from inst.sh.in), bootstrap tools and one"
    echo "compressed package tar. Sources: an oldlinux-files tree."
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
[ -d "$SRC/Linux-0.12" ] || { echo "[ERROR] not an oldlinux-files tree: '$SRC' (use -s)" >&2; exit 1; }
[ -f "$SRC/Linux-0.12/images/bootimage-0.12.Z" ] || { echo "[ERROR] no Linux-0.12/images/bootimage-0.12.Z in '$SRC'" >&2; exit 1; }
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/all/bin" "$W/all/etc" "$W/all/usr/bin" "$W/all/usr/include" "$W/all/usr/local/bin" "$W/all/usr/local/lib"

minixcat() {
    python3 -I - "$1" "$2" <<'PYEOF'
import sys, struct
img = open(sys.argv[1], 'rb').read()
B = lambda n: img[n*1024:(n+1)*1024]
ni, nz, im, zm = struct.unpack('<HHHH', B(1)[:8]); it = 2 + im + zm
def inode(n):
    n -= 1; b = B(it + n // 32); o = (n % 32) * 32
    m, u, s = struct.unpack('<HHI', b[o:o+8]); return s, struct.unpack('<9H', b[o+14:o+32])
def data(z, s):
    zs = list(z[:7]) + (list(struct.unpack('<512H', B(z[7]))) if z[7] else [])
    return b''.join(B(q) if q else b'\0'*1024 for q in zs[:(s+1023)//1024])[:s]
ino = 1
for p in sys.argv[2].strip('/').split('/'):
    d = data(*reversed(inode(ino)))
    ino = next(struct.unpack('<H', d[i:i+2])[0] for i in range(0, len(d), 16)
               if struct.unpack('<H', d[i:i+2])[0] and d[i+2:i+16].rstrip(b'\0').decode() == p)
sys.stdout.buffer.write(data(*reversed(inode(ino))))
PYEOF
}

aoutstrip() {
    python3 -I - "$@" <<'PYEOF'
import sys, struct
for f in sys.argv[1:]:
    d = bytearray(open(f, 'rb').read())
    m, t, dd, bss, s, e, tr, dr = struct.unpack('<8I', d[:32])
    if m & 0xffff != 0o413 or tr or dr or not s: continue
    struct.pack_into('<I', d, 16, 0)
    open(f, 'wb').write(d[:1024 + t + dd])
PYEOF
}

R11=$SRC/images/rootimage-0.11-20040305
for p in bin/mkfs bin/mount bin/umount bin/mknod usr/bin/tar usr/bin/compress; do
    minixcat "$R11" "/$p" > "$W/bin/$(basename $p)"
done
gzip -dc "$SRC/bin-src/fdisk-0.91.tar.Z" | tar xOf - fdisk/fdisk > "$W/bin/fdisk"

B12=$SRC/Linux-0.12/binaries
mkdir "$W/x"
gzip -dc "$B12/usr.bin/fileutil.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$B12/usr.bin/utils.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$B12/compilers/as86.tar.Z" | tar xf - -C "$W/x" 2>/dev/null
gzip -dc "$B12/compilers/gccbin.tar.Z" | tar xf - -C "$W/x"
gzip -dc "$SRC/libs/libc/libc-0.1x/include-0.11.tar.Z" | tar xf - -C "$W/x"
chmod -R u+rwX "$W/x"
cp "$W/bin/umount" "$W/bin/mknod" "$W/all/bin/"
# sync like V6 s2/sync.s: mov $36,%eax; int $0x80; xor %ebx,%ebx; mov $1,%eax; int $0x80
python3 -I -c '
import struct, sys
code = bytes.fromhex("b824000000cd8031dbb801000000cd80")
hdr = struct.pack("<8I", 0x010b, 4096, 0, 0, 0, 0, 0, 0)
open(sys.argv[1], "wb").write(hdr.ljust(1024, b"\0") + code.ljust(4096, b"\0"))
' "$W/all/bin/sync"
chmod 755 "$W/all/bin/"*
for f in make egrep kermit em dir vdir expand unexpand split tac as86 ld86; do
    cp -p "$W/x/usr/bin/$f" "$W/all/usr/bin/"
done
aoutstrip "$W/all/usr/bin/"*
mv "$W/x/gccbin/gcc" "$W/all/usr/local/bin/"
mv "$W/x/gccbin/"* "$W/all/usr/local/lib/"
gzip -dc "$SRC/bin-src/shoelace.tar.Z" | tar xf - -C "$W/x" shoe
cp -p "$W/x/shoe/shoelace" "$W/all/shoelace"
for f in laceup bootlace winiboot disktab; do cp -p "$W/x/shoe/$f" "$W/all/etc/"; done
chmod 755 "$W/all/shoelace" "$W/all/etc/laceup"
chmod 644 "$W/all/etc/bootlace" "$W/all/etc/winiboot" "$W/all/etc/disktab"
aoutstrip "$W/all/etc/laceup"
printf '# ShoeLace for Linux 0.12: load /Image (its ROOT_DEV at offset 508 is 0x0302 = /dev/hd2)\nboot\t\t/Image\n' > "$W/all/etc/config"
IMAGE_S=$(( ($(gzip -dc "$SRC/Linux-0.12/images/bootimage-0.12.Z" | wc -c) + 511) / 512 ))
cp -rp "$W/x/include-0.12/." "$W/all/usr/include/"
sed -i -e 's/^extern inline int strlen(/extern inline size_t strlen(/' \
    -e 's/^\(extern inline void \* memcpy(void \* dest,const void \* src, \)int n)/\1size_t n)/' \
    -e 's/^\(extern inline int memcmp(const void \* cs,const void \* ct,\)int count)/\1size_t count)/' \
    "$W/all/usr/include/string.h"
[ "$(grep -c -E '^extern inline size_t strlen\(|memcpy\(.*size_t n\)|memcmp\(.*size_t count\)' "$W/all/usr/include/string.h")" = 3 ] || { echo "[ERROR] string.h prototypes not patched" >&2; exit 1; }
tar xf "$SRC/kernel/0.1x/linux-0.12.tar" -C "$W/all/usr/include" --strip-components=2 linux-0.12/include/utime.h
mkdir -p "$W/all/usr/src"
cp "$SRC/bin/uname.c" "$W/all/usr/src/uname.c"
# --sort=name: readdir order changes the compressed size by up to ~20 blocks from run to run
tar --format=v7 --owner=0 --group=0 --sort=name -cf "$W/all.tar" -C "$W/all" bin etc shoelace usr

for f in fdisk mkfs mount tar; do compress -c "$W/bin/$f" > "$W/$f.Z"; done
compress -c "$W/all.tar" > "$W/all.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=5
POS=$SCRIPT_N
declare -A O N
for f in compress:bin/compress fdisk:fdisk.Z mkfs:mkfs.Z mount:mount.Z tar:tar.Z pkg:all.tar.Z; do
    k=${f%%:*}; O[$k]=$POS; N[$k]=$(blocks "$W/${f#*:}"); POS=$((POS + N[$k]))
done
[ $POS -le 1440 ] || { echo "[ERROR] needs $POS blocks > 1440" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/" \
    -e "s/@COMPRESS_O@/${O[compress]}/; s/@COMPRESS_N@/${N[compress]}/" \
    -e "s/@FDISK_O@/${O[fdisk]}/g; s/@FDISK_N@/${N[fdisk]}/g" \
    -e "s/@MKFS_O@/${O[mkfs]}/; s/@MKFS_N@/${N[mkfs]}/" \
    -e "s/@MOUNT_O@/${O[mount]}/; s/@MOUNT_N@/${N[mount]}/" \
    -e "s/@TAR_O@/${O[tar]}/; s/@TAR_N@/${N[tar]}/" \
    -e "s/@PKG_O@/${O[pkg]}/; s/@PKG_N@/${N[pkg]}/" \
    -e "s/@IMAGE_S@/$IMAGE_S/" \
    "$HERE/inst.sh.in" > "$W/inst"
! grep -n '@[A-Z_]*@' "$W/inst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/inst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
put() { dd if="$1" of="$OUT" bs=1024 seek="$2" conv=notrunc status=none; }
put "$W/inst" 0
put "$W/bin/compress" "${O[compress]}"
for k in fdisk mkfs mount tar; do put "$W/$k.Z" "${O[$k]}"; done
put "$W/all.tar.Z" "${O[pkg]}"

printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N
for k in compress fdisk mkfs mount tar pkg; do printf '%-9s %5s %5s\n' $k ${O[$k]} ${N[$k]}; done
echo "used $POS / 1440 blocks -> $OUT"
