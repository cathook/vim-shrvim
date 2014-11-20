"""""""""""""""""""""""""""""""""""" Commands """"""""""""""""""""""""""""""""""
command! -nargs=0 ShrVimTryUsePython3 call _ShrVimTryUsePython3(1)
command! -nargs=0 ShrVimTryUsePython2 call _ShrVimTryUsePython2(1)
command! -nargs=+ ShrVimConnect call _ShrVimCallPythonFunc('connect', [<f-args>])
command! -nargs=0 ShrVimDisconnect call _ShrVimCallPythonFunc('disconnect', [])
command! -nargs=0 ShrVimSync call _ShrVimCallPythonFunc('sync', [])
command! -nargs=0 ShrVimShowInfo call _ShrVimCallPythonFunc('show_info', [])
command! -nargs=1 ShrVimSetTimeout call _ShrVimCallPythonFunc('set_bvar', ['TIMEOUT', <f-args>])
command! -nargs=1 ShrVimSetNumOfGroups call _ShrVimCallPythonFunc('set_bvar', ['NUM_GROUPS', <f-args>])


""""""""""""""""""""""""""""""""""""" Setup """"""""""""""""""""""""""""""""""""
" Highlight for other users.
for i in range(0, 100)
    exec 'hi ShrVimNor' . i . ' ctermbg=darkyellow'
    exec 'hi ShrVimIns' . i . ' ctermbg=darkred'
    exec 'hi ShrVimVbk' . i . ' ctermbg=darkblue'
endfor


let g:shrvim_auto_sync_level = 3


" Auto commands
autocmd! InsertLeave * call _ShrVimAutoSync(1)
autocmd! CursorMoved * call _ShrVimAutoSync(1)
autocmd! CursorHold * call _ShrVimAutoSync(1)
autocmd! CursorMovedI * call _ShrVimAutoSync(3)
autocmd! CursorHoldI * call _ShrVimAutoSync(3)


""""""""""""""""""""""""""""""""""" Functions """"""""""""""""""""""""""""""""""
function! _ShrVimTryUsePython3(show_err)
    if has('python3')
        command! -nargs=* ShrVimPython python3 <args>
        call _ShrVimSetup()
        return 1
    else
        if a:show_err
            echoerr 'Sorry, :python3 is not supported in this version'
        endif
        return 0
    endif
endfunction


function! _ShrVimTryUsePython2(show_err)
    if has('python')
        command! -nargs=* ShrVimPython python <args>
        call _ShrVimSetup()
        return 1
    else
        if a:show_err
            echoerr 'Sorry, :python is not supported in this version'
        endif
        return 0
    endif
endfunction


function! _ShrVimCallPythonFunc(func_name, args)
    if exists('g:shrvim_setupped') && g:shrvim_setupped == 1
        if len(a:args) == 0
            exe 'ShrVimPython ' . a:func_name . '()'
        else
            let args_str = '"' . join(a:args, '", "') . '"'
            exe 'ShrVimPython ' . a:func_name . '(' . args_str . ')'
        endif
    endif
endfunction


function! _ShrVimAutoSync(level)
    let level = g:shrvim_auto_sync_level
    if exists('b:shrvim_auto_sync_level')
        let level = b:shrvim_auto_sync_level
    endif
    if a:level <= level
        ShrVimSync
    endif
endfunction


function! _ShrVimSetup()
ShrVimPython << EOF
# python << EOF
# ^^ Force vim highlighting the python code below.
import json
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
    GROUP_NAME_PREFIX = 'gnp_'  # Group name's prefix.
    IDENTITY = 'identity'  # Identity of the user.
    INIT = 'init'  # Initial or not.
    LINES = 'lines'  # Lines.
    NUM_GROUPS = 'num_groups'  # Number of groups.
    SERVER_NAME = 'server_name'  # Server name.
    SERVER_PORT = 'port'  # Server port.
    TIMEOUT = 'timeout'  # Timeout for TCPConnection.
    USERS = 'users'  # List of users.

# Name of the normal cursor group.
NORMAL_CURSOR_GROUP = lambda x: 'ShrVimNor%d' % x

# Name of the insert cursor group.
INSERT_CURSOR_GROUP = lambda x: 'ShrVimIns%d' % x

# Name of the visual group.
VISUAL_GROUP = lambda x: 'ShrVimVbk%d' % x


DEFAULT_TIMEOUT = 1
DEFAULT_NUM_GROUPS = 5


class JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
    BYE = 'bye'  # Resets the user and do nothong.
    CURSORS = 'cursors'  # other users' cursor position
    DIFF = 'diff'  # Difference between this time and last time.
    ERROR = 'error'  # error string
    IDENTITY = 'identity'  # identity of myself
    INIT = 'init'  # initialize connect flag
    MODE = 'mode'  # vim mode.
    NICKNAME = 'nickname'  # nick name of the user.
    OTHERS = 'others'  # other users info.


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
    def __getitem__(self, mark):  # pylint: disable=R0201
        """Gets the cursor position with specifying the mark.

        Args:
            mark: Mark of the cursor to get.

        Return:
            Cursor position.
        """
        pos = [int(x) for x in vim.eval('getpos("%s")' % mark)]
        row = pos[1] - 1
        line = VimInfo.transform_to_vim(VimInfo.lines[row])
        col = len(VimInfo.transform_to_py(line[ : pos[2] - 1]))
        return (row, col)

    def __setitem__(self, mark, rc):  # pylint: disable=R0201
        """Sets the cursor position with specifying the mark.

        Args:
            mark: Mark of the cursor to set.
            rc: The new cursor position.
        """
        row, col = self.transform_to_vim(rc)
        mark = mark if mark != CURSOR_MARK.V else CURSOR_MARK.CURRENT
        vim.eval('setpos("%s", [0, %d, %d, 0])' % (mark, row + 1, col + 1))

    def transform_to_vim(self, rc):  # pylint: disable=R0201
        """Transform rc in utf-8 to rc in bytes.

        Args:
            rc: Cursor position.

        Return:
            Cursor position.
        """
        row = rc[0]
        line = VimInfo.lines[row] if row < len(VimInfo.lines) else ''
        col = len(VimInfo.transform_to_vim(line[ : rc[1]]))
        return (row, col)


class GroupInfo(object):
    """Higilights informations about a user group.

    Attributes:
        _normal_cursor_ranges: List of highlight block ranges in normal mode.
        _insert_cursor_ranges: List of highlight block ranges in insert mode.
        _visual_ranges: List of highlight block ranges in visual blocks.
    """
    def __init__(self):
        """Constructor."""
        self._normal_cursor_ranges = []
        self._insert_cursor_ranges = []
        self._visual_ranges = []

    def set_mode_cursor(self, mode, rc):
        """Sets the mode and the cursor.

        Args:
            mode: The mode.
            rc: The cursor position.
        """
        if mode in (MODE.INSERT, MODE.REPLACE):
            self._insert_cursor_ranges.append((rc[0], rc[1], rc[1] + 1))
        else:
            self._normal_cursor_ranges.append((rc[0], rc[1], rc[1] + 1))

    def add_visual(self, rang):
        """Add a visual position.

        Args:
            rang: The position.
        """
        self._visual_ranges += [rang]

    @property
    def normal_cursor_ranges(self):
        """Gets the normal cursor ranges."""
        return self._normal_cursor_ranges

    @property
    def insert_cursor_ranges(self):
        """Gets the insert cursor ranges."""
        return self._insert_cursor_ranges

    @property
    def visual_ranges(self):
        """Gets the visual ranges."""
        return self._visual_ranges


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
                          self._groups[index].normal_cursor_ranges)
            VimInfo.match(INSERT_CURSOR_GROUP(index), MATCH_PRI.INSERT,
                          self._groups[index].insert_cursor_ranges)
            VimInfo.match(VISUAL_GROUP(index), MATCH_PRI.VISUAL,
                          self._groups[index].visual_ranges)

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


class VimLinesInfo(object):
    """An interface for accessing the vim's buffer.

    Attributes:
        _lines: An list of lines, which is encoded text got from vim.buffer.
    """
    def __init__(self):
        """Constructor."""
        self._lines = [VimInfo.transform_to_py(line)
                       for line in vim.current.buffer]

    def __getitem__(self, index):
        """Get a specified line.

        Args:
            index: The line number.
        """
        return self._lines[index]

    def __setitem__(self, index, text):
        """Sets a specified line.

        Args:
            index: The line number.
            text: The new text.
        """
        self._lines[index] = text
        if isinstance(index, slice):
            lines = [VimInfo.transform_to_vim(line) for line in text]
            if index.start is not None and index.stop is not None:
                vim.current.buffer[index.start : index.stop] = lines
            elif index.start is None and index.stop is not None:
                vim.current.buffer[ : index.stop] = lines
            elif index.start is not None and index.stop is None:
                vim.current.buffer[index.start : ] = lines
            else:
                vim.current.buffer[:] = lines
        else:
            vim.current.buffer[index] = VimInfo.transform_to_vim(text)

    def __len__(self):
        """Gets the number of rows."""
        return len(self._lines)

    def gen_patch(self, orig_lines):
        """Creates a patch from an old one.

        Args:
            orig_lines: Original lines of the text.

        Return:
            A list of replacing information.
        """
        orig_rows, new_rows = len(orig_lines), len(self._lines)
        for first in range(min(orig_rows, new_rows)):
            if orig_lines[first] != self._lines[first]:
                break
        else:
            if orig_rows < new_rows:
                return [(orig_rows, orig_rows, self._lines[orig_rows : ])]
            elif orig_rows > new_rows:
                return [(first + 1, orig_rows, [])]
            else:
                return []
        delta = new_rows - orig_rows
        for last in range(orig_rows - 1, first - 1, -1):
            if orig_lines[last] != self._lines[last + delta]:
                break
        else:
            last -= 1
        return [(first, last + 1, self._lines[first : last + delta + 1])]

    def apply_patch(self, patch_info):
        """Applies a patch.

        Args:
            patch_info: A list of replacing information.

        Return:
            A list of text.
        """
        offset = 0
        for beg, end, lines in patch_info:
            self.__setitem__(slice(beg + offset, end + offset), lines)
            offset += len(lines) - (end - beg)


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
        self._lines = None

    def init(self):
        """Initialize informations for this time."""
        self._lines = VimLinesInfo()

    @property
    def lines(self):
        """Gets list of lines in the buffer."""
        return self._lines

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
            rcs = []
            for row, col_beg, col_end in positions:
                col_beg = VimInfo.cursors.transform_to_vim((row, col_beg))[1]
                col_end = VimInfo.cursors.transform_to_vim((row, col_end))[1]
                rcs += [(row, col) for col in range(col_beg, col_end)]
            patterns = '\\|'.join(['\\%%%dl\\%%%dc' % (rc[0] + 1, rc[1] + 1)
                                   for rc in rcs])
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

    @staticmethod
    def display_width(data):
        """Gets the width for the data to be display.

        Args:
            data: The data.

        Return:
            A number.
        """
        return vim.strwidth(VimInfo.transform_to_vim(data))

    @staticmethod
    def confirm(prompt, options=None, default=None):
        """Confirm something from the user.

        Args:
            prompt: Prompt string.
            options: List of options.
            default: Default option.
        """
        if options is None:
            ret = vim.eval('confirm("%s")' % prompt)
        elif default is None:
            ret = vim.eval('confirm("%s", "%s")' %
                           (prompt, '\\n'.join('&' + o for o in options)))
        else:
            ret = vim.eval('confirm("%s", "%s", "%s")' %
                           (prompt, '\\n'.join('&' + o for o in options),
                            default))
        return int(ret) - 1

# Copy from https://bitbucket.org/gutworth/six/src/c17477e81e482d34bf3cda043b2eca643084e5fd/six.py
def with_metaclass(meta, *bases):
    """Create a base class with a metaclass."""
    class metaclass(meta):  # pylint: disable=W0232
        def __new__(cls, name, this_bases, d):
            return meta(name, bases, d)
    return type.__new__(metaclass, 'temporary_class', (), {})


class VimInfo(with_metaclass(VimInfoMeta, object)):  # pylint: disable=W0232
    """An interface for accessing the vim's vars, buffer, cursors, etc."""
    pass


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
            self.close()
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
def init_for_this_time():
    py_bvars.curr_scope = vim.current.buffer
    py_wvars.curr_scope = vim.current.window
    VimInfo.init()

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
            JSON_TOKEN.DIFF : VimInfo.lines.gen_patch(
                py_bvars.get(VARNAMES.LINES, ['']))}


