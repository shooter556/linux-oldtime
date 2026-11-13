# Linux 0.11 — install to hard disk, fix the root diskette, rebuild the kernel

[中文](#中文) | [English](#english)

---

## 中文

用几张自制软盘把 Linux 0.11（1991 年 12 月）从 boot + root 软盘装到硬盘上。在装好的系统里，先用 0.11 自己的 gcc 重新编译 GNU fileutils，修好 root 盘，再重新编译 0.11 内核。全部材料来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)。主机只负责收集文件、做软盘，所有安装和编译都在虚拟机里完成。

在 86Box（Cx486SRx2、8MB 内存、IDE 硬盘 128 柱面 / 16 磁头 / 63 扇区）上验证通过。

思路和 [0.12](../0.12/) 一样，但 0.11 有几处不同，详见下面的“和 0.12 的区别”。

### 文件

| 文件 | 说明 |
|---|---|
| `mkinstall.sh` | 主机端：生成 `install.flp` 和 `pkg.flp` |
| `inst.sh.in` | 安装盘里的 guest 脚本模板 |
| `mkfu.sh` | 主机端：生成 fileutils 源码盘 `fu.flp` |
| `fuinst.sh.in` | 源码盘里的 guest 脚本模板 |
| `mkkernel.sh` | 主机端：生成内核源码盘 `kernel.flp` |
| `kinst.sh.in` | 内核源码盘里的 guest 脚本模板 |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）。

### 和 0.12 的区别

- **网上的 rootimage-0.11 不是原版。** oldlinux 及其镜像站、archive.org、kernel.org 上找到的 0.11 root 盘都是 2004 年前后重做的：
  - rm、cp、mv、ln 等文件工具和 0.12 root 盘上的同名文件逐字节相同，日期是 1992-01-15（0.12 的发布日）。
  - 盘上还有 0.11 用不上的 mkswap。
  - Linus 的 0.11 说明文档写着原版 root 盘带 fdisk、mkfs、mount、mknod，这张盘上都没有。
- **这些 0.12 工具在 0.11 上会报 `Not owner`。** 它们调用了 lstat（84 号）等系统调用，而 0.11 只有 0–71 号。0.11 对未知调用返回 -1，libc 把它当成 errno 1（EPERM）。坏掉的有 rm、cp、mv、ln、chgrp、du、touch，ls 碰到符号链接时也会出错。tar 和 dir、vdir 也受影响，所以 guest 里只能 `tar x`，不能 `tar c`。
- **bash 是 1.05**，比 0.12 的 1.12 旧：
  - 没有 `let`。
  - 在函数里用 `eval` 执行，`cd` 不生效，失败也拿不到退出码。所以脚本里的命令都改成用 `/bin/sh -c` 执行。
  - 不认 `tools/build` 这种带 `/` 的相对路径，会报 command not found；写成 `./tools/build` 或绝对路径才行。
  - `$-` 只输出 `o`，分不出是不是交互式 shell。
- **root 盘自带 `/usr/bin/sync`**，不用像 0.12 那样等 30 秒。
- **键盘布局在 `include/linux/config.h` 里设置**（不是 `keyboard.S`）。Makefile 里没有 `SWAP_DEV`，因为 0.11 不支持换出到磁盘。启动时也没有 SVGA 选择提示。

### 软盘

都是 **raw** 盘：盘的开头是 guest 脚本，脚本里写好了各段数据的 1K 块偏移，guest 里用 `dd skip=… count=…` 取出。

`install.flp`：

- 原样存放的 `compress`，以及压缩成 `.Z` 的 fdisk、mkfs、mount、tar
- `rootdev`：要写进 boot 盘偏移 508 的两个字节（`01 03`，即 ROOT_DEV=0x0301）
- root tree：整张 rootimage-0.11 的内容（含设备文件），在主机上用 Python 直接读 Minix 镜像打成 tar（GNU 格式）。`/dev/null` 换成真正的设备文件（c 1 3），`/etc/rc`、`/etc/mtab` 改成 `/dev/hd1`，并加上 `/mnt` 和 `bin/{fdisk,mkfs,mount,umount,mknod}`。tar 和 compress 不放进去，因为解包时它们正在运行，另外单独 dd 到 `/mnt/usr/bin`。

`pkg.flp`：

- 0.12 的 make、egrep、kermit、em、expand、unexpand、split、tac、as86、ld86
- 0.11 的 gcc（`gccbin.tar.Z`，与 0.12 的那份逐字节相同）
- `/usr/include`

`fu.flp`：

