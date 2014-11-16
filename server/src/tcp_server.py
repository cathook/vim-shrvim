"""TCP Server."""

import log
import select
import socket
import threading
import time

from json_package import JSONPackage
from json_package import JSONPackageError
from request_handler import RequestHandler


FREQUENCY = 8
TIMEOUT = 1


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
            thr.stop()
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


class _TCPConnectionHandler(threading.Thread):
    """A thread to handle a connection.

    Attributes:
        _sock:  The connection socket.
        _users_text_manager: An instance of UsersTextManager.
        _stop_flag: Stopping flag.
    """
    def __init__(self, conn, users_text_manager):
        """Constructor.

        Args:
            conn: The connection.
            users_text_manager: An instance of UsersTextManager.
        """
        super(_TCPConnectionHandler, self).__init__()
        self._conn = TCPConnection(conn)
        self._users_text_manager = users_text_manager
        self._stop_flag = False
        self._request_handler = RequestHandler(self._users_text_manager)

    def run(self):
        """Runs the thread."""
        try:
            while not self._stop_flag:
                try:
                    request = JSONPackage(recv_func=self._conn.recv_all).content
                    response = self._request_handler.handle(request)
                    JSONPackage(response).send(self._conn.send_all)
                except JSONPackageError as e:
                    log.error(str(e))
        except socket.error as e:
            log.error(str(e))
        self._conn.close()

    def stop(self):
        """Stops the thread."""
        self._stop_flag = True
        self._conn.stop()


class TCPConnection(object):
    """My custom tcp connection.

    Args:
        _conn: The TCP-connection.
        _stop_flag: Stopping flag.
    """
    def __init__(self, conn):
        """Constructor.

        Args:
            conn: TCP-connection.
        """
        self._conn = conn
        self._conn.settimeout(TIMEOUT)
        self._stop_flag = False

    def send_all(self, data):
        """Sends the data until timeout or the socket closed.

        Args:
            data: Data to be sent.
        """
        recvd_byte, total_byte = 0, len(data)
        while recvd_byte < total_byte and not self._stop_flag:
            try:
                recvd_byte += self._conn.send(data[recvd_byte : ])
            except socket.timeout:
                continue

    def recv_all(self, nbyte):
        """Receives the data until timeout or the socket closed.

        Args:
            nbyte: Bytes of data to receive.

        Return:
            Bytes of data.
        """
        ret = b''
        while nbyte > 0 and not self._stop_flag:
            try:
                recv = self._conn.recv(nbyte)
            except socket.timeout:
                continue
            if not recv:
                raise socket.error('Connection die.')
            ret += recv
            nbyte -= len(recv)
        return ret

    def close(self):
        """Closes the connection."""
        self._conn.close()

    def stop(self):
        """Stops."""
        self._stop_flag = True
