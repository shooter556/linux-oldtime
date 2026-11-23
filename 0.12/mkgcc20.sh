#!/usr/bin/env bash
set -eu -o pipefail

SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output OUTDIR [-f|--force]"
    echo
    echo "Build raw 1.44M floppies to bootstrap gcc 2.0 with gcc 1.40 on Linux 0.12:"
    echo "  gcctools.flp      patched gnulib (__truncdfsf2), /bin/true, df.c, float.h.ieee,"
    echo "                    ftest.c, hdr.c; its script symlinks as/ld/ar/ranlib/nm/size/strip/gar/cpp"
    echo "  gccsrc1..N.flp    gcc-2.0 trimmed to C only and pre-patched (Makefile.in, x-i386v,"
    echo "                    t-svr3, i386gas.h, fp387.asm); each one an independent tar.Z"
    echo "Each floppy starts with a 2K guest script: dd if=/dev/fd1 of=/tmp/g bs=1024 count=2"
    echo
    echo "  -s, --source DIR   oldlinux-files tree (default: \$OLDLINUX)"
    echo "  -o, --output DIR   directory for the floppy images"
    echo "  -f, --force        overwrite existing images in DIR"
    echo "  -h, --help         show this help"
    echo
    echo "Host needs: bash, python3, bzip2, gzip, tar, compress (ncompress), gcc (for enquire)."
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
GCC2=$SRC/gnu/gcc-2/gcc-2.0.tar.bz2
GCCBIN=$SRC/Linux-0.12/binaries/compilers/gccbin.tar.Z
DFC=$SRC/Linux-0.12/sources/sbin/df.c
for f in "$GCC2" "$GCCBIN" "$DFC"; do
    [ -f "$f" ] || { echo "[ERROR] missing $f (use -s)" >&2; exit 1; }
done
for c in compress gcc bzip2; do
    command -v $c >/dev/null || { echo "[ERROR] need $c" >&2; exit 1; }
done
mkdir -p "$OUT"
if [ $FORCE = 0 ] && ls "$OUT"/gcc*.flp >/dev/null 2>&1; then
    echo "[ERROR] $OUT already has gcc*.flp (use -f)" >&2; exit 1
fi
rm -f "$OUT"/gcc*.flp

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# --- gcc-2.0 source: C only, patched as on 0.95a, original mtimes kept ---
mkdir "$W/src"
tar xjf "$GCC2" -C "$W/src"
G=$W/src/gcc-2.0
(cd "$G" && ls | grep -E '^(cp-|objc|g\+\+|c\+\+)|\.texi$|\.info|^ChangeLog|^OChangeLog|\.com$|^configure\.bat$|\.(aux|cps|fns|kys|pgs|tps|vrs)$' | xargs rm -f)
(cd "$G/config" && ls | grep -v -x -E 'i386\.(c|h|md)|i386gas\.h|bsd386\.h|unx386\.h|xm-i386\.h|xm-i386v\.h|xm-svr3\.h|x-i386v|t-svr3' | xargs rm -f)
python3 -I - "$G" <<'PYEOF'
import os, sys
os.chdir(sys.argv[1])
def patch(p, subs):
    st = os.stat(p); s = open(p).read()
    for a, b in subs:
        if s.count(a) != 1:
            sys.exit("[ERROR] patch failed: %s: %r" % (p, a))
        s = s.replace(a, b)
    open(p, 'w').write(s); os.utime(p, (st.st_mtime, st.st_mtime))