- GNU fileutils 3.1 源码，来自 `Linux-0.12/sources`
- GNU Bison 1.14 二进制，来自 `Linux-0.12/binaries`，用来生成 getdate 和 posixtm 的语法分析器
- 改过的 `/etc/profile`，以及单独存放的 `Makefile.l011` 和 `lib/posixtm.c`（给 `update` 步骤用）

`kernel.flp`：`linux-0.11.tar` 原版源码，改了三处：

- `Makefile`：`ROOT_DEV=/dev/hd1`
- `Makefile`：`tools/build` 改成 `./tools/build`
- `config.h`：`KBD_US`

各程序的来源：

| 程序 | 来源 |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z` |
| mkfs、mount、umount、mknod、tar、compress | `images/rootimage-0.11-20040305`（只用这些不调用 0.11 没有的系统调用的程序） |
| fileutils | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`，在 0.11 上用 0.11 的 gcc 和 libc 编译 |

### fileutils 移植

0.11 的 libc（`gccbin.tar.Z` 里的 `libc.a`，1991 年 9 月）没有 lstat、getgroups、readlink，头文件里也没有 `S_IFLNK`，所以 fileutils 编出来自动用 stat 代替 lstat。不用 configure，因为它的测试要用 rm 和 mv，`mkfu.sh` 直接生成 `Makefile.l011`：

- `DEFS`：`-DDIRENT -DST_BLOCKS_MISSING -DBSIZE=1024 -DSTDC_HEADERS -DPOSIX -DUSG -DFCHMOD_MISSING -DMKFIFO_MISSING -DFTRUNCATE_MISSING`
- `lib/eaccess.c`：去掉 getgroups（0.11 没有附加组）
- `lib/fileblocks.c`：按 Minix v1 文件系统计算块数（7 个直接块、1 个一级间接块、1 个二级间接块，1K 一块）
- `lib/posixtm.c`：用 `#define` 把 bison 输出里的全局 `yy*` 名改成 `zz*`，再 `#include "posixtm.tab.c"`。原版用 `sed 's/yy/zz/g'`，但 root 盘上的 sed 处理这个 21KB 的文件时会 out of memory。
- `.SUFFIXES:`：关掉 make 的内置后缀规则，否则 make 会因为找不到 yacc 而失败

libc 的 `rename()` 移动目录时会调用 `/usr/bin/mvdir`，所以也编译、安装 mvdir。

### 步骤

主机：

```
./mkinstall.sh -s /path/to/oldlinux-files -o .            # install.flp + pkg.flp
./mkfu.sh      -s /path/to/oldlinux-files -o fu.flp
./mkkernel.sh  -s /path/to/oldlinux-files -o kernel.flp
```

还需要：

- `Linux-0.11/images/` 下的 `bootimage-0.11` 和 `rootimage-0.11`，解压后各写成一张 1.44M 盘
- 一块空硬盘镜像，MBR 只设置 `55 AA` 签名
- **把虚拟机时钟设成 199x 年**。0.11 用 CMOS 的两位数年份减 70 计算年份，2026 年会被算成 1926 年。之后新生成的文件比源码还“旧”，make 会一直重新编译。

安装（A = boot → root 盘，B = install.flp）：

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=4
sh /tmp/inst part --apply       # fdisk 由管道驱动，建整盘一个分区；之后重启（只在开机时读分区表）
sh /tmp/inst install --apply    # mkfs、mount /mnt、解 root tree
sh /tmp/inst pkg --apply        # B 换 pkg.flp，不要重启；解开发包，umount
sh /tmp/inst rootdev --apply    # B 换 boot 盘，写 ROOT_DEV=0x0301
                                # 关机，只放 boot 盘启动 → 硬盘为根
```

重新编译 fileutils、修 root 盘（从硬盘启动后，B = fu.flp）：

```
dd if=/dev/fd1 of=/tmp/fuinst bs=1024 count=5
sh /tmp/fuinst unpack --apply   # 解源码，装 bison
sh /tmp/fuinst profile --apply  # 改 /etc/profile，见下面“遇到的坑”
                                # 重启（只放 boot 盘），让登录 shell 读新的 profile
sh /tmp/fuinst build --apply    # make -f Makefile.l011
sh /tmp/fuinst install --apply  # 装到原位置，旧程序存到 /usr/lib/fu-orig；修 /dev/null
sh /tmp/fuinst fixroot --apply  # B 换 root 盘（或它的副本）
```

`fixroot` 会：

- 把 root 盘上的 fileutils 换成新编的
- 删掉 mkswap、a.out、`.bash_history`、file、`/etc/magic`、mkfifo
- 加上 fdisk、mkfs、mount、umount、mknod、mvdir 和 `/mnt`，并换上新的 `/etc/profile`
- 把 `/dev/null` 换成真正的设备文件

做完还剩 28 块。再删掉以前拿这张盘做根盘时留在 `/tmp` 里的文件，剩 71 块。

编译内核（B = kernel.flp）：

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply           # 用 dd 把 gcc-* 复制成 gas/gld/gar/cpp，解源码
cd /usr/src/linux-0.11; make
dd bs=8192 if=Image of=/dev/fd1 # B 换一张空白盘
```

