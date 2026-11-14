#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy with the guest script /tmp/kinst (from kinst.sh.in)"
    echo "and a compressed tar of usr/src/linux-0.12 (Makefile: ROOT_DEV=/dev/hd2,"
    echo "SWAP_DEV=/dev/hd1, keyboard.S: KBD_US) plus usr/src/sync.c. Sources: an oldlinux-files tree."
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
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/usr/src"
tar xf "$SRC/kernel/0.1x/linux-0.12.tar" -C "$W/usr/src"
MK=$W/usr/src/linux-0.12/Makefile
sed -i -e 's|^ROOT_DEV=/dev/hd6$|ROOT_DEV=/dev/hd2|' -e 's|^SWAP_DEV=/dev/hd2$|SWAP_DEV=/dev/hd1|' "$MK"
grep -q '^ROOT_DEV=/dev/hd2$' "$MK" && grep -q '^SWAP_DEV=/dev/hd1$' "$MK" || { echo "[ERROR] Makefile patch failed" >&2; exit 1; }
CF=$W/usr/src/linux-0.12/kernel/chr_drv/keyboard.S
sed -i 's|^#define KBD_FINNISH$|#define KBD_US|' "$CF"
grep -q '^#define KBD_US$' "$CF" || { echo "[ERROR] keyboard.S patch failed" >&2; exit 1; }
printf 'main()\n{\n\tsync();\n\treturn 0;\n}\n' > "$W/usr/src/sync.c"
tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=2
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
