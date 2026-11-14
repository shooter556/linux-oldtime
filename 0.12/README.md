# Linux 0.12 — install to hard disk, rebuild the kernel

[中文](#中文) | [English](#english)

---

## 中文

用两张自制软盘，把 Linux 0.12（1992 年 1 月）从 boot + root 软盘装到硬盘上，并在装好的系统里用当年的 gcc 1.40 重新编译 0.12 内核。全部材料来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)，主机只负责收集文件、做软盘，安装过程在虚拟机里完成。

在 86Box（i386SX、387、8MB 内存、IDE 硬盘 128 柱面 / 16 磁头 / 63 扇区）上验证通过。

### 文件

| 文件 | 说明 |
|---|---|
| `mkinstall.sh` | 主机端：生成安装盘 `install.flp` |
| `inst.sh.in` | 安装盘里的 guest 脚本模板（bash 1.12） |
| `mkkernel.sh` | 主机端：生成内核源码盘 `kernel.flp` |
| `kinst.sh.in` | 源码盘里的 guest 脚本模板 |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）。

### 软盘格式

两张盘都是 **raw** 盘（没有文件系统）。0.12 原版 root 盘上没有 mount、tar、mkfs，guest 里只能用 `dd skip=… count=…` 按 1K 块偏移取文件。盘的开头是 guest 脚本，脚本里已经写好了各段的偏移。

`install.flp`（约 1371/1440 块）：

- `compress`：原样存放，后面所有 `.Z` 都靠它解压
- `fdisk`、`mkfs`、`mount`、`tar`：各自压缩成 `.Z`
- 一个 `.Z` 软件包，已按最终路径摆好：
  - `bin/{umount,mknod,sync}`：sync 是主机上手工拼的最小 a.out，只做 `sync`、`exit(0)` 两次系统调用（同 V6 的 `s2/sync.s`）
  - root 盘上没有的程序：make、egrep、kermit、em、dir、vdir、expand、unexpand、split、tac、as86、ld86
  - gcc 1.40：`/usr/local/bin/gcc` 和 `/usr/local/lib/gcc-*`、crt0.o、libc.a、gnulib
  - `/usr/include`

`kernel.flp`：`linux-0.12.tar` 原版源码，另外改了三处：

- `Makefile`：`ROOT_DEV=/dev/hd2`、`SWAP_DEV=/dev/hd1`
- `kernel/chr_drv/keyboard.S`：`KBD_US`
- 外加一个 `sync.c`，kinst 用它测试 gcc 能否正常工作

各程序的来源：

| 程序 | 来源 |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z`（Owen LeBlanc，1992，gcc 1.40 编译） |
| mkfs、mount、umount、mknod、tar、compress | `images/rootimage-0.11-20040305` |
| 其他 | `Linux-0.12/binaries/`、`libs/libc/libc-0.1x/include-0.11.tar.Z`、`kernel/0.1x/linux-0.12.tar` |

### 安装

```
./mkinstall.sh -s /path/to/oldlinux-files -o install.flp
./mkkernel.sh  -s /path/to/oldlinux-files -o kernel.flp
```

还需要：

- `Linux-0.12/images/` 下的 `bootimage-0.12` 和 `rootimage-0.12`（解压后各写成一张 1.44M 盘）
- 一块空硬盘镜像，只把 MBR 的最后两个字节设成 `55 AA`。否则 0.12 内核会报 `Bad partition table` 并 panic。

guest 里（A = boot → root 盘，B = install.flp）：

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=4
sh /tmp/inst part --apply 16 63 128     # 磁头 扇区 柱面；fdisk 由管道驱动，建 hd1 swap（16 柱面）、hd2 root
                                        # 等 30 秒，重启（0.12 只在开机时读分区表）
sh /tmp/inst install --apply            # mkswap hd1、mkfs hd2、拷 root 盘、解软件包、umount
                                        # B 换成 boot 盘
sh /tmp/inst rootdev --apply            # SWAP_DEV（偏移 506）写 0x0301、ROOT_DEV（偏移 508）写 0x0302
                                        # 等 30 秒，关机，只放 boot 盘启动
```

每个子命令都可以先用 `--dry-run` 只打印命令。

