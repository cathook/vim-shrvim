function! SharedVimConnect(server_name, port, identity)
    let b:shared_vim_server_name = a:server_name
    let b:shared_vim_port = a:port
    let b:shared_vim_identity = a:identity
    let b:shared_vim_init = 1
    call SharedVimSync()
endfunction


function! SharedVimDisconnect()
    unlet! b:shared_vim_server_name
    unlet! b:shared_vim_port
    unlet! b:shared_vim_identity
    unlet! b:shared_vim_init
endfunction


function! SharedVimSync()
python << EOF
import json
import re
import socket
import vim
import zlib


class JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
    CURSOR = 'cursor'  # cursor position
    CURSORS = 'cursors'  # other users' cursor position
    ERROR = 'error'  # error string
    IDENTITY = 'identity'  # identity of myself
    INIT = 'init'  # initialize connect flag
    TEXT = 'text'  # text content in the buffer

def vim_input(prompt='', default_value=''):
    vim.command('call inputsave()')
    vim.command("let user_input = input('%s','%s')" % (prompt, default_value))
    vim.command('call inputrestore()')
    return vim.eval('user_input')

class StringTCP(object):
    """Send/receive strings by tcp connection.

    Attributes:
        _connection: The tcp connection.
    """
    ENCODING = 'utf-8'
    COMPRESS_LEVEL = 2
    HEADER_LENGTH = 10

    def __init__(self, sock=None, servername=None, port=None):
        """Constructor.

        Args:
            sock: The tcp connection.  if it is None, the constructor will
                    automatically creates an tcp connection to servername:port.
            servername: The server name if needs.
            port: The server port if needs.
        """
        if sock is None:
            self._connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._connection.connect((servername, port))
        else:
            self._connection = sock

    def send_string(self, string):
        """Sends a string to the tcp-connection.

        Args:
            string: The string to be sent.
        """
        body = StringTCP._create_body_from_string(string)
        header = StringTCP._create_header_from_body(body)
        self._connection.send(header + body)

    def recv_string(self):
        """Receives a string from the tcp-connection.

        Returns:
            The string received.
        """
        header = StringTCP._recv_header_string(self._connection)
        body = StringTCP._recv_body_string(self._connection, header)
        return body

    def close(self):
        """Closes the socket."""
        self._connection.close()

    @staticmethod
    def _create_body_from_string(string):
        """Creates package body from data string.

        Args:
            string: Data string.
        """
        byte_string = string.encode(StringTCP.ENCODING)
        return zlib.compress(byte_string, StringTCP.COMPRESS_LEVEL)

    @staticmethod
    def _create_header_from_body(body):
        """Creates package header from package body.

        Args:
            body: Package body.
        """
        header_string = ('%%0%dd' % StringTCP.HEADER_LENGTH) % len(body)
        return header_string.encode(StringTCP.ENCODING)

    @staticmethod
    def _recv_header_string(conn):
        """Receives package header from specified tcp connection.

        Args:
            conn: The specified tcp connection.

        Returns:
            Package header.
        """
        return conn.recv(StringTCP.HEADER_LENGTH).decode(StringTCP.ENCODING)

    @staticmethod
    def _recv_body_string(conn, header):
        """Receives package body from specified tcp connection and header.

        Args:
            conn: The specified tcp connection.
            header: The package header.

        Returns:
            Package body.
        """
        body_length = int(header)
        body = conn.recv(body_length)
        body_byte = zlib.decompress(body)
        return body_byte.decode(StringTCP.ENCODING)


def rc_to_num(lines, rc):
    """Transforms cursor position from row-col format to numeric format.

    Args:
        lines: List of lines of the context.
        rc: A 2-tuple for row-col position.

    Returns:
        A number for cursor position.
    """
    result = 0
    for row in range(0, rc[0]):
        result += len(lines[row]) + 1
    result += rc[1]
    return result

def nums_to_rcs(lines, nums):
    """Transforms cursor positions from numeric format to row-col format.

    Args:
        lines: List of lines of the context.
        nums: List of number of each positions to be transformed.

    Returns:
        A list of 2-tuple row-col format cursor positions.
    """
    sorted_index = sorted(range(len(nums)), key=lambda x: nums[x])
    now_index, max_index = 0, len(sorted_index)
    num = 0
    rcs = [None] * len(nums)
    for row in range(len(lines)):
        num_max = num + len(lines[row])
        while now_index < max_index:
            if nums[sorted_index[now_index]] > num_max:
                break
            rcs[sorted_index[now_index]] = \
                    (row, nums[sorted_index[now_index]] - num)
            now_index += 1
        else:
            break
        num = num_max + 1
    return rcs


def main():
    """Main process."""
    try:
        # Fetches information.
        server_name = vim.current.buffer.vars['shared_vim_server_name']
        port = vim.current.buffer.vars['shared_vim_port']
        identity = vim.current.buffer.vars['shared_vim_identity']
        cursor_position = rc_to_num(vim.current.buffer[:],
                                    (vim.current.window.cursor[0] - 1,
                                     vim.current.window.cursor[1]))
        text = '\n'.join(vim.current.buffer[:])
        init_flag = vim.current.buffer.vars['shared_vim_init']

        if text and init_flag:
            result = vim_input('It will clear the buffer, would you want to ' +
                               'continue? [Y/n] ', 'Y')
            if result == 'y' or result == 'Y':
                vim.current.buffer[0 : len(vim.current.buffer)] = ['']
                text = ''
            else:
                return
            print('')

        # Creates request.
        request = {
            JSON_TOKEN.IDENTITY : identity,
            JSON_TOKEN.TEXT : text,
            JSON_TOKEN.CURSOR : cursor_position,
            JSON_TOKEN.INIT : bool(init_flag),
        }

        # Connects to the server and gets the response.
        print('Connect to %s:%d' % (server_name, port))
        conn = StringTCP(servername=server_name, port=port)
        conn.send_string(json.dumps(request))
        response = json.loads(conn.recv_string())
        conn.close()

        # Sync.
        if JSON_TOKEN.ERROR in response:
            raise Exception('from server: ' + response[JSON_TOKEN.ERROR])
        else:
            lines = re.split(r'\n', response[JSON_TOKEN.TEXT])
            rcs = nums_to_rcs(lines, response[JSON_TOKEN.CURSORS])
            my_rc = nums_to_rcs(lines, [response[JSON_TOKEN.CURSOR]])[0]

            other_cursors_ptrn = '/%s/' % ('\\|'.join(
                    ['\\%%%dl\\%%%dc' % (rc[0] + 1, rc[1] + 1) for rc in rcs]))

            vim.command('match SharedVimOthersCursors %s' % other_cursors_ptrn)
            vim.current.buffer[0 : len(vim.current.buffer)] = lines
            vim.current.window.cursor = (my_rc[0] + 1, my_rc[1])

    except Exception as e:
        print(e)

main()
EOF
    let b:shared_vim_init = 0
endfunction


function! SharedVimEventsHandler(event_name)
    if exists('b:shared_vim_server_name')
        if a:event_name == 'VimCursorMoved'
            call SharedVimSync()
        endif
    endif
endfunction


autocmd CursorMoved * call SharedVimEventsHandler('VimCursorMoved')

highlight SharedVimOthersCursors ctermbg=darkred
