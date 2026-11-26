#!/usr/bin/env python3
# Minimal user-mode runner for Linux 0.1x ZMAGIC a.out binaries (unicorn).
# usage: l01run.py [-C|--chdir DIR] BINARY ARGS...   (stdin/stdout/stderr passed through)
import sys, os, struct, errno
from unicorn import *
from unicorn.x86_const import *

args = sys.argv[1:]
if not args or args[0] in ('-h', '--help'):
    print('usage: l01run.py [-C DIR] BINARY ARGS...  (L01ROOT=DIR maps the guest / into DIR)'); sys.exit(0)
if args[0] in ('-C', '--chdir'):
    os.chdir(args[1]); args = args[2:]
ROOT = os.environ.get('L01ROOT', '')
def P(x):
    if not ROOT: return x
    h = os.path.normpath(ROOT + x if x.startswith('/') else os.path.join(os.getcwd(), x))
    return h if h == ROOT or h.startswith(ROOT + '/') else ROOT
path = args[0]
d = open(P(path), 'rb').read()
magic, a_text, a_data, a_bss = struct.unpack('<4I', d[:16])
assert magic & 0xffff == 0o413, oct(magic)
MEM = 0x4000000
mu = Uc(UC_ARCH_X86, UC_MODE_32)
mu.mem_map(0, MEM)
MAGIC = 0x5000000
mu.mem_map(MAGIC, 0x1000); mu.mem_write(MAGIC, b'\x90' * 16)
handlers = {}; saved = []
REGS = [UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI,
        UC_X86_REG_EDI, UC_X86_REG_EBP, UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EFLAGS]
def hook_magic(uc, addr, size, _):
    v = saved.pop()
    for r, x in zip(REGS, v): uc.reg_write(r, x)
    uc.reg_write(UC_X86_REG_EAX, (-errno.EINTR) & 0xffffffff)
mu.mem_write(0, d[1024:1024 + a_text + a_data])
brk = a_text + a_data + a_bss

# the guest environment travels across exec in L01ENV (0x1f-separated)
envs = [e.encode('latin-1') for e in os.environ['L01ENV'].split('\x1f')] if os.environ.get('L01ENV') \
    else [b'PATH=/usr/local/bin:/bin:/usr/bin', b'HOME=/']
argv = [a.encode() for a in args]
sp = MEM
ptrs = []
for s in argv + envs:
    sp -= len(s) + 1
    mu.mem_write(sp, s + b'\0'); ptrs.append(sp)
sp &= ~3
ap, ep = ptrs[:len(argv)], ptrs[len(argv):]
tbl = ap + [0] + ep + [0]
sp -= 4 * len(tbl)
argv_at = sp; envp_at = sp + 4 * (len(ap) + 1)
mu.mem_write(sp, struct.pack('<%dI' % len(tbl), *tbl))
sp -= 12
mu.mem_write(sp, struct.pack('<3I', len(ap), argv_at, envp_at))
mu.reg_write(UC_X86_REG_ESP, sp)

fds = {0: 0, 1: 1, 2: 2}
def rawstr(a):
    b = mu.mem_read(a, min(1024, MEM - a)); return bytes(b[:b.index(0)]).decode('latin-1')
def cstr(a): return P(rawstr(a))
def strv(a):
    r = []
    while True:
        q = struct.unpack('<I', mu.mem_read(a, 4))[0]
        if not q: return r
        r.append(rawstr(q)); a += 4
def stat_pack(st):
    return struct.pack('<HHHBxHBxHxxIIII', st.st_dev & 0xffff, st.st_ino & 0xffff, st.st_mode & 0xffff,
                       min(st.st_nlink, 255), st.st_uid & 0xffff, st.st_gid & 0xff, 0, st.st_size,
                       int(st.st_atime), int(st.st_mtime), int(st.st_ctime))
trace = os.environ.get('L01TRACE')

