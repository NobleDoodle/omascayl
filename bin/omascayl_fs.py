"""Safe file operations for Omascayl's helpers (bin/omascayl-integrate,
bin/omascayl-store, and the launcher stub, which embeds a copy of this file).

Writes and deletes are made relative to directory handles opened without
following symlinks and checked to be the user's own, below a base directory
the user configured (HOME, XDG_DATA_HOME, XDG_STATE_HOME). New files go
through a random O_CREAT|O_EXCL|O_NOFOLLOW temporary that is fsynced and
renamed into place within the same directory. Reads are bounded and never
block on a FIFO. Helper programs run by absolute path, with a time limit.
"""

import os
import secrets
import shutil
import stat
import subprocess

TRUSTED_PATH = "/usr/bin:/usr/share/omarchy/bin"
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def base_dir(path):
    """Open a base directory the user configured; it must be the user's own."""
    if not isinstance(path, str) or not os.path.isabs(path):
        raise OSError("not an absolute path: %r" % (path,))
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    if os.fstat(fd).st_uid != os.getuid():
        os.close(fd)
        raise OSError("not owned by the user: %s" % path)
    return fd


def sub_dir(parent, parts, create):
    """Walk parts below parent: no symlinks, every directory the user's own."""
    fd = os.dup(parent)
    for part in parts:
        if part in ("", ".", "..") or "/" in part:
            os.close(fd)
            raise OSError("bad path component: %r" % (part,))
        try:
            nxt = os.open(part, DIR_FLAGS, dir_fd=fd)
        except FileNotFoundError:
            if not create:
                os.close(fd)
                raise
            try:
                os.mkdir(part, 0o755, dir_fd=fd)
                nxt = os.open(part, DIR_FLAGS, dir_fd=fd)
            except OSError:
                os.close(fd)
                raise
        except OSError:
            os.close(fd)
            raise
        os.close(fd)
        fd = nxt
        if os.fstat(fd).st_uid != os.getuid():
            os.close(fd)
            raise OSError("not owned by the user: %s" % part)
    return fd


def read_small(dirfd, name, limit=1 << 20):
    """A regular file's bytes, or None: no symlinks, no FIFOs, bounded."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dirfd)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
            return None
        return os.read(fd, limit + 1)
    finally:
        os.close(fd)


def exists(dirfd, name):
    try:
        os.stat(name, dir_fd=dirfd, follow_symlinks=False)
        return True
    except FileNotFoundError:
        return False


def readlink_or_none(dirfd, name):
    try:
        return os.readlink(name, dir_fd=dirfd)
    except OSError:
        return None


def temp_name(name):
    return ".%s.%s" % (name, secrets.token_hex(8))


def create_temp(dirfd, name, mode):
    """A new random temporary next to name: (fd, tmpname)."""
    tmp = temp_name(name)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, mode, dir_fd=dirfd)
    return fd, tmp


def write_file(dirfd, name, data, mode):
    """Replace dirfd/name with data unless it already holds exactly that.
    Returns whether anything changed."""
    if read_small(dirfd, name) == data:
        try:
            if stat.S_IMODE(os.stat(name, dir_fd=dirfd, follow_symlinks=False).st_mode) == mode:
                return False
        except OSError:
            pass
    fd, tmp = create_temp(dirfd, name, mode)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fchmod(fd, mode)
        os.fsync(fd)
    except BaseException:
        os.close(fd)
        os.unlink(tmp, dir_fd=dirfd)
        raise
    os.close(fd)
    os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
    os.fsync(dirfd)
    return True


def link_to(dirfd, name, target):
    """Make dirfd/name a symlink to target, replacing what is there atomically."""
    tmp = temp_name(name)
    os.symlink(target, tmp, dir_fd=dirfd)
    os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)


def remove(dirfd, name):
    """Remove dirfd/name whatever it is, never following a symlink.
    shutil.rmtree with dir_fd is the symlink-attack-safe variant."""
    try:
        st = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if stat.S_ISDIR(st.st_mode):
        shutil.rmtree(name, dir_fd=dirfd)
    else:
        os.unlink(name, dir_fd=dirfd)


def run_tool(argv, timeout=10):
    """Run a helper by absolute path, bounded: update-desktop-database, for
    one, reads every file in the applications folder and would block on a
    FIFO there."""
    if not os.path.isabs(argv[0]) or not os.access(argv[0], os.X_OK):
        return
    try:
        subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=timeout,
                       env=dict(os.environ, PATH=TRUSTED_PATH))
    except (OSError, subprocess.SubprocessError):
        pass


def data_home():
    home = os.environ.get("HOME", "")
    path = os.environ.get("XDG_DATA_HOME", "")
    return path if os.path.isabs(path) else os.path.join(home, ".local", "share")


def state_home():
    home = os.environ.get("HOME", "")
    path = os.environ.get("XDG_STATE_HOME", "")
    return path if os.path.isabs(path) else os.path.join(home, ".local", "state")


def open_base(path, home_parts):
    """Open a base directory, creating it below HOME if it does not exist."""
    if os.path.isdir(path):
        return base_dir(path)
    home = base_dir(os.environ.get("HOME", ""))
    try:
        if os.path.join(os.environ["HOME"], *home_parts) != path:
            raise OSError("missing base directory: %s" % path)
        return sub_dir(home, home_parts, True)
    finally:
        os.close(home)
