# linux-oldtime

[中文](#中文) | [English](#english)

## 中文

在模拟器里折腾早期 Linux（1991–1992）的记录、脚本和工具。每个版本一个子目录，原始材料都来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)。

| 目录 | 内容 |
|---|---|
| [0.10](0.10/) | 在 0.11 上从源码（还原成 Linus 原版）重编 0.10，做出 boot/root 盘；不靠 Minix 装到硬盘；装上 gcc 后在 0.10 里重编内核，并从源码编了 grep、diff、bison、fileutils、make、sed |
| [0.11](0.11/) | 把 0.11 装到硬盘，用 0.11 自己的 gcc 重编 fileutils 修好 root 盘，再重编内核 |
| [0.12](0.12/) | 用两张自制软盘把 0.12 装到硬盘，再用 gcc 1.40 重新编译内核 |
| [0.95](0.95/) | 在 0.12 上用 gcc 2.0 从源码做出美式键盘的 0.95 boot 盘，并以 RELNOTES 为基础重做 root 盘（另加 vi、df、tar 等）；再装到硬盘（含 gcc 2.0），用 ShoeLace 从硬盘启动 |
| [tools](tools/) | 在主机上直接运行 0.11–0.95 的程序（l01run，基于 unicorn），以及解开 Minix 文件系统；软盘交给虚拟机之前先在主机上试编 |

## English

Notes, scripts and tools from running early Linux (1991–1992) in emulators. Each version has its own directory; all original material comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files).

| Directory | Contents |
|---|---|
| [0.10](0.10/) | Rebuild 0.10 from source (restored to Linus's original) on 0.11, make boot/root diskettes, install to hard disk without Minix; with gcc, 0.10 rebuilds its own kernel and builds grep, diff, bison, fileutils, make and sed from source |
| [0.11](0.11/) | Install 0.11 to a hard disk, rebuild fileutils with 0.11's own gcc to repair the root diskette, then rebuild the kernel |
| [0.12](0.12/) | Install 0.12 to a hard disk from two home-made floppies, then rebuild the kernel with gcc 1.40 |
| [0.95](0.95/) | Build a US-keyboard 0.95 boot diskette from source with gcc 2.0 on 0.12, and rebuild the root diskette from the RELNOTES (plus vi, df, tar and more); then install to the hard disk (with gcc 2.0), booting with ShoeLace |
| [tools](tools/) | Run 0.11–0.95 programs directly on the host (l01run, on unicorn) and extract Minix filesystems; try builds on the host before the floppies go to the VM |
