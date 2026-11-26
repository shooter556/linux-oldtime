# tools — run Linux 0.1x/0.95 programs on the host

[中文](#中文) | [English](#english)

---

## 中文

在主机上直接运行 Linux 0.11–0.95 的 a.out 程序（gcc、make、sh、compress 等），软盘交给虚拟机之前先确认能编过、能解压。只模拟用户态，不跑内核，也不需要 86Box。

| 文件 | 说明 |
|---|---|
| `l01` | 入口脚本。第一次用时在 `tools/.venv` 建虚拟环境并装 [unicorn](https://www.unicorn-engine.org/)，换机器只需要 python3 |
| `l01run.py` | 用 unicorn 运行 ZMAGIC a.out，把系统调用转给主机 |
| `minixget.py` | 把 Minix v1 文件系统（硬盘某个分区或软盘）解到主机目录 |

```sh
tools/l01 get -i c.img -p 2 -o hd012            # 解出 0.12 硬盘的 hda2
H=$PWD/hd012; T=$PWD/tools                      # L01ROOT 要绝对路径
cd $H/usr/src/0.95 && L01ROOT=$H $T/l01 run /usr/bin/make fileutils
$T/l01 -s                                       # 只重建虚拟环境
```

`L01ROOT` 把 guest 的 `/` 映射到主机目录；guest 里的绝对路径都落在这个目录下面。

- l01run：支持 fork/exec/wait、管道、读目录（按 minix 16 字节目录项伪造）、bash 1.12 用的 SIGCHLD（sigsuspend），以及 symlink、lstat、readlink。exec 时把 guest 的环境变量传给新进程（主机上经 `L01ENV` 传递）。
- minixget：保留权限、修改时间和硬链接；跳过设备文件和 FIFO；指向绝对路径的软链接改写成指向解包目录内部，主机解析时就不会跑出去。

限制：

- `gettimeofday`（78 号）没有实现，`ls -l` 会打印 `unhandled syscall 78`，不影响结果。
- guest 在运行时新建的、指向绝对路径的软链接，主机会按主机的根目录解析，在模拟器里读不到；真实系统里没有这个问题。
- 在 `L01ROOT` 之外的相对路径会被限制到 `L01ROOT`，所以要在解包目录里面工作。
- 某一步失败后，`cat x.tab.c > x.c` 这类重定向会留下空文件，下一次 make 会认为它是新的；重试前要换一份干净的源码。

---

## English

Run Linux 0.11–0.95 a.out programs (gcc, make, sh, compress, …) directly on the host, to check that a build or a decompression works before the floppies go to the VM. User mode only: no kernel, no 86Box.

| File | Purpose |
|---|---|
| `l01` | Entry script. On first use it creates `tools/.venv` with [unicorn](https://www.unicorn-engine.org/), so a fresh machine needs only python3 |
| `l01run.py` | Runs ZMAGIC a.out binaries with unicorn, passing system calls to the host |
| `minixget.py` | Extracts a Minix v1 filesystem (a hard disk partition or a floppy) into a host directory |

```sh
tools/l01 get -i c.img -p 2 -o hd012            # extract hda2 of a 0.12 hard disk
H=$PWD/hd012; T=$PWD/tools                      # L01ROOT must be absolute
cd $H/usr/src/0.95 && L01ROOT=$H $T/l01 run /usr/bin/make fileutils
$T/l01 -s                                       # only recreate the venv
```

`L01ROOT` maps the guest `/` onto a host directory; absolute guest paths land under it.

- l01run: fork/exec/wait, pipes, directory reads (faked as 16-byte minix entries), SIGCHLD via sigsuspend for bash 1.12, and symlink, lstat, readlink. exec passes the guest environment on to the new process (through `L01ENV` on the host).
- minixget: keeps modes, mtimes and hard links; skips device nodes and FIFOs; absolute symlink targets are rewritten to point inside the output directory, so the host resolves them within it.

Limits:

- `gettimeofday` (78) is not implemented; `ls -l` prints `unhandled syscall 78`, the output is still right.
- A symlink to an absolute path created by the guest at run time resolves against the host root, so it cannot be read in the emulator; a real system has no such problem.
- Relative paths outside `L01ROOT` are clamped to `L01ROOT`, so work inside the extracted tree.
- After a failed step, a redirect such as `cat x.tab.c > x.c` leaves an empty file that the next make takes as up to date; retry from a clean copy of the source.