patch('Makefile.in', [
    ('LANGUAGES = c c++ objective-c proto\n', 'LANGUAGES = c\n'),
    ('CFLAGS = -g\n', 'CFLAGS =\n'),
    ('\nCC = cc\n', '\nCC = /usr/local/bin/gcc\n'),
    ('OLDCC = cc\n', 'OLDCC = /usr/local/bin/gcc\n'),
    ("version=`awk '{printf \"%s\", substr ($$4, 2, length ($$4) - 3); }' $(srcdir)/version.c`\n", 'version=2.0\n'),
    ('LIBGCC1 = libgcc1.a\n', 'LIBGCC1 = libgcc1.null\n'),
    ('LIB2FUNCS_EXTRA = \n', 'LIB2FUNCS_EXTRA = fp387.asm\n'),
    ('\t$(INSTALL_PROGRAM) $(srcdir)/c++ $(bindir)/c++\n\t$(INSTALL_PROGRAM) $(srcdir)/g++ $(bindir)/g++\n', ''),
])
patch('config/x-i386v', [('CLIB=-lPW\n', 'CLIB=\n')])
patch('config/t-svr3', [('EXTRA_PARTS=crtbegin.o crtend.o\n', '')])
st = os.stat('config/i386gas.h')
open('config/i386gas.h', 'a').write('''
/* Linux 0.12: libc has atexit, so libgcc2 must not define exit() calling SysV _cleanup(). */
#define HAVE_ATEXIT

/* Linux headers say size_t is unsigned int; gcc 2's default long unsigned int
   makes every strlen/memcpy/memcmp declaration "conflict with the built-in". */
#define SIZE_TYPE "unsigned int"

/* libc atof/ldexp are soft-float and return double in eax:edx; gcc 2 expects st(0). */
#if __GNUC__ >= 2
#define REAL_VALUE_ATOF(x) __atof387 (x)
#define REAL_VALUE_LDEXP(x, y) __ldexp387 (x, y)
extern double __atof387 (), __ldexp387 ();
#endif
''')
t = st.st_mtime
os.utime('config/i386gas.h', (t, t))
open('fp387.asm', 'w').write('''\t.text
\t.align 2
.globl ___atof387
___atof387:
\tpushl 4(%esp)
\tcall _atof
\taddl $4,%esp
\tpushl %edx
\tpushl %eax
\tfldl (%esp)
\taddl $8,%esp
\tret
\t.align 2
.globl ___ldexp387
___ldexp387:
\tpushl 12(%esp)
\tpushl 12(%esp)
\tpushl 12(%esp)
\tcall _ldexp
\taddl $12,%esp
\tpushl %edx
\tpushl %eax
\tfldl (%esp)
\taddl $8,%esp
\tret
''')
os.utime('fp387.asm', (t, t))
PYEOF
touch -d '1992-02-22 12:00' "$G" "$G/config"

# --- tools ---
T=$W/tools/usr/src/gcc/tools
mkdir -p "$T"
mkdir "$W/gccbin"
gzip -dc "$GCCBIN" | tar xf - -C "$W/gccbin"
chmod -R u+rwX "$W/gccbin"
# gnulib fp-interf.o __truncdfsf2 returned float2double(double2float(x)) in eax:edx;
# make it fldl/fstps/popl %eax, skipping the two call relocations at +0x135/+0x13b.
python3 -I - "$W/gccbin/gccbin/gnulib" "$T/gnulib" <<'PYEOF'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
off = 8
while off < len(d):
    name = d[off:off+16].decode().strip(); size = int(d[off+48:off+58])
    if name.startswith('fp-interf.o'):
        base = off + 60 + 32
        break
    off += 60 + size + (size & 1)
else:
    sys.exit('[ERROR] fp-interf.o not in gnulib')
orig = bytes.fromhex('ff742408ff742408e8c7feffff50e8c1feffff83c40cc3')
if bytes(d[base+0x12c:base+0x12c+len(orig)]) != orig:
    sys.exit('[ERROR] unexpected __truncdfsf2 bytes in gnulib')
for o, b in [(0x12c, 'dd442404'), (0x130, '83ec04'), (0x133, 'eb0a'), (0x13f, 'd91c24'), (0x142, '58'), (0x143, 'c3')]:
    b = bytes.fromhex(b); d[base+o:base+o+len(b)] = b
