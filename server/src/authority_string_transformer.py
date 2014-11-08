"""AuthroityStringTransformer."""

from users_text_manager import AUTHORITY


class AuthorityStringTransformerError(Exception):
    """Error raised by AuthorityStringTransformer."""
    pass

class AuthorityStringTransformer:  # pylint:disable=W0232
    """Transforms authority between number and strin format."""
    @staticmethod
    def to_string(authority):
        """Transform number authority value to string value.

        Args:
            authority: Authority in number format.

        Returns:
            authority: Corrosponding authority in string format.
        """
        if authority == AUTHORITY.READONLY:
            return 'RO'
        elif authority == AUTHORITY.READWRITE:
            return 'RW'
        raise AuthorityStringTransformerError('Invalid number.')

    @staticmethod
    def to_number(string):
        """Transform string authority value to number value.

        Args:
            authority: Authority in string format.

        Returns:
            authority: Corrosponding authority in number format.
        """
        if string == 'RO':
            return AUTHORITY.READONLY
        elif string == 'RW':
            return AUTHORITY.READWRITE
        raise AuthorityStringTransformerError('Invalid string.')
