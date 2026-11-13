#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy with the guest script /tmp/fuinst (from fuinst.sh.in)"
    echo "and a compressed tar of:"
    echo "  usr/src/fileutils-3.1   GNU fileutils 3.1 (Linux-0.12/sources), ported to"
    echo "                          Linux 0.11 + its gcc/libc: Makefile.l011 instead of"
    echo "                          configure, no getgroups, Minix-fs st_blocks"
    echo "  usr/local/bin/bison, usr/gnu/lib/bison.{simple,hairy}   GNU Bison 1.14"
    echo "                          (Linux-0.12/binaries), for getdate.y/posixtm.y"
    echo "  (lib/posixtm.c wraps bison's posixtm.tab.c with yy->zz #defines; 0.11 sed can't do it)"
    echo "plus, raw after the tar, /etc/profile of rootimage-0.11 with 'cd \$HOME' run only by"
    echo "the login shell (0.11 bash reads /etc/profile in every sh -c, e.g. under make)."
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
[ -d "$SRC/Linux-0.12" ] || { echo "[ERROR] not an oldlinux-files tree: '$SRC' (use -s)" >&2; exit 1; }
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/usr/src" "$W/usr/local/bin" "$W/usr/gnu/lib" "$W/x"
gzip -dc "$SRC/Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z" | tar xf - -C "$W/usr/src"
gzip -dc "$SRC/Linux-0.12/binaries/compilers/bison.tar.Z" | tar xf - -C "$W/x"
chmod -R u+rwX "$W/usr/src" "$W/x"
B=$(dirname "$(find "$W/x" -type f -name bison)")
cp "$B/bison" "$W/usr/local/bin/"
cp "$B/bison.simple" "$B/bison.hairy" "$W/usr/gnu/lib/"
chmod 755 "$W/usr/local/bin/bison"

gzip -dc "$SRC/Linux-0.11/images/rootimage-0.11.Z" > "$W/root.img"
python3 -I - "$W/root.img" "$W/profile" <<'PYEOF'
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
for p in ('etc', 'profile'):
    d = data(*inode(ino))
    ino = next(struct.unpack('<H', d[i:i+2])[0] for i in range(0, len(d), 16)
               if struct.unpack('<H', d[i:i+2])[0] and d[i+2:i+16].rstrip(b'\0').decode() == p)
prof = data(*inode(ino))
old = b'\ncd $HOME\n'
if prof.count(old) != 1:
    sys.exit('[ERROR] cd $HOME line not found in /etc/profile')
prof = prof.replace(old, b'\n[ -z "$PROFILED" ] && cd $HOME\nPROFILED=1\nexport PROFILED\n')
open(sys.argv[2], 'wb').write(prof)
PYEOF

FU=$W/usr/src/fileutils-3.1
cp "$FU/src/ls.c" "$FU/src/dir.c"
cp "$FU/src/ls.c" "$FU/src/vdir.c"
python3 -I - "$FU" <<'PYEOF'
import sys, os
fu = sys.argv[1]

def patch(rel, old, new):
    p = os.path.join(fu, rel); s = open(p).read()
    if s.count(old) != 1:
        sys.exit('[ERROR] patch target not unique in ' + rel)
    open(p, 'w').write(s.replace(old, new))

# 0.11 has no supplementary groups and no getgroups(); limits.h says NGROUPS_MAX 0.
patch('lib/eaccess.c',
      '#ifndef NGROUPS_MAX\n#define NGROUPS_MAX sysconf (_SC_NGROUPS_MAX)\n#endif\n',
      '#undef NGROUPS_MAX\t/* Linux 0.11: no getgroups */\n')

# st_blocks for the Minix v1 fs: 1K zones, 7 direct, 1 indirect, 1 double indirect.
p = os.path.join(fu, 'lib/fileblocks.c'); s = open(p).read()
a = s.index('/* Number of direct block addresses'); b = s.index('#endif', s.index('return datablks'))
s = s[:a] + '''/* Linux 0.11 Minix fs: 1K zones, 7 direct, 1 indirect, 1 double indirect,
   512 zone numbers per indirect zone. Result in 512-byte blocks. */
#define NDIR	7
#define NINDIR	512

long
st_blocks (size)
     long size;
{
  long datablks = (size + 1024 - 1) / 1024;
  long indrblks = 0;

  if (datablks > NDIR)
    {
      indrblks = 1;
      if (datablks > NDIR + NINDIR)
	indrblks += 1 + (datablks - NDIR - NINDIR - 1) / NINDIR + 1;
    }

  return 2 * (datablks + indrblks);
}
''' + s[b:]
open(p, 'w').write(s)

# Flat makefile replacing configure (whose tests need a working rm/mv).
defs = ('-DDIRENT -DST_BLOCKS_MISSING -DBSIZE=1024 -DSTDC_HEADERS -DPOSIX -DUSG '
        '-DFCHMOD_MISSING -DMKFIFO_MISSING -DFTRUNCATE_MISSING')
libo = ('argmatch backupfile basename dirname eaccess error filemode getopt getopt1 '
        'getversion idcache isdir makepath modechange savedir stripslash xmalloc '
        'xstrdup yesno getdate posixtm fnmatch stpcpy strdup fileblocks').split()
