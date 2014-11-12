"""""""""""""""""""""""" Global variable for settings """"""""""""""""""""""""""
if !exists('g:shared_vim_force_to_use')
    let g:shared_vim_python3_first = 1
endif


""""""""""""""""""""" Functions supplies by this plugin. """""""""""""""""""""""
function! SharedVimConnect(server_name, port, identity)
    let b:shared_vim_server_name = a:server_name
    let b:shared_vim_port = a:port
    let b:shared_vim_identity = a:identity
    let b:shared_vim_init = 1
    call SharedVimSync()
endfunction


function! SharedVimDisconnect()
    let b:shared_vim_goal = 'disconnect'
    call SharedVimMainFunc()
    unlet! b:shared_vim_server_name
    unlet! b:shared_vim_port
    unlet! b:shared_vim_identity
    unlet! b:shared_vim_init
endfunction


function! SharedVimSync()
    let b:shared_vim_goal = 'sync'
    call SharedVimMainFunc()
    let b:shared_vim_init = 0
endfunction


"""""""""""""""""""""""""""" Setup for this plugin """""""""""""""""""""""""""""
" Highlight for other users.
for i in range(1, g:shared_vim_num_groups)
    exec 'hi SharedVimNor' . i . ' ctermbg=darkyellow'
    exec 'hi SharedVimIns' . i . ' ctermbg=darkred'
    exec 'hi SharedVimVbk' . i . ' ctermbg=darkblue'
endfor


" Sync
function! SharedVimTrySync()
    if exists('b:shared_vim_server_name')
        call SharedVimSync()
    endif
endfunction

" Auto commands
autocmd! CursorMoved * call  SharedVimTrySync()
autocmd! CursorMovedI * call SharedVimTrySync()
autocmd! CursorHold * call   SharedVimTrySync()
autocmd! CursorHoldI * call  SharedVimTrySync()
autocmd! InsertEnter * call  SharedVimTrySync()
autocmd! InsertLeave * call  SharedVimTrySync()


"""""""""""""""""""""""""""""""" Main procedure """"""""""""""""""""""""""""""""
function! SharedVimChoosePythonVersion()
    if (g:shared_vim_python3_first || !has('python')) && has('python3')
        command! -nargs=* SharedVimPython python3 <args>
        return 1
    elseif has('python')
        command! -nargs=* SharedVimPython python <args>
        return 1
    else
        return 0
    endif
endfunction


function! SharedVimMainFunc()
    if !SharedVimChoosePythonVersion()
        echoerr 'Sorry, this plugin is not supported by this version of vim.'
        return
    endif
SharedVimPython << EOF
# python << EOF
# ^^ Force vim highlighting the python code below.
import bisect
import json
import re
import six
import socket
import sys
import vim
import zlib

if sys.version_info[0] >= 3:
    unicode = str

DEFAULT_NUM_GROUPS = 5  # Default number of groups.
DEFAULT_TIMEOUT = 5  # Default timeout.

class GOALS:  # pylint:disable=W0232
    SYNC = 'sync'  # Sync.
    DISCONNECT = 'disconnect'  # Disconnect.

class CURSOR_MARK:  # pylint:disable=W0232
    """Enumeration type of cursor marks."""
    CURRENT = '.'
    V = 'v'

class MATCH_PRI:  # pylint:disable=W0232
    """Enumerations types of match priority."""
    NORMAL = 2
    INSERT = 3
    VISUAL = 1

class MODE:  # pylint:disable=W0232
    """Enumeration type of mode."""
    NORMAL = 1  # normal mode.
    INSERT = 2  # insert mode.
    REPLACE = 3  # replace mode.
    VISUAL = 4  # visual mode.
    LINE_VISUAL = 5  # line visual mode.
    BLOCK_VISUAL = 6  # block visual mode.

class VARNAMES:  # pylint: disable=W0232
    """Enumeration types of variable name in vim."""
    PREFIX = 'shared_vim_'  # Shared prefix of the variable names.
    IDENTITY = PREFIX + 'identity'  # Identity of the user.
    INIT = PREFIX + 'init'  # Initial or not.
    NUM_GROUPS = PREFIX + 'num_groups'  # Number of groups.
    SERVER_NAME = PREFIX + 'server_name'  # Server name.
    SERVER_PORT = PREFIX + 'port'  # Server port.
    TIMEOUT = PREFIX + 'timeout'  # Timeout for TCPConnection.
    GOAL = PREFIX + 'goal'  # Goal of this python code.

# Name of the normal cursor group.
NORMAL_CURSOR_GROUP = lambda x: 'SharedVimNor%d' % x