def set_my_info(json_info):
    """Sets my information gived by server.

    Args:
        json_info: JSON information gived by server.
    """
    VimInfo.lines.apply_patch(json_info[JSON_TOKEN.DIFF])
    py_bvars[VARNAMES.LINES] = VimInfo.lines[:]
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
        curr_rc = cursors[CURSOR_MARK.CURRENT]
        VimInfo.highlight[name].set_mode_cursor(mode, curr_rc)
        if mode in (MODE.VISUAL, MODE.LINE_VISUAL, MODE.BLOCK_VISUAL):
            last_rc = cursors[CURSOR_MARK.V]
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
            col_beg = 0 if row != beg[0] else beg[1]
            col_end = (len(VimInfo.lines[row]) if row != end[0] else end[1]) + 1
            VimInfo.highlight[name].add_visual((row, col_beg, col_end))
    elif mode == MODE.LINE_VISUAL:
        for row in range(beg[0], end[0] + 1):
            VimInfo.highlight[name].add_visual(
                (row, 0, len(VimInfo.lines[row]) + 1))
    elif mode == MODE.BLOCK_VISUAL:
        set_other_block_visual(name, beg, end)


def set_other_block_visual(name, beg, end):
    """Sets the other user's virtical-visual block.

    Args:
        name: Name of this user.
        beg: The first row-column position of the range.
        end: The last row-column position of the range.
    """
    w1 = VimInfo.display_width(VimInfo.lines[beg[0]][ : beg[1]])
    w2 = VimInfo.display_width(VimInfo.lines[end[0]][ : end[1]])
    left, right = min(w1, w2), max(w1, w2)
    for row in range(beg[0], end[0] + 1):
        for beg_col in range(len(VimInfo.lines[row]) + 1):
            w = VimInfo.display_width(VimInfo.lines[row][ : beg_col])
            if left < w:
                beg_col -= 1
                break
        else:
            continue
        for end_col in range(beg_col, len(VimInfo.lines[row]) + 1):
            w = VimInfo.display_width(VimInfo.lines[row][ : end_col])
            if right < w:
                break
        VimInfo.highlight[name].add_visual((row, beg_col, end_col))


############################## Supported operations ############################
def connect(server_name, server_port, identity):
    """Connects to the server.

    Args:
        server_name: Server name.
        server_port: Server port.
        identity: Identity string of this user.
    """
    init_for_this_time()
    if len(VimInfo.lines) > 1 or len(VimInfo.lines[0]) > 0:
        c = VimInfo.confirm(
            'This tool will rewrite the whole buffer, continue? ',
            ['Yes', 'No'], 'No')
        if c != 0:
            return
    VimInfo.lines[:] = ['']
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
    init_for_this_time()
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
    init_for_this_time()
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
    init_for_this_time()
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
    init_for_this_time()
    py_bvars[getattr(VARNAMES, variable_name)] = value
    print('bvars[%s] = %s' % (getattr(VARNAMES, variable_name), value))

EOF
endfunction

"""""""""""""""""""""""""""""""" Initialize """"""""""""""""""""""""""""""""""""

if _ShrVimTryUsePython3(0) || _ShrVimTryUsePython2(0)
    let g:shrvim_setupped = 1
endif
