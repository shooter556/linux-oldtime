# Linux 0.12 — install to hard disk, rebuild the kernel

[中文](#中文) | [English](#english)

---

## 中文

用两张自制软盘，把 Linux 0.12（1992 年 1 月）从 boot + root 软盘装到硬盘上，并在装好的系统里用当年的 gcc 1.40 重新编译 0.12 内核。材料来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)（内核源码来自 Linux 历史 git 仓库），主机只负责收集文件、做软盘，安装过程在虚拟机里完成。

在 86Box（i386SX、387、8MB 内存、IDE 硬盘 128 柱面 / 16 磁头 / 63 扇区）上验证通过。

### 文件

| 文件 | 说明 |
|---|---|
| `mkinstall.sh` | 主机端：生成安装盘 `install.flp` |
| `inst.sh.in` | 安装盘里的 guest 脚本模板（bash 1.12） |
| `mkkernel.sh` | 主机端：生成内核源码盘 `kernel.flp` |
| `kinst.sh.in` | 源码盘里的 guest 脚本模板 |
| `mkgcc20.sh` | 主机端：生成自举 gcc 2.0 用的 `gcctools.flp`、`gccsrc1.flp`、`gccsrc2.flp` |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）；`mkgcc20.sh` 另外要 bzip2 和 gcc（在主机上跑 enquire）。

### 软盘格式

两张盘都是 **raw** 盘（没有文件系统）。0.12 原版 root 盘上没有 mount、tar、mkfs，guest 里只能用 `dd skip=… count=…` 按 1K 块偏移取文件。盘的开头是 guest 脚本，脚本里已经写好了各段的偏移。

`install.flp`（约 1421/1440 块）：

- `compress`：原样存放，后面所有 `.Z` 都靠它解压
- `fdisk`、`mkfs`、`mount`、`tar`：各自压缩成 `.Z`
- 一个 `.Z` 软件包，已按最终路径摆好：
  - `bin/{umount,mknod,sync}`：sync 是主机上手工拼的最小 a.out，只做 `sync`、`exit(0)` 两次系统调用（同 V6 的 `s2/sync.s`）
  - root 盘上没有的程序：make、egrep、kermit、em、dir、vdir、expand、unexpand、split、tac、as86、ld86
  - gcc 1.40：`/usr/local/bin/gcc` 和 `/usr/local/lib/gcc-*`、crt0.o、libc.a、gnulib
  - `/usr/include`
  - ShoeLace（`bin-src/shoelace.tar.Z`，1992-01-17 的 Linux 版）：`/shoelace`、`/etc/{laceup,bootlace,winiboot,disktab}`，另有生成的 `/etc/config`（`boot /Image`）