编译内核（从硬盘启动后，B = kernel.flp）：

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply                   # gas/gld/gar/cpp 硬链接、解源码、用 gcc 编 /bin/sync 测试 gcc
cd /usr/src/linux-0.12; make
dd bs=8192 if=Image of=/dev/fd1         # B 换一张空白盘
```

### 遇到的坑

- 开机的 SVGA 提示不要按回车，按空格。setup.s 会把模拟器的显卡误认成 Ahead 芯片，列出的模式都不能用。
- 0.12 root 盘上没有 `sync` 命令。`/etc/update` 每 30 秒 sync 一次（间隔写死），所以重启前要等 30 秒。fdisk 的 `w` 命令自己会调用 sync。装到硬盘后有安装包里的 `/bin/sync`。
- `part` 阶段放进 root 盘 `/tmp` 的 fdisk，重启后可能变成 0 字节，所以 `install` 会从安装盘重新取 compress 和 fdisk。
- 0.12 已经支持换页到 swap 分区：分区先用 root 盘上的 `/bin/mkswap` 初始化，再把 boot 盘偏移 506 的字设成该分区，开机自动启用，不需要 swapon。swap 文件要到 0.95 才支持。
- root 盘上没有 `/mnt`，`/tmp` 只剩约 117KB，所以 fdisk、mkfs、mount 分阶段放进 `/tmp`。
- GNU mv 移动目录要借助 `/usr/bin/mvdir`（0.12 没有 rename 系统调用），所以软件包预先按最终路径摆好。
- 不能用 `/mnt/bin/umount` 卸载 `/mnt`：程序本身在要卸载的盘上，会报 EBUSY。要先拷到 `/tmp` 再运行。
- 往软盘写 SWAP_DEV、ROOT_DEV 时 dd 必须带 `bs=1`，否则 `seek` 按 512 字节一块计算。bash 1.12 的 `echo -e '\001\003\002\003'` 支持八进制转义，可以生成这四个字节。
- fdisk 0.91 提示 “Linux cannot currently use N sectors”，是它自己的 bug：拿扇区数跟 65535 比较。Minix v1 的上限是 65535 **块**。
- 0.12 的 execve 只认 ZMAGIC，OMAGIC 格式的程序（比如后来的 rdev 二进制）跑不了。
- `/usr/include/unistd.h` 要 include `utime.h`，include-0.11 里没有这个文件，从内核源码里补上。
- 0.12 键盘布局的定义在 `kernel/chr_drv/keyboard.S` 里，默认是 `KBD_FINNISH`，不在 `config.h`。

---

## English

Two home-made floppies that install Linux 0.12 (January 1992) from the boot + root diskettes onto a hard disk, then rebuild the 0.12 kernel inside the installed system with the period gcc 1.40. Every file comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files). The host only collects files and writes floppy images; the installation itself runs inside the VM.

Tested on 86Box (i386SX, 387, 8 MB RAM, IDE disk 128 cyl / 16 heads / 63 sectors).

### Files

| File | Purpose |
|---|---|
| `mkinstall.sh` | host: builds the install floppy `install.flp` |
| `inst.sh.in` | guest script template stored on the install floppy (bash 1.12) |
| `mkkernel.sh` | host: builds the kernel source floppy `kernel.flp` |
| `kinst.sh.in` | guest script template stored on the source floppy |

Host requirements: bash, python3, gzip, tar, `compress` (ncompress).

### Floppy format

Both floppies are **raw** (no filesystem). The stock 0.12 root diskette has no mount, tar or mkfs, so files are pulled out in the guest with `dd skip=… count=…` at 1K-block offsets. Each floppy starts with the guest script, which already contains those offsets.

`install.flp` (about 1371/1440 blocks):

- `compress`, stored plain; every `.Z` below is unpacked with it
- `fdisk`, `mkfs`, `mount`, `tar`, each compressed to `.Z`
- one `.Z` package laid out at its final paths:
  - `bin/{umount,mknod,sync}`: sync is a minimal a.out built on the host that only makes the `sync` and `exit(0)` system calls (like V6 `s2/sync.s`)
  - programs missing from the root diskette: make, egrep, kermit, em, dir, vdir, expand, unexpand, split, tac, as86, ld86
  - gcc 1.40: `/usr/local/bin/gcc` and `/usr/local/lib/gcc-*`, crt0.o, libc.a, gnulib
  - `/usr/include`

`kernel.flp`: the stock `linux-0.12.tar` source, with three changes:

- `Makefile`: `ROOT_DEV=/dev/hd2`, `SWAP_DEV=/dev/hd1`
- `kernel/chr_drv/keyboard.S`: `KBD_US`
- an added `sync.c`, which kinst compiles to check that gcc works

Where the programs come from:

| Program | Source |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z` (Owen LeBlanc, 1992, built with gcc 1.40) |
| mkfs, mount, umount, mknod, tar, compress | `images/rootimage-0.11-20040305` |
| everything else | `Linux-0.12/binaries/`, `libs/libc/libc-0.1x/include-0.11.tar.Z`, `kernel/0.1x/linux-0.12.tar` |