# Name of the insert cursor group.
INSERT_CURSOR_GROUP = lambda x: 'InsertVimNor%d' % x

# Name of the visual group.
VISUAL_GROUP = lambda x: 'VisualVimNor%d' % x


class JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
    BYE = 'bye'  # Disconnects with the server.
    CURSORS = 'cursors'  # other users' cursor position
    ERROR = 'error'  # error string
    IDENTITY = 'identity'  # identity of myself
    INIT = 'init'  # initialize connect flag
    MODE = 'mode'  # vim mode.
    NICKNAME = 'nickname'  # nick name of the user.
    OTHERS = 'others'  # other users info.
    TEXT = 'text'  # text content in the buffer


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
        string = json.dumps(self.content)
        body = JSONPackage._create_body_from_string(string)
        header = JSONPackage._create_header_from_body(body)
        fd.send(header + body)

    def recv_from(self, fd):
        """Receives a string from the tcp-connection.

        Args:
            fd: Socket fd.
        """
        header = JSONPackage._recv_header_string(fd)
        body = JSONPackage._recv_body_string(fd, header)
        self.content = json.loads(body)

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
        byte = conn.recv(JSONPackage.HEADER_LENGTH)
        return byte.decode(JSONPackage.ENCODING)

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
        return body_byte.decode(JSONPackage.ENCODING)


class VimVarInfo(object):  # pylint: disable=W0232
    """Gets/sets variables in vim."""
    def __getitem__(self, variable_name):
        """Gets the specified vim variable.

        Args:
            variable_name: Name of the variable to get.

        Return:
            None if the value is not exists, otherwise the value.
        """
        return self.get(variable_name)

    def get(self, variable_name, default_value=None):
        """Gets the specified vim variable.

        Args:
            variable_name: Name of the variable to get.
            default_value: The default to return if the variable is not exist.

        Return:
            default_value if the value is not exists, otherwise the value.
        """
        if variable_name not in vim.current.buffer.vars:
            return default_value
        return VimInfo.transform_to_py(vim.current.buffer.vars[variable_name])

    def __setitem__(self, variable_name, value):
        """Sets the specifiec vim variable.

        Args:
            variable_name: Name of the variable to set.
            value: The new value.
        """
        vim.current.buffer.vars[variable_name] = VimInfo.transform_to_vim(value)

    def __delitem__(self, variable_name):
        """Deletes the specifiec vim variable.

        Args:
            variable_name: Name of the variable to delete.
        """
        del vim.current.buffer.vars[variable_name]


class VimCursorsInfo(object):  # pylint: disable=W0232
    """Gets/sets the cursor position in vim."""
    def __init__(self, *_):
        """Constructor."""
        self._text_num_sum = []

    def __getitem__(self, mark):
        """Gets the cursor position with specifying the mark.

        Args:
            mark: Mark of the cursor to get.

        Return:
            Cursor position.
        """
        pos = [int(x) for x in vim.eval('getpos("%s")' % mark)]
        return self.rc_to_num((pos[1] - 1, pos[2] - 1))

    def __setitem__(self, mark, value):
        """Sets the cursor position with specifying the mark.

        Args:
            mark: Mark of the cursor to set.
        """
        row, col = self.num_to_rc(value)
        mark = mark if mark != CURSOR_MARK.V else CURSOR_MARK.CURRENT
        vim.eval('setpos("%s", [0, %d, %d, 0])' % (mark, row + 1, col + 1))

    def rc_to_num(self, rc):
        """Transforms row-column cursor position to bytes position.

        Args:
            rc: Row-column cursor position.

        Return:
            byte position.
        """
        base = self._text_num_sum[rc[0] - 1] if rc[0] > 0 else 0
        line = VimInfo.transform_to_vim(VimInfo.lines[rc[0]])
        return base + len(VimInfo.transform_to_py(line[ : rc[1]]))

    def num_to_rc(self, num, rmin=0):
        """Transforms byte position to row-column cursor position.

        Args:
            num: byte cursor position.

        Return:
            List of row-column position.
        """
        row = bisect.bisect_right(self._text_num_sum, num, lo=rmin)
        col = num - (0 if row == 0 else self._text_num_sum[row - 1])
        return (row, len(VimInfo.transform_to_vim(VimInfo.lines[row][ : col])))

    def nums_to_rcs(self, nums):
        """Transforms list of sorted byte positions.

        Args:
            nums: list of byte cursor positions.

        Return:
            List of row-column positions.
        """
        ret, last_r = [], 0
        for num in nums:
            my_rc = self.num_to_rc(num, rmin=last_r)
            ret += [my_rc]
            last_r = my_rc[0]
        return ret

    def update_text_lines(self):
        """Updates the content lines.

        Args:
            lines: List of content lines.
        """
        self._text_num_sum, pre = [], 0
        for line in VimInfo.lines:
            self._text_num_sum += [pre + len(line) + 1]
            pre += len(line) + 1