每个子命令都可以先用 `--dry-run` 只打印命令。

### 遇到的坑

- **`/etc/profile` 里有 `cd $HOME`，而 bash 1.05 每起一个 shell 都会读它，包括 make 用来执行命令的 `sh -c`。** 结果 make 的每条命令都跑到 `/usr/root` 去执行，报 `src/xxx.c: No such file`。改成：
  ```
  [ -z "$PROFILED" ] && cd $HOME
  PROFILED=1
  export PROFILED
  ```
  改完要重启一次。正在运行的登录 shell 不会重新读 profile，环境里没有 `PROFILED`，编内核时 `(cd kernel; make)` 会报 `kernel: ENOENT`。`fuinst build` 自己设了 `PROFILED`，所以不重启也能编过，问题要到编内核时才出现。
- root 盘上的 sed 基本不能用：处理稍大的文件就 out of memory 并段错误，在 `` `echo … | sed …` `` 里也什么都不输出。所以 guest 脚本里不用 sed。
- gcc-ranlib 会调用写死路径的 `/usr/local/bin/gar`，要先从 `gcc-ar` 复制一份过去。
- 硬盘上原来没有 `/usr/lib`。
- 删不掉文件时，可以用 `cat /dev/null > 文件` 释放空间，用 dd 代替 cp，用 dd 复制代替 ln。新的 fileutils 装好之前只能这样。
- 不能用 dd 覆盖正在运行的 dd 本身：0.11 是按需从文件读程序页面的，覆盖后正在运行的程序会出错。所以 `install` 一律用新编的 `src/dd` 来复制。
- 0.11 在 open 块设备时检查软盘是否换过，所以中途换盘不会读到旧的缓存。
- **rootimage-0.11 上的 `/dev/null` 是个普通文件**（模式 666），不是设备。写进去的东西都会留在里面，`cat /dev/null > 文件` 就会把这些内容拷过去。例如 `fuinst build` 里的 `grep PROFILED /etc/profile > /dev/null` 会把 profile 里的几行留在 `/dev/null` 里。现在 `install.flp` 解出来的就是真正的设备（c 1 3），`fuinst install` 和 `fixroot` 也会修好硬盘和 root 盘上的 `/dev/null`。用旧盘装好的系统，在装好新 fileutils 后手工修：`rm /dev/null; mknod /dev/null c 1 3; chmod 666 /dev/null`。

---

## English

A few home-made floppies that install Linux 0.11 (December 1991) from the boot + root diskettes onto a hard disk. Inside the installed system, GNU fileutils is first rebuilt with 0.11's own gcc to repair the root diskette, then the 0.11 kernel is rebuilt. Every file comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files). The host only collects files and writes floppy images; all installing and compiling happens inside the VM.

Tested on 86Box (Cx486SRx2, 8 MB RAM, IDE disk 128 cyl / 16 heads / 63 sectors).

The approach follows [0.12](../0.12/), with the 0.11 differences listed below.

### Files

| File | Purpose |
|---|---|
| `mkinstall.sh` | host: builds `install.flp` and `pkg.flp` |
| `inst.sh.in` | guest script template stored on the install floppy |
| `mkfu.sh` | host: builds the fileutils source floppy `fu.flp` |
| `fuinst.sh.in` | guest script template stored on that floppy |
| `mkkernel.sh` | host: builds the kernel source floppy `kernel.flp` |
| `kinst.sh.in` | guest script template stored on that floppy |

Host requirements: bash, python3, gzip, tar, `compress` (ncompress).

### Differences from 0.12

- **The rootimage-0.11 found online is not the original.** Every 0.11 root diskette on oldlinux and its mirrors, archive.org and kernel.org is a rebuild from around 2004:
  - rm, cp, mv, ln and the other file utilities are byte-identical to the ones on the 0.12 root diskette and dated 1992-01-15 (the 0.12 release day).
  - It carries mkswap, which 0.11 cannot use.
  - Linus's 0.11 notes say the original root diskette had fdisk, mkfs, mount and mknod; this one has none of them.
