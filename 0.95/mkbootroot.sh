#!/usr/bin/env bash
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${OLDLINUX:-}

usage() {
    echo "Usage: $(basename "$0") -s|--source DIR -o|--output FLOPPY_IMAGE [-f|--force]"
    echo
    echo "Build a 1.44M raw floppy for an installed Linux 0.12 with gcc 2.0 (see ../0.12),"
    echo "to make Linux 0.95 boot and root diskettes there. It holds the guest script"
    echo "/tmp/br (from brinst.sh.in) and a compressed v7 tar of usr/src:"
    echo "  linux/          stock linux-0.95.tar; ROOT_DEV=FLOPPY, KBD_US"
    echo "and in usr/src/0.95:"
    echo "  poe-IGL/        poeigl-1.2 init/getty/login (+ memory.h, sys/param.h and"
    echo "                  sys/resource.h from the 0.95 kernel, MAXPATHLEN in login.c)"
    echo "  system/         Linus's mkfs.c, mkswap.c, mknod.c (system-0.12.tar.Z)"
    echo "  fdisk.c         fdisk 0.91 (Linux-0.95/sources/sbin/fdisk-0.91.tar.Z), HDIO_REQ, fflush"
    echo "  df.c            Linux-0.12/sources/usr.bin/df.c (Peter MacDonald)"
    echo "  mount.c umount.c  Linux-0.12/sources/sbin, lock file opened O_WRONLY"
    echo "  swapsrc/        Linux-0.12/sources/sbin/swapon.tar.Z, __NR_swapon 87"
    echo "  update.c        system-0.98.tar.Z;  sync.c  main() { sync(); }"
    echo "  uname.c         bin/uname.c (Jeff Comstock, 1992)"
    echo "  fileutils-3.1/  GNU fileutils 3.1 + Makefile.l095 (only the root diskette programs)"
    echo "  gzip-1.1.1/     gzip 1.1.1 source (./gzip-1.1.1) + Makefile.l095 (gzip.mk); for tools.flp"
    echo "  include/        string.h of the 0.95 kernel (include-0.12's fails with gcc 2.0 -O)"
    echo "  lib/libc.a      libc-0.12.a (the 0.12 HD has the 1991 gccbin libc), linked via -L"
    echo "  bison/          GNU Bison 1.14 binary, for getdate.y/posixtm.y (touch)"
    echo "  bin/            vi (elvis 1.4, Linux-0.12/binaries/usr.bin/vi.Z), tar and compress"
    echo "                  (images/rootimage-0.11-20040305), stripped"
    echo "  etc/            inittab rc passwd group issue securetty for the root diskette"
    echo "  Makefile        tools.mk"
    echo "  inst.sh.in      0.95 HD installer, put on gcc.flp by \"sh /tmp/br gccpkg\""
    echo "  shoe/           ShoeLace binaries (bin-src/shoelace.tar.Z, Linux build of 1992-01-17)"
    echo "                  + config \"boot /Image\", put on gcc.flp to boot 0.95 from hda2"
    echo "Sources: an oldlinux-files tree. Patched files keep their 1992 timestamps."
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
[ -d "$SRC/Linux-0.95" ] || { echo "[ERROR] not an oldlinux-files tree: '$SRC' (use -s)" >&2; exit 1; }
[ ! -e "$OUT" ] || [ $FORCE = 1 ] || { echo "[ERROR] $OUT exists (use -f)" >&2; exit 1; }
command -v compress >/dev/null || { echo "[ERROR] need ncompress (compress)" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=$W/usr/src/0.95
mkdir -p "$D/swapsrc" "$D/bison" "$D/etc" "$W/x"

tar xf "$SRC/Linux-0.95/sources/system/linux-0.95.tar" -C "$W/usr/src"
gzip -dc "$SRC/Linux-0.12/sources/sbin/poeigl-1.2.tar.Z" | tar xf - -C "$D"
gzip -dc "$SRC/Linux-0.12/sources/sbin/system-0.12.tar.Z" | tar xf - -C "$D" \
    system/mkfs.c system/mkswap.c system/mknod.c
gzip -dc "$SRC/Linux-0.95/sources/sbin/fdisk-0.91.tar.Z" | tar xf - -C "$W/x" fdisk/fdisk.c
# fdisk 0.91 is dated 1992-04-01: date it like update.c
cp "$W/x/fdisk/fdisk.c" "$D/fdisk.c"
touch -d '1992-03-08 12:00' "$D/fdisk.c"
cp -p "$SRC/Linux-0.12/sources/usr.bin/df.c" "$D/df.c"   # sbin/df.c is the same with CRLF
gzip -dc "$SRC/Linux-0.12/sources/sbin/mount.c.Z" > "$D/mount.c"
gzip -dc "$SRC/Linux-0.12/sources/sbin/umount.c.Z" > "$D/umount.c"
touch -r "$SRC/Linux-0.12/sources/sbin/mount.c.Z" "$D/mount.c"
touch -r "$SRC/Linux-0.12/sources/sbin/umount.c.Z" "$D/umount.c"
gzip -dc "$SRC/Linux-0.12/sources/sbin/swapon.tar.Z" | tar xf - -C "$D/swapsrc" cmd_swapon.c lib_swapon.c
gzip -dc "$SRC/bin-src/system-0.98.tar.Z" | tar xf - -C "$W/x" system-0.98/update.c
# no older update source survives; date it like sync.c so the guest clock only has to pass 0.95's release
cp "$W/x/system-0.98/update.c" "$D/update.c"
printf 'main()\n{\n\tsync();\n\treturn 0;\n}\n' > "$D/sync.c"
touch -d '1992-03-08 12:00' "$D/sync.c"
cp "$SRC/bin/uname.c" "$D/uname.c"
gzip -dc "$SRC/Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z" | tar xf - -C "$D"
gzip -dc "$SRC/Linux-0.12/binaries/compilers/bison.tar.Z" | tar xf - -C "$W/x"
B=$(dirname "$(find "$W/x" -type f -name bison)")
cp -p "$B/bison" "$B/bison.simple" "$B/bison.hairy" "$D/bison/"
cp -p -R "$HERE/gzip-1.1.1" "$D/gzip-1.1.1"
cp "$HERE/gzip.mk" "$D/gzip-1.1.1/Makefile.l095"
cp "$HERE/tools.mk" "$D/Makefile"
cp "$HERE/inst.sh.in" "$D/inst.sh.in"
# ShoeLace boots /Image from the hda2 Minix fs (WiniBoot in the MBR, bootlace in hda2's boot block)
mkdir -p "$D/shoe"
gzip -dc "$SRC/bin-src/shoelace.tar.Z" | tar xf - -C "$W/x" shoe
for f in shoelace laceup bootlace winiboot disktab; do cp -p "$W/x/shoe/$f" "$D/shoe/"; done
printf '# ShoeLace for Linux 0.95: load /Image (its ROOT_DEV at offset 508 is 0x0302 = /dev/hda2)\nboot\t\t/Image\n' \
    > "$D/shoe/config"
touch -d '1992-03-08 12:00' "$D/Makefile"
chmod -R u+rwX,go+rX "$D"
chmod 755 "$D/bison/bison"

tar xf "$SRC/Linux-0.95/sources/system/linux-0.95.tar" -C "$W/x" \
    linux/include/sys/param.h linux/include/sys/resource.h
mkdir -p "$D/poe-IGL/sys" "$D/include"
# the 0.12 HD links gccbin's 1991 libc (no gethostname, lstat, symlink, ...): ship libc-0.12.a, used via -L
mkdir -p "$D/lib"
gzip -dc "$SRC/libs/libc/libc-0.1x/libc-0.12.a.Z" > "$D/lib/libc.a"
touch -d "@$(head -c 36 "$D/lib/libc.a" | tail -c 12)" "$D/lib/libc.a"
cp -p "$W/usr/src/linux/include/string.h" "$D/include/"
cp -p "$W/x/linux/include/sys/param.h" "$W/x/linux/include/sys/resource.h" "$D/poe-IGL/sys/"
printf '#include <string.h>\n' > "$D/poe-IGL/memory.h"
touch -d '1992-02-29 12:00' "$D/poe-IGL/memory.h"

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

# binaries for the root diskette: no source of these old enough (or at all) to build here
mkdir -p "$D/bin"
gzip -dc "$SRC/Linux-0.12/binaries/usr.bin/vi.Z" > "$D/bin/vi"
for p in tar compress; do
    minixcat "$SRC/images/rootimage-0.11-20040305" "/usr/bin/$p" > "$D/bin/$p"
done
aoutstrip "$D/bin/vi" "$D/bin/tar" "$D/bin/compress"
chmod 755 "$D/bin/"*

python3 -I - "$D" <<'PYEOF'
import sys, os, time
d = sys.argv[1]
T92 = int(time.mktime((1992, 3, 8, 12, 0, 0, 0, 0, -1)))

def patch(rel, old, new):
    p = os.path.join(d, rel); st = os.stat(p); s = open(p, encoding='latin-1').read()
    if s.count(old) != 1:
        sys.exit('[ERROR] patch target not unique in ' + rel)
    open(p, 'w', encoding='latin-1').write(s.replace(old, new))
    os.utime(p, (st.st_atime, st.st_mtime))

patch('../linux/Makefile', '\nROOT_DEV=/dev/hdb1\n', '\nROOT_DEV=FLOPPY\n')
patch('../linux/kernel/chr_drv/keyboard.S', '\n#define KBD_FINNISH\n', '\n#define KBD_US\n')

# login.c uses MAXPATHLEN, which no 0.12/0.95 header defines; same fix as poe's
# own patch of 1992-03-02 (bin-src/poe-IGL.patch).
patch('poe-IGL/login.c', '#define TTYGRPNAME      "other"\n',
      '#define TTYGRPNAME      "other"\n#include <limits.h>\n#define MAXPATHLEN _POSIX_PATH_MAX\n')

# fdisk 0.91 wants HDIO_REQ from Owen's kernel ioctl.patch; the stock 0.95 kernel has no
# hd_ioctl, so the ioctl just fails and geometry is set by hand (x h/s/c).
patch('fdisk.c', '#include <linux/hdreg.h>\n', '''#include <linux/hdreg.h>
#ifndef HDIO_REQ
#define HDIO_REQ 0x301
struct hd_geometry {
	unsigned char heads;
	unsigned char sectors;
	unsigned short cylinders;
};
#endif
''')

# libc-0.12 does not flush stdout before reading stdin: every prompt showed up after the answer.
patch('fdisk.c', '\t\tfputs(mesg, stdout);\n', '\t\tfputs(mesg, stdout), fflush(stdout);\n')

# 0.95 sys_write checks f_mode: without O_WRONLY nothing reaches /etc/mtab.
patch('mount.c', 'open(LOCK_FILE,O_CREAT | O_EXCL,0644)', 'open(LOCK_FILE,O_WRONLY | O_CREAT | O_EXCL,0644)')
patch('umount.c', 'open(LOCK_FILE,O_CREAT | O_EXCL,0600)', 'open(LOCK_FILE,O_WRONLY | O_CREAT | O_EXCL,0600)')

# include-0.12 unistd.h has no swapon, and its _syscall1 asm ("b" input) fails with gcc 2.0:
# expand it as the 0.95 kernel unistd.h does (movl to ebx, "g" input, bx clobbered).
patch('swapsrc/lib_swapon.c', '#define __LIBRARY__\n', '#define __LIBRARY__\n#define __NR_swapon\t87\n')
patch('swapsrc/lib_swapon.c', '_syscall1(int,swapon,const char *,specialfile)\n', '''int swapon(const char * specialfile)
{
long __res;
__asm__ volatile ("movl %2,%%ebx\\n\\t"
	"int $0x80"
	: "=a" (__res)
	: "0" (__NR_swapon),"g" ((long)(specialfile)):"bx");
if (__res >= 0)
	return (int) __res;
errno = -__res;
return -1;
}
''')

fu = os.path.join(d, 'fileutils-3.1')
# NGROUPS_MAX is 0 in include-0.12 limits.h: no supplementary groups.
patch('fileutils-3.1/lib/eaccess.c',
      '#ifndef NGROUPS_MAX\n#define NGROUPS_MAX sysconf (_SC_NGROUPS_MAX)\n#endif\n',
      '#undef NGROUPS_MAX\t/* Linux 0.12: NGROUPS_MAX 0 */\n')

# st_blocks for the Minix v1 fs: 1K zones, 7 direct, 1 indirect, 1 double indirect.
p = os.path.join(fu, 'lib/fileblocks.c'); st = os.stat(p); s = open(p).read()
a = s.index('/* Number of direct block addresses'); b = s.index('#endif', s.index('return datablks'))
s = s[:a] + '''/* Minix v1 fs: 1K zones, 7 direct, 1 indirect, 1 double indirect,
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
os.utime(p, (st.st_atime, st.st_mtime))

# include-0.12 sys/stat.h lacks S_IFLNK, so ln -s would fall back to hard links;
# lib/system.h derives S_ISLNK from it (0.12 kernel value). libc-0.12 has symlink/lstat/readlink.
defs = ('-DS_IFLNK=0120000 -DDIRENT -DST_BLOCKS_MISSING -DBSIZE=1024 -DSTDC_HEADERS -DPOSIX -DUSG '
        '-DFCHMOD_MISSING -DMKFIFO_MISSING -DFTRUNCATE_MISSING')
libo = ('argmatch backupfile basename dirname eaccess error filemode getopt getopt1 '
        'getversion idcache isdir makepath modechange savedir stripslash xmalloc '
        'xstrdup yesno getdate posixtm fnmatch stpcpy strdup fileblocks').split()
progs = {'chgrp': ['chgrp'], 'chmod': ['chmod'], 'chown': ['chown'],
         'cp': ['cp', 'cp-aux', 'cp-hash'], 'ln': ['ln'], 'ls': ['ls'],
         'dd': ['dd'], 'mkdir': ['mkdir'], 'mv': ['mv'], 'rm': ['rm'], 'rmdir': ['rmdir'],
         'touch': ['touch']}
T = '\t'
m = ['# Linux 0.12 + gcc 2.0 build of GNU fileutils 3.1 for the 0.95 root diskette',
     '# (generated by mkbootroot.sh, replaces configure). Usage: make -f Makefile.l095', '',
     '.SUFFIXES:', '',
     'CC = gcc', 'AR = /usr/local/lib/gcc-ar', 'RANLIB = /usr/local/lib/gcc-ranlib', 'BISON = bison',
     'DEFS = ' + defs, 'CFLAGS = -O -Ilib -I/usr/src/0.95/include $(DEFS)', 'LDFLAGS = -L/usr/src/0.95/lib -Xlinker -s', '',
     'PROGS = ' + ' '.join('src/' + p for p in progs), '',
     'all: $(PROGS)', '',
     'lib/libfu.a: ' + ' '.join('lib/%s.o' % o for o in libo),
     T + '$(AR) cr lib/libfu.a ' + ' '.join('lib/%s.o' % o for o in libo),
     T + '$(RANLIB) lib/libfu.a', '',
     'lib/getdate.c: lib/getdate.y',
     T + 'cd lib; $(BISON) getdate.y; cat getdate.tab.c > getdate.c', '',
     'lib/posixtm.tab.c: lib/posixtm.y',
     T + 'cd lib; $(BISON) posixtm.y', '',
     'lib/posixtm.o: lib/posixtm.tab.c', '']
for o in libo:
    m += ['lib/%s.o: lib/%s.c' % (o, o), T + '$(CC) $(CFLAGS) -c lib/%s.c -o lib/%s.o' % (o, o), '']
for s in sorted({s for v in progs.values() for s in v} | {'version'}):
    m += ['src/%s.o: src/%s.c' % (s, s), T + '$(CC) $(CFLAGS) -c src/%s.c -o src/%s.o' % (s, s), '']
for p, objs in progs.items():
    o = ' '.join('src/%s.o' % x for x in objs)
    m += ['src/%s: %s src/version.o lib/libfu.a' % (p, o),
          T + '$(CC) $(LDFLAGS) -o src/%s %s src/version.o lib/libfu.a' % (p, o), '']
open(os.path.join(fu, 'Makefile.l095'), 'w').write('\n'.join(m))

# posixtm.c = bison output with yy* globals renamed, so touch links with getdate.o.
open(os.path.join(fu, 'lib/posixtm.c'), 'w').write('''/* posixtm.tab.c with its global yy* names renamed to zz* (see Makefile.l095). */
#define yyparse zzparse
#define yychar zzchar
#define yylval zzlval
#define yylloc zzlloc
#define yynerrs zznerrs
#define yydebug zzdebug
#include "posixtm.tab.c"
''')
for f in ('Makefile.l095', 'lib/posixtm.c'):
    os.utime(os.path.join(fu, f), (T92, T92))

# Root diskette /etc. inittab: poe's sample minus the serial line (no getty on a
# missing /dev/tty64); securetty: the four consoles init starts gettys on.
poe = os.path.join(d, 'poe-IGL')
it = open(os.path.join(poe, 'inittab')).read()
it = ''.join(l for l in it.splitlines(True) if not l.startswith('tty64:'))
etc = {'inittab': it,
       'rc': '/etc/update &\n> /etc/mtab\n> /etc/utmp\necho " Ok. "\n',
       'passwd': 'root::0:0:root:/:/bin/sh\n',
       'group': 'root::0:root\n',
       'issue': '\nLinux 0.95 i386\n\n',
       'securetty': 'tty1\ntty2\ntty3\ntty4\n'}
for n, s in etc.items():
    p = os.path.join(d, 'etc', n); open(p, 'w').write(s); os.utime(p, (T92, T92))

bad = [os.path.relpath(os.path.join(r, n), d) for r, ds, fs in os.walk(os.path.dirname(d)) for n in ds + fs if len(n) > 14]
if bad:
    sys.exit('[ERROR] names longer than 14 chars (Minix fs): ' + ' '.join(bad))
PYEOF

# new files and directories touched since unpacking: date them like sync.c
find "$W/usr" -newermt 1993-01-01 -exec touch -h -d '1992-03-08 12:00' {} +
tar --format=v7 --owner=0 --group=0 -cf "$W/pkg.tar" -C "$W" usr
compress -c "$W/pkg.tar" > "$W/pkg.tar.Z"

blocks() { echo $(( ($(stat -c%s "$1") + 1023) / 1024 )); }
SCRIPT_N=7
PKG_O=$SCRIPT_N PKG_N=$(blocks "$W/pkg.tar.Z")
[ $((PKG_O + PKG_N)) -le 1440 ] || { echo "[ERROR] needs $((PKG_O + PKG_N)) blocks > 1440" >&2; exit 1; }

sed -e "s/@SCRIPT_N@/$SCRIPT_N/; s/@PKG_O@/$PKG_O/; s/@PKG_N@/$PKG_N/" "$HERE/brinst.sh.in" > "$W/br"
! grep -n -E "@(SCRIPT_N|PKG_O|PKG_N)@" "$W/br" || { echo "[ERROR] unreplaced placeholder" >&2; exit 1; }
[ $(blocks "$W/br") -le $SCRIPT_N ] || { echo "[ERROR] script > $SCRIPT_N KB" >&2; exit 1; }

dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
dd if="$W/br" of="$OUT" bs=1024 conv=notrunc status=none
dd if="$W/pkg.tar.Z" of="$OUT" bs=1024 seek="$PKG_O" conv=notrunc status=none
printf '%-9s %5s %5s\n' item skip count script 0 $SCRIPT_N pkg $PKG_O $PKG_N
echo "used $((PKG_O + PKG_N)) / 1440 blocks -> $OUT"
echo "newest file in the package: $(tar -tvf "$W/pkg.tar" | awk '{print $4" "$5}' | sort | tail -1)"
echo "(the guest clock must be later than that, or make rebuilds everything each run)"
