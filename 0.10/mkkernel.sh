#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy for the Linux 0.11 guest: the guest script /tmp/kinst"
    echo "(from kinst.sh.in) and a compressed tar holding"
    echo "  usr/src/linux-0.10   Linus's 0.10, restored from the RCS revisions 1.1 in the"
    echo "                       surviving linux-0.10.tar.gz (a Ted Ts'o working tree)"
    echo "  usr/src/update-0.10  the original 0.10 /bin/update"
    echo "  usr/bin/cut, tr      0.12 binaries, needed by the 0.10 Makefile"
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
mkdir -p "$W/usr/src" "$W/usr/bin" "$W/x"
tar xzf "$SRC/kernel/0.1x/linux-0.10.tar.gz" -C "$W/usr/src"
K=$W/usr/src/linux-0.10

# RCS ",v" reader: print revision REV of FILE (no rcs package needed).
rcsco() {
python3 -I - "$1" "$2" <<'EOF'
import re, sys
def tokens(s):
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c == '@':
            j, out = i + 1, []
            while True:
                k = s.index('@', j)
                if k + 1 < n and s[k + 1] == '@':
                    out.append(s[j:k + 1]); j = k + 2
                else:
                    out.append(s[j:k]); i = k + 1; break
            yield ''.join(out)
        elif c in ';:':
            yield c; i += 1
        else:
            j = i
            while j < n and not s[j].isspace() and s[j] not in ';:@':
                j += 1
            yield s[i:j]; i = j
t = list(tokens(open(sys.argv[1], encoding='latin-1').read()))
REV = re.compile(r'\d+(\.\d+)+$')
head = t[t.index('head') + 1]
nxt, text = {}, {}
for i, v in enumerate(t[:-1]):
    if REV.match(v) and t[i + 1] == 'date':
        j = t.index('next', i)
        nxt[v] = t[j + 1] if REV.match(t[j + 1]) else None
    if REV.match(v) and t[i + 1] == 'log':
        text[v] = t[i + 4]
def apply(lines, diff):
    d, res, pos, i = diff.split('\n'), [], 0, 0
    while i < len(d):
        m = re.match(r'([ad])(\d+) (\d+)$', d[i])
        if not m:
            i += 1; continue
        l, c = int(m.group(2)), int(m.group(3))
        if m.group(1) == 'd':
            res += lines[pos:l - 1]; pos = l - 1 + c; i += 1
        else:
            res += lines[pos:l]; pos = l; res += d[i + 1:i + 1 + c]; i += 1 + c
    return res + lines[pos:]
r, lines = head, text[head].split('\n')
while r != sys.argv[2]:
    r = nxt[r]; lines = apply(lines, text[r])
sys.stdout.write('\n'.join(lines))
EOF
}

# Restore Linus's 0.10: every file Ted Ts'o put under RCS goes back to rev 1.1.
for v in $(cd "$K" && find . -path '*/RCS/*,v' | sort); do
    f=$(dirname "$(dirname "$v")")/$(basename "$v" ,v)
    rcsco "$K/$v" 1.1 > "$K/$f.new"
    mv "$K/$f.new" "$K/$f"
done
# tytso's own files and editor/patch leftovers
(cd "$K" && find . \( -name RCS -o -name '*~' -o -name '*.orig' -o -name '*.orig.orig' \) -prune -exec rm -rf {} +)
rm -f "$K/boot/bootsect.sg" "$K/boot/setup.sg" "$K/boot/gas-convert" \
      "$K/kernel/blk_drv/ramdisk.c" "$K/kernel/malloc.c" "$K/kernel/chr_drv/keyboard.S.jtkohl"
grep -q "isupper(_ctmp)?_ctmp+('a'+'A')" "$K/include/ctype.h" || { echo "[ERROR] ctype.h is not rev 1.1" >&2; exit 1; }
! grep -q 'BADNESS' "$K/fs/buffer.c" || { echo "[ERROR] buffer.c is not rev 1.1" >&2; exit 1; }

# Build with the 0.11 guest's tools instead of Minix's.
MK=$K/Makefile
sed -i -e 's|^AS86\t=as -0 -a$|AS86\t=as86 -0 -a|' \
       -e 's|^LD86\t=ld -0$|LD86\t=ld86 -0|' \
       -e '/^\tchmem +65000 tools\/build$/d' \
       -e 's|^\ttools/build boot/bootsect|\t./tools/build boot/bootsect|' \
       -e 's/| cut -c25-31 |/| cut -c34-41 |/' \
       -e 's|"SYSSIZE = ("|"SYSSIZE = ["|' -e 's|"+ 15 ) / 16"|"+ 15 ] / 16"|' "$MK"
# as86 -a (asld mode) groups with [ ], not ( )
grep -q '^AS86	=as86 -0 -a$' "$MK" && grep -q '^LD86	=ld86 -0$' "$MK" && ! grep -q chmem "$MK" \
    && grep -q '^	\./tools/build boot/bootsect' "$MK" && grep -q 'cut -c34-41' "$MK" \
    && grep -q '"SYSSIZE = \["' "$MK" && grep -q '"+ 15 \] / 16"' "$MK" \
    || { echo "[ERROR] Makefile patch failed" >&2; exit 1; }
# Minix asld comments start with '|', as86 uses '!'
for f in bootsect setup; do sed -i 's/|/!/' "$K/boot/$f.s"; done
! grep -q '|' "$K/boot/bootsect.s" "$K/boot/setup.s" || { echo "[ERROR] '|' left in boot/*.s" >&2; exit 1; }

gzip -dc "$SRC/Linux-0.10/binaries/sbin/update.Z" > "$W/usr/src/update-0.10"
gzip -dc "$SRC/Linux-0.12/binaries/usr.bin/fileutil.tar.Z" | tar xf - -C "$W/x" usr/bin/cut
mv "$W/x/usr/bin/cut" "$W/usr/bin/cut"
gzip -dc "$SRC/Linux-0.12/binaries/usr.bin/tr.Z" > "$W/usr/bin/tr"
chmod 755 "$W/usr/bin/cut" "$W/usr/bin/tr" "$W/usr/src/update-0.10"

tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=4
PKG_O=$SCRIPT_N PKG_N=$(blocks "$W/pkg.tar.Z")
[ $((PKG_O + PKG_N)) -le 1440 ] || { echo "[ERROR] too big" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@PKG_O@/$PKG_O/; s/@PKG_N@/$PKG_N/" "$HERE/kinst.sh.in" > "$W/kinst"
! grep -n '@[A-Z_]*@' "$W/kinst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/kinst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/kinst" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/pkg.tar.Z" of="$OUT" bs=1024 seek="$PKG_O" conv=notrunc status=none
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N pkg $PKG_O $PKG_N
echo "used $((PKG_O + PKG_N)) / 1440 blocks -> $OUT"
