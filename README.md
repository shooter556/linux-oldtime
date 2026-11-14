# linux-oldtime

[中文](#中文) | [English](#english)

## 中文

在模拟器里折腾早期 Linux（1991–1992）的记录、脚本和工具。每个版本一个子目录，原始材料都来自 [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files)。

| 目录 | 内容 |
|---|---|
| [0.10](0.10/) | 在 0.11 上从源码（还原成 Linus 原版）重编 0.10，做出 boot/root 盘；不靠 Minix 装到硬盘；装上 gcc 后在 0.10 里重编内核，并从源码编了 grep、diff、bison、fileutils、make、sed |
| [0.11](0.11/) | 把 0.11 装到硬盘，用 0.11 自己的 gcc 重编 fileutils 修好 root 盘，再重编内核 |
| [0.12](0.12/) | 用两张自制软盘把 0.12 装到硬盘，再用 gcc 1.40 重新编译内核 |

## English

Notes, scripts and tools from running early Linux (1991–1992) in emulators. Each version has its own directory; all original material comes from [oldlinux-files](https://github.com/oldlinux-web/oldlinux-files).

| Directory | Contents |
|---|---|
| [0.10](0.10/) | Rebuild 0.10 from source (restored to Linus's original) on 0.11, make boot/root diskettes, install to hard disk without Minix; with gcc, 0.10 rebuilds its own kernel and builds grep, diff, bison, fileutils, make and sed from source |
| [0.11](0.11/) | Install 0.11 to a hard disk, rebuild fileutils with 0.11's own gcc to repair the root diskette, then rebuild the kernel |
| [0.12](0.12/) | Install 0.12 to a hard disk from two home-made floppies, then rebuild the kernel with gcc 1.40 |