progs = {'chgrp': ['chgrp'], 'chmod': ['chmod'], 'chown': ['chown'],
         'cp': ['cp', 'cp-aux', 'cp-hash'], 'dd': ['dd'], 'du': ['du'],
         'ginstall': ['install'], 'ln': ['ln'], 'ls': ['ls'], 'dir': ['dir'],
         'vdir': ['vdir'], 'mkdir': ['mkdir'], 'mkfifo': ['mkfifo'], 'mknod': ['mknod'],
         'mv': ['mv'], 'mvdir': ['mvdir'], 'rm': ['rm'], 'rmdir': ['rmdir'],
         'touch': ['touch']}
extra = {'dir': '-DMULTI_COL', 'vdir': '-DLONG_FORMAT'}
T = '\t'
m = ['# Linux 0.11 build of GNU fileutils 3.1 (generated, replaces configure).',
     '# Usage: make -f Makefile.l011', '',
     '# No built-in suffix rules: with the guest clock before 1991 they would try',
     '# yacc on lib/posixtm.y (0.11 computes CMOS year 26 as 1926).',
     '.SUFFIXES:', '',
     'CC = gcc', 'AR = /usr/local/lib/gcc-ar', 'RANLIB = /usr/local/lib/gcc-ranlib',
     'DEFS = ' + defs, 'CFLAGS = -O -Ilib $(DEFS)', 'LDFLAGS = -s', '',
     'PROGS = ' + ' '.join('src/' + p for p in progs), '',
     'all: $(PROGS)', '',
     'lib/libfu.a: ' + ' '.join('lib/%s.o' % o for o in libo),
     T + '$(AR) cr lib/libfu.a ' + ' '.join('lib/%s.o' % o for o in libo),
     T + '$(RANLIB) lib/libfu.a', '',
     'lib/getdate.c: lib/getdate.y',
     T + 'cd lib; bison getdate.y; cat getdate.tab.c > getdate.c', '',
     'lib/posixtm.tab.c: lib/posixtm.y',
     T + 'cd lib; bison posixtm.y', '',
     'lib/posixtm.o: lib/posixtm.tab.c', '']
for o in libo:
    m += ['lib/%s.o: lib/%s.c' % (o, o), T + '$(CC) $(CFLAGS) -c lib/%s.c -o lib/%s.o' % (o, o), '']
srcs = sorted({s for v in progs.values() for s in v} | {'version'})
for s in srcs:
    m += ['src/%s.o: src/%s.c' % (s, s),
          T + '$(CC) $(CFLAGS) %s-c src/%s.c -o src/%s.o' % (extra[s] + ' ' if s in extra else '', s, s), '']
for p, objs in progs.items():
    o = ' '.join('src/%s.o' % x for x in objs)
    m += ['src/%s: %s src/version.o lib/libfu.a' % (p, o),
          T + '$(CC) $(LDFLAGS) -o src/%s %s src/version.o lib/libfu.a' % (p, o), '']
open(os.path.join(fu, 'Makefile.l011'), 'w').write('\n'.join(m))

# posixtm.c = bison output with yy* globals renamed, so touch can link it with
# getdate.o. Replaces sed 's/yy/zz/g', which runs out of memory on Linux 0.11.
open(os.path.join(fu, 'lib/posixtm.c'), 'w').write('''/* posixtm.tab.c with its global yy* names renamed to zz* (see Makefile.l011). */
#define yyparse zzparse
#define yychar zzchar
#define yylval zzlval
#define yylloc zzlloc
#define yynerrs zznerrs
#define yydebug zzdebug
#include "posixtm.tab.c"
''')
PYEOF

tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=5
PKG_O=$SCRIPT_N PKG_N=$(blocks "$W/pkg.tar.Z")
PROF_O=$((PKG_O + PKG_N)) PROF_SIZE=$(stat -c%s "$W/profile")
MK_O=$((PROF_O + 1)) MK_SIZE=$(stat -c%s "$FU/Makefile.l011")
PT_O=$((MK_O + $(blocks "$FU/Makefile.l011"))) PT_SIZE=$(stat -c%s "$FU/lib/posixtm.c")
END=$((PT_O + 1))
[ $END -le 1440 ] || { echo "[ERROR] too big" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@PKG_O@/$PKG_O/; s/@PKG_N@/$PKG_N/" \
    -e "s/@PROF_SKIP@/$((PROF_O * 1024))/g; s/@PROF_SIZE@/$PROF_SIZE/g" \
    -e "s/@MK_SKIP@/$((MK_O * 1024))/g; s/@MK_SIZE@/$MK_SIZE/g" \
    -e "s/@PT_SKIP@/$((PT_O * 1024))/g; s/@PT_SIZE@/$PT_SIZE/g" "$HERE/fuinst.sh.in" > "$W/fuinst"
! grep -n '@[A-Z_]*@' "$W/fuinst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/fuinst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/fuinst" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/pkg.tar.Z" of="$OUT" bs=1024 seek="$PKG_O" conv=notrunc status=none
dd if="$W/profile" of="$OUT" bs=1024 seek="$PROF_O" conv=notrunc status=none
dd if="$FU/Makefile.l011" of="$OUT" bs=1024 seek="$MK_O" conv=notrunc status=none
dd if="$FU/lib/posixtm.c" of="$OUT" bs=1024 seek="$PT_O" conv=notrunc status=none
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N pkg $PKG_O $PKG_N profile $PROF_O 1 \
    makefile $MK_O $(blocks "$FU/Makefile.l011") posixtm.c $PT_O 1
echo "used $END / 1440 blocks -> $OUT"
