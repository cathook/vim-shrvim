"""""""""""""""""""""""" Global variable for settings """"""""""""""""""""""""""
if !exists('g:shared_vim_force_to_use')
    let g:shared_vim_python3_first = 1
endif


if !exists('g:shared_vim_timeout')
    let g:shared_vim_timeout = 5
endif


if !exists('g:shared_vim_num_groups')
    let g:shared_vim_num_groups = 5
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
    unlet! b:shared_vim_server_name
    unlet! b:shared_vim_port
    unlet! b:shared_vim_identity
    unlet! b:shared_vim_init
    let b:shared_vim_todo = 'disconnect'
    call SharedVimMainFunc()
endfunction


function! SharedVimSync()
    let b:shared_vim_todo = 'sync'
    call SharedVimMainFunc()
    let b:shared_vim_init = 0
endfunction


"""""""""""""""""""""""""""" Setup for this plugin """""""""""""""""""""""""""""
" Highlight for other users.
for i in range(1, 5)
    exec 'hi SharedVimNor' . i . ' ctermbg=darkyellow'
    exec 'hi SharedVimIns' . i . ' ctermbg=darkred'
    exec 'hi SharedVimVbk' . i . ' ctermbg=darkblue'
endfor


" Sync
autocmd! CursorMoved * call  SharedVimSync()
autocmd! CursorMovedI * call SharedVimSync()
autocmd! CursorHold * call   SharedVimSync()
autocmd! CursorHoldI * call  SharedVimSync()
autocmd! InsertEnter * call  SharedVimSync()
autocmd! InsertLeave * call  SharedVimSync()


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
import socket
import vim
import zlib

TIMEOUT = 5

NUM_GROUPS = 5
NORMAL_CURSOR_GROUPS = ['SharedVimNor%d' % i for i in range(1, NUM_GROUPS + 1)]
INSERT_CURSOR_GROUPS = ['SharedVimIns%d' % i for i in range(1, NUM_GROUPS + 1)]
VISUAL_GROUPS = ['SharedVimVbk%d' % i for i in range(1, NUM_GROUPS + 1)]

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

class _JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
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


class _VimVarInfo(object):
    """Gets/sets the variable in vim."""
    def __init__(self):
        """Constructor."""
        pass

    def __getattr__(self, variable_name):
        """Gets the specified vim variable.

        Args:
            variable_name: Variable name.

        Returns:
            None if the value is not exists, otherwise the value.
        """
        if variable_name not in vim.current.buffer.vars:
            return None
        ret = vim.current.buffer.vars[variable_name]
        if isinstance(ret, bytes):
            return ret.decode(JSONPackage.ENCODING)
        return ret

    def __setattr__(self, variable_name, value):
        """Sets the specifiec vim variable.

        Args:
            variable_name: Variable name.
            value: Value.
        """
        vim.current.buffer.vars[variable_name] = value

    def __getitem__(self, variable_name):
        """Gets the specified vim variable.

        Args:
            variable_name: Variable name.

        Returns:
            None if the value is not exists, otherwise the value.
        """
        return self.__getattr__(variable_name)

    def __setitem__(self, variable_name, value):
        """Sets the specifiec vim variable.

        Args:
            variable_name: Variable name.
            value: Value.
        """
        self.__setattr__(variable_name, value)

    def __delitem__(self, variable_name):
        """Deletes the specified vim variable.

        Args:
            variable_name: Variable name.
        """
        del vim.current.buffer.vars[variable_name]


class _VimCursorsInfo(object):
    """Gets/sets the cursor in vim.

    Attributes:
        _info: A instance of VimInfo.
    """
    def __init__(self, info):
        """Constructor.

        Args:
            info: An instance of VimInfo.
        """
        self._info = info

    def __getitem__(self, mark):
        """Gets the cursor position.

        Args:
            mark: Which cursor.

        Return:
            Cursor position.
        """
        pos = [int(x) for x in vim.eval('getpos("%s")' % mark)]
        return self._info.rc_to_num((pos[1] - 1, pos[2] - 1))

    def __setitem__(self, mark, value):
        """Sets the cursor position.

        Args:
            mark: Which cursor.
        """
        pos = self._info.num_to_rc(value)
        if mark == CURSOR_MARK.V:
            mark = CURSOR_MARK.CURRENT
        vim.eval('setpos("%s", [0, %d, %d, 0])' %
                 (mark, pos[0] + 1, pos[1] + 1))


class _GroupInfo(object):
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
        return self._normal_cursor_positions

    @property
    def insert_cursor_positions(self):
        return self._insert_cursor_positions

    @property
    def visual_positions(self):
        return self._visual_positions