- **Those 0.12 utilities fail on 0.11 with `Not owner`.** They call lstat (number 84) and other system calls, while 0.11 only has 0–71. 0.11 returns -1 for an unknown call, which libc reads as errno 1 (EPERM). rm, cp, mv, ln, chgrp, du and touch are broken, and ls fails on symlinks. tar, dir and vdir are affected too, so the guest can only `tar x`, never `tar c`.
- **bash is 1.05**, older than 0.12's 1.12:
  - It has no `let`.
  - `eval` inside a function neither keeps a `cd` nor reports a failure, so every script command runs through `/bin/sh -c`.
  - It says "command not found" for a relative path with a slash such as `tools/build`; `./tools/build` or an absolute path works.
  - `$-` prints only `o`, so it cannot tell an interactive shell from a non-interactive one.
- **The root diskette has `/usr/bin/sync`**, so there is no 30 s wait as on 0.12.
- **The keyboard is chosen in `include/linux/config.h`** (not `keyboard.S`). The Makefile has no `SWAP_DEV`, because 0.11 cannot page out to disk. There is no SVGA prompt at boot.

### Floppies

All are **raw**: each floppy starts with a guest script that contains the 1K-block offsets of the data behind it, and the guest pulls the data out with `dd skip=… count=…`.

`install.flp`:

- `compress`, stored plain, plus fdisk, mkfs, mount and tar compressed to `.Z`
- `rootdev`: the two bytes written at offset 508 of the boot diskette (`01 03`, i.e. ROOT_DEV=0x0301)
- the root tree: everything on rootimage-0.11, device nodes included, read straight from the Minix image by Python on the host and packed as a GNU-format tar. `/dev/null` becomes a real device (c 1 3), `/etc/rc` and `/etc/mtab` say `/dev/hd1`, and `/mnt` plus `bin/{fdisk,mkfs,mount,umount,mknod}` are added. tar and compress are left out because they are running during the unpack; they are dd'ed into `/mnt/usr/bin` separately.

`pkg.flp`:

- make, egrep, kermit, em, expand, unexpand, split, tac, as86 and ld86 from 0.12
- 0.11's gcc (`gccbin.tar.Z`, byte-identical to 0.12's)
- `/usr/include`

`fu.flp`:

- the GNU fileutils 3.1 source from `Linux-0.12/sources`
- the GNU Bison 1.14 binary from `Linux-0.12/binaries`, which generates the getdate and posixtm parsers
- the fixed `/etc/profile`, plus separate copies of `Makefile.l011` and `lib/posixtm.c` for the `update` step

`kernel.flp`: the stock `linux-0.11.tar` source, with three changes:

- `Makefile`: `ROOT_DEV=/dev/hd1`
- `Makefile`: `tools/build` becomes `./tools/build`
- `config.h`: `KBD_US`

Where the programs come from:

| Program | Source |
|---|---|
| fdisk | `bin-src/fdisk-0.91.tar.Z` |
| mkfs, mount, umount, mknod, tar, compress | `images/rootimage-0.11-20040305` (only programs that use no system call 0.11 lacks) |
| fileutils | `Linux-0.12/sources/usr.bin/fileutils-3.1.tar.Z`, built on 0.11 with 0.11's gcc and libc |

### Porting fileutils

0.11's libc (`libc.a` in `gccbin.tar.Z`, September 1991) has no lstat, getgroups or readlink, and its headers have no `S_IFLNK`, so fileutils falls back to stat instead of lstat on its own. configure is not used, because its tests need rm and mv; `mkfu.sh` writes `Makefile.l011` directly:

- `DEFS`: `-DDIRENT -DST_BLOCKS_MISSING -DBSIZE=1024 -DSTDC_HEADERS -DPOSIX -DUSG -DFCHMOD_MISSING -DMKFIFO_MISSING -DFTRUNCATE_MISSING`
- `lib/eaccess.c`: getgroups removed (0.11 has no supplementary groups)
- `lib/fileblocks.c`: block counts for the Minix v1 filesystem (7 direct, 1 indirect, 1 double-indirect, 1K blocks)
- `lib/posixtm.c`: `#define`s rename the global `yy*` names in bison's output to `zz*`, then it does `#include "posixtm.tab.c"`. The original used `sed 's/yy/zz/g'`, but the root diskette's sed runs out of memory on that 21 KB file.
- `.SUFFIXES:`: disables make's built-in suffix rules, which would otherwise fail looking for yacc

libc's `rename()` runs `/usr/bin/mvdir` to move a directory, so mvdir is built and installed as well.

### Steps

Host:

```
./mkinstall.sh -s /path/to/oldlinux-files -o .            # install.flp + pkg.flp
./mkfu.sh      -s /path/to/oldlinux-files -o fu.flp
./mkkernel.sh  -s /path/to/oldlinux-files -o kernel.flp
```

