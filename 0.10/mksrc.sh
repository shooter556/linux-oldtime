#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy of tool sources for a Linux 0.10 system that has the"
    echo "dev.flp tools: the guest script /tmp/sinst (from sinst.sh.in) and one"
    echo "compressed tar per package, each unpacked into /usr/src."
    echo "  grep-1.5   Linux-0.10/sources (patched: memory.h, size_t in dfa.h)"
    echo "  diff-1.15  Linux-0.10/sources (built like Linus's 0.10 binary: -DUSG)"
    echo "  bison      bin-src/bison.tar.gz (1988 source), plus fileutils-3.1's getdate.y"
    echo "             and posixtm.y as a test"
    echo "  fileutils  fileutils-3.1 (Linux-0.12/sources) with the 0.11 port (../0.11/mkfu.sh):"
    echo "             flat Makefile.l010, eaccess/fileblocks fixes, posixtm.c wrapper"
    echo "  make-3.62  FSF source (tsx-11 archive) + Simon Marlow's 1992 Linux patch (C part)"
    echo "             + fixes for the 0.10 libc (all under #ifdef LINUX); docs removed"
    echo "  sed-1.13   TAMU 1.0D source (the oldest sed source found; 0.10 shipped a 1.08 binary)"
    echo "  tar-1.11.1 FSF source (tsx-11); hand-written Makefile.l010 instead of configure"
    echo "  patch-2.0.12u8  FSF source (tsx-11); hand-written config.h and Makefile.l010"
    echo "  more       BSD more 5.19 with a Feb 1992 Linux port (tsx-11), + /etc/termcap"
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
command -v patch >/dev/null || { echo "[ERROR] need patch" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# grep 1.5: build with -DUSG (libc has no index/bcopy); the USG branch includes
# <memory.h>, which 0.10 lacks, and dfa.h's "typedef int size_t" clashes with
# <string.h>'s unsigned one.
mkdir "$W/grep"
gzip -dc "$SRC/Linux-0.10/sources/usr.bin/grep-1.5.tar.Z" | tar xf - -C "$W/grep"
G=$W/grep/grep-1.5
echo '#include <string.h>' > "$G/memory.h"
sed -i 's|^typedef int size_t;$|/* size_t comes from <string.h> */|' "$G/dfa.h"
! grep -q '^typedef int size_t;' "$G/dfa.h" || { echo "[ERROR] dfa.h patch failed" >&2; exit 1; }
tar --format=v7 --owner=0 --group=0 -cf "$W/grep.tar" -C "$W/grep" grep-1.5
compress -c "$W/grep.tar" > "$W/grep.tar.Z"

# diff 1.15: the tarball carries a SunOS build (gdiff, *.o); keep only the source.
# Linus built it from Makefile.dist with -DUSG and no -g.
mkdir "$W/diff"
gzip -dc "$SRC/Linux-0.10/sources/usr.bin/diff-1.15.tar.Z" | tar xf - -C "$W/diff"
rm -f "$W/diff/diff-1.15/gdiff" "$W/diff/diff-1.15/gdiff3" "$W/diff/diff-1.15/makeout" "$W/diff/diff-1.15/"*.o
tar --format=v7 --owner=0 --group=0 -cf "$W/diff.tar" -C "$W/diff" diff-1.15
compress -c "$W/diff.tar" > "$W/diff.tar.Z"

# bison (1988 source, no version number; the tarball has no top directory).
mkdir -p "$W/bison/bison-1988/test"
tar xzf "$SRC/bin-src/bison.tar.gz" -C "$W/bison/bison-1988"
gzip -dc "$SRC/Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z" | tar xf - -C "$W/bison" fileutils-3.1/lib/getdate.y fileutils-3.1/lib/posixtm.y
mv "$W/bison/fileutils-3.1/lib/"*.y "$W/bison/bison-1988/test/"
rm -rf "$W/bison/fileutils-3.1"
chmod -R u+rwX,go+rX "$W/bison"
tar --format=v7 --owner=0 --group=0 -cf "$W/bison.tar" -C "$W/bison" bison-1988
compress -c "$W/bison.tar" > "$W/bison.tar.Z"

# fileutils 3.1: the same port as for 0.11 (see ../0.11/mkfu.sh); getdate.y and
# posixtm.y go through the 1988 bison built above.
mkdir "$W/fu"
gzip -dc "$SRC/Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z" | tar xf - -C "$W/fu"
chmod -R u+rwX "$W/fu"
FU=$W/fu/fileutils-3.1
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

# 0.10 (like 0.11) has no supplementary groups and no getgroups(); limits.h says NGROUPS_MAX 0.
patch('lib/eaccess.c',
      '#ifndef NGROUPS_MAX\n#define NGROUPS_MAX sysconf (_SC_NGROUPS_MAX)\n#endif\n',
      '#undef NGROUPS_MAX\t/* Linux 0.10: no getgroups */\n')

# st_blocks for the Minix v1 fs: 1K zones, 7 direct, 1 indirect, 1 double indirect.
p = os.path.join(fu, 'lib/fileblocks.c'); s = open(p).read()
a = s.index('/* Number of direct block addresses'); b = s.index('#endif', s.index('return datablks'))
s = s[:a] + '''/* Linux 0.10 Minix fs: 1K zones, 7 direct, 1 indirect, 1 double indirect,
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
m = ['# Linux 0.10 build of GNU fileutils 3.1 (generated, replaces configure).',
     '# Usage: make -f Makefile.l010', '',
     '# No built-in suffix rules: with the guest clock before 1991 they would try',
     '# yacc on lib/posixtm.y (0.10 computes CMOS year 26 as 1926).',
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
open(os.path.join(fu, 'Makefile.l010'), 'w').write('\n'.join(m))

# posixtm.c = bison output with yy* globals renamed, so touch can link it with
# getdate.o. Replaces sed 's/yy/zz/g', which runs out of memory on Linux 0.10.
open(os.path.join(fu, 'lib/posixtm.c'), 'w').write('''/* posixtm.tab.c with its global yy* names renamed to zz* (see Makefile.l010). */
#define yyparse zzparse
#define yychar zzchar
#define yylval zzlval
#define yylloc zzlloc
#define yynerrs zznerrs
#define yydebug zzdebug
#include "posixtm.tab.c"
''')
PYEOF
tar --format=v7 --owner=0 --group=0 -cf "$W/fu.tar" -C "$W/fu" fileutils-3.1
compress -c "$W/fu.tar" > "$W/fu.tar.Z"

# make 3.62: Simon Marlow's patch (bin-src/gmake-3_62_patch.txt, March 1992) has
# Makefile hunks for a locally edited Makefile; only its C part is applied, the
# Makefile settings are passed on the make command line instead.
mkdir "$W/make"
gzip -dc "$SRC/ftp-archives/tsx-11.mit.edu/1993-12-07/sources/FSF/from_prep/make-3.62.tar.Z" | tar xf - -C "$W/make"
M=$W/make/make-3.62
sed -n '/^diff -cr gmake-3.62\/\/commands.c/,$p' "$SRC/bin-src/gmake-3_62_patch.txt" | tr -d '\r' | (cd "$M" && patch -p1 -s)
(cd "$M" && rm -f make.texinfo make.info* make.dvi make.aux make.cp make.cps make.fn make.fns \
    make.ky make.kys make.pg make.pgs make.toc make.tp make.tps make.vr make.vrs texinfo.tex \
    gpl.texinfo TAGS tags)
python3 -I - "$M" <<'EOF'
import sys, os
m = sys.argv[1]
def patch(rel, old, new, n=1):
    p = os.path.join(m, rel); s = open(p).read()
    if s.count(old) != n:
        sys.exit('[ERROR] make patch target not found in ' + rel)
    open(p, 'w').write(s.replace(old, new))
# Linux 0.10 <signal.h> has SIGCHLD only, no SIGBUS/SIGSYS; libc has no
# sys_siglist, getdtablesize, getgroups (NGROUPS_MAX is 0) or getlogin.
patch('make.h', '#ifdef\tuts\n',
      '#if defined (LINUX) && !defined (SIGCLD)\n#define\tSIGCLD\tSIGCHLD\n#endif\n\n#ifdef\tuts\n')
patch('main.c', '\t || defined (M_XENIX) || defined (APOLLO))',
      '\t || defined (M_XENIX) || defined (APOLLO) || defined (LINUX))')
patch('read.c', '\t\t  extern char *getlogin ();\n\t\t  char *name = getlogin ();',
      '\t\t  extern char *cuserid ();\n\t\t  char *name = cuserid ((char *) 0);')
c = '(defined(USG) && !defined(HAVE_SIGLIST)) || defined(DGUX)'
patch('job.c', '#if\t' + c, '#if\t' + c + ' || defined(LINUX)', 2)
patch('main.c', '#if\t' + c, '#if\t' + c + ' || defined(LINUX)', 2)
patch('job.c', '#define getdtablesize() NOFILE\n#endif\n#endif\n',
      '#define getdtablesize() NOFILE\n#endif\n#else\n#define getdtablesize() 20\t/* NR_OPEN */\n#endif\n')
patch('job.c', '#if\t!defined (USG) || defined (POSIX)\n#ifndef\tPOSIX\n      extern int getgroups ();',
      '#if\t(!defined (USG) || defined (POSIX)) && !defined (LINUX)\n#ifndef\tPOSIX\n      extern int getgroups ();')
patch('job.c', '#ifndef\tUSG\n\t\t  register int i;\n\t\t  for (i = 0; i < ngroups; ++i)',
      '#if\t!defined (USG) && !defined (LINUX)\n\t\t  register int i;\n\t\t  for (i = 0; i < ngroups; ++i)')
for sig, txt in (('SIGBUS', 'Bus Error'), ('SIGSYS', 'Bad Argument to System Call')):
    patch('job.c', '      case %s:\n\tsys_siglist[i] = "%s";\n\tbreak;\n' % (sig, txt),
          '#ifdef\t%s\n      case %s:\n\tsys_siglist[i] = "%s";\n\tbreak;\n#endif\n' % (sig, sig, txt))
EOF
chmod -R u+rwX,go+rX "$W/make"
tar --format=v7 --owner=0 --group=0 -cf "$W/make.tar" -C "$W/make" make-3.62
compress -c "$W/make.tar" > "$W/make.tar.Z"

# sed 1.13: TAMU's tree, configured for Linux in 1993; DEFS is overridden at build time.
mkdir "$W/sed"
tar xzf "$SRC/distributions/TAMU/TAMU-1.0D/src/tar/sed-1.13.tar.gz" -C "$W/sed" ./usr.bin/sed-1.13
mv "$W/sed/usr.bin/sed-1.13" "$W/sed/" && rm -rf "$W/sed/usr.bin" "$W/sed/sed-1.13/config.status" "$W/sed/sed-1.13/sed113A.Notes"
chmod -R u+rwX,go+rX "$W/sed"
tar --format=v7 --owner=0 --group=0 -cf "$W/sed.tar" -C "$W/sed" sed-1.13
compress -c "$W/sed.tar" > "$W/sed.tar.Z"

T11=$SRC/ftp-archives/tsx-11.mit.edu/1993-12-07/sources

# tar 1.11.1: configure needs a working shell environment; Makefile.l010 is
# Makefile.in with what configure would find on Linux 0.10.
mkdir "$W/tar"
gzip -dc "$T11/FSF/from_prep/tar-1.11.1.tar.Z" | tar xf - -C "$W/tar"
python3 -I - "$W/tar/tar-1.11.1" <<'EOF'
import sys, os
t = sys.argv[1]
p = os.path.join(t, 'port.h'); s = open(p).read()
old = '#if !defined(S_ISLNK) && defined(S_IFLNK)'
if s.count(old) != 1:
    sys.exit('[ERROR] port.h patch target not found')
open(p, 'w').write(s.replace(old, '#if defined(MKFIFO_MISSING) && defined(S_IFIFO)\t/* Linux 0.10 libc */\n'
    '#define mkfifo(path, mode) (mknod ((path), (mode) | S_IFIFO, 0))\n#endif\n' + old))
defs = ('-DRETSIGTYPE=void -DDIRENT -DSTDC_HEADERS -DHAVE_UNISTD_H -DHAVE_LIMITS_H -DUSG '
        '-DNO_REMOTE -DHAVE_STRSTR -DHAVE_VALLOC -DHAVE_MKDIR -DHAVE_MKNOD -DHAVE_RENAME '
        '-DHAVE_FTIME -DHAVE_VPRINTF -DHAVE_GETPWUID -DHAVE_GETGRGID -DMKFIFO_MISSING')
m = open(os.path.join(t, 'Makefile.in')).read()
for a, b in (('@srcdir@', '.'), ('@CC@', 'gcc'), ('@YACC@', 'bison -y'), ('@INSTALL@', 'cp'),
             ('@INSTALL_PROGRAM@', 'cp'), ('@INSTALL_DATA@', 'cp'), ('@DEF_AR_FILE@', '-'),
             ('@DEFS@', defs), ('@RTAPELIB@', ''), ('@LIBS@', ''), ('@PROGS@', 'tar'),
             ('@MALLOC@', ''), ('CFLAGS = -g', 'CFLAGS = -O'), ('LDFLAGS = -g', 'LDFLAGS = -s'),
             ('\tyacc getdate.y', '\tbison -y getdate.y')):
    if a not in m:
        sys.exit('[ERROR] Makefile.in has no ' + a)
    m = m.replace(a, b)
open(os.path.join(t, 'Makefile.l010'), 'w').write('# Linux 0.10: Makefile.in filled in by hand (no configure)\n' + m)
EOF
tar --format=v7 --owner=0 --group=0 -cf "$W/tar.tar" -C "$W/tar" tar-1.11.1
compress -c "$W/tar.tar" > "$W/tar.tar.Z"

# patch 2.0.12u8: Configure is interactive; config.h and Makefile.l010 by hand.
mkdir "$W/patch"
gzip -dc "$T11/FSF/from_prep/patch-2.0.12u8.tar.Z" | tar xf - -C "$W/patch"
PD=$W/patch/patch-2.0.12u8
{ echo '/* config.h for Linux 0.10, written by hand (Configure is interactive). */'
  echo '#define index strchr'
  echo '#define rindex strrchr'
  echo '#define VOIDSIG'
  echo '#define HAVE_UNISTD_H'
  for i in 1 2 3 4 5 6; do echo "#define Reg$i register"; done
  for i in 7 8 9 10 11 12 13 14 15 16; do echo "#define Reg$i"; done; } > "$PD/config.h"
printf '%s\n' '# Linux 0.10 (no Configure)' 'CC = gcc' 'CFLAGS = -O -DDIRENT' 'LDFLAGS = -s' \
    'obj = patch.o pch.o inp.o util.o version.o backupfile.o' '' 'patch: $(obj)' \
    '	$(CC) $(LDFLAGS) $(obj) -o patch' > "$PD/Makefile.l010"
tar --format=v7 --owner=0 --group=0 -cf "$W/patch.tar" -C "$W/patch" patch-2.0.12u8
compress -c "$W/patch.tar" > "$W/patch.tar.Z"

# more: BSD more 5.19 ported to Linux in Feb 1992; needs /etc/termcap, taken
# from rootimage-0.11 (same file as on the 1991 Linux-0.11/images root image).
mkdir -p "$W/more/more"
gzip -dc "$T11/usr.bin/more.tar.Z" | tar xf - -C "$W/more/more"
rm -f "$W/more/more/"*.ORIG
gzip -dc "$SRC/Linux-0.11/images/rootimage-0.11.Z" > "$W/root11.img"
python3 -I - "$W/root11.img" "$W/more/more/termcap" <<'EOF'
import struct, sys
img = open(sys.argv[1], 'rb').read()
B = lambda n: img[n*1024:(n+1)*1024]
ni, nz, im, zm = struct.unpack('<HHHH', B(1)[:8]); it = 2 + im + zm
def inode(n):
    o = it*1024 + (n-1)*32; s = struct.unpack('<I', img[o+4:o+8])[0]
    return s, struct.unpack('<9H', img[o+14:o+32])
def data(n):
    s, z = inode(n)
    return b''.join(B(q) for q in z[:7] if q)[:s]
ino = 1
for part in ('etc', 'termcap'):
    d = data(ino)
    ino = next(struct.unpack('<H', d[i:i+2])[0] for i in range(0, len(d), 16)
               if d[i+2:i+16].rstrip(b'\0').decode() == part)
open(sys.argv[2], 'wb').write(data(ino))
EOF
chmod -R u+rwX,go+rX "$W/tar" "$W/patch" "$W/more"
tar --format=v7 --owner=0 --group=0 -cf "$W/more.tar" -C "$W/more" more
compress -c "$W/more.tar" > "$W/more.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=6
GREP_O=$SCRIPT_N GREP_N=$(blocks "$W/grep.tar.Z")
DIFF_O=$((GREP_O + GREP_N)) DIFF_N=$(blocks "$W/diff.tar.Z")
BISON_O=$((DIFF_O + DIFF_N)) BISON_N=$(blocks "$W/bison.tar.Z")
FU_O=$((BISON_O + BISON_N)) FU_N=$(blocks "$W/fu.tar.Z")
MAKE_O=$((FU_O + FU_N)) MAKE_N=$(blocks "$W/make.tar.Z")
SED_O=$((MAKE_O + MAKE_N)) SED_N=$(blocks "$W/sed.tar.Z")
TAR_O=$((SED_O + SED_N)) TAR_N=$(blocks "$W/tar.tar.Z")
PATCH_O=$((TAR_O + TAR_N)) PATCH_N=$(blocks "$W/patch.tar.Z")
MORE_O=$((PATCH_O + PATCH_N)) MORE_N=$(blocks "$W/more.tar.Z")
END=$((MORE_O + MORE_N))
[ $END -le 1440 ] || { echo "[ERROR] too big: $END blocks" >&2; exit 1; }

# "SKIP SEEK COUNT" triples, 100 blocks each, for the guest's unpack()
chunks() {
    local o=$1 n=$2 k=0 c out=
    while [ $k -lt $n ]; do
        c=$(( n - k < 100 ? n - k : 100 ))
        out="$out \"$((o + k)) $k $c\""
        k=$((k + c))
    done
    echo "${out# }"
}
sub=
for k in GREP DIFF BISON FU MAKE SED TAR PATCH MORE; do
    o=${k}_O n=${k}_N
    sub="$sub s/@${k}_C@/$(chunks ${!o} ${!n})/;"
done

sed -e "$sub" -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@GREP_O@/$GREP_O/; s/@GREP_N@/$GREP_N/" \
    -e "s/@DIFF_O@/$DIFF_O/; s/@DIFF_N@/$DIFF_N/; s/@BISON_O@/$BISON_O/; s/@BISON_N@/$BISON_N/" \
    -e "s/@FU_O@/$FU_O/; s/@FU_N@/$FU_N/; s/@MAKE_O@/$MAKE_O/; s/@MAKE_N@/$MAKE_N/" \
    -e "s/@SED_O@/$SED_O/; s/@SED_N@/$SED_N/; s/@MAKE_E@/$SED_O/; s/@SED_E@/$TAR_O/" \
    -e "s/@TAR_O@/$TAR_O/; s/@TAR_N@/$TAR_N/; s/@TAR_E@/$PATCH_O/; s/@PATCH_O@/$PATCH_O/" \
    -e "s/@PATCH_N@/$PATCH_N/; s/@PATCH_E@/$MORE_O/; s/@MORE_O@/$MORE_O/; s/@MORE_N@/$MORE_N/; s/@MORE_E@/$END/" \
    -e "s/@GREP_E@/$DIFF_O/; s/@DIFF_E@/$BISON_O/; s/@BISON_E@/$FU_O/; s/@FU_E@/$MAKE_O/" \
    "$HERE/sinst.sh.in" > "$W/sinst"
! grep -n '@[A-Z_]*@' "$W/sinst" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/sinst") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/sinst" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/grep.tar.Z" of="$OUT" bs=1024 seek=$GREP_O conv=notrunc status=none
dd if="$W/diff.tar.Z" of="$OUT" bs=1024 seek=$DIFF_O conv=notrunc status=none
dd if="$W/bison.tar.Z" of="$OUT" bs=1024 seek=$BISON_O conv=notrunc status=none
dd if="$W/fu.tar.Z" of="$OUT" bs=1024 seek=$FU_O conv=notrunc status=none
dd if="$W/make.tar.Z" of="$OUT" bs=1024 seek=$MAKE_O conv=notrunc status=none
dd if="$W/sed.tar.Z" of="$OUT" bs=1024 seek=$SED_O conv=notrunc status=none
for k in tar patch more; do
    o=${k^^}_O; dd if="$W/$k.tar.Z" of="$OUT" bs=1024 seek=${!o} conv=notrunc status=none
done
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N grep $GREP_O $GREP_N diff $DIFF_O $DIFF_N \
    bison $BISON_O $BISON_N fileutils $FU_O $FU_N make $MAKE_O $MAKE_N sed $SED_O $SED_N \
    tar $TAR_O $TAR_N patch $PATCH_O $PATCH_N more $MORE_O $MORE_N
echo "used $END / 1440 blocks -> $OUT"
