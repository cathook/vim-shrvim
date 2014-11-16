"""JSONPackage"""

import json


class JSONPackageError(Exception):
    """Error raised by JSONPackage."""
    pass

class JSONPackage(object):
    """Send/receive json object by gived function.

    Attributes:
        content: Content of the package body.

    Static attributes:
        _ENCODING: Encoding of the package.
        _HEADER_LENGTH: Length of the header.
    """
    _ENCODING = 'utf-8'
    _HEADER_LENGTH = 10
    def __init__(self, content=None, recv_func=None):
        """Constructor.

        If the receive_func is not None, it will grap the default content by
        calling that function instead of by the argument "content".

        The detail of arguments/return values format see the method "recv_from".

        Args:
            content: The default content of this package.
            recv_func: A function for receive the default content.
        """
        self.content = content
        if recv_func is not None:
            self.recv(recv_func)

    def send(self, send_func):
        """Sends by calling the gived sending function.

        Args:
            send_func: A function which will send the whole data gived.
                Function format:
                    send_func(bytes_data): None
        """
        try:
            body = bytes(json.dumps(self.content), JSONPackage._ENCODING)
            header_str = ('%%0%dd' % JSONPackage._HEADER_LENGTH) % len(body)
            send_func(bytes(header_str, JSONPackage._ENCODING) + body)
        except TypeError as e:
            raise JSONPackageError('json: %r' % e)
        except UnicodeError as e:
            raise JSONPackageError('Cannot encode the string: %r.' % e)

    def recv(self, recv_func):
        """Receives a json object from a gived function.

        It will calls the give function like this:
            recv_func(<num_of_bytes>) => bytes with length <num_of_bytes>

        Args:
            recv_func: A function to be called to get the serialize data.
        """
        try:
            header_str = str(recv_func(JSONPackage._HEADER_LENGTH),
                             JSONPackage._ENCODING)
            body_str = str(recv_func(int(header_str)), JSONPackage._ENCODING)
        except UnicodeError as e:
            raise JSONPackageError('Cannot decode the bytes: %r.' % e)
        except ValueError as e:
            raise JSONPackageError('Cannot get the body length %r' % e)
        try:
            self.content = json.loads(body_str)
        except ValueError as e:
            raise JSONPackageError('Cannot loads to the json object: %r' % e)
