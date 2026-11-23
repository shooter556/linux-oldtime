# Linux 0.95 root diskette programs, built on Linux 0.12 with gcc 2.0 + libc-0.12.
# Installed by mkbootroot.sh as /usr/src/0.95/Makefile.  Usage: make  (or make -n)

CC = gcc
# include/string.h = the 0.95 kernel one: include-0.12's strtok asm fails with gcc 2.0 -O
# -Dlinux: gcc 2.0 configured as i386-gas-sysv does not predefine it (gcc 1.40 did); poeigl needs it
CFLAGS = -O -Dlinux -I/usr/src/0.95/include
# login.c: gcc 2.0 cc1 -O dies with signal 11 on it, so it is compiled without -O
CFLAGS_NOOPT = -Dlinux -I/usr/src/0.95/include
# lib/libc.a = libc-0.12; -L puts it before the system (1991 gccbin) libc
LDFLAGS = -L/usr/src/0.95/lib -Xlinker -s
B = /usr/src/0.95/bison

PROGS = poe-IGL/init poe-IGL/agetty poe-IGL/login \
	system/mkfs system/mkswap system/mknod fdisk df mount umount swapon sync update

all: $(PROGS) fileutils gzip

poe-IGL/init: poe-IGL/simpleinit.c
	cd poe-IGL; $(CC) $(CFLAGS) -I. $(LDFLAGS) -o init simpleinit.c

poe-IGL/agetty: poe-IGL/agetty.c poe-IGL/utmp2.c
	cd poe-IGL; $(CC) $(CFLAGS) -I. $(LDFLAGS) -o agetty agetty.c utmp2.c

poe-IGL/ufc/crypt_util.o: poe-IGL/ufc/crypt_util.c
	cd poe-IGL/ufc; $(CC) $(CFLAGS) -DSYSV -DUSG -c crypt_util.c

poe-IGL/ufc/crypt.o: poe-IGL/ufc/crypt.c
	cd poe-IGL/ufc; $(CC) $(CFLAGS) -DSYSV -DUSG -c crypt.c

poe-IGL/login.o: poe-IGL/login.c
	cd poe-IGL; $(CC) $(CFLAGS_NOOPT) -I. -c login.c

poe-IGL/login: poe-IGL/login.o poe-IGL/utmp2.c poe-IGL/putenv.c poe-IGL/setenv.c \
		poe-IGL/ufc/crypt_util.o poe-IGL/ufc/crypt.o
	cd poe-IGL; $(CC) $(CFLAGS) -I. $(LDFLAGS) -o login login.o utmp2.c putenv.c setenv.c \
		ufc/crypt_util.o ufc/crypt.o

system/mkfs: system/mkfs.c
	cd system; $(CC) $(CFLAGS) $(LDFLAGS) -o mkfs mkfs.c

system/mkswap: system/mkswap.c
	cd system; $(CC) $(CFLAGS) $(LDFLAGS) -o mkswap mkswap.c

system/mknod: system/mknod.c
	cd system; $(CC) $(CFLAGS) $(LDFLAGS) -o mknod mknod.c

fdisk: fdisk.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o fdisk fdisk.c

df: df.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o df df.c

mount: mount.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o mount mount.c

umount: umount.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o umount umount.c

swapon: swapsrc/cmd_swapon.c swapsrc/lib_swapon.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o swapon swapsrc/cmd_swapon.c swapsrc/lib_swapon.c

sync: sync.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o sync sync.c

update: update.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o update update.c

fileutils:
	cd fileutils-3.1; BISON_SIMPLE=$(B)/bison.simple BISON_HAIRY=$(B)/bison.hairy \
		$(MAKE) -f Makefile.l095 BISON=$(B)/bison

# not for the root diskette: gccpkg puts it on tools.flp
gzip:
	cd gzip-1.2.3; $(MAKE) -f Makefile.l095
