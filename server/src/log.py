"""Log information handler."""

import sys
import threading


_lock = threading.Lock()


def info(string):
    """Prints the informations string to the interface.

    Args:
        string: String to be printed.
    """
    with _lock:
        info.interface.write(string)
        info.interface.flush()

info.interface = sys.stdout  # Interface of the info string to be printed at.


def error(string):
    """Prints the error string to the interface.

    Args:
        string: String to be printed.
    """
    with _lock:
        error.interface.write(string)
        error.interface.flush()

error.interface = sys.stderr  # Interface of the error string to be printed at.
