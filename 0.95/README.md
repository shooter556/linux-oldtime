# Linux 0.95 — build US-keyboard boot and root diskettes on 0.12, install to the hard disk

[中文](#中文) | [English](#english)

---

## 中文

oldlinux-files 里的 `bootimage-0.95` 是芬兰键盘，原版 `rootimage-0.95` 也没有留下来。这里在装好的 Linux 0.12（带 gcc 2.0，见 [../0.12](../0.12/)）里，从源码重新做一套 0.95 的 boot + root 软盘：内核用原版 0.95 源码，只改成美式键盘、从软盘取根；root 盘的内容以 `RELNOTES-0.95` 为基础，另外加了 vi、df、dd、tar、compress 和能建分区的 fdisk，程序尽量从源码编译。主机只负责收集源码、做一张软盘，编译和写盘都在虚拟机里完成。之后用这套软盘把 0.95 装到硬盘，连同 gcc 2.0 编译环境，用 ShoeLace 从硬盘启动。

在 86Box 上验证：0.12 虚拟机里编译、写盘通过；新开的 0.95 虚拟机用这两张盘启动到 `login:` 提示，装到硬盘后经 WiniBoot、ShoeLace 从硬盘启动。硬盘安装中途有几处是手工修正后再并入脚本的（见“遇到的坑”），并入后的脚本没有从头重跑一遍。

### 文件

| 文件 | 说明 |
|---|---|
| `mkbootroot.sh` | 主机端：生成源码盘 `br095.flp` |
| `brinst.sh.in` | 源码盘里的 guest 脚本模板（bash 1.12） |
| `tools.mk` | 在 guest 里成为 `/usr/src/0.95/Makefile`，编 root 盘上的程序和 gzip |
| `gzip.mk` | 在 guest 里成为 `/usr/src/0.95/gzip-1.1.1/Makefile.l095`，代替 configure |
| `inst.sh.in` | 0.95 硬盘安装脚本模板，由 `gccpkg` 写到 gcc.flp 开头 |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）。

### 源码盘

`br095.flp` 是 raw 盘（没有文件系统）：开头 6 块是 guest 脚本，后面是一个 compress 过的 v7 tar 包（约 1243 块），按最终路径摆好：

- `/usr/src/linux`：原版 `linux-0.95.tar`，只改两处，都保留原时间戳：
  - `Makefile`：`ROOT_DEV=/dev/hdb1` 改成 `ROOT_DEV=FLOPPY`（原版 bootimage-0.95 偏移 508 也是 `00 00`）
  - `kernel/chr_drv/keyboard.S`：`KBD_FINNISH` 改成 `KBD_US`
- `/usr/src/0.95`：root 盘程序的源码、`Makefile`（即 `tools.mk`），以及 `etc/` 下 root 盘用的 inittab、rc、passwd、group、issue、securetty；硬盘安装用的 `inst.sh.in` 和 `shoe/`（`bin-src/shoelace.tar.Z` 里 1992-01-17 的 Linux 版 ShoeLace 二进制，加一个只有 `boot /Image` 的 config）；`gzip-1.1.1/`（仓库里的 `gzip-1.1.1`：FreeBSD 1993-06-18 导入的 gzip，提交 222b83e890，标题写 1.1、实为 1.1.1，第一个默认 `.gz` 的版本；去掉了 BSD Makefile，加 `Makefile.l095`），build 时编好放进 tools.flp（1993 年的 gzip 二进制都要共享库，0.95 用不了）

root 盘上的程序和来源：

| 程序 | 来源 |
|---|---|
| sh | 0.12 硬盘上的 `/bin/sh`（bash 1.12，1992-03-01 二进制；本地没有 1.12 源码） |
| cat | 0.12 硬盘上的 `/usr/bin/cat` |
| init、agetty、login | `Linux-0.12/sources/sbin/poeigl-1.2.tar.Z`，原样 |
| mkfs、mkswap、mknod | `Linux-0.12/sources/sbin/system-0.12.tar.Z`（Linus） |
| fdisk | `Linux-0.95/sources/sbin/fdisk-0.91.tar.Z`（Owen LeBlanc，能建分区；0.95 自带的 `fdisk.c` 只能列分区） |
| df | `Linux-0.12/sources/usr.bin/df.c`（Peter MacDonald） |
| mount、umount | `Linux-0.12/sources/sbin/mount.c.Z`、`umount.c.Z` |
| swapon | `Linux-0.12/sources/sbin/swapon.tar.Z` |
| sync | 手写的 `main() { sync(); }` |
| /etc/update | `bin-src/system-0.98.tar.Z` 的 `update.c`（没有更早的源码） |
| ls cp mv rm ln mkdir rmdir chmod chown chgrp touch dd | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`，bison 1.14 二进制处理 `.y` |
| vi | `Linux-0.12/binaries/usr.bin/vi.Z`（elvis 1.4 二进制） |
| tar、compress | `images/rootimage-0.11-20040305` 里的二进制（本地 tar-1.10 源码包是截断的，1.11.1 又太晚） |

RELNOTES 原版 root 盘上没有 vi、df、dd、tar、compress，这里为了装硬盘加上了。三个二进制在主机上去掉了符号表。

### 使用

```
./mkbootroot.sh -s /path/to/oldlinux-files -o br095.flp
```

另外准备两张空白 1.44M 盘：`boot.flp`、`root.flp`。

guest 里（已装好的 0.12 + gcc 2.0，B = br095.flp）：

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=6
sh /tmp/br unpack --apply     # 解到 /usr/src/linux 和 /usr/src/0.95（已存在则拒绝）
sh /tmp/br build --apply      # make root 盘程序，再 make 0.95 内核
                              # B 换成 boot.flp
sh /tmp/br boot --apply       # dd Image 到 B
                              # B 换成 root.flp
sh /tmp/br root --apply       # mkfs 1440、拷程序和 /etc、mknod /dev、umount
```

每个子命令都可以先用 `--dry-run` 只打印命令。`/usr/src/linux` 如果已有 0.12 的源码，先挪走。

启动：A 放 boot.flp，提示 `Insert root floppy and press ENTER` 时换成 root.flp。看到 ` Ok. ` 和 `login:`，用 `root` 登录，没有密码。新硬盘还没分区时会提示 `Bad partition table on dev 0300`，不影响启动。vi 如果显示不对，用 `TERM=con80x25 vi`。

root 盘的 `/dev`（0.95 新编号）：`PS0 PS1 at0 at1`、`hda hda1–8`（3,0–8）、`hdb hdb1–8`（3,64–72）、`ram mem kmem null port`、`tty tty0 console tty1–8 ttys1–4`。0.95 时的软驱名就是这样：PS0/PS1 是 1.44M 的 A:/B:，at0/at1 是 1.2M（INSTALL-0.95a）。

### 装到硬盘

硬盘按 0.95 虚拟机的设置：128 柱面、16 磁头、63 扇区。gcc 2.0 要 387，0.95 虚拟机要打开 FPU。

一套东西压缩后约 1.7M，分两张盘：

- `gcc.flp`：开头 8 块是安装脚本（`inst.sh.in` 填上块数），后面是一个 compress 过的 tar：0.12 硬盘上的 gcc 2.0（`/usr/local`）、gccbin 的 as/ld 等、libc-0.12（作 `/usr/local/lib/libc.a`）、`/usr/include`（换上 0.95 内核的 `string.h`）、`/usr/bin/make`，以及 ShoeLace 和偏移 508 改成 `02 03` 的 `/Image`
- `tools.flp`：0.12 硬盘 `/usr/bin` 里 root 盘没有的工具：grep egrep sed head tail cmp cut paste du split tac expand unexpand basename file stty uniq mkfifo dir vdir em kermit as86 ld86 等，加上 build 时编的 gzip 1.1.1

0.12 里（B = br095.flp，源码已 unpack、build）：

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=6
sh /tmp/br gccpkg --apply     # 提示时 B 换成空白的 gcc.flp，再换成 tools.flp
```

0.95 里（boot + root 软盘启动，B = gcc.flp）：

```
dd if=/dev/PS1 of=/tmp/inst bs=1024 count=8
sh /tmp/inst part --apply 128 16 63   # 柱面 磁头 扇区；hda1 swap 16 柱面，hda2 其余；之后等 30 秒重启
dd if=/dev/PS1 of=/tmp/inst bs=1024 count=8
sh /tmp/inst install --apply          # 中途提示时 B 换成 tools.flp
```

`part` 用 fdisk 0.91 写分区表，已经是这样分的就跳过。`install` 做 mkswap、swapon、mkfs，把 root 盘的 `bin dev etc usr` 拷过去，解开两张盘，建 gunzip、zcat 到 `/usr/bin/gzip` 的硬链接，在 `/usr/local/bin` 建 as、ld、cpp 等的硬链接，写 `/etc/profile`（PATH 加 `/usr/local/bin`）、在 `/etc/rc` 开头加 `swapon /dev/hda1`，最后 `laceup /dev/hda2 wini`（bootlace 写进 hda2 的引导块）、`laceup -w 2 /dev/hda`（WiniBoot 写进 MBR，保留分区表，默认第 2 分区）。

完成后等 30 秒、关机、取出软盘再开机：

- WiniBoot 显示分区表和 `Boot:`，按 `1`–`4` 立刻启动对应分区（不用回车），约 15 秒不按就启动默认分区；按别的键会取消倒计时。
- ShoeLace 读 `/etc/config`，载入 `/Image`。它会提示 `/dev/fd0 not found`（找内存盘设备的默认名，0.95 没有 fd0）和 `kernel : kernel not found`（先按 Minix 的部件方式找），都不影响启动。

ShoeLace 的几点用法：

- 换内核：新 Image 偏移 508 也要写成 `02 03`，这个版本的 ShoeLace 不设根设备（那段代码被注释掉了），用的是 Image 里的值：`(dd if=Image bs=508 count=1; echo -n -e '\002\003'; dd if=Image bs=510 skip=1) > /Image`
- 改了 `/etc/config` 不用重装。`laceup -w N /dev/hda` 改默认分区；千万别对 `/dev/hda` 跑不带 `-w` 的 laceup，会覆盖分区表。
- WiniBoot 的超时写死在代码里：MBR 偏移 132–133 是 tick 数（小端，原值 `0e 01` = 270，每秒 18.2），比如改成 5 秒：`echo -n -e '\133\000' | dd of=/dev/hda bs=1 seek=132 count=2`。重跑 `laceup -w` 会恢复原值。0 表示不超时。
- ShoeLace 默认按 0.95 的 4 个 setup 扇区摆放 Image（它在 0x90C00 处把后面的数据挪到 0x10000），setup 大小不同的内核要注意。

### 遇到的坑

0.12 硬盘上的编译环境和想象的不一样，这几个问题都是在 guest 里编的时候才出现的：

- gcc 2.0 是按 `i386-gas-sysv` 配置的，不预定义 `linux`（gcc 1.40 会）。poeigl 靠 `#ifdef linux` 选分支，否则报 `_PATH_LOGIN`、`VSWTCH` 未声明。`tools.mk` 加了 `-Dlinux`。
- 0.12 硬盘上的 libc.a 是 gccbin.tar.Z 里 1991 年的那份，没有 `gethostname`、`lstat`、`symlink`、`readlink`、`getgroups`、`sigaction`、`ttyname` 等；头文件（include-0.11.tar.Z，解出来目录叫 include-0.12）却是新的。包里带了 `libs/libc/libc-0.1x/libc-0.12.a.Z`，放在 `/usr/src/0.95/lib/libc.a`，用 `-L/usr/src/0.95/lib` 链接（gcc 2.0 的链接命令里 `-L` 在默认 `-lc` 之前）。这些程序只在 0.95 上跑，用 libc-0.12 正合适。系统的 libc 和头文件都没动。
- include-0.12 的 `string.h` 全是 `extern inline` 内嵌汇编，gcc 2.0 在 `-O` 下会编这些函数体，`strtok` 的 `"=b"` 约束报 `inconsistent operand constraints in an 'asm'`。改用 0.95 内核的 `include/string.h`（Linus 已经为 gcc 2 改过），放在 `/usr/src/0.95/include`。
- 同样的问题出在 `unistd.h` 的 `_syscall1`（`"b"` 输入）。`lib_swapon.c` 按 0.95 内核 `unistd.h` 的写法展开（`movl` 到 ebx、`"g"` 输入、声明 bx 被改）。include-0.12 也没有 `__NR_swapon`，补 `87`。
- gcc 2.0 的 cc1 用 `-O` 编 poeigl 的 `login.c` 会崩（signal 11，0.12 内核打印 `nonexistent page error in do_no_page`），去掉 `-O` 就能过，所以 `login.c` 单独不优化。
- gcc 2.0 驱动的链接 spec 里没有 `%{s}`，`-s` 只报 `unrecognized option` 警告，不会 strip。用 `-Xlinker -s`。
- `conflicting types for built-in function`（strlen、memcpy、memcmp）警告可以忽略，原因同 0.12 里编 0.95 内核。
- 源码目录不能和 make 目标同名：最初 swapon 源码放在 `swapon/`，make 把这个目录当成已有的目标，跳过了编译。现在叫 `swapsrc/`。
- poeigl-1.2 要的头文件比 include-0.12 新：补 `memory.h`（只 include `string.h`）、0.95 内核的 `sys/param.h`（`MAXHOSTNAMELEN`）和 `sys/resource.h`；`login.c` 的 `MAXPATHLEN` 按 poe 自己 1992-03-02 的补丁定义成 `_POSIX_PATH_MAX`。crt0.o 定义了 `environ`。
- 0.95 的 `sys_write` 会检查文件打开方式：mount、umount 的锁文件原来只用 `O_CREAT | O_EXCL` 打开，写不进 `/etc/mtab`，补上 `O_WRONLY`。
- fileutils 3.1：include-0.12 的 `NGROUPS_MAX` 是 0，`eaccess.c` 里 `#undef`；Minix 没有 `st_blocks`，`fileblocks.c` 按 Minix v1（7 个直接块、1 个一次间接、1 个二次间接）计算；`posixtm.y` 的 bison 输出把 `yy*` 改名成 `zz*`，才能和 `getdate` 链接在一起。用生成的 `Makefile.l095` 代替 configure，只编 root 盘要的 12 个程序。
- fdisk 0.91 要用 Owen 内核补丁（ioctl.patch）里的 `HDIO_REQ` 和 `struct hd_geometry`，在 `fdisk.c` 里补上定义。原版 0.95 内核没有 `hd_ioctl`，所以 fdisk 显示 `0 heads, 0 sectors, 0 cylinders`，要在 `x` 菜单用 `h`、`s`、`c` 手动设置。
- fdisk 的提示要等输入以后才显示：libc-0.12 读 stdin 前不刷新 stdout。`read_char` 里改成 `fputs(mesg, stdout), fflush(stdout);`。
- `Linux-0.12/sources/sbin/df.c` 是 CRLF 换行，gcc 2.0 报 `parse error before character 015`；`usr.bin/df.c` 是同一份源码，用它。
- fdisk 0.91 的源码日期是 1992-04-01，比 0.95 晚，和 `update.c` 一样改成 1992-03-08。
- 包里所有文件的时间都在 1992-03-08 或更早，guest 的时钟要比这个晚，否则 make 每次都会全部重编。
- 包解开时要 `cd /`：包里的路径以 `usr/src` 开头。
- Minix 文件名最多 14 个字符，`mkbootroot.sh` 会检查。
- 0.12 没有 rename 系统调用，mv 不能移动目录：要替换包里的某个目录，从源码盘单独解出来，再 `rm -rf` 旧的。

硬盘安装时：

- root 盘上没有 grep、sed，安装脚本只用 bash 自己的 `while read`、`case` 解析 fdisk 输出。
- root 盘的 ln（fileutils 3.1 配 libc-0.12）不支持符号链接，自动改成硬链接，所以 `/usr/local/bin` 下的 as、ld、cpp 等都是在 `/mnt` 里建的硬链接。
- 安装脚本超过 4K，`dd count=4` 读到的是截断的脚本，bash 报 `Unexpected EOF`。现在留 8 块，`gccpkg` 会检查大小。
- fdisk 0.91 写出的第 1 分区起始 CHS 不对（显示磁头 f、扇区 4），起始扇区和大小是对的，Linux 和 WiniBoot（只启动第 2 分区）都不受影响。它对 hda2 提示 `Linux cannot currently use 47361 sectors`，是拿扇区数和 65535 比，实际 56448 块没超 64M 的限制。
- 主机上用 ncompress 压的 ShoeLace 包，0.95 上的 compress（和 0.12 硬盘上的是同一个二进制）解到一半就退出，原因没查清；同样由主机压缩的源码包在 0.12 上解压没问题。现在 ShoeLace 放在 gcc.flp 里，由 0.12 上的 compress 压缩。
- 0.11 的 compress 用 `-d` 解文件时总会在文件名后加 `.Z`（`shoe.tar.Z` 变成找 `shoe.tar.ZZ`），只用管道方式。

---

## English

The `bootimage-0.95` in oldlinux-files has a Finnish keyboard, and the original `rootimage-0.95` did not survive. This rebuilds a 0.95 boot + root diskette pair from source inside an installed Linux 0.12 with gcc 2.0 (see [../0.12](../0.12/)). The kernel is the stock 0.95 source changed only to a US keyboard and a floppy root; the root diskette is based on `RELNOTES-0.95`, plus vi, df, dd, tar, compress and an fdisk that can create partitions, with programs built from source wherever possible. The host only collects sources and writes one floppy; compiling and writing the diskettes happen inside the VM. The diskettes then install 0.95 to the hard disk, with the gcc 2.0 development environment, booting from the hard disk with ShoeLace.

Tested on 86Box: the build and both diskettes are made in the 0.12 VM, a fresh 0.95 VM boots from them to the `login:` prompt, and after the install it boots from the hard disk via WiniBoot and ShoeLace. A few hard disk install steps were fixed by hand on the way and then folded into the scripts (see Pitfalls); the final scripts have not been rerun from scratch.

### Files

| File | Purpose |
|---|---|
| `mkbootroot.sh` | host: builds the source floppy `br095.flp` |
| `brinst.sh.in` | guest script template stored on the source floppy (bash 1.12) |
| `tools.mk` | becomes `/usr/src/0.95/Makefile` in the guest; builds the root diskette programs and gzip |
| `gzip.mk` | becomes `/usr/src/0.95/gzip-1.1.1/Makefile.l095` in the guest, instead of configure |
| `inst.sh.in` | 0.95 hard disk installer template, written to the start of gcc.flp by `gccpkg` |

Host needs: bash, python3, gzip, tar, `compress` (ncompress package).

### Source floppy

`br095.flp` is a raw floppy (no filesystem): the guest script in the first 6 blocks, then a compressed v7 tar (about 1243 blocks) laid out at final paths:

- `/usr/src/linux`: stock `linux-0.95.tar` with two changes, both keeping their timestamps:
  - `Makefile`: `ROOT_DEV=/dev/hdb1` becomes `ROOT_DEV=FLOPPY` (the original bootimage-0.95 also has `00 00` at offset 508)
  - `kernel/chr_drv/keyboard.S`: `KBD_FINNISH` becomes `KBD_US`
- `/usr/src/0.95`: sources of the root diskette programs, a `Makefile` (`tools.mk`), and in `etc/` the inittab, rc, passwd, group, issue and securetty for the root diskette; for the hard disk install, `inst.sh.in` and `shoe/` (the 1992-01-17 Linux build of ShoeLace from `bin-src/shoelace.tar.Z`, plus a config holding only `boot /Image`); `gzip-1.1.1/` (the repo's `gzip-1.1.1`: FreeBSD's import of 1993-06-18, commit 222b83e890, titled 1.1 but really 1.1.1, the first version with `.gz` by default; its BSD Makefile dropped, `Makefile.l095` added), built by build and put on tools.flp (the 1993 gzip binaries all need shared libraries, which 0.95 lacks)

Root diskette programs and their sources:

| Program | Source |
|---|---|
| sh | `/bin/sh` of the 0.12 hard disk (bash 1.12, 1992-03-01 binary; no 1.12 source available) |
| cat | `/usr/bin/cat` of the 0.12 hard disk |
| init, agetty, login | `Linux-0.12/sources/sbin/poeigl-1.2.tar.Z`, unpatched |
| mkfs, mkswap, mknod | `Linux-0.12/sources/sbin/system-0.12.tar.Z` (Linus) |
| fdisk | `Linux-0.95/sources/sbin/fdisk-0.91.tar.Z` (Owen LeBlanc, creates partitions; the `fdisk.c` shipped with 0.95 only lists them) |
| df | `Linux-0.12/sources/usr.bin/df.c` (Peter MacDonald) |
| mount, umount | `Linux-0.12/sources/sbin/mount.c.Z`, `umount.c.Z` |
| swapon | `Linux-0.12/sources/sbin/swapon.tar.Z` |
| sync | a hand-written `main() { sync(); }` |
| /etc/update | `update.c` from `bin-src/system-0.98.tar.Z` (no older source exists) |
| ls cp mv rm ln mkdir rmdir chmod chown chgrp touch dd | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`, `.y` files via the bison 1.14 binary |
| vi | `Linux-0.12/binaries/usr.bin/vi.Z` (elvis 1.4 binary) |
| tar, compress | binaries from `images/rootimage-0.11-20040305` (the local tar-1.10 source archive is truncated, and 1.11.1 is too late) |

The original RELNOTES root diskette had no vi, df, dd, tar or compress; they are added here for the hard disk install. The three binaries have their symbol tables stripped on the host.

### Usage

```
./mkbootroot.sh -s /path/to/oldlinux-files -o br095.flp
```

Also prepare two blank 1.44M images: `boot.flp` and `root.flp`.

In the guest (installed 0.12 + gcc 2.0, B = br095.flp):

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=6
sh /tmp/br unpack --apply     # unpack into /usr/src/linux and /usr/src/0.95 (refuses if they exist)
sh /tmp/br build --apply      # make the root diskette programs, then the 0.95 kernel
                              # B = boot.flp
sh /tmp/br boot --apply       # dd Image to B
                              # B = root.flp
sh /tmp/br root --apply       # mkfs 1440, copy programs and /etc, mknod /dev, umount
```

Every subcommand takes `--dry-run` to print the commands only. If `/usr/src/linux` already holds the 0.12 source, move it away first.

Booting: boot.flp in A; at `Insert root floppy and press ENTER` swap in root.flp. You get ` Ok. ` and `login:`; log in as `root` with no password. A blank, unpartitioned hard disk gives `Bad partition table on dev 0300`, which does not stop the boot. If vi looks wrong, run `TERM=con80x25 vi`.

Root diskette `/dev` (0.95 numbering): `PS0 PS1 at0 at1`, `hda hda1–8` (3,0–8), `hdb hdb1–8` (3,64–72), `ram mem kmem null port`, `tty tty0 console tty1–8 ttys1–4`. These are the floppy names of the 0.95 days: PS0/PS1 are 1.44M A:/B:, at0/at1 are 1.2M (INSTALL-0.95a).

### Installing to the hard disk

The disk follows the 0.95 VM: 128 cylinders, 16 heads, 63 sectors. gcc 2.0 needs a 387, so enable the FPU in the 0.95 VM.

Compressed, everything is about 1.7M, so it takes two floppies:

- `gcc.flp`: the installer in the first 8 blocks (`inst.sh.in` with the block counts filled in), then a compressed tar: gcc 2.0 from the 0.12 hard disk (`/usr/local`), gccbin's as/ld and friends, libc-0.12 (as `/usr/local/lib/libc.a`), `/usr/include` (with the 0.95 kernel's `string.h`), `/usr/bin/make`, plus ShoeLace and `/Image` with `02 03` at offset 508
- `tools.flp`: tools from the 0.12 `/usr/bin` that the root diskette lacks: grep egrep sed head tail cmp cut paste du split tac expand unexpand basename file stty uniq mkfifo dir vdir em kermit as86 ld86 and so on, plus gzip 1.1.1 built by build