class _VimHighlightInfo(object):
    """Highlight informations about users.

    Attributes:
        _info: A instance of VimInfo.
        _groups: A list of instance of GroupInfo.
        _username_to_group: A dict for mapping the username to the instance of
            GroupInfo.
    """
    def __init__(self, info):
        """Constructor.

        Args:
            info: An instance of VimInfo.
        """
        self._info = info
        self._groups = [_GroupInfo() for unused_i in range(NUM_GROUPS)]
        self._username_to_group = {}

    def __getitem__(self, name):
        """Gets the cursor position.

        Args:
            name: User name.

        Return:
            Cursor position.
        """
        return self._username_to_group[name]

    def _get_group_id(self, string):
        """Transform the gived string to a valid group index.

        Args:
            string: The gived string.

        Return:
            The index in range(0, NUM_GROUPS)
        """
        x = 0
        for c in string:
            x = (x * 23 + ord(c)) % NUM_GROUPS
        return x

    def reset(self, usernames):
        """Reset the users.

        Args:
            usernames: A list of username.
        """
        self._username_to_group = {}
        for name in usernames:
            gid = self._get_group_id(name)
            self._username_to_group[name] = self._groups[gid]

    def render(self):
        """Render the highlight to vim."""
        for index in range(NUM_GROUPS):
            self._info.match(NORMAL_CURSOR_GROUPS[index], MATCH_PRI.NORMAL,
                             self._groups[index].normal_cursor_positions)
            self._info.match(INSERT_CURSOR_GROUPS[index], MATCH_PRI.INSERT,
                             self._groups[index].insert_cursor_positions)
            self._info.match(VISUAL_GROUPS[index], MATCH_PRI.VISUAL,
                             self._groups[index].visual_positions)


class VimInfo(object):
    """Gets/sets the information about vim.

    Attributes:
        _cursor_info: An instance of _VimCursorInfo.
        _highlight_info: An instance of _VimHighlightInfo.
        _mode: Last mode.
        _text_num_sum: ...
        _var_info: An instance of VimVarInfo.
    """
    def __init__(self):
        """Constructor."""
        self._var_info = _VimVarInfo()
        self._cursor_info = _VimCursorsInfo(self)
        self._highlight_info = _VimHighlightInfo(self)
        self._text_num_sum = []
        self._mode = None
        self._calc_text_num_sum(vim.current.buffer[:])

    @property
    def text(self):
        """Gets the buffer text."""
        return '\n'.join(vim.current.buffer[:])

    @text.setter
    def text(self, value):
        """Sets the buffer text."""
        lines = re.split('\n', value)
        if not lines:
            lines = ['']
        buflen = len(vim.current.buffer)
        vim.current.buffer[0 : buflen] = lines
        self._calc_text_num_sum(lines)

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

    @property
    def cursors(self):
        """Gets/sets the cursor information.  Delegates to VimCursorInfo."""
        return self._cursor_info

    @property
    def highlight(self):
        """Gets/sets the highlight info.  Delegates to VimHighlightInfo."""
        return self._highlight_info

    def match(self, group_name, priority, positions):
        """Set the match informations.

        Args:
            group_name: Group name.
            priority: Priority for the vim function matchadd().
            positions: List of row-column position.
        """
        last_id = self.var['shared_vim_' + group_name]
        if last_id is not None and last_id > 0:
            ret = vim.eval('matchdelete(%d)' % int(last_id))
            del self.var['shared_vim_' + group_name]
        if positions:
            rcs = [(rc[0] + 1, rc[1] + 1) for rc in positions]
            patterns = '\\|'.join(['\\%%%dl\\%%%dc' % rc for rc in rcs])
            mid = int(vim.eval("matchadd('%s', '%s', %d)" %
                               (group_name, patterns, priority)))
            if mid != -1:
                self.var['shared_vim_' + group_name] = mid

    @property
    def var(self):
        """Gets/sets the var information.  Delegates to VimVarInfo."""
        return self._var_info

    def rowlen(self, row):
        """Gets the length of a specified row.

        Args:
            row: The specified line row.

        Return:
            Length of that row.
        """
        prev = 0 if row == 0 else self._text_num_sum[row - 1]
        return self._text_num_sum[row] - prev - 1

    def num_to_rc(self, num, rmin=0):
        """Transforms byte position to row-column cursor position.

        Args:
            num: byte cursor position.

        Return:
            List of row-column position.
        """
        row = bisect.bisect_right(self._text_num_sum, num, lo=rmin)
        col = num - (0 if row == 0 else self._text_num_sum[row - 1])
        return (row, col)

    def nums_to_rcs(self, nums):
        """Transforms list of sorted byte positions.

        Args:
            nums: list of byte cursor positions.

        Return:
            List of row-column positions.
        """
        ret = []
        last_r = 0
        for num in nums:
            my_rc = self.num_to_rc(num, rmin=last_r)
            ret += [my_rc]
            last_r = my_rc[0]
        return ret

    def rc_to_num(self, rc):
        """Transforms row-column cursor position to bytes position.

        Args:
            rc: Row-column cursor position.

        Return:
            byte position.
        """
        return rc[1] + (self._text_num_sum[rc[0] - 1] if rc[0] > 0 else 0)

    def _calc_text_num_sum(self, lines):
        """Calculates the sum bytes of each line.

        Args:
            lines: Lines of text.
        """
        self._text_num_sum, pre = [], 0
        for index in range(len(lines)):
            self._text_num_sum += [pre + len(lines[index]) + 1]
            pre += len(lines[index]) + 1


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


