# gzip 1.1.1 for the 0.95 hard disk, built on Linux 0.12 with gcc 2.0 + libc-0.12 (like tools.mk).
# Installed by mkbootroot.sh as /usr/src/0.95/gzip-1.1.1/Makefile.l095, instead of configure.
# Usage: make -f Makefile.l095 [check]
# Harmless warnings: built-in strlen/memcpy/memcmp, `ERROR' redefined (gzip.h vs errno.h).

CC = gcc
DEFS = -DDIRENT -DSTDC_HEADERS -DHAVE_UNISTD_H -DRETSIGTYPE=void
CFLAGS = -O -I/usr/src/0.95/include
LDFLAGS = -L/usr/src/0.95/lib -Xlinker -s

OBJS = gzip.o zip.o deflate.o trees.o bits.o unzip.o inflate.o util.o \
       crypt.o lzw.o unlzw.o unpack.o getopt.o

.c.o:
	$(CC) -c $(DEFS) $(CFLAGS) $<

gzip: $(OBJS)
	$(CC) $(LDFLAGS) -o gzip $(OBJS)

check: gzip
	./gzip -c COPYING > _gz.z
	./gzip -dc _gz.z > _gz
	cmp _gz COPYING
	rm -f _gz _gz.z

clean:
	rm -f $(OBJS) gzip _gz _gz.z