`kernel.flp`：用 `git archive` 从 Linux 历史仓库（[history.git](https://git.kernel.org/pub/scm/linux/kernel/git/history/history.git)，tag 形如 `0.12`、`0.95`）导出指定 tag 的原版源码，不做任何修改，解到 `/usr/src/linux`：

- 外加一个 `sync.c`，kinst 用它测试 gcc 能否正常工作
- `mkkernel.sh` 会打印该 tag 里 `ROOT_DEV`、`SWAP_DEV`、键盘布局所在的文件、行号和原值，在虚拟机里用 `em` 或 `sed` 手动改成 `ROOT_DEV=/dev/hd2`、`SWAP_DEV=/dev/hd1`、US 键盘
- 只用一张软盘，0.99.14 及以后的版本放不下，会报错

各程序的来源：

| 程序 | 来源 |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z`（Owen LeBlanc，1992，gcc 1.40 编译） |
| mkfs、mount、umount、mknod、tar、compress | `images/rootimage-0.11-20040305` |
| 其他 | `Linux-0.12/binaries/`、`libs/libc/libc-0.1x/include-0.11.tar.Z`、`kernel/0.1x/linux-0.12.tar` |

### 安装

```
./mkinstall.sh -s /path/to/oldlinux-files -o install.flp
./mkkernel.sh  -s /path/to/history -t 0.12 -o kernel.flp
```

还需要：

- `Linux-0.12/images/` 下的 `bootimage-0.12` 和 `rootimage-0.12`（解压后各写成一张 1.44M 盘）
- 一块空硬盘镜像，只把 MBR 的最后两个字节设成 `55 AA`。否则 0.12 内核会报 `Bad partition table` 并 panic。

guest 里（A = boot → root 盘，B = install.flp）：

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=5
sh /tmp/inst part --apply 128 16 63     # 柱面 磁头 扇区；fdisk 由管道驱动，建 hd1 swap（16 柱面）、hd2 root
                                        # 已有分区会先全部删掉；已是目标布局则跳过，可重复执行
                                        # 等 30 秒，重启（0.12 只在开机时读分区表）
sh /tmp/inst install --apply            # mkswap hd1、mkfs hd2、拷 root 盘、解软件包；中途提示时 B 换成 boot 盘
                                        # 再写 boot 盘的 SWAP_DEV（偏移 506）0x0301、ROOT_DEV（偏移 508）0x0302，
                                        # 拷成 hd2 的 /Image，laceup 装 ShoeLace 和 WiniBoot，umount
                                        # 等 30 秒，关机，取出两张软盘，从硬盘启动
```

`install` 的最后几步和 0.95 一样：`laceup /dev/hd2 wini`（bootlace 写进 hd2 的引导块）、`laceup -w 2 /dev/hd0`（WiniBoot 写进 MBR，保留分区表，默认第 2 分区）。内核 `/Image` 是从 B 里的 boot 盘取的前 285 个扇区（`bootimage-0.12` 的大小，`mkinstall.sh` 按 `Linux-0.12/images/bootimage-0.12.Z` 算出来填进脚本），所以 boot 盘必须是这个 `bootimage-0.12`；换内核时偏移 506–509 也要是 `01 03 02 03`，ShoeLace 不设根设备，用的是 Image 里的值。

从硬盘启动：WiniBoot 显示分区表和 `Boot:`，按 `1`–`4` 立刻启动对应分区（不用回车），约 15 秒不按就启动默认分区；ShoeLace 读 `/etc/config`，载入 `/Image`。改了 `/etc/config` 不用重装；千万别对 `/dev/hd0` 跑不带 `-w` 的 laceup，会覆盖分区表。

每个子命令都可以先用 `--dry-run` 只打印命令。

编译内核（从硬盘启动后，B = kernel.flp）：

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply                   # gas/gld/gar/cpp 硬链接、解源码、用 gcc 编 /bin/sync 测试 gcc
cd /usr/src/linux; make
dd bs=8192 if=Image of=/dev/fd1         # B 换一张空白盘
```

### 自举 gcc 2.0，再编译 0.95 内核

在装好的 0.12 上用 gcc 1.40 三阶段自举官方 gcc-2.0（1992-02-22），再用它编译原版 0.95 内核，0.95 内核能正常启动。VM：i386SX + **387**、4MB 内存、hd1 上约 8MB swap。

```
./mkgcc20.sh -s /path/to/oldlinux-files -o gcc20/
```

- `gcctools.flp`：打过补丁的 gnulib（`__truncdfsf2` 改 13 个字节）、`/bin/true`（主机上拼的 a.out）、`df.c`、主机上用 gcc 2.0 的 enquire 生成的 `float.h.ieee`、测试程序 `ftest.c`/`hdr.c`；脚本把 as、ld、ar、ranlib、nm、size、strip、gar、cpp 软链接到 `/usr/local/bin`（cpp 指向 2.0 安装后的位置）。
- `gccsrc1.flp`、`gccsrc2.flp`：只保留 C 的 gcc-2.0 源码，每张一个独立的 tar.Z。Makefile.in、`config/x-i386v`、`config/t-svr3`、`config/i386gas.h` 已预先改好，加了 `fp387.asm`，改过的文件保留 1992 年的原时间戳。

guest 里，每张盘（顺序：gcctools、gccsrc1、gccsrc2）：

```
dd if=/dev/fd1 of=/tmp/g bs=1024 count=2
sh /tmp/g --apply                       # 先用 --dry-run 看
```

然后：

```
cd /usr/src/gcc/gcc-2.0
./configure --gas i386-gas-sysv
make bootstrap                          # mv 报 cc1plus、collect2 等不存在是正常的
for file in *.o; do cmp $file stage2/$file; done
cmp cc1 stage2/cc1; cmp cpp stage2/cpp; cmp gcc stage2/gcc     # 无输出 = 通过
cp /usr/local/bin/gcc /usr/local/bin/gcc140                    # 安装会覆盖 1.40 的驱动
make CC="stage2/gcc -Bstage2/" CFLAGS=-O install-common install-libgcc install-headers
cp /usr/src/gcc/tools/float.h.ieee /usr/local/lib/gcc/i386-gas-sysv/2.0/include/float.h
```

在 `/tmp` 编 `ftest.c`：`i=24`、`3->3`、`atof: 0`（libc 是软浮点，double 返回值放在 eax:edx，gcc 2.0 从 st(0) 取，所以是 0）；`hdr.c`：`hello 5 6 2147483647`、`FLT_DIG=6 DBL_DIG=15`。

0.95 内核：源码用原版 0.95（`git archive` 后重新打成 v7 tar，compress 后 dd 到软盘），只改 `ROOT_DEV=/dev/hd2` 和 `keyboard.S` 的 `KBD_US`，不要打开 `-fcombine-regs`。

注意：

- 必须打开 387。gcc 2.0 默认生成 387 代码，0.12 的 387 模拟不完整。
- BIOS 日期必须晚于 1992-02-22（源码里最新文件的日期），否则 make 会反复重新生成 Makefile。
- gcc 2.0 只提供驱动、cpp、cc1、libgcc.a 和头文件；as、ld、ar 等仍是 gccbin（1991）里的。
- 0.95 内核里有大量 `conflicting types for built-in function` 警告（strlen、memcpy、memcmp）：gcc 2.0 的 `size_t` 是 `long unsigned int`，内核是 `unsigned int`，i386 上一样，可以忽略。
- 0.95 不再读 boot 盘偏移 506 的 SWAP_DEV，要用 swapon。

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

Two home-made floppies that install Linux 0.12 (January 1992) from the boot + root diskettes onto a hard disk, then rebuild the 0.12 kernel inside the installed system with the period gcc 1.40. Files come from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files) (kernel source from the Linux history git repo). The host only collects files and writes floppy images; the installation itself runs inside the VM.

Tested on 86Box (i386SX, 387, 8 MB RAM, IDE disk 128 cyl / 16 heads / 63 sectors).

### Files

| File | Purpose |
|---|---|
| `mkinstall.sh` | host: builds the install floppy `install.flp` |
| `inst.sh.in` | guest script template stored on the install floppy (bash 1.12) |
| `mkkernel.sh` | host: builds the kernel source floppy `kernel.flp` |
| `kinst.sh.in` | guest script template stored on the source floppy |
| `mkgcc20.sh` | host: builds `gcctools.flp`, `gccsrc1.flp`, `gccsrc2.flp` for bootstrapping gcc 2.0 |

Host requirements: bash, python3, gzip, tar, `compress` (ncompress); `mkgcc20.sh` also needs bzip2 and gcc (to run enquire on the host).

### Floppy format

Both floppies are **raw** (no filesystem). The stock 0.12 root diskette has no mount, tar or mkfs, so files are pulled out in the guest with `dd skip=… count=…` at 1K-block offsets. Each floppy starts with the guest script, which already contains those offsets.

`install.flp` (about 1421/1440 blocks):

- `compress`, stored plain; every `.Z` below is unpacked with it
- `fdisk`, `mkfs`, `mount`, `tar`, each compressed to `.Z`
- one `.Z` package laid out at its final paths:
  - `bin/{umount,mknod,sync}`: sync is a minimal a.out built on the host that only makes the `sync` and `exit(0)` system calls (like V6 `s2/sync.s`)
  - programs missing from the root diskette: make, egrep, kermit, em, dir, vdir, expand, unexpand, split, tac, as86, ld86
  - gcc 1.40: `/usr/local/bin/gcc` and `/usr/local/lib/gcc-*`, crt0.o, libc.a, gnulib
  - `/usr/include`
  - ShoeLace (`bin-src/shoelace.tar.Z`, the Linux build of 1992-01-17): `/shoelace`, `/etc/{laceup,bootlace,winiboot,disktab}`, plus a generated `/etc/config` (`boot /Image`)

`kernel.flp`: the stock source of one tag, exported unmodified with `git archive` from the Linux history repo ([history.git](https://git.kernel.org/pub/scm/linux/kernel/git/history/history.git), tags such as `0.12`, `0.95`) and unpacked to `/usr/src/linux`:

- an added `sync.c`, which kinst compiles to check that gcc works
- `mkkernel.sh` prints the file, line and stock value of `ROOT_DEV`, `SWAP_DEV` and the keyboard layout in that tag; change them by hand in the guest with `em` or `sed` to `ROOT_DEV=/dev/hd2`, `SWAP_DEV=/dev/hd1` and a US keyboard
- one floppy only: 0.99.14 and later do not fit and are rejected

Where the programs come from:

| Program | Source |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z` (Owen LeBlanc, 1992, built with gcc 1.40) |
| mkfs, mount, umount, mknod, tar, compress | `images/rootimage-0.11-20040305` |
| everything else | `Linux-0.12/binaries/`, `libs/libc/libc-0.1x/include-0.11.tar.Z`, `kernel/0.1x/linux-0.12.tar` |

### Install

```
./mkinstall.sh -s /path/to/oldlinux-files -o install.flp
./mkkernel.sh  -s /path/to/history -t 0.12 -o kernel.flp
```

You also need:

- `bootimage-0.12` and `rootimage-0.12` from `Linux-0.12/images/`, each unpacked onto its own 1.44M floppy
- a blank hard disk image whose MBR has only the `55 AA` signature set. Without it, the 0.12 kernel prints `Bad partition table` and panics.

In the guest (A = boot then root diskette, B = install.flp):

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=5
sh /tmp/inst part --apply 128 16 63     # cylinders heads sectors; fdisk fed through a pipe, hd1 swap (16 cyl), hd2 root
                                        # wipes any existing partitions; skips if already laid out, so it can be rerun
                                        # wait 30 s, reboot (0.12 reads the partition table only at boot)
sh /tmp/inst install --apply            # mkswap hd1, mkfs hd2, copy the root diskette, unpack the package; at the prompt put the boot diskette into B
                                        # then write SWAP_DEV = 0x0301 at offset 506 and ROOT_DEV = 0x0302 at 508 on it,
                                        # copy it to hd2 as /Image, laceup installs ShoeLace and WiniBoot, umount
                                        # wait 30 s, power off, remove both floppies, boot from the hard disk
```

The last steps of `install` are the same as on 0.95: `laceup /dev/hd2 wini` (bootlace into hd2's boot block) and `laceup -w 2 /dev/hd0` (WiniBoot into the MBR, partition table kept, default partition 2). `/Image` is the first 285 sectors of the boot diskette in B (the size of `bootimage-0.12`, which `mkinstall.sh` works out from `Linux-0.12/images/bootimage-0.12.Z` and fills into the script), so the boot diskette must hold this `bootimage-0.12`. For another kernel, offsets 506–509 must also be `01 03 02 03`: ShoeLace does not set the root device and uses the value in the Image.

Booting from the hard disk: WiniBoot shows the partition table and `Boot:`. `1`–`4` boots that partition at once (no Enter); after about 15 seconds it boots the default partition. ShoeLace reads `/etc/config` and loads `/Image`. Changing `/etc/config` needs no reinstall; never run laceup on `/dev/hd0` without `-w`, it overwrites the partition table.

Every sub-command accepts `--dry-run` to print the commands without running them.

Rebuilding the kernel (booted from the hard disk, B = kernel.flp):

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply                   # hard-link gas/gld/gar/cpp, unpack the source, build /bin/sync to test gcc
cd /usr/src/linux; make
dd bs=8192 if=Image of=/dev/fd1         # with a blank floppy in B
```

### Bootstrapping gcc 2.0, then building the 0.95 kernel

On the installed 0.12, gcc 1.40 does a three-stage bootstrap of the official gcc-2.0 (1992-02-22); that gcc 2.0 then builds the stock 0.95 kernel, which boots. VM: i386SX + **387**, 4 MB RAM, about 8 MB of swap on hd1.

```
./mkgcc20.sh -s /path/to/oldlinux-files -o gcc20/
```

- `gcctools.flp`: patched gnulib (13 bytes in `__truncdfsf2`), `/bin/true` (an a.out built on the host), `df.c`, `float.h.ieee` produced on the host by gcc 2.0's enquire, test programs `ftest.c`/`hdr.c`. Its script symlinks as, ld, ar, ranlib, nm, size, strip, gar and cpp into `/usr/local/bin` (cpp points at where gcc 2.0 installs it).
- `gccsrc1.flp`, `gccsrc2.flp`: the gcc-2.0 source trimmed to C, one independent tar.Z each. Makefile.in, `config/x-i386v`, `config/t-svr3` and `config/i386gas.h` are pre-patched, `fp387.asm` is added, and patched files keep their 1992 timestamps.

In the guest, for each floppy (order: gcctools, gccsrc1, gccsrc2):

```
dd if=/dev/fd1 of=/tmp/g bs=1024 count=2
sh /tmp/g --apply                       # try --dry-run first
```

Then:

```
cd /usr/src/gcc/gcc-2.0
./configure --gas i386-gas-sysv
make bootstrap                          # mv complaining about cc1plus, collect2 etc. is normal
for file in *.o; do cmp $file stage2/$file; done
cmp cc1 stage2/cc1; cmp cpp stage2/cpp; cmp gcc stage2/gcc     # no output = pass
cp /usr/local/bin/gcc /usr/local/bin/gcc140                    # install overwrites the 1.40 driver
make CC="stage2/gcc -Bstage2/" CFLAGS=-O install-common install-libgcc install-headers
cp /usr/src/gcc/tools/float.h.ieee /usr/local/lib/gcc/i386-gas-sysv/2.0/include/float.h
```

Build `ftest.c` in `/tmp`: `i=24`, `3->3`, `atof: 0` (libc is soft-float and returns double in eax:edx, gcc 2.0 reads st(0)); `hdr.c`: `hello 5 6 2147483647`, `FLT_DIG=6 DBL_DIG=15`.

0.95 kernel: the stock 0.95 source (`git archive`, repacked as a v7 tar, compressed and dd'd to a floppy), with only `ROOT_DEV=/dev/hd2` and `KBD_US` in `keyboard.S` changed. Do not enable `-fcombine-regs`.

Notes:

- The 387 must be enabled. gcc 2.0 emits 387 code by default and the 0.12 387 emulation is incomplete.
- The BIOS date must be after 1992-02-22 (the newest file in the source), or make keeps regenerating the Makefile.
- gcc 2.0 provides only the driver, cpp, cc1, libgcc.a and headers; as, ld, ar etc. are still the ones from gccbin (1991).
- The 0.95 build prints many `conflicting types for built-in function` warnings (strlen, memcpy, memcmp): gcc 2.0's `size_t` is `long unsigned int`, the kernel's is `unsigned int`; identical on i386, harmless.
- 0.95 no longer reads SWAP_DEV at offset 506 of the boot diskette; it needs swapon.

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
