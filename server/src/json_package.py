"""Contains tcp package object."""

import json
import zlib


class JSONPackageError(Exception):
    """Error raised by JSONPackage."""
    pass

class JSONPackage(object):
    """Send/receive json by tcp connection.

    Attribute:
        content: Content of the package body.
    """
    ENCODING = 'utf-8'
    COMPRESS_LEVEL = 2
    HEADER_LENGTH = 10
    def __init__(self):
        """Constructor."""
        self.content = None

    def send_to(self, fd):
        """Sends a string to the tcp-connection.

        Args:
            fd: Socket fd.
        """
        try:
            string = json.dumps(self.content)
            body = JSONPackage._create_body_from_string(string)
            header = JSONPackage._create_header_from_body(body)
            fd.send(header + body)
        except TypeError as e:
            raise JSONPackageError('json: %r' % e)

    def recv_from(self, fd):
        """Receives a string from the tcp-connection.

        Args:
            fd: Socket fd.
        """
        header = JSONPackage._recv_header_string(fd)
        body = JSONPackage._recv_body_string(fd, header)
        try:
            self.content = json.loads(body)
        except ValueError as e:
            raise JSONPackageError('Cannot loads to the json object: %r' % e)

    @staticmethod
    def _create_body_from_string(string):
        """Creates package body from data string.

        Args:
            string: Data string.

        Returns:
            Package body.
        """
        byte_string = string.encode(JSONPackage.ENCODING)
        return zlib.compress(byte_string, JSONPackage.COMPRESS_LEVEL)

    @staticmethod
    def _create_header_from_body(body):
        """Creates package header from package body.

        Args:
            body: Package body.

        Returns:
            Package header.
        """
        header_string = ('%%0%dd' % JSONPackage.HEADER_LENGTH) % len(body)
        return header_string.encode(JSONPackage.ENCODING)

    @staticmethod
    def _recv_header_string(conn):
        """Receives package header from specified tcp connection.

        Args:
            conn: The specified tcp connection.

        Returns:
            Package header.
        """
        try:
            byte = conn.recv(JSONPackage.HEADER_LENGTH)
            return byte.decode(JSONPackage.ENCODING)
        except UnicodeError as e:
            raise JSONPackageError('Cannot decode the header string: %r.' % e)

    @staticmethod
    def _recv_body_string(conn, header):
        """Receives package body from specified tcp connection and header.

        Args:
            conn: The specified tcp connection.
            header: The package header.

        Returns:
            Package body.
        """
        try:
            body_length = int(header)
            body = conn.recv(body_length)
            body_byte = zlib.decompress(body)
            return body_byte.decode(JSONPackage.ENCODING)
        except UnicodeError as e:
            raise JSONPackageError('Cannot decode the body string: %r.' % e)
        except ValueError as e:
            raise JSONPackageError('Cannot get the body_length: %r' % e)
        except zlib.error as e:
            raise JSONPackageError('Cannot decompress the body: %r.' % e)