class TCPClientError(Exception):
    """Exception raised by TCPClient."""
    pass

class TCPClient(object):
    """TCP client.

    Attributes:
        _sock: Connection.
    """
    def __init__(self, vim_info):
        """Constructor, automatically connects to the server.

        Args:
            vim_info: An instane of VimInfo.
        """
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect((vim_info.var.shared_vim_server_name,
                          vim_info.var.shared_vim_port))
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


def get_my_info(vim_info):
    """Gets my information for server.

    Args:
        vim_info: An instance of VimInfo.

    Return:
        The information for server.
    """
    return {
        _JSON_TOKEN.IDENTITY : vim_info.var.shared_vim_identity,
        _JSON_TOKEN.INIT : vim_info.var.shared_vim_init,
        _JSON_TOKEN.MODE : vim_info.mode,
        _JSON_TOKEN.CURSORS : {
            CURSOR_MARK.CURRENT : vim_info.cursors[CURSOR_MARK.CURRENT],
            CURSOR_MARK.V : vim_info.cursors[CURSOR_MARK.V],
        },
        _JSON_TOKEN.TEXT : vim_info.text,
    }


def set_my_info(vim_info, json_info):
    """Sets my information gived by server.

    Args:
        vim_info: An instance of VimInfo.
        json_info: JSON information gived by server.
    """
    vim_info.text = json_info[_JSON_TOKEN.TEXT]
    mode = json_info[_JSON_TOKEN.MODE]
    vim_info.mode = mode
    if mode in (MODE.VISUAL, MODE.BLOCK_VISUAL, MODE.LINE_VISUAL):
        old_mode, vim_info.mode = mode, MODE.NORMAL
        vim_info.cursors[CURSOR_MARK.V] = \
                json_info[_JSON_TOKEN.CURSORS][CURSOR_MARK.V]
        vim_info.mode = old_mode
    vim_info.cursors[CURSOR_MARK.CURRENT] = \
            json_info[_JSON_TOKEN.CURSORS][CURSOR_MARK.CURRENT]


def set_others_info(vim_info, json_info):
    """Sets the informations about other user.

    Args:
        vim_info: An instance of VimInfo.
        json_info: JSON information gived by server.
    """
    users = json_info[_JSON_TOKEN.OTHERS]
    vim_info.highlight.reset([user[_JSON_TOKEN.NICKNAME] for user in users])
    for user in users:
        name, mode = user[_JSON_TOKEN.NICKNAME], user[_JSON_TOKEN.MODE]
        cursors = user[_JSON_TOKEN.CURSORS]
        curr_rc = vim_info.num_to_rc(cursors[CURSOR_MARK.CURRENT])
        vim_info.highlight[name].set_mode_cursor(mode, curr_rc)
        if mode in (MODE.VISUAL, MODE.LINE_VISUAL, MODE.BLOCK_VISUAL):
            last_rc = vim_info.num_to_rc(cursors[CURSOR_MARK.V])
            if last_rc[0] > curr_rc[0] or \
                    (last_rc[0] == curr_rc[0] and last_rc[1] > curr_rc[1]):
                last_rc, curr_rc = curr_rc, last_rc
            set_other_visual(vim_info, name, mode, last_rc, curr_rc)
    vim_info.highlight.render()

def set_other_visual(vim_info, name, mode, beg, end):
    """Sets the other user's visual block.

    Args:
        vim_info: An instance of VimInfo.
        name: Name of this user.
        mode: Mode of this user.
        beg: The first row-column position of the range.
        end: The last row-column position of the range.
    """
    if mode == MODE.VISUAL:
        for row in range(beg[0], end[0] + 1):
            first = 0 if row != beg[0] else beg[1]
            last = vim_info.rowlen(row) if row != end[0] else end[1]
            for col in range(first, last + 1):
                vim_info.highlight[name].add_visual((row, col))
    elif mode == MODE.LINE_VISUAL:
        for row in range(beg[0], end[0] + 1):
            for col in range(0, vim_info.rowlen(row)):
                vim_info.highlight[name].add_visual((row, col))
    elif mode == MODE.BLOCK_VISUAL:
        left, right = min([beg[1], end[1]]), max([beg[1], end[1]])
        for row in range(beg[0], end[0] + 1):
            for col in range(left, right + 1):
                vim_info.highlight[name].add_visual((row, col))


def setup_default_value(info):
    """Setups the default from the gived vim_info.
    
    Args:
        vim_info: An instance of VimInfo.
    """
    TIMEOUT = info.var.shared_vim_timeout
    NUM_GROUPS = info.var.shared_vim_num_groups


def main():
    """Main function."""
    try:
        vim_info = VimInfo()
        setup_default_value(vim_info)
        conn = TCPClient(vim_info)
        response = conn.request(get_my_info(vim_info))
        conn.close()
        if _JSON_TOKEN.ERROR in response:
            raise Exception(response[_JSON_TOKEN.ERROR])
        set_my_info(vim_info, response)
        set_others_info(vim_info, response)
    except TCPClientError as e:
        print(e)
    except Exception as e:
        import sys
        print('?? %r' % e)

main()
EOF
endfunction