On 0.12 (B = br095.flp, sources unpacked and built):

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=6
sh /tmp/br gccpkg --apply     # when asked, B = blank gcc.flp, then tools.flp
```

On 0.95 (booted from the boot + root diskettes, B = gcc.flp):

```
dd if=/dev/PS1 of=/tmp/inst bs=1024 count=8
sh /tmp/inst part --apply 128 16 63   # cylinders heads sectors; hda1 swap 16 cyl, hda2 the rest; wait 30s, reboot
dd if=/dev/PS1 of=/tmp/inst bs=1024 count=8
sh /tmp/inst install --apply          # B = tools.flp when asked
```

`part` writes the partition table with fdisk 0.91 and skips if it is already laid out that way. `install` runs mkswap, swapon and mkfs, copies `bin dev etc usr` of the root diskette, unpacks both floppies, hard-links gunzip and zcat to `/usr/bin/gzip`, makes hard links for as, ld, cpp and friends in `/usr/local/bin`, writes `/etc/profile` (PATH with `/usr/local/bin`), puts `swapon /dev/hda1` at the top of `/etc/rc`, and finally runs `laceup /dev/hda2 wini` (bootlace into hda2's boot block) and `laceup -w 2 /dev/hda` (WiniBoot into the MBR, keeping the partition table, default partition 2).

Then wait 30 seconds, power off, remove the floppies and boot:

- WiniBoot shows the partition table and `Boot:`. `1`–`4` boots that partition at once (no Enter); after about 15 seconds it boots the default partition; any other key cancels the countdown.
- ShoeLace reads `/etc/config` and loads `/Image`. It says `/dev/fd0 not found` (the default RAM image device name; 0.95 has no fd0) and `kernel : kernel not found` (it first tries Minix components); neither stops the boot.

Using ShoeLace:

- New kernel: put `02 03` at offset 508 of the new Image as well. This ShoeLace build does not set the root device (that code is commented out) and uses the Image's own value: `(dd if=Image bs=508 count=1; echo -n -e '\002\003'; dd if=Image bs=510 skip=1) > /Image`
- Changing `/etc/config` needs no reinstall. `laceup -w N /dev/hda` changes the default partition; never run laceup on `/dev/hda` without `-w`, it overwrites the partition table.
- The WiniBoot timeout is hard-coded: MBR offset 132–133 holds the tick count (little endian, originally `0e 01` = 270, 18.2 per second). For 5 seconds: `echo -n -e '\133\000' | dd of=/dev/hda bs=1 seek=132 count=2`. Rerunning `laceup -w` restores it. 0 means no timeout.
- ShoeLace lays the Image out for 0.95's 4 setup sectors (at 0x90C00 it moves the rest to 0x10000); mind this with kernels of a different setup size.

### Pitfalls

The build environment on the 0.12 hard disk was not what it looked like; all of these showed up only when building in the guest:

- gcc 2.0 is configured as `i386-gas-sysv` and does not predefine `linux` (gcc 1.40 did). poeigl picks its branches with `#ifdef linux`, otherwise `_PATH_LOGIN` and `VSWTCH` are undeclared. `tools.mk` adds `-Dlinux`.
- The libc.a on the 0.12 hard disk is the 1991 one from gccbin.tar.Z, without `gethostname`, `lstat`, `symlink`, `readlink`, `getgroups`, `sigaction`, `ttyname` and more, while the headers (include-0.11.tar.Z, which unpacks as include-0.12) are newer. The package carries `libs/libc/libc-0.1x/libc-0.12.a.Z` as `/usr/src/0.95/lib/libc.a`, linked via `-L/usr/src/0.95/lib` (gcc 2.0's link command puts `-L` before the default `-lc`). The programs only run on 0.95, so libc-0.12 is the right library. The system libc and headers are untouched.
- include-0.12's `string.h` is all `extern inline` asm; gcc 2.0 compiles those bodies at `-O`, and `strtok`'s `"=b"` constraint fails with `inconsistent operand constraints in an 'asm'`. The 0.95 kernel's `include/string.h` (already fixed by Linus for gcc 2) is used instead, from `/usr/src/0.95/include`.
- The same problem hits `_syscall1` in `unistd.h` (a `"b"` input). `lib_swapon.c` expands it the way the 0.95 kernel `unistd.h` does (`movl` to ebx, `"g"` input, bx clobbered). include-0.12 also lacks `__NR_swapon`; it is defined as `87`.
- gcc 2.0's cc1 crashes on poeigl's `login.c` at `-O` (signal 11; the 0.12 kernel prints `nonexistent page error in do_no_page`) and is fine without `-O`, so `login.c` alone is built unoptimized.
- The gcc 2.0 driver's link spec has no `%{s}`: `-s` only gives an `unrecognized option` warning and nothing is stripped. Use `-Xlinker -s`.
- `conflicting types for built-in function` warnings (strlen, memcpy, memcmp) are harmless, for the same reason as when building the 0.95 kernel on 0.12.
- A source directory must not share its name with a make target: the swapon sources first lived in `swapon/`, make took the directory for an existing target and skipped the build. It is now `swapsrc/`.
- poeigl-1.2 wants newer headers than include-0.12: a `memory.h` (just includes `string.h`), the 0.95 kernel's `sys/param.h` (`MAXHOSTNAMELEN`) and `sys/resource.h`; `MAXPATHLEN` in `login.c` is `_POSIX_PATH_MAX`, as in poe's own patch of 1992-03-02. crt0.o defines `environ`.
- 0.95's `sys_write` checks the open mode: mount and umount opened their lock file with only `O_CREAT | O_EXCL` and could not write `/etc/mtab`; `O_WRONLY` is added.
- fileutils 3.1: `NGROUPS_MAX` is 0 in include-0.12, so `eaccess.c` `#undef`s it; Minix has no `st_blocks`, so `fileblocks.c` computes it for Minix v1 (7 direct, 1 indirect, 1 double indirect); the bison output of `posixtm.y` has its `yy*` names renamed to `zz*` so it links together with `getdate`. A generated `Makefile.l095` replaces configure and builds only the 12 root diskette programs.
- fdisk 0.91 wants `HDIO_REQ` and `struct hd_geometry` from Owen's kernel ioctl.patch; they are defined in `fdisk.c`. The stock 0.95 kernel has no `hd_ioctl`, so fdisk shows `0 heads, 0 sectors, 0 cylinders`; set them by hand with `h`, `s`, `c` in the `x` menu.
- fdisk prompts appeared only after the answer: libc-0.12 does not flush stdout before reading stdin. `read_char` now does `fputs(mesg, stdout), fflush(stdout);`.
- `Linux-0.12/sources/sbin/df.c` has CRLF line ends and gcc 2.0 says `parse error before character 015`; `usr.bin/df.c` is the same source and is used instead.
- fdisk 0.91 is dated 1992-04-01, after 0.95; like `update.c` it is redated 1992-03-08.
- Every file in the package is dated 1992-03-08 or earlier; the guest clock must be later, or make rebuilds everything each run.
- Unpack with `cd /`: package paths start with `usr/src`.
- Minix file names are at most 14 characters; `mkbootroot.sh` checks this.
- 0.12 has no rename syscall, so mv cannot move directories: to replace a directory from the package, extract it alone from the source floppy, then `rm -rf` the old one.

During the hard disk install:

- The root diskette has no grep or sed; the installer parses fdisk output with bash's own `while read` and `case`.
- The root diskette's ln (fileutils 3.1 with libc-0.12) has no symlink support and falls back to hard links, so as, ld, cpp and friends in `/usr/local/bin` are hard links made inside `/mnt`.
- The installer grew past 4K; `dd count=4` read a truncated script and bash said `Unexpected EOF`. It now gets 8 blocks and `gccpkg` checks the size.
- fdisk 0.91 wrote a wrong start CHS for partition 1 (head f, sector 4); its start sector and size are right, so neither Linux nor WiniBoot (which boots partition 2) cares. Its `Linux cannot currently use 47361 sectors` for hda2 compares sectors with 65535; the 56448 blocks are within the 64M limit.
- A ShoeLace package compressed by ncompress on the host made the 0.95 compress (the same binary as on the 0.12 hard disk) stop halfway; the cause is unknown, while the host-compressed source package unpacks fine on 0.12. ShoeLace now goes on gcc.flp, compressed by compress on 0.12.
- The 0.11 compress always appends `.Z` to file names with `-d` (`shoe.tar.Z` makes it look for `shoe.tar.ZZ`); use it in pipes only.