class GroupInfo(object):
    """Higilights informations about a user group.

    Attributes:
        _normal_cursor_positions: List of cursor positions in normal mode.
        _insert_cursor_positions: List of cursor positions in insert mode.
        _visual_positions: List of positions in visual blocks.
    """
    def __init__(self):
        """Constructor."""
        self._normal_cursor_positions = []
        self._insert_cursor_positions = []
        self._visual_positions = []

    def set_mode_cursor(self, mode, rc):
        """Sets the mode and the cursor.

        Args:
            mode: The mode.
            rc: The cursor position.
        """
        if mode in (MODE.INSERT, MODE.REPLACE):
            self._insert_cursor_positions += [rc]
        else:
            self._normal_cursor_positions += [rc]

    def add_visual(self, rc):
        """Add a visual position.

        Args:
            rc: The position.
        """
        self._visual_positions += [rc]

    @property
    def normal_cursor_positions(self):
        """Gets the normal cursor positions."""
        return self._normal_cursor_positions

    @property
    def insert_cursor_positions(self):
        """Gets the insert cursor positions."""
        return self._insert_cursor_positions

    @property
    def visual_positions(self):
        """Gets the visual positions."""
        return self._visual_positions


class VimHighlightInfo(object):
    """Highlight informations about users.

    Attributes:
        _groups: A list of instance of GroupInfo.
        _username_to_group: A dict for mapping the username to the instance of
            GroupInfo.
    """
    def __init__(self):
        """Constructor."""
        self._groups = None
        self._username_to_group = {}

    def __getitem__(self, name):
        """Gets the group (a instance of GroupInfo) by nickname.

        Args:
            name: Nick name.

        Return:
            The group in which the user is.
        """
        return self._username_to_group[name]

    def reset(self, nicknames):
        """Reset the users.

        Args:
            nicknames: A list of nickname.
        """
        if self._groups is None:
            self._groups = [GroupInfo() for _ in range(self.num_of_groups())]
        self._username_to_group = {name : self._groups[self._get_group_id(name)]
                                   for name in nicknames}

    def render(self):
        """Render the highlight to vim."""
        for index in range(self.num_of_groups()):
            VimInfo.match(NORMAL_CURSOR_GROUP(index), MATCH_PRI.NORMAL,
                          self._groups[index].normal_cursor_positions)
            VimInfo.match(INSERT_CURSOR_GROUP(index), MATCH_PRI.INSERT,
                          self._groups[index].insert_cursor_positions)
            VimInfo.match(VISUAL_GROUP(index), MATCH_PRI.VISUAL,
                          self._groups[index].visual_positions)

    def _get_group_id(self, string):
        """Transform the gived string to a valid group index.

        Args:
            string: The gived string.

        Return:
            The index in [0, number of groups)
        """
        x = 0
        for c in string:
            x = (x * 23 + ord(c)) % self.num_of_groups()
        return x

    @staticmethod
    def num_of_groups():
        """Gets the number of groups."""
        return VimInfo.var.get(VARNAMES.NUM_GROUPS, DEFAULT_NUM_GROUPS)