### Install

```
./mkinstall.sh -s /path/to/oldlinux-files -o install.flp
./mkkernel.sh  -s /path/to/oldlinux-files -o kernel.flp
```

You also need:

- `bootimage-0.12` and `rootimage-0.12` from `Linux-0.12/images/`, each unpacked onto its own 1.44M floppy
- a blank hard disk image whose MBR has only the `55 AA` signature set. Without it, the 0.12 kernel prints `Bad partition table` and panics.

In the guest (A = boot then root diskette, B = install.flp):

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=4
sh /tmp/inst part --apply 16 63 128     # heads sectors cylinders; fdisk fed through a pipe, hd1 swap (16 cyl), hd2 root
                                        # wait 30 s, reboot (0.12 reads the partition table only at boot)
sh /tmp/inst install --apply            # mkswap hd1, mkfs hd2, copy the root diskette, unpack the package, umount
                                        # put the boot diskette into B
sh /tmp/inst rootdev --apply            # write SWAP_DEV = 0x0301 at offset 506, ROOT_DEV = 0x0302 at 508
                                        # wait 30 s, power off, boot from the boot diskette alone
```

Every sub-command accepts `--dry-run` to print the commands without running them.

Rebuilding the kernel (booted from the hard disk, B = kernel.flp):

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply                   # hard-link gas/gld/gar/cpp, unpack the source, build /bin/sync to test gcc
cd /usr/src/linux-0.12; make
dd bs=8192 if=Image of=/dev/fd1         # with a blank floppy in B
```

### Pitfalls

- At the SVGA prompt, press space, not Enter. setup.s mistakes the emulated card for an Ahead chip, and none of the modes it lists work.
- The 0.12 root diskette has no `sync` command. `/etc/update` syncs every 30 s (the interval is hard-coded), so wait 30 s before rebooting. fdisk's `w` command calls sync itself. Once installed, the package's `/bin/sync` is available.
- The fdisk left in the root diskette's `/tmp` by `part` may be 0 bytes after the reboot, so `install` fetches compress and fdisk from the install floppy again.
- 0.12 already pages to a swap partition: initialize it with `/bin/mkswap` from the root diskette and set the word at offset 506 of the boot diskette to that partition. Swap is enabled at boot; there is no swapon. Swap files arrived in 0.95.
- There is no `/mnt` on the root diskette, and `/tmp` has only about 117 KB free, so fdisk, mkfs and mount are staged into `/tmp` one phase at a time.
- GNU mv needs `/usr/bin/mvdir` to move directories (0.12 has no rename system call), so the package is pre-arranged at its final paths.
- `/mnt/bin/umount` cannot unmount `/mnt`: the binary lives on that disk, so you get EBUSY. Copy it to `/tmp` and run it from there.
- When writing SWAP_DEV and ROOT_DEV to the floppy, dd needs `bs=1`; otherwise `seek` counts 512-byte blocks. bash 1.12's `echo -e '\001\003\002\003'` accepts octal escapes and produces the four bytes.
- fdisk 0.91's "Linux cannot currently use N sectors" warning is a bug in fdisk: it compares the sector count with 65535. The Minix v1 limit is 65535 **blocks**.
- 0.12's execve accepts only ZMAGIC binaries, so OMAGIC programs (such as the later rdev binary) won't run.
- `/usr/include/unistd.h` includes `utime.h`, which is missing from include-0.11; the installer takes it from the kernel source.
- The 0.12 keyboard layout is selected in `kernel/chr_drv/keyboard.S` (default `KBD_FINNISH`), not in `config.h`.
