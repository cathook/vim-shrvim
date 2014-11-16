"""""""""""""""""""""""""""""""""""" Commands """"""""""""""""""""""""""""""""""
command! -nargs=0 SharedVimTryUsePython3 call _SharedVimTryUsePython3(1)
command! -nargs=0 SharedVimTryUsePython2 call _SharedVimTryUsePython2(1)
command! -nargs=+ SharedVimConnect call _SharedVimCallPythonFunc('connect', [<f-args>])
command! -nargs=0 SharedVimDisconnect call _SharedVimCallPythonFunc('disconnect', [])
command! -nargs=0 SharedVimSync call _SharedVimCallPythonFunc('sync', [])
command! -nargs=0 SharedVimShowInfo call _SharedVimCallPythonFunc('show_info', [])
command! -nargs=1 SharedVimSetTimeout call _SharedVimCallPythonFunc('set_bvar', ['TIMEOUT', <f-args>])
command! -nargs=1 SharedVimSetNumOfGroups call _SharedVimCallPythonFunc('set_bvar', ['NUM_GROUPS', <f-args>])


""""""""""""""""""""""""""""""""""""" Setup """"""""""""""""""""""""""""""""""""
" Highlight for other users.
for i in range(0, 100)
    exec 'hi SharedVimNor' . i . ' ctermbg=darkyellow'
    exec 'hi SharedVimIns' . i . ' ctermbg=darkred'
    exec 'hi SharedVimVbk' . i . ' ctermbg=darkblue'
endfor


let g:shared_vim_auto_sync_level = 3


" Auto commands
autocmd! InsertLeave * call _SharedVimAutoSync(1)
autocmd! CursorMoved * call _SharedVimAutoSync(1)
autocmd! CursorHold * call _SharedVimAutoSync(1)
autocmd! InsertEnter * call _SharedVimAutoSync(2)
autocmd! CursorMovedI * call _SharedVimAutoSync(3)
autocmd! CursorHoldI * call _SharedVimAutoSync(3)


""""""""""""""""""""""""""""""""""" Functions """"""""""""""""""""""""""""""""""
function! _SharedVimTryUsePython3(show_err)
    if has('python3')
        command! -nargs=* SharedVimPython python3 <args>
        call _SharedVimSetup()
        return 1
    else
        if a:show_err
            echoerr 'Sorry, :python3 is not supported in this version'
        endif
        return 0
    endif
endfunction


function! _SharedVimTryUsePython2(show_err)
    if has('python')
        command! -nargs=* SharedVimPython python <args>
        call _SharedVimSetup()
        return 1
    else
        if a:show_err
            echoerr 'Sorry, :python is not supported in this version'
        endif
        return 0
    endif
endfunction


function! _SharedVimCallPythonFunc(func_name, args)
    if exists('g:shared_vim_setupped') && g:shared_vim_setupped == 1
        if len(a:args) == 0
            exe 'SharedVimPython ' . a:func_name . '()'
        else
            let args_str = '"' . join(a:args, '", "') . '"'
            exe 'SharedVimPython ' . a:func_name . '(' . args_str . ')'
        endif
    endif
endfunction

function! _SharedVimAutoSync(level)
    if !exists('b:shared_vim_auto_sync_level')
        let b:shared_vim_auto_sync_level = g:shared_vim_auto_sync_level
    endif
    if a:level <= b:shared_vim_auto_sync_level
        SharedVimSync
    endif
endfunction


function! _SharedVimSetup()
SharedVimPython << EOF
# python << EOF
# ^^ Force vim highlighting the python code below.
import bisect
import json
import re
import socket
import sys
import vim

if sys.version_info[0] == 3:
    unicode = str

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
    GROUP_NAME_PREFIX = 'gnp'  # Group name's prefix.
    IDENTITY = 'identity'  # Identity of the user.
    INIT = 'init'  # Initial or not.
    NUM_GROUPS = 'num_groups'  # Number of groups.
    SERVER_NAME = 'server_name'  # Server name.
    SERVER_PORT = 'port'  # Server port.
    TIMEOUT = 'timeout'  # Timeout for TCPConnection.
    USERS = 'users'  # List of users.

# Name of the normal cursor group.
NORMAL_CURSOR_GROUP = lambda x: 'SharedVimNor%d' % x

# Name of the insert cursor group.
INSERT_CURSOR_GROUP = lambda x: 'SharedVimIns%d' % x

# Name of the visual group.
VISUAL_GROUP = lambda x: 'SharedVimVbk%d' % x


DEFAULT_TIMEOUT = 1
DEFAULT_NUM_GROUPS = 5


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


############### Handler for Variable stores only in python #####################
class ScopeVars(object):
    """A scoped variables handler.

    Attributes:
        _curr_scope: Current scope number.
        _vars: A dict contains all scope's variables and the values.
    """
    def __init__(self):
        """Constructor."""
        self._curr_scope = None
        self._vars = {}

    @property
    def curr_scope(self):
        """Gets the current scope number."""
        return self._curr_scope

    @curr_scope.setter
    def curr_scope(self, value):
        """Sets the current scope number."""
        self._curr_scope = value
        self._vars.setdefault(self._curr_scope, {})

    def get(self, variable_name, default=None):
        """Gets the specified variable.

        Args:
            variable_name: Name of the variable to get.
            default: The default value to return if the variable is not exist.

        Return:
            The value.
        """
        return self._vars[self._curr_scope].get(variable_name, default)

    def __getitem__(self, variable_name):
        """Gets the specified variable.

        Args:
            variable_name: Name of the variable to get.

        Return:
            The value.
        """
        return self._vars[self._curr_scope][variable_name]

    def __setitem__(self, variable_name, value):
        """Sets the specifiec variable.

        Args:
            variable_name: Name of the variable to set.
            value: The new value.
        """
        self._vars[self._curr_scope][variable_name] = value

    def __delitem__(self, variable_name):
        """Deletes the specifiec variable.

        Args:
            variable_name: Name of the variable to delete.
        """
        del self._vars[self._curr_scope][variable_name]

    def __contains__(self, variable_name):
        """Checks whether the variable is exist or not.

        Args:
            variable_name: Name of the variable to check.

        Return:
            True if the variable exists; otherwise, False.
        """
        return variable_name in self._vars[self._curr_scope]


# For scope=buffer
py_bvars = ScopeVars()

# For scope=window
py_wvars = ScopeVars()

############################### Interface to vim ###############################
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
        line = VimInfo.lines[row][ : col] if row < len(VimInfo.lines) else ''
        return (row, len(VimInfo.transform_to_vim(line)))

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
        return py_bvars.get(VARNAMES.NUM_GROUPS, DEFAULT_NUM_GROUPS)


class VimInfoMeta(type):
    """An interface for accessing the vim's vars, buffer, cursors, etc.

    Static attributes:
        cursors: An instance of VimCursorsInfo, for accessing the cursor
                information in vim.
        highlight: An instance of VimHighlightInfo, for accessing the
                 information about highlight in vim.
        ENCODING: vim's encoding.
    """
    cursors = VimCursorsInfo()
    highlight = VimHighlightInfo()
    ENCODING = vim.eval('&encoding')

    def __init__(self, *args):
        """Constructor."""
        self._mode = None

    @property
    def lines(self):  # pylint: disable=R0201
        """Gets list of lines in the buffer."""
        return [VimInfo.transform_to_py(line) for line in vim.current.buffer[:]]

    @lines.setter
    def lines(self, lines):  # pylint: disable=R0201
        """Sets the buffer by list of lines."""
        tr = [VimInfo.transform_to_vim(line) for line in lines]
        vim.current.buffer[0 : len(vim.current.buffer)] = tr

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
        last_id = py_wvars.get(VARNAMES.GROUP_NAME_PREFIX + group_name, None)
        if last_id is not None and last_id > 0:
            vim.eval('matchdelete(%d)' % last_id)
            del py_wvars[VARNAMES.GROUP_NAME_PREFIX + group_name]
        if positions:
            rcs = [(rc[0] + 1, rc[1] + 1) for rc in positions]
            patterns = '\\|'.join(['\\%%%dl\\%%%dc' % rc for rc in rcs])
            mid = int(vim.eval("matchadd('%s', '%s', %d)" %
                               (group_name, patterns, priority)))
            if mid != -1:
                py_wvars[VARNAMES.GROUP_NAME_PREFIX + group_name] = mid

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


# Copy from https://bitbucket.org/gutworth/six/src/c17477e81e482d34bf3cda043b2eca643084e5fd/six.py
def with_metaclass(meta, *bases):
    """Create a base class with a metaclass."""
    class metaclass(meta):  # pylint: disable=W0232
        def __new__(cls, name, this_bases, d):
            return meta(name, bases, d)
    return type.__new__(metaclass, 'temporary_class', (), {})


class VimInfo(with_metaclass(VimInfoMeta, object)):  # pylint: disable=W0232
    """An interface for accessing the vim's vars, buffer, cursors, etc."""
    @staticmethod
    def init():
        """Initializes some settings."""
        VimInfo.cursors.update_text_lines()