class VimInfoMeta(type):
    """An interface for accessing the vim's vars, buffer, cursors, etc.

    Static attributes:
        var: An instance of VimVarInfo, for accessing the variables in vim.
        cursors: An instance of VimCursorsInfo, for accessing the cursor
                information in vim.
        highlight: An instance of VimHighlightInfo, for accessing the
                 information about highlight in vim.
        ENCODING: vim's encoding.
    """
    var = VimVarInfo()
    cursors = VimCursorsInfo()
    highlight = VimHighlightInfo()
    ENCODING = vim.options['encoding']

    def __init__(self, *args):
        """Constructor."""
        self._mode = None

    @property
    def lines(self):  # pylint: disable=R0201
        """Gets list of lines in the buffer."""
        return [VimInfo.transform_to_py(line)
                for line in vim.current.buffer[:]]

    @lines.setter
    def lines(self, lines):  # pylint: disable=R0201
        """Sets the buffer by list of lines."""
        vim.current.buffer[0 : len(vim.current.buffer)] = \
            [VimInfo.transform_to_vim(line) for line in lines]

    @property
    def text(self):
        """Gets the buffer text."""
        return '\n'.join(self.lines)

    @text.setter
    def text(self, text):
        """Sets the buffer text."""
        lines = re.split('\n', text)
        self.lines = lines if lines else ['']
        VimInfo.cursors.update_text_lines()

    @property
    def mode(self):
        """Gets the current mode."""
        mode_str = vim.eval('mode()')
        if mode_str == 'i':
            self._mode = MODE.INSERT
        elif mode_str == 'R':
            self._mode = MODE.REPLACE
        elif mode_str == 'v':
            self._mode = MODE.VISUAL
        elif mode_str == 'V':
            self._mode = MODE.LINE_VISUAL
        elif len(mode_str) == 1 and ord(mode_str) == 22:
            self._mode = MODE.BLOCK_VISUAL
        else:
            self._mode = MODE.NORMAL
        return self._mode

    @mode.setter
    def mode(self, value):
        """Sets the current mode."""
        if self._mode != value:
            if value == MODE.INSERT:
                vim.command('startinsert')
            elif value == MODE.REPLACE:
                vim.command('startreplace')
            elif value == MODE.VISUAL:
                vim.command('exe "norm! v"')
            elif value == MODE.LINE_VISUAL:
                vim.command('exe "norm! V"')
            elif value == MODE.BLOCK_VISUAL:
                vim.command('exe "norm! %c"' % 22)
            else:
                vim.command('exe "norm! \\<esc>"')
            self._mode = value

    @staticmethod
    def match(group_name, priority, positions):
        """Set the match informations.

        Args:
            group_name: Group name.
            priority: Priority for the vim function matchadd().
            positions: List of row-column position.
        """
        last_id = VimInfo.var[VARNAMES.PREFIX + group_name]
        if last_id is not None and last_id > 0:
            ret = vim.eval('matchdelete(%d)' % int(last_id))
            del VimInfo.var[VARNAMES.PREFIX + group_name]
        if positions:
            rcs = [(rc[0] + 1, rc[1] + 1) for rc in positions]
            patterns = '\\|'.join(['\\%%%dl\\%%%dc' % rc for rc in rcs])
            mid = int(vim.eval("matchadd('%s', '%s', %d)" %
                               (group_name, patterns, priority)))
            if mid != -1:
                VimInfo.var[VARNAMES.PREFIX + group_name] = mid

    @staticmethod
    def transform_to_py(data):
        """Transforms the data to python's data type if needs.

        In python, we always use unicode(python2)/str(python3) instead of bytes.

        Args:
            data: The data to be transform.

        Return:
            Data which are transformed.
        """
        return (data if not isinstance(data, bytes)
                     else data.decode(VimInfo.ENCODING))

    @staticmethod
    def transform_to_vim(data):
        """Transforms the data to vim's data type if needs.

        Args:
            data: The data to be transform.

        Return:
            Data which are transformed.
        """
        return (data if not isinstance(data, unicode)
                     else data.encode(VimInfo.ENCODING))


class VimInfo(six.with_metaclass(VimInfoMeta, object)):
    """An interface for accessing the vim's vars, buffer, cursors, etc."""
    @staticmethod
    def init():
        """Initializes some settings."""
        VimInfo.cursors.update_text_lines()


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
        self._conn.settimeout(
            VimInfo.var.get(VARNAMES.TIMEOUT, DEFAULT_TIMEOUT))

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


class TCPClientError(Exception):
    """Exception raised by TCPClient."""
    pass

class TCPClient(object):
    """TCP client.

    Attributes:
        _sock: Connection.
    """
    def __init__(self):
        """Constructor, automatically connects to the server."""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect((VimInfo.var[VARNAMES.SERVER_NAME],
                          VimInfo.var[VARNAMES.SERVER_PORT]))
            self._sock = TCPConnection(sock)
        except TypeError as e:
            raise TCPClientError('Cannot connect to server: %r' % e)
        except socket.error as e:
            raise TCPClientError('Cannot connect to server: %r' % e)

    def request(self, req):
        """Sends a request to server and get the response.

        Args:
            req: An request.

        Return:
            The response.
        """
        pkg = JSONPackage()
        pkg.content = req
        pkg.send_to(self._sock)
        pkg.recv_from(self._sock)
        return pkg.content

    def close(self):
        """Closes the socket."""
        self._sock.close()