def sysc(n, b, c, dd):
    global brk
    if trace: print('sys', n, hex(b), hex(c), hex(dd), rawstr(b) if n in (5, 12, 18, 33, 11) else '', file=sys.stderr)
    if n == 1: sys.stdout.flush(); os._exit(b & 0xff)
    if n == 3: return rd(b, c, dd)
    if n == 4: return os.write(fds[b], bytes(mu.mem_read(c, dd)))
    if n in (5, 8):
        fl = c if n == 5 else 0o1101
        nf = min(set(range(20)) - set(fds))
        pth = cstr(b)
        if n == 5 and os.path.isdir(pth) and fl & 3 == 0:
            ents = [(os.stat(pth).st_ino, '.'), (os.stat(P(rawstr(b) + '/..')).st_ino, '..')]
            ents += [(os.lstat(pth + '/' + e).st_ino, e) for e in os.listdir(pth)]
            r, w = os.pipe()
            blob = b''.join(struct.pack('<H', i & 0xffff or 1) + e.encode()[:14].ljust(14, b'\0') for i, e in ents)
            dirbufs[nf] = [blob, 0, pth]; fds[nf] = r; os.close(w); return nf
        fds[nf] = os.open(pth, fl & 0o7777, (dd if n == 5 else c) & 0o7777); return nf
    if n == 12: os.chdir(cstr(b)); return 0
    if n == 6: dirbufs.pop(b, None); os.close(fds.pop(b)); return 0
    if n == 10: os.unlink(cstr(b)); return 0
    if n == 2:
        sys.stdout.flush(); sys.stderr.flush()
        return os.fork()
    if n == 7:
        pid, st = os.waitpid(b if b < 0x80000000 else -1, dd)
        code = os.waitstatus_to_exitcode(st)
        w = (code & 0xff) << 8 if code >= 0 else -code
        if c: mu.mem_write(c, struct.pack('<I', w))
        return pid
    if n == 11:
        prog = rawstr(b); av = strv(c); os.environ['L01ENV'] = '\x1f'.join(strv(dd)) if dd else ''
        if not os.path.exists(P(prog)): return -errno.ENOENT
        tmp = {k: os.dup(v) for k, v in fds.items()}
        for v in set(fds.values()): os.close(v)
        for k, v in tmp.items(): os.dup2(v, k); os.close(v)
        os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), prog] + av[1:])
    if n == 37: return 0
    if n == 67:
        old = handlers.get(b, 0)
        if c: handlers[b] = struct.unpack('<I', mu.mem_read(c, 4))[0]
        if dd: mu.mem_write(dd, struct.pack('<I', old) + b'\0' * 12)
        return 0
    if n == 72:
        h = handlers.get(17, 0)
        if h > 1:
            try: os.waitid(os.P_ALL, 0, os.WEXITED | os.WNOWAIT)
            except ChildProcessError: return -errno.EINTR
            saved.append([mu.reg_read(r) for r in REGS])
            sp = mu.reg_read(UC_X86_REG_ESP) - 64
            mu.mem_write(sp, struct.pack('<2I', MAGIC, 17))
            mu.reg_write(UC_X86_REG_ESP, sp); mu.reg_write(UC_X86_REG_EIP, h)
            return None
        return -errno.EINTR
    if n in (55, 57, 66, 68, 69): return 0
    if n in (64, 65): return os.getpid()
    if n == 59: mu.mem_write(b, b''.join(x.ljust(9, b'\0') for x in (b'Linux', b'l095', b'0.95', b'0', b'i386'))); return 0
    if n == 63:
        if c in fds: os.close(fds[c])
        fds[c] = os.dup(fds[b]); return c
    if n == 42:
        r, w = os.pipe(); a = min(set(range(20)) - set(fds)); fds[a] = r
        bb = min(set(range(20)) - set(fds)); fds[bb] = w
        mu.mem_write(b, struct.pack('<2I', a, bb)); return 0
    if n == 13:
        import time; t = int(time.time())
        if b: mu.mem_write(b, struct.pack('<I', t))
        return t
    if n == 15: os.chmod(cstr(b), c); return 0
    if n == 18: mu.mem_write(c, stat_pack(os.stat(cstr(b)))); return 0
    if n == 19 and b in dirbufs:
        dirbufs[b][1] = c + (dirbufs[b][1] if dd == 1 else 0); return dirbufs[b][1]
    if n == 19: return os.lseek(fds[b], struct.unpack('<i', struct.pack('<I', c))[0], dd)
    if n == 20: return os.getpid()
    if n in (23, 24, 46, 47, 49, 50, 70, 71): return 0
    if n == 28 and b in dirbufs: mu.mem_write(c, stat_pack(os.stat(dirbufs[b][2]))); return 0
    if n == 28: mu.mem_write(c, stat_pack(os.fstat(fds[b]))); return 0
    if n == 30:
        if c: a, m = struct.unpack('<2I', mu.mem_read(c, 8)); os.utime(cstr(b), (a, m))
        return 0
    if n == 16: return 0
    if n == 9: os.link(cstr(b), cstr(c)); return 0
    if n == 83: os.symlink(rawstr(b), cstr(c)); return 0
    if n == 84: mu.mem_write(c, stat_pack(os.lstat(cstr(b)))); return 0
    if n == 85:
        t = os.readlink(cstr(b)).encode('latin-1')[:dd]
        if ROOT and t.startswith(ROOT.encode() + b'/'): t = t[len(ROOT):]
        mu.mem_write(c, t); return len(t)
    if n == 33: os.access(cstr(b), c & 7) or (_ for _ in ()).throw(OSError(errno.EACCES, '')); return 0
    if n == 41:
        nf = min(set(range(20)) - set(fds)); fds[nf] = os.dup(fds[b]); return nf
    if n == 45:
        if b >= brk and b < MEM - 0x100000: brk = b
        return brk
    if n == 48:
        old = handlers.get(b, 0); handlers[b] = c; return old
    if n == 54: return -errno.ENOTTY
    if n == 60: return 0o22
    print('unhandled syscall', n, file=sys.stderr); return -errno.ENOSYS

dirbufs = {}
def rd(fd, buf, cnt):
    if fd in dirbufs:
        bl, pos = dirbufs[fd][:2]; r = bl[pos:pos + cnt]; dirbufs[fd][1] += len(r)
        mu.mem_write(buf, r); return len(r)
    r = os.read(fds[fd], cnt); mu.mem_write(buf, r); return len(r)

def hook_intr(uc, intno, _):
    if intno != 0x80:
        print('interrupt', intno, hex(uc.reg_read(UC_X86_REG_EIP)), file=sys.stderr); os._exit(99)
    n, b, c, dd = (uc.reg_read(r) for r in (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX))
    try:
        r = sysc(n, b, c, dd)
    except OSError as e:
        r = -e.errno
    except KeyError:
        r = -errno.EBADF
    if r is not None: uc.reg_write(UC_X86_REG_EAX, r & 0xffffffff)

mu.hook_add(UC_HOOK_INTR, hook_intr)
mu.hook_add(UC_HOOK_CODE, hook_magic, begin=MAGIC, end=MAGIC)
mu.emu_start(struct.unpack('<8I', d[:32])[5], 0xffffffff)