########################### About connection to server #########################
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
            body = json.dumps(self.content)
            header_str = ('%%0%dd' % JSONPackage._HEADER_LENGTH) % len(body)
            send_func(header_str + body)
        except TypeError as e:
            raise JSONPackageError('json: %s' % str(e))
        except UnicodeError as e:
            raise JSONPackageError('Cannot encode the string: %s.' % str(e))

    def recv(self, recv_func):
        """Receives a json object from a gived function.

        It will calls the give function like this:
            recv_func(<num_of_bytes>) => bytes with length <num_of_bytes>

        Args:
            recv_func: A function to be called to get the serialize data.
        """
        try:
            header_str = unicode(recv_func(JSONPackage._HEADER_LENGTH),
                                 JSONPackage._ENCODING)
            body_str = unicode(recv_func(int(header_str)),
                               JSONPackage._ENCODING)
        except UnicodeError as e:
            raise JSONPackageError('Cannot decode the bytes: %r.' % e)
        except ValueError as e:
            raise JSONPackageError('Cannot get the body length %r' % e)
        try:
            self.content = json.loads(body_str)
        except ValueError as e:
            raise JSONPackageError('Cannot loads to the json object: %r' % e)


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
        self._conn.settimeout(py_bvars.get(VARNAMES.TIMEOUT, DEFAULT_TIMEOUT))

    def send_all(self, data):
        """Sends the data until timeout or the socket closed.

        Args:
            data: Data to be sent.
        """
        self._conn.sendall(data)

    def recv_all(self, nbyte):
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
        _conn: Connection.

    Static attributes:
        _conns: A dict stores connections.
    """
    _conns = {}
    def __init__(self, server_name, port_name):
        """Constructor, automatically connects to the server.

        Args:
            server_name: Server name.
            port_name: Port name.
        """
        key = (server_name, port_name)
        if key not in TCPClient._conns:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.connect((server_name, port_name))
                TCPClient._conns[key] = TCPConnection(sock)
            except TypeError as e:
                raise TCPClientError('Cannot connect to server: %s' % str(e))
            except socket.error as e:
                raise TCPClientError('Cannot connect to server: %s' % str(e))
        self._conn = TCPClient._conns[key]

    def request(self, req):
        """Sends a request to server and get the response.

        Args:
            req: An request.

        Return:
            The response.
        """
        try:
            JSONPackage(req).send(self._conn.send_all)
            return JSONPackage(recv_func=self._conn.recv_all).content
        except socket.error as e:
            raise TCPClientError(e)
        except JSONPackageError as e:
            raise TCPClientError(e)

    def close(self):
        """Closes the socket."""
        self._conn.close()
        for key, conn in TCPClient._conns.items():
            if conn is self._conn:
                del TCPClient._conns[key]
                break


################################ Some operations ###############################
def set_scopes():
    py_bvars.curr_scope = vim.current.buffer.number
    py_wvars.curr_scope = vim.current.window.number

def get_my_info(init):
    """Gets my information for server.

    Return:
        The information for server.
    """
    return {JSON_TOKEN.IDENTITY : py_bvars[VARNAMES.IDENTITY],
            JSON_TOKEN.INIT : init,
            JSON_TOKEN.MODE : VimInfo.mode,
            JSON_TOKEN.CURSORS : {
                CURSOR_MARK.CURRENT : VimInfo.cursors[CURSOR_MARK.CURRENT],
                CURSOR_MARK.V : VimInfo.cursors[CURSOR_MARK.V],
            },
            JSON_TOKEN.TEXT : VimInfo.text}


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
            set_other_visual(name, mode, last_rc, curr_rc)
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


############################## Supported operations ############################
def connect(server_name, server_port, identity):
    """Connects to the server.

    Args:
        server_name: Server name.
        server_port: Server port.
        identity: Identity string of this user.
    """
    set_scopes()
    py_bvars[VARNAMES.SERVER_NAME] = server_name
    py_bvars[VARNAMES.SERVER_PORT] = int(server_port)
    py_bvars[VARNAMES.IDENTITY] = identity
    sync(init=True)


def sync(init=False):
    """Sync with the server.

    Args:
        init: Flag for whether it should tell the server to reset this user or
                not.
    """
    set_scopes()
    if VARNAMES.SERVER_NAME in py_bvars:
        try:
            conn = TCPClient(py_bvars[VARNAMES.SERVER_NAME],
                             py_bvars[VARNAMES.SERVER_PORT])
            response = conn.request(get_my_info(init))
        except TCPClientError as e:
            print(str(e))
            return
        if JSON_TOKEN.ERROR in response:
            print(response[JSON_TOKEN.ERROR])
            return
        set_my_info(response)
        set_others_info(response)
        py_bvars[VARNAMES.USERS] = ', '.join(
            [user[JSON_TOKEN.NICKNAME] for user in response[JSON_TOKEN.OTHERS]])


def disconnect():
    """Disconnects with the server."""
    set_scopes()
    if VARNAMES.SERVER_NAME in py_bvars:
        VimInfo.highlight.reset([])
        VimInfo.highlight.render()
        try:
            conn = TCPClient(py_bvars[VARNAMES.SERVER_NAME],
                             py_bvars[VARNAMES.SERVER_PORT])
            conn.request({
                JSON_TOKEN.BYE : True,
                JSON_TOKEN.IDENTITY : py_bvars[VARNAMES.IDENTITY]})
        except TCPClientError as e:
            print(str(e))
        conn.close()
        del py_bvars[VARNAMES.SERVER_NAME]
        del py_bvars[VARNAMES.SERVER_PORT]
        del py_bvars[VARNAMES.IDENTITY]
        print('bye')


def show_info():
    """Shows the informations."""
    set_scopes()
    print('Highlight information:')
    print('Groups of normal cursor position:')
    for index in range(VimInfo.highlight.num_of_groups()):
        vim.command('hi %s' % NORMAL_CURSOR_GROUP(index))
    print('Groups of insert cursor position:')
    for index in range(VimInfo.highlight.num_of_groups()):
        vim.command('hi %s' % INSERT_CURSOR_GROUP(index))
    print('Groups of selection area:')
    for index in range(VimInfo.highlight.num_of_groups()):
        vim.command('hi %s' % VISUAL_GROUP(index))
    print('Users: %r' % py_bvars[VARNAMES.USERS])


def set_bvar(variable_name, value):
    """Sets the variable of the current buffer.

    Args:
        variable_name: Variable name.
        value: Value.
    """
    set_scopes()
    py_bvars[getattr(VARNAMES, variable_name)] = value
    print('bvars[%s] = %s' % (getattr(VARNAMES, variable_name), value))


################################## Initialize ##################################
VimInfo.init()

EOF
endfunction

"""""""""""""""""""""""""""""""" Initialize """"""""""""""""""""""""""""""""""""

if _SharedVimTryUsePython3(0) || _SharedVimTryUsePython2(0)
    let g:shared_vim_setupped = 1
endif
