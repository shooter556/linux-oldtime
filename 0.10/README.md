# Linux 0.10 — rebuild the boot and root diskettes

[中文](#中文) | [English](#english)

---

## 中文

0.10（1991 年 11 月）的 boot 盘和 root 盘镜像都没有保存下来，现在只剩源码。这里用装在硬盘上的 [0.11](../0.11/) 系统，从源码重新编出 0.10 内核，做出 boot 盘和 root 盘。全部材料来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)。主机只负责收集文件、做软盘，编译和做盘都在虚拟机里完成。

在 86Box（Cx486SRx2、8MB 内存、IDE 硬盘 128 柱面 / 16 磁头 / 63 扇区）上验证通过：用 boot 盘启动，换上 root 盘后进入 shell，整个过程不需要 Minix。装到硬盘还没做。

### 文件

| 文件 | 说明 |
|---|---|
| `mkkernel.sh` | 主机端：生成 `kernel.flp` |
| `kinst.sh.in` | `kernel.flp` 里的 guest 脚本模板（在 0.11 上运行） |

主机需要：bash、python3、gzip、tar、`compress`（ncompress 包）。

### 源码：还原 Linus 的原版

现存的 `linux-0.10.tar.gz` 不是 Linus 发布的原包，而是 Ted Ts'o 1991 年 11–12 月的工作目录：文件属主都是 `tytso`，带着 RCS 目录，不少文件被他改过。从 RCS 历史可以看出改动分三类：

- Linus 后来给的修复：`fs/buffer.c` 1.2（"Used new version of buffer.c supplied from Linus"）
- tytso 自己修的小 bug：`ctype.h` 里 `tolower()` 的 `+` 应为 `-`，`exit.c` 里 waitpid 的返回码
- 12 月 1 日 "Patches sent to Linus"：`suser()`、uid/euid 权限检查、目录的 sticky 位、setreuid/setregid（实现了，但没加进系统调用表）、`alarm()` 返回值、`kill()` 返回错误码、exec 的 `from_kmem`。这些基本都进了 0.11。

另外还有 jtkohl 的 CapsLock 改 Ctrl 补丁、没写完也没进 Makefile 的 `ramdisk.c` 和 `malloc.c`，以及 tytso 为了在 Minix 上编译而注释掉的 boot 规则。

`mkkernel.sh` 把所有放进 RCS 的文件都退回 1.1（就是 tytso 拿到时的样子），并删掉他新增的文件。没进 RCS 的文件都是只读的，日期不晚于 1991-11-02，保持原样。**buffer.c 也用 1.1**，保留了原版的 bug（见下文）。

RCS 1.1 只是 tytso 第一次 check-in 时的状态。如果他在那之前就改过某个文件，这里查不出来。

### 改动：用 0.11 的工具编译

0.10 的 Makefile 用的是 Minix 上的工具。为了在 0.11 上编译，改了这些地方：

- `AS86`/`LD86`：Minix 的 `as -0 -a`、`ld -0` 换成 `as86 -0 -a`、`ld86 -0`
- 删掉 `chmem +65000 tools/build`
- `tools/build` 改成 `./tools/build`（0.11 的 bash 1.05 不认带 `/` 的相对路径）
- 生成 `tmp.s` 的 SYSSIZE 规则：
  - `cut -c25-31` 改成 `-c34-41`。原规则是按 Minix ls 的输出格式写的；GNU ls 3.1 多一列 group，第 25–31 列正好是组名 `root`
  - `( … ) / 16` 改成 `[ … ] / 16`。as86 加了 `-a`（asld 兼容模式）后只能用方括号分组，圆括号会报 `factor expected`
- `boot/bootsect.s`、`boot/setup.s`：注释符 Minix asld 的 `|` 换成 as86 的 `!`，其余语法不变

规则里要用的 `cut` 和 `tr`，0.11 上没有，从 0.12 的二进制里带过去（GNU fileutils 的 cut、textutils 1.2 的 tr，系统调用都不超过 54 号）。

### kernel.flp

raw 盘：开头是 guest 脚本，后面是一个压缩 tar，内容是：

- `usr/src/linux-0.10`：上面还原、修改过的源码
- `usr/src/update-0.10`：0.10 原版的 `/bin/update`（`Linux-0.10/binaries/sbin/update.Z`）
- `usr/bin/cut`、`usr/bin/tr`

### 步骤

