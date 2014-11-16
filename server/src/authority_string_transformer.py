"""For transformating the type of authroity."""

from users_text_manager import AUTHORITY


_mappings = [
    (AUTHORITY.READONLY, 'RO'),
    (AUTHORITY.READWRITE, 'RW'),
]


class Error(Exception):
    """Error raised by AuthorityStringTransformer."""
    pass


def to_string(authority):
    """Transform number authority value to string value.

    Args:
        authority: Authority in number format.

    Return:
        Corrosponding authority in string format.
    """
    for item in _mappings:
        if item[0] == authority:
            return item[1]
    raise Error('Invalid number.')


def to_number(string):
    """Transform string authority value to number value.

    Args:
        authority: Authority in string format.

    Return:
        Corrosponding authority in number format.
    """
    for item in _mappings:
        if item[1] == string:
            return item[0]
    raise Error('Invalid string.')
