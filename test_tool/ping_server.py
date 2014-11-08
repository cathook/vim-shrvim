#! /usr/bin/env python3

import log
import sys
import tcp_server
import threading

from json_package import JSONPackage

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
        self._sock = sock
        self._users_text_manager = users_text_manager

    def run(self):
        """Runs the thread."""
        request = self._receive()
        self._handle(request)
        self._sock.close()


    def _handle(self, request):
        """Handles the request.

        Args:
            request: The request package.
        """
        log.info(str(request.content) + '\n')
        request.send_to(self._sock)

    def _receive(self):
        """Receive a request.

        Return:
            The request package.
        """
        request = JSONPackage()
        request.recv_from(self._sock)
        return request


tcp_server._TCPConnectionHandler = _TCPConnectionHandler

def main():
    server = tcp_server.TCPServer(int(sys.argv[1]), None)
    server.start()

if __name__ == '__main__':
    main()
