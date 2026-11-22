# Linux 0.95 — build US-keyboard boot and root diskettes on 0.12

[中文](#中文) | [English](#english)

---

## 中文

oldlinux-files 里的 `bootimage-0.95` 是芬兰键盘，原版 `rootimage-0.95` 也没有留下来。这里在装好的 Linux 0.12（带 gcc 2.0，见 [../0.12](../0.12/)）里，从源码重新做一套 0.95 的 boot + root 软盘：内核用原版 0.95 源码，只改成美式键盘、从软盘取根；root 盘的内容按 `RELNOTES-0.95` 还原，程序尽量从源码编译。主机只负责收集源码、做一张软盘，编译和写盘都在虚拟机里完成。

在 86Box 上验证：0.12 虚拟机里编译、写盘通过；新开的 0.95 虚拟机用这两张盘启动到 `login:` 提示。

### 文件

| 文件 | 说明 |
|---|---|
| `mkbootroot.sh` | 主机端：生成源码盘 `br095.flp` |
| `brinst.sh.in` | 源码盘里的 guest 脚本模板（bash 1.12） |
| `tools.mk` | 在 guest 里成为 `/usr/src/0.95/Makefile`，编 root 盘上的程序 |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）。

### 源码盘

`br095.flp` 是 raw 盘（没有文件系统）：开头 4 块是 guest 脚本，后面是一个 compress 过的 v7 tar 包（约 660 块），按最终路径摆好：

- `/usr/src/linux`：原版 `linux-0.95.tar`，只改两处，都保留原时间戳：
  - `Makefile`：`ROOT_DEV=/dev/hdb1` 改成 `ROOT_DEV=FLOPPY`（原版 bootimage-0.95 偏移 508 也是 `00 00`）
  - `kernel/chr_drv/keyboard.S`：`KBD_FINNISH` 改成 `KBD_US`
- `/usr/src/0.95`：root 盘程序的源码、`Makefile`（即 `tools.mk`），以及 `etc/` 下 root 盘用的 inittab、rc、passwd、group、issue、securetty

root 盘上的程序和来源：

| 程序 | 来源 |
|---|---|
| sh | 0.12 硬盘上的 `/bin/sh`（bash 1.12，1992-03-01 二进制；本地没有 1.12 源码） |
| cat | 0.12 硬盘上的 `/usr/bin/cat` |
| init、agetty、login | `Linux-0.12/sources/sbin/poeigl-1.2.tar.Z`，原样 |
| mkfs、mkswap、mknod | `Linux-0.12/sources/sbin/system-0.12.tar.Z`（Linus） |
| fdisk | `Linux-0.95/sources/sbin/fdisk.c`（只能列分区，用 hda 命名） |
| mount、umount | `Linux-0.12/sources/sbin/mount.c.Z`、`umount.c.Z` |
| swapon | `Linux-0.12/sources/sbin/swapon.tar.Z` |
| sync | 手写的 `main() { sync(); }` |
| /etc/update | `bin-src/system-0.98.tar.Z` 的 `update.c`（没有更早的源码） |
| ls cp mv rm ln mkdir rmdir chmod chown chgrp touch | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`，bison 1.14 二进制处理 `.y` |

按 RELNOTES，root 盘上不放 tar、compress、dd。

### 使用

```
./mkbootroot.sh -s /path/to/oldlinux-files -o br095.flp
```

另外准备两张空白 1.44M 盘：`boot.flp`、`root.flp`。

guest 里（已装好的 0.12 + gcc 2.0，B = br095.flp）：

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=4
sh /tmp/br unpack --apply     # 解到 /usr/src/linux 和 /usr/src/0.95（已存在则拒绝）
sh /tmp/br build --apply      # make root 盘程序，再 make 0.95 内核
                              # B 换成 boot.flp
sh /tmp/br boot --apply       # dd Image 到 B
                              # B 换成 root.flp
sh /tmp/br root --apply       # mkfs 1440、拷程序和 /etc、mknod /dev、umount
```

每个子命令都可以先用 `--dry-run` 只打印命令。`/usr/src/linux` 如果已有 0.12 的源码，先挪走。

启动：A 放 boot.flp，提示 `Insert root floppy and press ENTER` 时换成 root.flp。看到 ` Ok. ` 和 `login:`，用 `root` 登录，没有密码。新硬盘还没分区时会提示 `Bad partition table on dev 0300`，不影响启动。

root 盘的 `/dev`（0.95 新编号）：`PS0 PS1 at0 at1`、`hda hda1–8`（3,0–8）、`hdb hdb1–8`（3,64–72）、`ram mem kmem null port`、`tty tty0 console tty1–8 ttys1–4`。

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
- fileutils 3.1：include-0.12 的 `NGROUPS_MAX` 是 0，`eaccess.c` 里 `#undef`；Minix 没有 `st_blocks`，`fileblocks.c` 按 Minix v1（7 个直接块、1 个一次间接、1 个二次间接）计算；`posixtm.y` 的 bison 输出把 `yy*` 改名成 `zz*`，才能和 `getdate` 链接在一起。用生成的 `Makefile.l095` 代替 configure，只编 root 盘要的 11 个程序。
- 包里所有文件的时间都在 1992-03-08 或更早，guest 的时钟要比这个晚，否则 make 每次都会全部重编。
- 包解开时要 `cd /`：包里的路径以 `usr/src` 开头。
- Minix 文件名最多 14 个字符，`mkbootroot.sh` 会检查。
- 0.12 没有 rename 系统调用，mv 不能移动目录：要替换包里的某个目录，从源码盘单独解出来，再 `rm -rf` 旧的。

---

## English

The `bootimage-0.95` in oldlinux-files has a Finnish keyboard, and the original `rootimage-0.95` did not survive. This rebuilds a 0.95 boot + root diskette pair from source inside an installed Linux 0.12 with gcc 2.0 (see [../0.12](../0.12/)). The kernel is the stock 0.95 source changed only to a US keyboard and a floppy root; the root diskette follows `RELNOTES-0.95`, with programs built from source wherever possible. The host only collects sources and writes one floppy; compiling and writing the diskettes happen inside the VM.

Tested on 86Box: the build and both diskettes are made in the 0.12 VM, and a fresh 0.95 VM boots from them to the `login:` prompt.

### Files

| File | Purpose |
|---|---|
| `mkbootroot.sh` | host: builds the source floppy `br095.flp` |
| `brinst.sh.in` | guest script template stored on the source floppy (bash 1.12) |
| `tools.mk` | becomes `/usr/src/0.95/Makefile` in the guest; builds the root diskette programs |

Host needs: bash, python3, gzip, tar, `compress` (ncompress package).

### Source floppy

`br095.flp` is a raw floppy (no filesystem): the guest script in the first 4 blocks, then a compressed v7 tar (about 660 blocks) laid out at final paths:

- `/usr/src/linux`: stock `linux-0.95.tar` with two changes, both keeping their timestamps:
  - `Makefile`: `ROOT_DEV=/dev/hdb1` becomes `ROOT_DEV=FLOPPY` (the original bootimage-0.95 also has `00 00` at offset 508)
  - `kernel/chr_drv/keyboard.S`: `KBD_FINNISH` becomes `KBD_US`
- `/usr/src/0.95`: sources of the root diskette programs, a `Makefile` (`tools.mk`), and in `etc/` the inittab, rc, passwd, group, issue and securetty for the root diskette

Root diskette programs and their sources:

| Program | Source |
|---|---|
| sh | `/bin/sh` of the 0.12 hard disk (bash 1.12, 1992-03-01 binary; no 1.12 source available) |
| cat | `/usr/bin/cat` of the 0.12 hard disk |
| init, agetty, login | `Linux-0.12/sources/sbin/poeigl-1.2.tar.Z`, unpatched |
| mkfs, mkswap, mknod | `Linux-0.12/sources/sbin/system-0.12.tar.Z` (Linus) |
| fdisk | `Linux-0.95/sources/sbin/fdisk.c` (lists partitions only, hda names) |
| mount, umount | `Linux-0.12/sources/sbin/mount.c.Z`, `umount.c.Z` |
| swapon | `Linux-0.12/sources/sbin/swapon.tar.Z` |
| sync | a hand-written `main() { sync(); }` |
| /etc/update | `update.c` from `bin-src/system-0.98.tar.Z` (no older source exists) |
| ls cp mv rm ln mkdir rmdir chmod chown chgrp touch | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`, `.y` files via the bison 1.14 binary |

As in the RELNOTES, there is no tar, compress or dd on the root diskette.

### Usage

```
./mkbootroot.sh -s /path/to/oldlinux-files -o br095.flp
```

Also prepare two blank 1.44M images: `boot.flp` and `root.flp`.

In the guest (installed 0.12 + gcc 2.0, B = br095.flp):

```
dd if=/dev/fd1 of=/tmp/br bs=1024 count=4
sh /tmp/br unpack --apply     # unpack into /usr/src/linux and /usr/src/0.95 (refuses if they exist)
sh /tmp/br build --apply      # make the root diskette programs, then the 0.95 kernel
                              # B = boot.flp
sh /tmp/br boot --apply       # dd Image to B
                              # B = root.flp
sh /tmp/br root --apply       # mkfs 1440, copy programs and /etc, mknod /dev, umount
```

Every subcommand takes `--dry-run` to print the commands only. If `/usr/src/linux` already holds the 0.12 source, move it away first.

Booting: boot.flp in A; at `Insert root floppy and press ENTER` swap in root.flp. You get ` Ok. ` and `login:`; log in as `root` with no password. A blank, unpartitioned hard disk gives `Bad partition table on dev 0300`, which does not stop the boot.

Root diskette `/dev` (0.95 numbering): `PS0 PS1 at0 at1`, `hda hda1–8` (3,0–8), `hdb hdb1–8` (3,64–72), `ram mem kmem null port`, `tty tty0 console tty1–8 ttys1–4`.

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
- fileutils 3.1: `NGROUPS_MAX` is 0 in include-0.12, so `eaccess.c` `#undef`s it; Minix has no `st_blocks`, so `fileblocks.c` computes it for Minix v1 (7 direct, 1 indirect, 1 double indirect); the bison output of `posixtm.y` has its `yy*` names renamed to `zz*` so it links together with `getdate`. A generated `Makefile.l095` replaces configure and builds only the 11 root diskette programs.
- Every file in the package is dated 1992-03-08 or earlier; the guest clock must be later, or make rebuilds everything each run.
- Unpack with `cd /`: package paths start with `usr/src`.
- Minix file names are at most 14 characters; `mkbootroot.sh` checks this.
- 0.12 has no rename syscall, so mv cannot move directories: to replace a directory from the package, extract it alone from the source floppy, then `rm -rf` the old one.