open(sys.argv[2], 'wb').write(d)
PYEOF
# true: xor %ebx,%ebx; mov $1,%eax; int $0x80
python3 -I -c '
import struct, sys
code = bytes.fromhex("31dbb801000000cd80")
hdr = struct.pack("<8I", 0x010b, 4096, 0, 0, 0, 0, 0, 0)
open(sys.argv[1], "wb").write(hdr.ljust(1024, b"\0") + code.ljust(4096, b"\0"))
' "$T/true"
cp "$DFC" "$T/df.c"
gcc -w -std=gnu89 -mlong-double-64 -DNO_SC -o "$W/enquire" "$G/enquire.c"
"$W/enquire" -f > "$T/float.h.ieee"
! grep -q WARNING "$T/float.h.ieee" || { echo "[ERROR] host enquire warned" >&2; exit 1; }
cat > "$T/ftest.c" <<'EOF'
#include <stdio.h>

extern double atof();

int main()
{
	volatile float a, t;
	int i = 0;

	a = 1.0;
	do {
		a = a + a;
		i++;
		t = a + 1.0;
		t = t - a;
		t = t - 1.0;
	} while (t == 0.0 && i < 2000);
	printf("i=%d\n", i);
	a = 3.0;
	printf("3->%d\n", (int) a);
	printf("atof: %d\n", (int) (atof("2.5") * 2.0));
	return 0;
}
EOF
cat > "$T/hdr.c" <<'EOF'
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>
#include <float.h>
#include <assert.h>

int sum(int n, ...)
{
	va_list ap;
	int s = 0;

	va_start(ap, n);
	while (n-- > 0)
		s += va_arg(ap, int);
	va_end(ap);
	return s;
}

int main()
{
	assert(sizeof(int) == 4);
	printf("%s %d %d %d\n", "hello", (int) strlen("hello"), sum(3, 1, 2, 3), INT_MAX);
	printf("FLT_DIG=%d DBL_DIG=%d\n", FLT_DIG, DBL_DIG);
	return 0;
}
EOF

SCRIPT_N=2
MAXPKG=$((1440 - SCRIPT_N))
blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }

header() {  # $1 title, $2 what, $3 body
    cat <<EOF
# $1 for Linux 0.12 (bash 1.12). Read from drive B:
#   dd if=/dev/fd1 of=/tmp/g bs=1024 count=$SCRIPT_N
FD=/dev/fd1
DIR=/usr/src/gcc

usage() {
  echo "usage: sh /tmp/g -n|--dry-run|-a|--apply"
  echo "  $2"
  echo "  -n, --dry-run  print commands only;  -a, --apply  really run"
  exit 1
}

run() {
  echo "+ \$*"
  if [ \$DRY = 0 ]; then eval "\$*" || { echo "FAILED: \$*"; exit 1; }; fi
}

[ \$# = 1 ] || usage
case "\$1" in
  -n|--dry-run) DRY=1 ;;
  -a|--apply) DRY=0 ;;
  *) usage ;;
esac

[ -d /usr/src ] || run "mkdir /usr/src"
[ -d \$DIR ] || run "mkdir \$DIR"
$3
exit 0
EOF
}

floppy() {  # $1 image, $2 script, $3 payload
    [ $(blocks "$2") -le $SCRIPT_N ] || { echo "[ERROR] $(basename "$1") script > $SCRIPT_N KB" >&2; exit 1; }
    [ $(blocks "$3") -le $MAXPKG ] || { echo "[ERROR] $(basename "$1") payload too big" >&2; exit 1; }
    dd if=/dev/zero of="$1" bs=1024 count=1440 status=none
    dd if="$2" of="$1" bs=1024 conv=notrunc status=none
    dd if="$3" of="$1" bs=1024 seek=$SCRIPT_N conv=notrunc status=none
    printf '%-14s %5s blocks\n' "$(basename "$1")" $((SCRIPT_N + $(blocks "$3")))
}

