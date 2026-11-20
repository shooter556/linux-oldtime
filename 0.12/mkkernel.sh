#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC= TAG=

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -t|--tag TAG -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy with the guest script /tmp/kinst (from kinst.sh.in)"
    echo "and a compressed v7 tar of usr/src/linux (stock source of TAG, unmodified)"
    echo "plus usr/src/sync.c. Prints where ROOT_DEV, SWAP_DEV and the keyboard layout"
    echo "are set in TAG, to be edited by hand in the guest."
    echo
    echo "  -s, --source DIR   local clone of the Linux history repo"
    echo "                     https://git.kernel.org/pub/scm/linux/kernel/git/history/history.git"
    echo "  -t, --tag TAG      tag to export, e.g. 0.12, 0.95"
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
        -t|--tag) TAG=${2:?}; shift 2 ;;
        -o|--output) OUT=${2:?}; shift 2 ;;
        -f|--force) FORCE=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$SRC" ] && [ -n "$TAG" ] && [ -n "$OUT" ] || usage
git -C "$SRC" rev-parse -q --verify "refs/tags/$TAG^{tree}" >/dev/null || { echo "[ERROR] no tag '$TAG' in '$SRC'" >&2; exit 1; }
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/usr/src"
git -C "$SRC" archive --prefix=usr/src/linux/ "$TAG" | tar xf - -C "$W"
printf 'main()\n{\n\tsync();\n\treturn 0;\n}\n' > "$W/usr/src/sync.c"
tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=2
PKG_O=$SCRIPT_N PKG_N=$(blocks "$W/pkg.tar.Z")
# TODO: split onto several floppies (like mkgcc20.sh) for 0.99.14 and later
[ $((PKG_O + PKG_N)) -le 1440 ] || { echo "[ERROR] $TAG needs $((PKG_O + PKG_N)) blocks > 1440, one floppy is not enough" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@PKG_O@/$PKG_O/; s/@PKG_N@/$PKG_N/" "$HERE/kinst.sh.in" > "$W/kinst"
! grep -n '@[A-Z_]*@' "$W/kinst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/kinst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/kinst" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/pkg.tar.Z" of="$OUT" bs=1024 seek="$PKG_O" conv=notrunc status=none
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N pkg $PKG_O $PKG_N
echo "used $((PKG_O + PKG_N)) / 1440 blocks -> $OUT"
echo
echo "edit by hand in the guest (/usr/src/linux), stock values of $TAG:"
git -C "$SRC" grep -n -E '^(ROOT_DEV|SWAP_DEV)|^ *KEYBOARD' "$TAG" -- Makefile | sed "s|^$TAG:|  |" || true
git -C "$SRC" grep -n -E '^#define KBD_[A-Z_0-9]+$' "$TAG" -- '*keyboard.[Sc]' | sed "s|^$TAG:|  |" || true
echo "  wanted: ROOT_DEV=/dev/hd2, SWAP_DEV=/dev/hd1 (if present), US keyboard"
