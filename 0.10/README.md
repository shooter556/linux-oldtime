# Linux 0.10 — rebuild the diskettes, install to hard disk, build tools on 0.10

[中文](#中文) | [English](#english)

---

## 中文

0.10（1991 年 11 月）的 boot 盘和 root 盘镜像都没有保存下来，现在只剩源码。这里用装在硬盘上的 [0.11](../0.11/) 系统，从源码重新编出 0.10 内核，做出 boot 盘和 root 盘；再用这两张盘在 0.10 里把系统装到硬盘上，整个过程不需要 Minix。之后又给 0.10 装上 gcc，让它能重编自己的内核，并开始从源码编译工具。全部材料来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)。主机只负责收集文件、做软盘，编译和安装都在虚拟机里完成。

在 86Box（Cx486SRx2、8MB 内存、IDE 硬盘 128 柱面 / 16 磁头 / 63 扇区）上验证。

### 现状

| 部分 | 状态 |
|---|---|
| 在 0.11 上编 0.10 内核，做 boot 盘、root 盘 | 完成，能启动 |
| 在 0.10 里装到硬盘（fdisk、mkfs、拷文件、改 ROOT_DEV） | 完成，能从硬盘启动 |
| 引导盘 `dev.flp`：gcc 1.40、make、as86/ld86 等 | 完成 |
| 在 0.10 里重编 0.10 内核 | 完成，结果和 0.11 编的逐字节相同 |
| 源码盘 `src.flp`：grep、diff、bison、fileutils、make、sed | 已在 0.10 里编译成功 |
| 源码盘 `src.flp`：tar、patch、more | **没做完**：解包时读软盘就读错，见下面“软驱驱动的 bug” |

到这里为止。0.10 原版的软驱驱动不可靠，再往下做性价比太低；tytso 的那份（这里叫它 0.10a）也没有软驱补丁。

### 文件

| 文件 | 说明 |
|---|---|
| `mkkernel.sh` | 主机端：生成 `kernel.flp`（0.10 源码 + update + cut/tr） |
| `kinst.sh.in` | `kernel.flp` 的 guest 脚本模板（在 0.11 上运行：src / boot / root） |
| `mkdev.sh` | 主机端：生成引导盘 `dev.flp` |
| `dinst.sh.in` | `dev.flp` 的 guest 脚本模板（在 0.10 上运行：install / test） |
| `mksrc.sh` | 主机端：生成源码盘 `src.flp` |
| `sinst.sh.in` | `src.flp` 的 guest 脚本模板（在 0.10 上运行：`包名 unpack/build/install`） |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）、patch。

### 源码：还原 Linus 的原版

现存的 `linux-0.10.tar.gz` 不是 Linus 发布的原包，而是 Ted Ts'o 1991 年 11–12 月的工作目录：文件属主都是 `tytso`，带着 RCS 目录，不少文件被他改过。从 RCS 历史可以看出改动分三类：

- Linus 后来给的修复：`fs/buffer.c` 1.2（"Used new version of buffer.c supplied from Linus"）
- tytso 自己修的小 bug：`ctype.h` 里 `tolower()` 的 `+` 应为 `-`，`exit.c` 里 waitpid 的返回码
- 12 月 1 日 "Patches sent to Linus"：`suser()`、uid/euid 权限检查、目录的 sticky 位、setreuid/setregid（实现了，但没加进系统调用表）、`alarm()` 返回值、`kill()` 返回错误码、exec 的 `from_kmem`。这些基本都进了 0.11。

另外还有 jtkohl 的 CapsLock 改 Ctrl 补丁、没写完也没进 Makefile 的 `ramdisk.c` 和 `malloc.c`，以及 tytso 为了在 Minix 上编译而注释掉的 boot 规则。`Linux-0.10/sources/system/bin16.tar.Z` 里有 Linus 用 Minix 汇编好的 bootsect 和 setup，tytso 大概直接用的这两个文件。

`mkkernel.sh` 把所有放进 RCS 的文件都退回 1.1（就是 tytso 拿到时的样子），并删掉他新增的文件。没进 RCS 的文件都是只读的，日期不晚于 1991-11-02，保持原样。**buffer.c 也用 1.1**，保留了原版的 bug。RCS 1.1 只是 tytso 第一次 check-in 时的状态，如果他在那之前就改过某个文件，这里查不出来。