在 0.11 的硬盘系统里，B 放 `kernel.flp`：

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=4
sh /tmp/kinst src -a            # 解源码、update、cut、tr
cd /usr/src/linux-0.10; make
sh /tmp/kinst boot -a           # B 换空白盘：写 Image
sh /tmp/kinst root -a           # B 换空白盘：mkfs，放最小 root
```

每个子命令都可以先用 `-n` 只打印命令。

root 盘只放最小的一套：`/bin` 下有 sh、update、mkfs、mount、umount、mknod、fdisk；`/usr/bin` 下有 ls、cp、mv、mvdir、rm、rmdir、mkdir、cat、dd、chmod、sync。另外是 `/etc` 下的 profile、passwd、group、空的 mtab，以及设备节点 hd0–8、fd0/fd1、tty、tty0–3、null。程序都从 0.11 系统里拷，它们用到的系统调用 0.10 都有（0.10 只比 0.11 少 70、71 号 setreuid/setregid）。

启动：A 放 boot 盘，出现 `Insert root floppy and press ENTER` 后换 root 盘，按回车。boot 盘第 508 字节的 ROOT_DEV 是 0，意思是 root 和启动用的是同一种软盘。

### 0.10 和 0.11 的不同

- init 不读 `/etc/rc`，直接 fork 出 `/bin/update`（每 30 秒 sync 一次），再起 `/bin/sh`。shell 退出后 init 也退出，不会重新起 shell。
- 没有 ps。update 一般是 2 号进程（init 是 1，shell 是 3）。
- 软盘驱动比 0.11 弱：出错恢复简单，两个软驱同时用会冲突。

### buffer.c 1.1 的 bug

`getblk()` 回收一个空闲但还"脏"的缓冲块时，先把它从 hash 表里摘掉，再调用 `sync_dev()` 写盘，写盘时进程会睡眠。这时如果另一个进程恰好要读这个块原来对应的磁盘块，在 hash 表里找不到，就会另外分配一个缓冲块，从磁盘读到还没写回的旧内容，修改后再写回去。结果是前一个修改丢失。受影响的多半是位图、inode 表这类元数据，表现为文件系统损坏。

触发需要同时满足：所有缓冲块都已经用过一轮，开始回收；有两个进程同时在读写磁盘（管道也算两个进程）。Linus 在 1991-11-11 给出了修复（buffer.c 1.2）。

### 遇到的坑

- make 又重新生成了 tmp.s，把手工改好的那份覆盖了，只能改 Makefile。
- 0.11 硬盘上的 `/dev/null` 是普通文件，里面有东西，`cat /dev/null > 文件` 会把内容拷过去，见 [0.11](../0.11/) 的说明。脚本里改用 `> 文件`。

---

## English

The 0.10 (November 1991) boot and root diskette images did not survive; only the source did. This uses a [0.11](../0.11/) system installed on a hard disk to rebuild the 0.10 kernel from source and make a boot and a root diskette. All material comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files). The host only gathers files and builds floppies; compiling and making the diskettes happen inside the VM.

Tested on 86Box (Cx486SRx2, 8MB RAM, IDE disk 128 cylinders / 16 heads / 63 sectors): boot from the boot diskette, swap in the root diskette, get a shell, all without Minix. Installing to the hard disk is not done yet.

### Files

| File | Purpose |
|---|---|
| `mkkernel.sh` | host side: builds `kernel.flp` |
| `kinst.sh.in` | template of the guest script on `kernel.flp` (runs on 0.11) |

Host needs: bash, python3, gzip, tar, `compress` (ncompress package).

### Source: restoring Linus's original

The surviving `linux-0.10.tar.gz` is not Linus's release but Ted Ts'o's working tree from November–December 1991: every file is owned by `tytso`, there are RCS directories, and several files were modified. The RCS history shows three kinds of change:

- a later fix from Linus: `fs/buffer.c` 1.2 ("Used new version of buffer.c supplied from Linus")
- small fixes by tytso: the `+` in `ctype.h`'s `tolower()` that should be `-`, the waitpid exit code in `exit.c`
- "Patches sent to Linus" on December 1: `suser()`, uid/euid permission checks, sticky directories, setreuid/setregid (implemented but not added to the syscall table), the `alarm()` return value, `kill()` error codes, exec's `from_kmem`. Most of this went into 0.11.

There are also jtkohl's caps-lock-as-control patch, an unfinished `ramdisk.c` and `malloc.c` that no Makefile uses, and the boot rules tytso commented out to build on Minix.

`mkkernel.sh` puts every file under RCS back to revision 1.1 (the state tytso received it in) and removes the files he added. Files never put under RCS are read-only, dated no later than 1991-11-02, and are left alone. **buffer.c is also at 1.1**, so the original bug is kept (see below).

Revision 1.1 is only the state at tytso's first check-in. If he changed a file before that, it cannot be detected here.

### Changes: building with the 0.11 tools

The 0.10 Makefile expects Minix tools. To build on 0.11:

- `AS86`/`LD86`: Minix's `as -0 -a` and `ld -0` become `as86 -0 -a` and `ld86 -0`
- `chmem +65000 tools/build` is removed
- `tools/build` becomes `./tools/build` (0.11's bash 1.05 does not run relative paths containing `/`)
- the SYSSIZE rule that writes `tmp.s`:
  - `cut -c25-31` becomes `-c34-41`. The rule was written for Minix ls output; GNU ls 3.1 adds a group column, and columns 25–31 hold the group name `root`
  - `( … ) / 16` becomes `[ … ] / 16`. With `-a` (asld-compatible mode) as86 groups only with brackets; parentheses give `factor expected`
- `boot/bootsect.s`, `boot/setup.s`: Minix asld's `|` comment character becomes as86's `!`; the rest of the syntax is unchanged

The rule needs `cut` and `tr`, which 0.11 lacks; they come from the 0.12 binaries (cut from GNU fileutils, tr from textutils 1.2, both using syscalls no higher than 54).

### kernel.flp

A raw floppy: the guest script at the start, then a compressed tar with

- `usr/src/linux-0.10`: the restored and adapted source above
- `usr/src/update-0.10`: the original 0.10 `/bin/update` (`Linux-0.10/binaries/sbin/update.Z`)
- `usr/bin/cut`, `usr/bin/tr`

### Steps

On the 0.11 hard-disk system, with `kernel.flp` in drive B:

```
dd if=/dev/fd1 of=/tmp/kinst bs=1024 count=4
sh /tmp/kinst src -a            # unpack the source, update, cut, tr
cd /usr/src/linux-0.10; make
sh /tmp/kinst boot -a           # B = blank floppy: write Image
sh /tmp/kinst root -a           # B = blank floppy: mkfs, minimal root
```

Every sub-command accepts `-n` to print the commands without running them.

The root diskette holds a minimal set: sh, update, mkfs, mount, umount, mknod and fdisk in `/bin`; ls, cp, mv, mvdir, rm, rmdir, mkdir, cat, dd, chmod and sync in `/usr/bin`; profile, passwd, group and an empty mtab in `/etc`; device nodes hd0–8, fd0/fd1, tty, tty0–3 and null. The programs are copied from the 0.11 system; 0.10 has every syscall they use (it lacks only 0.11's 70 and 71, setreuid/setregid).

Boot: boot diskette in A; at `Insert root floppy and press ENTER` swap in the root diskette and press Enter. ROOT_DEV at offset 508 of the boot diskette is 0, meaning the same kind of floppy as the one booted from.

### 0.10 versus 0.11

- init does not read `/etc/rc`. It forks `/bin/update` (a sync every 30 seconds), then starts `/bin/sh`. When the shell exits, init exits too; no new shell is started.
- There is no ps. update is normally pid 2 (init is 1, the shell 3).
- The floppy driver is weaker than 0.11's: simple error recovery, and two drives in use at once conflict.

### The buffer.c 1.1 bug

When `getblk()` reclaims a free but dirty buffer, it first removes it from the hash table and then calls `sync_dev()` to write it, sleeping meanwhile. If another process now reads the disk block that buffer held, the hash lookup misses, so it takes another buffer, reads the not-yet-written old contents from disk, modifies them and writes them back. The first change is lost. The victims are mostly metadata such as bitmaps and inode tables, so the result is a corrupt filesystem.

It needs both: every buffer has been used once, so buffers are being reclaimed; and two processes doing disk I/O at the same time (a pipeline counts as two). Linus sent a fix on 1991-11-11 (buffer.c 1.2).

### Pitfalls

- make regenerated tmp.s and overwrote a hand-fixed copy, so the fix has to go into the Makefile.
- On the 0.11 hard disk `/dev/null` is a regular file with content, so `cat /dev/null > file` copies that content; see the [0.11](../0.11/) notes. The script uses `> file` instead.
