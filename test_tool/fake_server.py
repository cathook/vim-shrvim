#! /usr/bin/env python3

import copy
import log
import sys
import tcp_server
import threading

from tcp_server import _JSON_TOKEN
from json_package import JSONPackage

class MODE:  # pylint:disable=W0232
    """Enumeration type of mode."""
    NORMAL = 1  # normal mode.
    INSERT = 2  # insert mode.
    REPLACE = 3  # replace mode.
    VISUAL = 4  # visual mode.
    LINE_VISUAL = 5  # line visual mode.
    BLOCK_VISUAL = 6  # block visual mode.

counter = 0

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
        global counter
        fake_user1 = copy.deepcopy(request.content)
        fake_user1[_JSON_TOKEN.NICKNAME] = 'user1'
        del fake_user1[_JSON_TOKEN.TEXT]
        fake_user1[_JSON_TOKEN.MODE] = MODE.INSERT
        fake_user1[_JSON_TOKEN.CURSORS]['.'] = 0
        counter += 1
        fake_user2 = copy.deepcopy(request.content)
        fake_user2[_JSON_TOKEN.NICKNAME] = 'user2'
        del fake_user2[_JSON_TOKEN.TEXT]
        fake_user2[_JSON_TOKEN.MODE] = MODE.LINE_VISUAL
        fake_user2[_JSON_TOKEN.CURSORS]['.'] = 62
        fake_user2[_JSON_TOKEN.CURSORS]['v'] = 3
        request.content[_JSON_TOKEN.OTHERS] = [fake_user1, fake_user2]
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