### 改动：用 0.11 的工具编译

- `AS86`/`LD86`：Minix 的 `as -0 -a`、`ld -0` 换成 `as86 -0 -a`、`ld86 -0`
- 删掉 `chmem +65000 tools/build`
- `tools/build` 改成 `./tools/build`（0.11 的 bash 1.05 不认带 `/` 的相对路径）
- 生成 `tmp.s` 的 SYSSIZE 规则：
  - `cut -c25-31` 改成 `-c34-41`。原规则是按 Minix ls 的输出格式写的；GNU ls 3.1 多一列 group，第 25–31 列正好是组名 `root`
  - `( … ) / 16` 改成 `[ … ] / 16`。as86 加了 `-a`（asld 兼容模式）后只能用方括号分组，圆括号会报 `factor expected`
- `boot/bootsect.s`、`boot/setup.s`：注释符 Minix asld 的 `|` 换成 as86 的 `!`，其余语法不变

规则里要用的 `cut` 和 `tr`，0.11 上没有，从 0.12 的二进制里带过去。

### 第 1 步：在 0.11 上做 boot 盘和 root 盘

在 0.11 的硬盘系统里，B 放 `kernel.flp`：

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=4
sh /tmp/kinst src -a            # 解源码、update、cut、tr，编 uname
cd /usr/src/linux-0.10; make
sh /tmp/kinst boot -a           # B 换空白盘：写 Image
sh /tmp/kinst root -a           # B 换空白盘：mkfs，放最小 root
```

每个子命令都可以先用 `-n` 只打印命令。

root 盘只放最小的一套：`/bin` 下有 sh、update、mkfs、mount、umount、mknod、fdisk；`/usr/bin` 下有 ls、cp、mv、mvdir、rm、rmdir、mkdir、cat、dd、chmod、sync、uname；`/etc` 下有 profile、passwd、group、空的 mtab；设备节点 hd0–8、fd0/fd1、tty、tty0–3、null。程序都从 0.11 系统里拷，它们用到的系统调用 0.10 都有（0.10 只比 0.11 少 70、71 号 setreuid/setregid）。

uname 是 oldlinux-files 里的 `bin/uname.c`（Jeff Comstock，1992），`kinst src` 在 0.11 上用 gcc 1.40 编成 `/usr/src/uname-0.10`，`kinst root` 把它放进 root 盘的 `/usr/bin`，装硬盘时随 `cp /usr/bin/*` 一起拷过去。注意 0.10 内核的 `sys_uname` 返回的是写死的占位串，`uname -a` 显示 `linux .0 nodename release  version  machine `，和 0.11 完全一样，所以只能看出是 0.10/0.11 这一代，分不出具体版本。内核源码保持原样，没有为此修改。

启动：A 放 boot 盘，出现 `Insert root floppy and press ENTER` 后换 root 盘。boot 盘第 508 字节的 ROOT_DEV 是 0，意思是 root 和启动用的是同一种软盘。

### 第 2 步：在 0.10 里装到硬盘

完全照 Linus 的 INSTALL-0.10 来做，用的都是 root 盘上的程序。每步之间 sync，不用管道（原因见下面的 buffer bug）。

1. 分区（fdisk-0.91，手工给几何参数，hd1 占扇区 63–129023），然后重启：0.10 只在启动时读一次分区表。
   ```
   (echo x; echo h; echo 16; echo s; echo 63; echo c; echo 128; echo r; echo n; echo p; echo 1; echo 63; echo 129023; echo w; echo q; echo q; echo q) | fdisk /dev/hd0
   ```
2. 建文件系统、拷文件、建设备节点：
   ```
   mkfs /dev/hd1 64480; sync
   mount /dev/hd1 /mnt; cd /mnt
   mkdir bin dev etc usr usr/bin usr/root mnt tmp
   cp /bin/* bin; sync
   cp /usr/bin/* usr/bin; sync
   cp /etc/* etc; > etc/mtab; sync
   cd dev
   for i in 0 1 2 3 4 5 6 7 8; do mknod hd$i b 3 $i; done
   mknod fd0 b 2 28; mknod fd1 b 2 29; mknod tty c 5 0
   for i in 0 1 2 3; do mknod tty$i c 4 $i; done
   mknod null c 1 3
   cd /; umount /dev/hd1; sync
   ```
   拷完要检查 `ls /mnt/bin`。第一次装的时候 `/bin` 不知为什么是空的，启动时就只看到 `child 2 died`。
3. 改 boot 盘的 ROOT_DEV 为 0x0301（`/dev/hd1`），B 放 boot 盘。0.10 的 bash 不一定支持 `echo -e`，这两个字节直接从 `/bin/sh` 里取（它第 185024 字节起正好是 `01 03`）：
   ```
   dd if=/bin/sh of=/tmp/rd bs=1 skip=185024 count=2
   dd if=/tmp/rd of=/dev/fd1 bs=1 seek=508 count=2; sync
   ```
4. A 放改好的 boot 盘启动，root 直接挂在硬盘上。

### 第 3 步：编译环境（dev.flp）

“从源码编工具”总得先有几样二进制。`dev.flp` 里放的是：

- gcc 1.40 全套、crt0.o、libc.a（`Linux-0.10/binaries/compilers/gccbin.tar.Z`，0.10 原版，和 0.11 的逐字节相同）
- `/usr/include`（include-0.11，没有更早的）
- make、as86、ld86（0.12 的二进制）；pmake 和 `/usr/share/mk`（0.10 原版）
- compress、tar（rootimage-0.11 上的），用来解开后面的源码包

```
dd if=/dev/fd1 of=/tmp/dinst bs=1024 count=3
sh /tmp/dinst install -a        # 不用管道，每步写临时文件再解开
sh /tmp/dinst test -a           # 编译并运行 hello.c
```

装好后用 `kernel.flp` 在 0.10 里重编 0.10 内核（手工 dd、compress、tar，不用 kinst 的管道）。先要装好 grep（见下一步），否则 SYSSIZE 规则里的 `ls | grep` 拿不到大小，算出 0，内核一个扇区都不加载，开机就反复重启。编出来的 boot 盘和 0.11 编的**逐字节相同**。

### 第 4 步：从源码编工具（src.flp）

```
dd if=/dev/fd1 of=/tmp/sinst bs=1024 count=6
sh /tmp/sinst 包名 unpack -a    # 分段读软盘，每段 sync，解到 /usr/src
sh /tmp/sinst 包名 build -a
sh /tmp/sinst 包名 install -a
```

| 包 | 源码 | 移植要点 | 结果 |
|---|---|---|---|
| grep-1.5 | 0.10 原版源码 | `-DUSG`（libc 没有 index/bcopy）；补一个 `memory.h`；删掉 `dfa.h` 里和 `<string.h>` 冲突的 `typedef int size_t` | 成功 |
| diff-1.15 | 0.10 原版源码 | 照 Linus 当年 diffbin 的 README：原版 Makefile、`-DUSG`、不要 `-g`；源码包里混着的 SunOS 二进制已删除 | 成功 |
| bison（1988） | `bin-src/bison.tar.gz` | 它的 Makefile 用 `-g` 链接，gcc 1.40 会去找 libg.a（gccbin 里没有），改成单独链接 | 成功，能处理 fileutils 的 `getdate.y`、`posixtm.y` |
| fileutils-3.1 | 0.12 源码，沿用 [0.11](../0.11/) 的移植 | 扁平的 `Makefile.l010`；yacc 部分用上面的 bison；安装时用新编的 cp 覆盖旧程序 | 成功，19 个程序；硬盘上原有的 10 个和 0.11 编的逐字节相同 |
| make-3.62 | FSF 原版（tsx-11 存档）+ Simon Marlow 1992 年的 Linux 补丁（只用 C 部分） | 0.10 的 libc 和头文件缺 SIGCLD、sys_siglist、getdtablesize、getgroups、getlogin、setlinebuf，都用 `#ifdef LINUX` 补上；glob 库手工编（它的 Makefile 写死了 `ar`） | 成功，替换了 0.12 的二进制 make |
| sed-1.13 | TAMU 1.0D | 0.10 自带的是 sed 1.08 二进制；1.06（`gnu/pc/sed106.zoo`）里只有 MS-DOS 补丁，没有源码，所以只能用 1.13 | 成功 |
| tar-1.11.1 | FSF 原版（tsx-11） | 手写 `Makefile.l010` 代替 configure；mkfifo 用 mknod 实现 | 未完成：解包时读错软盘 |
| patch-2.0.12u8 | FSF 原版（tsx-11） | 手写 `config.h` 和 Makefile（Configure 是交互式的） | 未完成 |
| more | BSD more 5.19，1992 年 2 月的 Linux 移植（tsx-11） | 带上 rootimage-0.11 的 `/etc/termcap` | 未完成 |

compress 在 oldlinux-files 里找不到源码（tsx-11 存档里的 ncompress-4.2.4 是空文件），只能继续用二进制。

### 0.10 和 0.11 的不同

- init 不读 `/etc/rc`，直接 fork 出 `/bin/update`（每 30 秒 sync 一次），再起 `/bin/sh`。init 用 `wait()` 等**任意**子进程，所以 update 一退出（比如 `/bin/update` 不存在），init 就打印 `child 2 died` 并退出。update 一般是 2 号进程。
- exit.c 1.1 的 `waitpid` 先 `release()` 进程结构，再去读退出码，所以**子进程的退出码拿不到**：`child 2 died with code 0000` 里的 0000 不可信，bash 和 make 也都看不到命令失败，编译出错 make 照样往下走。只能盯着屏幕看。tytso 的 exit.c 1.2 修的就是这个。
- 软盘：没有选盘互斥，出错恢复简单，读写端口没有延时（0.11 才改好）。

### buffer.c 1.1 的 bug

`getblk()` 回收一个空闲但还“脏”的缓冲块时，先把它从 hash 表里摘掉，再调用 `sync_dev()` 写盘，写盘时会睡眠。这时如果有人读这个块原来对应的磁盘块，hash 表里找不到，就会从磁盘读到还没写回的旧内容。Linus 在 1991-11-11 给出了修复（buffer.c 1.2）。

实际碰到的情况：一口气 dd 几百块写成文件，紧接着再读回来解压，读到的是旧数据（compress 报 `not in compressed format`）。同样的命令分开执行、中间 sync 就正常。我把读到的文件从硬盘镜像里取出来比对过，软盘数据本身是对的。所以脚本里每一步后面都加了 sync。

### 软驱驱动的 bug

刚读完盘开头几块，直接跳到很远的地方（第 227 块、第 911 块）去读，读到的数据是错的，而且没有报错。重启后同样出错，所以不是缓存的问题；改成每段 100 块、每段之后 sync，第一段照样是错的。先顺序读过一遍之后再跳读就正常了。0.10 的 `floppy.c` 寻道代码里看不出明显问题，具体原因没查下去。tar、patch、more 就是卡在这里。

### 遇到的其他坑

- make 会重新生成 tmp.s，手工改好的那份会被覆盖，只能改 Makefile。
- 0.11 硬盘上的 `/dev/null` 是普通文件，里面有东西，`cat /dev/null > 文件` 会把内容拷过去（见 [0.11](../0.11/)）。
- 在 86Box 里换了软盘内容后，0.10 不一定察觉到，最好重启一次再读。

---

## English

The 0.10 (November 1991) boot and root diskette images did not survive; only the source did. This uses a [0.11](../0.11/) system installed on a hard disk to rebuild the 0.10 kernel from source and make a boot and a root diskette; with those, 0.10 installs itself to a hard disk, with no Minix involved. After that 0.10 gets gcc, rebuilds its own kernel, and starts building tools from source. All material comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files). The host only gathers files and builds floppies; compiling and installing happen inside the VM.

Tested on 86Box (Cx486SRx2, 8MB RAM, IDE disk 128 cylinders / 16 heads / 63 sectors).

### Status

| Part | Status |
|---|---|
| Build the 0.10 kernel on 0.11, make the boot and root diskettes | done, boots |
| Install to hard disk from within 0.10 (fdisk, mkfs, copy, ROOT_DEV) | done, boots from the hard disk |
| Bootstrap floppy `dev.flp`: gcc 1.40, make, as86/ld86 etc. | done |
| Rebuild the 0.10 kernel on 0.10 | done, byte-identical to the 0.11-built one |
| Source floppy `src.flp`: grep, diff, bison, fileutils, make, sed | built on 0.10 |
| Source floppy `src.flp`: tar, patch, more | **not finished**: reading the floppy returns wrong data, see "The floppy driver bug" |

This is where it stops. The original 0.10 floppy driver is too unreliable to go further, and tytso's tree (called 0.10a here) has no floppy fix either.

### Files

| File | Purpose |
|---|---|
| `mkkernel.sh` | host: builds `kernel.flp` (0.10 source + update + cut/tr) |
| `kinst.sh.in` | guest script template on `kernel.flp` (runs on 0.11: src / boot / root) |
| `mkdev.sh` | host: builds the bootstrap floppy `dev.flp` |
| `dinst.sh.in` | guest script template on `dev.flp` (runs on 0.10: install / test) |
| `mksrc.sh` | host: builds the source floppy `src.flp` |
| `sinst.sh.in` | guest script template on `src.flp` (runs on 0.10: `PACKAGE unpack/build/install`) |

Host needs: bash, python3, gzip, tar, `compress` (ncompress package), patch.

### Source: restoring Linus's original

The surviving `linux-0.10.tar.gz` is not Linus's release but Ted Ts'o's working tree from November–December 1991: every file is owned by `tytso`, there are RCS directories, and several files were modified. The RCS history shows three kinds of change:

- a later fix from Linus: `fs/buffer.c` 1.2 ("Used new version of buffer.c supplied from Linus")
- small fixes by tytso: the `+` in `ctype.h`'s `tolower()` that should be `-`, the waitpid exit code in `exit.c`
- "Patches sent to Linus" on December 1: `suser()`, uid/euid permission checks, sticky directories, setreuid/setregid (implemented but not added to the syscall table), the `alarm()` return value, `kill()` error codes, exec's `from_kmem`. Most of this went into 0.11.

There are also jtkohl's caps-lock-as-control patch, an unfinished `ramdisk.c` and `malloc.c` that no Makefile uses, and the boot rules tytso commented out to build on Minix. `Linux-0.10/sources/system/bin16.tar.Z` holds Linus's Minix-assembled bootsect and setup, which tytso probably used as they were.

`mkkernel.sh` puts every file under RCS back to revision 1.1 (the state tytso received it in) and removes the files he added. Files never put under RCS are read-only, dated no later than 1991-11-02, and are left alone. **buffer.c is also at 1.1**, so the original bug is kept. Revision 1.1 is only the state at tytso's first check-in; if he changed a file before that, it cannot be detected here.

### Changes: building with the 0.11 tools

- `AS86`/`LD86`: Minix's `as -0 -a` and `ld -0` become `as86 -0 -a` and `ld86 -0`
- `chmem +65000 tools/build` is removed
- `tools/build` becomes `./tools/build` (0.11's bash 1.05 does not run relative paths containing `/`)
- the SYSSIZE rule that writes `tmp.s`:
  - `cut -c25-31` becomes `-c34-41`. The rule was written for Minix ls output; GNU ls 3.1 adds a group column, and columns 25–31 hold the group name `root`
  - `( … ) / 16` becomes `[ … ] / 16`. With `-a` (asld-compatible mode) as86 groups only with brackets; parentheses give `factor expected`
- `boot/bootsect.s`, `boot/setup.s`: Minix asld's `|` comment character becomes as86's `!`; the rest of the syntax is unchanged

The rule needs `cut` and `tr`, which 0.11 lacks; they come from the 0.12 binaries.

### Step 1: make the boot and root diskettes on 0.11

On the 0.11 hard-disk system, with `kernel.flp` in drive B:

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=4
sh /tmp/kinst src -a            # unpack the source, update, cut, tr; build uname
cd /usr/src/linux-0.10; make
sh /tmp/kinst boot -a           # B = blank floppy: write Image
sh /tmp/kinst root -a           # B = blank floppy: mkfs, minimal root
```

Every sub-command accepts `-n` to print the commands without running them.

The root diskette holds a minimal set: sh, update, mkfs, mount, umount, mknod and fdisk in `/bin`; ls, cp, mv, mvdir, rm, rmdir, mkdir, cat, dd, chmod, sync and uname in `/usr/bin`; profile, passwd, group and an empty mtab in `/etc`; device nodes hd0–8, fd0/fd1, tty, tty0–3 and null. The programs are copied from the 0.11 system; 0.10 has every syscall they use (it lacks only 0.11's 70 and 71, setreuid/setregid).

uname is `bin/uname.c` from oldlinux-files (Jeff Comstock, 1992). `kinst src` builds it on 0.11 with gcc 1.40 as `/usr/src/uname-0.10`, `kinst root` puts it in `/usr/bin` of the root diskette, and `cp /usr/bin/*` carries it to the hard disk. Note that the 0.10 kernel's `sys_uname` returns hard-coded placeholder strings: `uname -a` prints `linux .0 nodename release  version  machine `, exactly as on 0.11, so it only tells the 0.10/0.11 generation, not the exact version. The kernel source is left stock; it is not patched for this.

Boot: boot diskette in A; at `Insert root floppy and press ENTER` swap in the root diskette. ROOT_DEV at offset 508 of the boot diskette is 0, meaning the same kind of floppy as the one booted from.

### Step 2: install to hard disk from within 0.10

This follows Linus's INSTALL-0.10, using only the programs on the root diskette. Sync between steps and avoid pipelines (see the buffer bug below).

1. Partition (fdisk-0.91, geometry entered by hand, hd1 = sectors 63–129023), then reboot: 0.10 reads the partition table only at boot.
   ```
   (echo x; echo h; echo 16; echo s; echo 63; echo c; echo 128; echo r; echo n; echo p; echo 1; echo 63; echo 129023; echo w; echo q; echo q; echo q) | fdisk /dev/hd0
   ```
2. Make the filesystem, copy files, create device nodes:
   ```
   mkfs /dev/hd1 64480; sync
   mount /dev/hd1 /mnt; cd /mnt
   mkdir bin dev etc usr usr/bin usr/root mnt tmp
   cp /bin/* bin; sync
   cp /usr/bin/* usr/bin; sync
   cp /etc/* etc; > etc/mtab; sync
   cd dev
   for i in 0 1 2 3 4 5 6 7 8; do mknod hd$i b 3 $i; done
   mknod fd0 b 2 28; mknod fd1 b 2 29; mknod tty c 5 0
   for i in 0 1 2 3; do mknod tty$i c 4 $i; done
   mknod null c 1 3
   cd /; umount /dev/hd1; sync
   ```
   Check `ls /mnt/bin` afterwards. On the first install `/bin` ended up empty for an unknown reason, and booting showed only `child 2 died`.
3. Set the boot diskette's ROOT_DEV to 0x0301 (`/dev/hd1`), boot diskette in B. 0.10's bash may lack `echo -e`, so the two bytes come from `/bin/sh` (offset 185024 happens to hold `01 03`):
   ```
   dd if=/bin/sh of=/tmp/rd bs=1 skip=185024 count=2
   dd if=/tmp/rd of=/dev/fd1 bs=1 seek=508 count=2; sync
   ```
4. Boot from the patched diskette in A; root is mounted from the hard disk.

### Step 3: development environment (dev.flp)

Building tools from source needs a few binaries to begin with. `dev.flp` carries:

- the gcc 1.40 tools, crt0.o and libc.a (`Linux-0.10/binaries/compilers/gccbin.tar.Z`, the 0.10 original, byte-identical to 0.11's)
- `/usr/include` (include-0.11; nothing older exists)
- make, as86, ld86 (0.12 binaries); pmake and `/usr/share/mk` (0.10 originals)
- compress and tar (from rootimage-0.11), to unpack the source packages

```
dd if=/dev/fd1 of=/tmp/dinst bs=1024 count=3
sh /tmp/dinst install -a        # no pipelines: temp files, unpacked step by step
sh /tmp/dinst test -a           # compile and run hello.c
```

Then rebuild the 0.10 kernel on 0.10 from `kernel.flp` (dd, compress and tar by hand, not kinst's pipeline). grep must be installed first (next step); without it the SYSSIZE rule's `ls | grep` yields nothing, SYSSIZE becomes 0, the boot sector loads no kernel and the machine reboots in a loop. The resulting boot diskette is **byte-identical** to the 0.11-built one.

### Step 4: tools from source (src.flp)

```
dd if=/dev/fd1 of=/tmp/sinst bs=1024 count=6
sh /tmp/sinst PACKAGE unpack -a # read the floppy in pieces with syncs, unpack into /usr/src
sh /tmp/sinst PACKAGE build -a
sh /tmp/sinst PACKAGE install -a
```

| Package | Source | Porting notes | Result |
|---|---|---|---|
| grep-1.5 | 0.10 original source | `-DUSG` (libc has no index/bcopy); a `memory.h` shim; drop `dfa.h`'s `typedef int size_t`, which clashes with `<string.h>` | built |
| diff-1.15 | 0.10 original source | as in Linus's 0.10 diffbin README: stock Makefile, `-DUSG`, no `-g`; the SunOS binaries in the tarball are removed | built |
| bison (1988) | `bin-src/bison.tar.gz` | its Makefile links with `-g`, which makes gcc 1.40 look for libg.a (not in gccbin); linked separately | built; handles fileutils' `getdate.y` and `posixtm.y` |
| fileutils-3.1 | 0.12 source, the [0.11](../0.11/) port | flat `Makefile.l010`; yacc via the bison above; installed with the new cp | built, 19 programs; the 10 already on disk are byte-identical to the 0.11 builds |
| make-3.62 | FSF original (tsx-11 archive) + Simon Marlow's 1992 Linux patch (C part only) | 0.10's libc/headers lack SIGCLD, sys_siglist, getdtablesize, getgroups, getlogin, setlinebuf; added under `#ifdef LINUX`; glob built by hand (its Makefile hard-codes `ar`) | built, replaces the 0.12 make binary |
| sed-1.13 | TAMU 1.0D | 0.10 shipped a sed 1.08 binary; 1.06 (`gnu/pc/sed106.zoo`) holds only MS-DOS patches, no source, so 1.13 it is | built |
| tar-1.11.1 | FSF original (tsx-11) | hand-written `Makefile.l010` instead of configure; mkfifo via mknod | not done: floppy read returns wrong data |
| patch-2.0.12u8 | FSF original (tsx-11) | hand-written `config.h` and Makefile (Configure is interactive) | not done |
| more | BSD more 5.19, Linux port of Feb 1992 (tsx-11) | ships rootimage-0.11's `/etc/termcap` | not done |

No compress source exists in oldlinux-files (the tsx-11 ncompress-4.2.4 file is empty), so compress stays a binary.

### 0.10 versus 0.11

- init does not read `/etc/rc`. It forks `/bin/update` (a sync every 30 seconds), then starts `/bin/sh`. init `wait()`s for **any** child, so when update exits (e.g. `/bin/update` is missing) init prints `child 2 died` and exits. update is normally pid 2.
- exit.c 1.1's `waitpid` calls `release()` on the task before reading its exit code, so **exit statuses are lost**: the 0000 in `child 2 died with code 0000` means nothing, and neither bash nor make sees a failing command; make carries on after a compile error. Watch the screen. tytso's exit.c 1.2 fixes this.
- Floppy: no drive-select locking, simple error recovery, no I/O delays on port access (fixed in 0.11).

### The buffer.c 1.1 bug

When `getblk()` reclaims a free but dirty buffer, it first removes it from the hash table and then calls `sync_dev()` to write it, sleeping meanwhile. Anyone reading that disk block now misses in the hash table and reads the not-yet-written old contents from disk. Linus sent a fix on 1991-11-11 (buffer.c 1.2).

What it looked like here: dd several hundred blocks into a file and immediately read it back to decompress, and the data is stale (compress: `not in compressed format`). The same commands run one at a time with a sync in between work. The file, pulled out of the disk image and compared, held the correct floppy data. The guest scripts therefore sync after every step.

### The floppy driver bug

Right after reading the first blocks of a floppy, a read far away (block 227, block 911) returns wrong data without an error. It happens after a reboot too, so it is not caching; reading in 100-block pieces with a sync after each still gets the first piece wrong. After one sequential pass over the disk, far reads are fine. Nothing obviously wrong shows in 0.10's `floppy.c` seek code, and the cause was not tracked down. This is where tar, patch and more stopped.

### Other pitfalls

- make regenerates tmp.s and overwrites a hand-fixed copy, so the fix has to go into the Makefile.
- On the 0.11 hard disk `/dev/null` is a regular file with content, so `cat /dev/null > file` copies that content (see [0.11](../0.11/)).
- 0.10 may not notice that a floppy's content changed under 86Box; reboot before reading it again.
