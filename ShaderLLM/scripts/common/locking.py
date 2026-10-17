"""Nonblocking file locks shared by the launcher and Minecraft world checks."""

from contextlib import contextmanager
import errno
import os


def _lock(stream, shared, release=False):
    stream.seek(0)
    if os.name == "nt":
        _windows_lock(stream, shared, release)
    else:
        import fcntl

        mode = (
            fcntl.LOCK_UN
            if release
            else ((fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB)
        )
        fcntl.lockf(stream, mode, 1, 0, os.SEEK_SET)


def _windows_lock(stream, shared, release):
    import ctypes
    from ctypes import wintypes
    import msvcrt

    class Overlapped(ctypes.Structure):
        _fields_ = [
            ("Internal", ctypes.c_size_t),
            ("InternalHigh", ctypes.c_size_t),
            ("Offset", wintypes.DWORD),
            ("OffsetHigh", wintypes.DWORD),
            ("hEvent", wintypes.HANDLE),
        ]

    # LockFileEx supplies the shared byte-range locks used for world reads.
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    overlapped = Overlapped()
    handle = msvcrt.get_osfhandle(stream.fileno())
    if release:
        function = kernel.UnlockFileEx
        function.argtypes = [
            wintypes.HANDLE,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.DWORD,
            ctypes.POINTER(Overlapped),
        ]
        arguments = (handle, 0, 1, 0, ctypes.byref(overlapped))
    else:
        function = kernel.LockFileEx
        function.argtypes = [
            wintypes.HANDLE,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.DWORD,
            ctypes.POINTER(Overlapped),
        ]
        flags = 1 | (0 if shared else 2)  # FAIL_IMMEDIATELY, EXCLUSIVE_LOCK
        arguments = (handle, flags, 0, 1, 0, ctypes.byref(overlapped))
    function.restype = wintypes.BOOL
    if not function(*arguments):
        raise ctypes.WinError(ctypes.get_last_error())


@contextmanager
def file_lock(path, *, shared=False, create=False):
    with path.open("a+b" if create else ("rb" if shared else "r+b")) as stream:
        if create and stream.seek(0, os.SEEK_END) == 0:
            stream.write(b"\0")
            stream.flush()
        try:
            _lock(stream, shared)
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                raise RuntimeError(
                    f"File is in use by another process: {path}"
                ) from error
            raise
        try:
            yield
        finally:
            _lock(stream, shared, release=True)