You also need:

- `bootimage-0.11` and `rootimage-0.11` from `Linux-0.11/images/`, each unpacked onto its own 1.44M floppy
- a blank hard disk image whose MBR has only the `55 AA` signature set
- **the VM clock set to a year in the 1990s.** 0.11 computes the year as the two-digit CMOS year minus 70, so 2026 becomes 1926. New files then look older than the sources, and make keeps rebuilding.

Install (A = boot then root diskette, B = install.flp):

```
dd if=/dev/fd1 of=/tmp/inst bs=1024 count=4
sh /tmp/inst part --apply       # fdisk fed through a pipe, one whole-disk partition; then reboot (the table is read only at boot)
sh /tmp/inst install --apply    # mkfs, mount /mnt, unpack the root tree
sh /tmp/inst pkg --apply        # B = pkg.flp, no reboot; unpack the development package, umount
sh /tmp/inst rootdev --apply    # B = boot diskette; write ROOT_DEV=0x0301
                                # power off, boot from the boot diskette alone -> root on the hard disk
```

Rebuild fileutils and repair the root diskette (booted from the hard disk, B = fu.flp):

```
dd if=/dev/fd1 of=/tmp/fuinst bs=1024 count=5
sh /tmp/fuinst unpack --apply   # unpack the source, install bison
sh /tmp/fuinst profile --apply  # fix /etc/profile, see Pitfalls
                                # reboot (boot floppy only) so the login shell reads the new profile
sh /tmp/fuinst build --apply    # make -f Makefile.l011
sh /tmp/fuinst install --apply  # install in place, old programs saved in /usr/lib/fu-orig; fix /dev/null
sh /tmp/fuinst fixroot --apply  # B = the root diskette (or a copy)
```

`fixroot`:

- replaces the root diskette's fileutils with the new ones
- deletes mkswap, a.out, `.bash_history`, file, `/etc/magic` and mkfifo
- adds fdisk, mkfs, mount, umount, mknod, mvdir and `/mnt`, and copies in the new `/etc/profile`
- makes `/dev/null` a real device

That leaves 28 free blocks; removing the files left in `/tmp` from when the diskette served as root gives 71.

Rebuild the kernel (B = kernel.flp):

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=2
sh /tmp/kinst --apply           # copy gcc-* to gas/gld/gar/cpp with dd, unpack the source
cd /usr/src/linux-0.11; make
dd bs=8192 if=Image of=/dev/fd1 # with a blank floppy in B
```

Every sub-command accepts `--dry-run` to print the commands without running them.

### Pitfalls

- **`/etc/profile` runs `cd $HOME`, and bash 1.05 reads it in every new shell, including the `sh -c` that make runs commands with.** Every make command then runs in `/usr/root` and fails with `src/xxx.c: No such file`. It is changed to:
  ```
  [ -z "$PROFILED" ] && cd $HOME
  PROFILED=1
  export PROFILED
  ```
  Reboot once after the change. The running login shell does not re-read the profile, so `PROFILED` is not in its environment and the kernel build fails at `(cd kernel; make)` with `kernel: ENOENT`. `fuinst build` sets `PROFILED` itself, so it works without a reboot and the problem only shows up at the kernel build.
- The root diskette's sed is close to useless: it runs out of memory and segfaults on a moderately sized file, and prints nothing inside `` `echo … | sed …` ``. The guest scripts don't use sed.
- gcc-ranlib runs a hard-coded `/usr/local/bin/gar`, so `gcc-ar` is copied there first.
- The hard disk has no `/usr/lib` to begin with.
- Until the new fileutils are installed, `cat /dev/null > file` frees a file's blocks, dd replaces cp, and a dd copy replaces ln.
- Don't overwrite the running dd with dd: 0.11 pages programs in from their files on demand, so the running copy breaks. `install` always copies with the freshly built `src/dd`.
- 0.11 checks for a floppy change when a block device is opened, so swapping disks mid-way does not return stale cached blocks.
- **rootimage-0.11's `/dev/null` is a regular file** (mode 666), not a device. Whatever is written to it stays there, and `cat /dev/null > file` copies it out again; e.g. `grep PROFILED /etc/profile > /dev/null` in `fuinst build` leaves the profile lines in `/dev/null`. `install.flp` now unpacks a real device (c 1 3), and `fuinst install` and `fixroot` fix `/dev/null` on the hard disk and on the root diskette. On a system installed from older floppies, fix it by hand once the new fileutils are in: `rm /dev/null; mknod /dev/null c 1 3; chmod 666 /dev/null`.