def get_my_info():
    """Gets my information for server.

    Return:
        The information for server.
    """
    return {
        JSON_TOKEN.IDENTITY : VimInfo.var[VARNAMES.IDENTITY],
        JSON_TOKEN.INIT : VimInfo.var[VARNAMES.INIT],
        JSON_TOKEN.MODE : VimInfo.mode,
        JSON_TOKEN.CURSORS : {
            CURSOR_MARK.CURRENT : VimInfo.cursors[CURSOR_MARK.CURRENT],
            CURSOR_MARK.V : VimInfo.cursors[CURSOR_MARK.V],
        },
        JSON_TOKEN.TEXT : VimInfo.text,
    }


def set_my_info(json_info):
    """Sets my information gived by server.

    Args:
        json_info: JSON information gived by server.
    """
    VimInfo.text = json_info[JSON_TOKEN.TEXT]
    mode = json_info[JSON_TOKEN.MODE]
    VimInfo.mode = mode
    if mode in (MODE.VISUAL, MODE.BLOCK_VISUAL, MODE.LINE_VISUAL):
        old_mode, VimInfo.mode = mode, MODE.NORMAL
        VimInfo.cursors[CURSOR_MARK.V] = \
            json_info[JSON_TOKEN.CURSORS][CURSOR_MARK.V]
        VimInfo.mode = old_mode
    VimInfo.cursors[CURSOR_MARK.CURRENT] = \
        json_info[JSON_TOKEN.CURSORS][CURSOR_MARK.CURRENT]


def set_others_info(json_info):
    """Sets the informations about other user.

    Args:
        json_info: JSON information gived by server.
    """
    users = json_info[JSON_TOKEN.OTHERS]
    VimInfo.highlight.reset([user[JSON_TOKEN.NICKNAME] for user in users])
    for user in users:
        name, mode = user[JSON_TOKEN.NICKNAME], user[JSON_TOKEN.MODE]
        cursors = user[JSON_TOKEN.CURSORS]
        curr_rc = VimInfo.cursors.num_to_rc(cursors[CURSOR_MARK.CURRENT])
        VimInfo.highlight[name].set_mode_cursor(mode, curr_rc)
        if mode in (MODE.VISUAL, MODE.LINE_VISUAL, MODE.BLOCK_VISUAL):
            last_rc = VimInfo.cursors.num_to_rc(cursors[CURSOR_MARK.V])
            if last_rc[0] > curr_rc[0] or \
                (last_rc[0] == curr_rc[0] and last_rc[1] > curr_rc[1]):
                last_rc, curr_rc = curr_rc, last_rc
            set_other_visual(VimInfo, name, mode, last_rc, curr_rc)
    VimInfo.highlight.render()

def set_other_visual(name, mode, beg, end):
    """Sets the other user's visual block.

    Args:
        name: Name of this user.
        mode: Mode of this user.
        beg: The first row-column position of the range.
        end: The last row-column position of the range.
    """
    if mode == MODE.VISUAL:
        for row in range(beg[0], end[0] + 1):
            first = 0 if row != beg[0] else beg[1]
            last = len(VimInfo.lines[row]) if row != end[0] else end[1]
            for col in range(first, last + 1):
                VimInfo.highlight[name].add_visual((row, col))
    elif mode == MODE.LINE_VISUAL:
        for row in range(beg[0], end[0] + 1):
            for col in range(0, len(VimInfo.lines[row])):
                VimInfo.highlight[name].add_visual((row, col))
    elif mode == MODE.BLOCK_VISUAL:
        left, right = min([beg[1], end[1]]), max([beg[1], end[1]])
        for row in range(beg[0], end[0] + 1):
            for col in range(left, right + 1):
                VimInfo.highlight[name].add_visual((row, col))


def sync():
    """Sync with the server."""
    conn = TCPClient()
    response = conn.request(get_my_info())
    conn.close()
    if JSON_TOKEN.ERROR in response:
        raise Exception(response[JSON_TOKEN.ERROR])
    set_my_info(response)
    set_others_info(response)


def disconnect():
    """Disconnects with the server."""
    conn = TCPClient()
    conn.request({JSON_TOKEN.BYE : True,
                  JSON_TOKEN.IDENTITY : VimInfo.var[VARNAMES.IDENTITY]})
    conn.close()
    print('bye')


def main():
    VimInfo.init()
    """Main function."""
    try:
        if VimInfo.var[VARNAMES.GOAL] == GOALS.SYNC:
            sync()
        elif VimInfo.var[VARNAMES.GOAL] == GOALS.DISCONNECT:
            disconnect()
    except TCPClientError as e:
        print(e)
    except Exception as e:
        print('[%r] %r' % (sys.exc_info()[2].tb_lineno, e))

main()
EOF
endfunction
