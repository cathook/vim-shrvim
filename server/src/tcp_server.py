"""TCP Server."""

import log
import select
import socket
import threading
import time

from json_package import JSONPackage
from json_package import JSONPackageError
from users_text_manager import AUTHORITY
from users_text_manager import UserInfo


FREQUENCY = 8

TIMEOUT = 5


class _JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
    BYE = 'bye'  # Resets the user and do nothong.
    CURSORS = 'cursors'  # other users' cursor position
    ERROR = 'error'  # error string
    IDENTITY = 'identity'  # identity of myself
    INIT = 'init'  # initialize connect flag
    MODE = 'mode'  # vim mode.
    NICKNAME = 'nickname'  # nick name of the user.
    OTHERS = 'others'  # other users info.
    TEXT = 'text'  # text content in the buffer


class TCPServer(threading.Thread):
    """A thread to be the tcp server.

    Attributes:
        _port: Port number.
        _sock: Socket fd.
        _users_text_manager: An instance of UsersTextManager.
        _stop_flag: Flag for stopping.
        _connection_handler_threads: List of connction handler threads.
    """
    def __init__(self, port, users_text_manager):
        """Constructor.

        Args:
            port: Port number.
            users_text_manager: An instance of UsersTextManager.
        """
        super(TCPServer, self).__init__()
        self._port = port
        self._sock = None
        self._users_text_manager = users_text_manager
        self._stop_flag = False
        self._connection_handler_threads = []

    @property
    def port(self):
        """Gets the port of this server.  None for unconnected case."""
        return self._port if self._sock else None

    def run(self):
        """Runs the thread."""
        self._build()
        self._accept()

    def stop(self):
        """Stops the thread."""
        self._stop_flag = True
        for thr in self._connection_handler_threads:
            thr.join()

    def _build(self):
        """Creates the socket."""
        timeout = 1
        while not self._stop_flag and not self._sock:
            try:
                self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self._sock.bind(('', self._port))
                self._sock.listen(1024)
            except socket.error as e:
                self._sock = None
                log.error(str(e) + '\n')
                log.info('Try it %d second(s) later.\n' % timeout)
                for _ in range(timeout * FREQUENCY):
                    if self._stop_flag:
                        break
                    time.sleep(float(1) / FREQUENCY)
                timeout *= 2
        if self._sock:
            log.info('Successfully built the tcp server.\n')

    def _accept(self):
        """Accepts the connection and calls the handler."""
        while not self._stop_flag:
            readable, _, _ = select.select([self._sock], [], [],
                                           float(1) / FREQUENCY)
            if readable:
                sock, addr = self._sock.accept()
                log.info('Client %r connect to server.\n' % str(addr))
                thr = _TCPConnectionHandler(sock, self._users_text_manager)
                thr.start()
                self._connection_handler_threads += [thr]


class TCPConnection(object):
    """My custom tcp connection.

    Args:
        _conn: The TCP-connection.
    """
    def __init__(self, conn):
        """Constructor.

        Args:
            conn: TCP-connection.
        """
        self._conn = conn
        self._conn.settimeout(TIMEOUT)

    def send(self, data):
        """Sends the data until timeout or the socket closed.

        Args:
            data: Data to be sent.
        """
        self._conn.sendall(data)

    def recv(self, nbyte):
        """Receives the data until timeout or the socket closed.

        Args:
            nbyte: Bytes of data to receive.

        Return:
            Bytes of data.
        """
        ret = b''
        while nbyte > 0:
            recv = self._conn.recv(nbyte)
            if not recv:
                raise socket.error('Connection die.')
            ret += recv
            nbyte -= len(recv)
        return ret

    def close(self):
        """Closes the connection."""
        self._conn.close()


class _TCPConnectionHandler(threading.Thread):
    """A thread to handle a connection.

    Attributes:
        _sock:  The connection socket.
        _users_text_manager: An instance of UsersTextManager.
    """
    def __init__(self, sock, users_text_manager):
        """Constructor.

        Args:
            sock: The connection socket.
            users_text_manager: An instance of UsersTextManager.
        """
        super(_TCPConnectionHandler, self).__init__()
        self._sock = TCPConnection(sock)
        self._users_text_manager = users_text_manager

    def run(self):
        """Runs the thread."""
        try:
            json_package = self._receive()
            json_info = self._sanitize(json_package.content)
            if json_info:
                self._handle(json_info)
            else:
                self._send({_JSON_TOKEN.ERROR : 'Invalid client.'})
        except JSONPackageError as e:
            log.error(str(e))
        except socket.error as e:
            log.error(str(e))
        self._sock.close()

    def _sanitize(self, request):
        """Sanitizes the request.

        Args:
            request: The request package.

        Return:
            Sanitized package.
        """
        identity = request[_JSON_TOKEN.IDENTITY]
        if identity not in self._users_text_manager.get_users_info():
            return None
        if request.get(_JSON_TOKEN.INIT) or request.get(_JSON_TOKEN.BYE, False):
            self._users_text_manager.reset_user(identity)
            request[_JSON_TOKEN.TEXT] = ''
            for mark in request.get(_JSON_TOKEN.CURSORS, []):
                request[_JSON_TOKEN.CURSORS][mark] = 0
            if _JSON_TOKEN.BYE in request:
                return None
        else:
            auth = self._users_text_manager.get_users_info()[identity].authority
            if auth < AUTHORITY.READWRITE:
                old_text = self._users_text_manager.get_user_text(identity)
                request[_JSON_TOKEN.TEXT] = old_text
        return request

    def _handle(self, request):
        """Handles the request.

        Args:
            request: The request package.
        """
        identity = request[_JSON_TOKEN.IDENTITY]
        text = request[_JSON_TOKEN.TEXT]
        user_info = UserInfo()
        user_info.mode = request[_JSON_TOKEN.MODE]
        user_info.cursors = request[_JSON_TOKEN.CURSORS]
        new_user_info, new_text = self._users_text_manager.update_user_text(
            identity, user_info, text)
        response = JSONPackage()
        response.content = {
            _JSON_TOKEN.TEXT : new_text,
            _JSON_TOKEN.CURSORS : new_user_info.cursors,
            _JSON_TOKEN.MODE : new_user_info.mode,
            _JSON_TOKEN.OTHERS : [
                {_JSON_TOKEN.NICKNAME : other.nick_name,
                 _JSON_TOKEN.MODE : other.mode,
                 _JSON_TOKEN.CURSORS: other.cursors}
                for iden, other in self._users_text_manager.get_users_info(
                    without=[identity], must_online=True).items()]
        }
        response.send_to(self._sock)


    def _receive(self):
        """Receive a request.

        Return:
            The request package.
        """
        request = JSONPackage()
        request.recv_from(self._sock)
        return request

    def _send(self, pkg):
        """Sends a response.

        Args:
            pkg: The package to be sent.
        """
        response = JSONPackage()
        response.content = pkg
        response.send_to(self._sock)