# --- source floppies: greedy split into independent tar.Z ---
(cd "$W/src" && find gcc-2.0 -type f | LC_ALL=C sort) > "$W/files"
python3 -I - "$W/src" "$W/files" "$W/groups" $((MAXPKG * 1024)) <<'PYEOF'
import os, subprocess, sys
src, files, out, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
names = open(files).read().split('\n')[:-1]
def tz(group):
    tar = subprocess.run(['tar', '--format=v7', '--owner=0', '--group=0', '--no-recursion',
                          '-cf', '-', '-C', src] + group, capture_output=True, check=True).stdout
    return len(subprocess.run(['compress', '-c'], input=tar, capture_output=True).stdout)
groups, cur = [], ['gcc-2.0', 'gcc-2.0/config']
for n in names:
    if tz(cur + [n]) > limit:
        groups.append(cur); cur = []
    cur.append(n)
groups.append(cur)
with open(out, 'w') as f:
    for g in groups:
        f.write(' '.join(g) + '\n')
PYEOF
NSRC=$(wc -l < "$W/groups")

K=0
while read -r line; do
    K=$((K + 1))
    # shellcheck disable=SC2086
    tar --format=v7 --owner=0 --group=0 --no-recursion -cf "$W/src$K.tar" -C "$W/src" $line
    compress -c "$W/src$K.tar" > "$W/src$K.tar.Z"
    N=$(blocks "$W/src$K.tar.Z")
    if [ $K -lt $NSRC ]; then NEXT="echo \"next: insert gccsrc$((K + 1)).flp into drive B, read its script, run it\""
    else NEXT="echo \"source complete: cd \$DIR/gcc-2.0; ./configure --gas i386-gas-sysv\""; fi
    header "gcc 2.0 source floppy $K/$NSRC" "unpack gcc-2.0 source part $K/$NSRC into \$DIR" "run \"cd \$DIR\"
run \"dd if=\$FD bs=1024 skip=$SCRIPT_N count=$N | compress -d | tar xvf -\"
$NEXT" > "$W/g$K"
    floppy "$OUT/gccsrc$K.flp" "$W/g$K" "$W/src$K.tar.Z"
done < "$W/groups"

# --- tools floppy ---
tar --format=v7 --owner=0 --group=0 -cf "$W/tools.tar" -C "$W/tools" usr
compress -c "$W/tools.tar" > "$W/tools.tar.Z"
N=$(blocks "$W/tools.tar.Z")
header "gcc 2.0 bootstrap tools floppy" "install tools into \$DIR/tools, as/ld/ar/ranlib/nm/size/strip/gar/cpp symlinks, fixed gnulib, /bin/true, df" "T=\$DIR/tools
run \"cd /\"
run \"dd if=\$FD bs=1024 skip=$SCRIPT_N count=$N | compress -d | tar xvf -\"
for p in as ld ar ranlib nm size strip; do
  [ -f /usr/local/bin/\$p ] || run \"ln -s /usr/local/lib/gcc-\$p /usr/local/bin/\$p\"
done
[ -f /usr/local/bin/gar ] || run \"ln -s /usr/local/lib/gcc-ar /usr/local/bin/gar\"
[ -f /usr/local/bin/cpp ] || run \"ln -s /usr/local/lib/gcc/i386-gas-sysv/2.0/cpp /usr/local/bin/cpp\"
[ -f /usr/local/lib/gnulib.orig ] || run \"cp /usr/local/lib/gnulib /usr/local/lib/gnulib.orig\"
run \"cp \$T/gnulib /usr/local/lib/gnulib\"
run \"cp \$T/true /bin/true\"
run \"chmod 755 /bin/true\"
run \"/bin/true\"
run \"gcc -o /usr/bin/df \$T/df.c\"
echo \"next: insert gccsrc1.flp into drive B, read its script, run it\"" > "$W/gt"
floppy "$OUT/gcctools.flp" "$W/gt" "$W/tools.tar.Z"

echo "-> $OUT"
