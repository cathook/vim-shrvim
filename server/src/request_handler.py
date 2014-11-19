"""RequestHandler."""

import bisect
import difflib
import log

from users_text_manager import AUTHORITY
from users_text_manager import UserInfo


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


def apply_patch(orig_lines, patch_info):
    """Applies a patch.

    Args:
        orig_lines: Original lines of the text.
        patch_info: A list of replacing information.

    Return:
        A list of text.
    """
    new_lines, done_len = [], 0
    for beg, end, lines in patch_info:
        new_lines += orig_lines[done_len : beg]
        new_lines += lines
        done_len = end
    return new_lines + orig_lines[done_len : ]


def _squash_patch(patch_info):
    """Squash list of replacing information to a smaller mount of information.

    Args:
        patch_info: Information of patches.

    Return:
        A list of replacing information.
    """
    ret, index = [], 0
    while index < len(patch_info):
        lines = patch_info[index][2]
        index2 = index + 1
        while index2 < len(patch_info) and \
              patch_info[index2 - 1][1] >= patch_info[index2][0]:
            lines += patch_info[index2][2]
            index2 += 1
        ret.append((patch_info[index][0], patch_info[index2 - 1][1], lines))
        index = index2
    return ret


def gen_patch(orig_lines, new_lines):
    """Creates a patch from two lines text.

    Args:
        orig_lines: Original lines of the text.
        new_lines: New lines of the text.

    Return:
        A list of replacing information.
    """
    diff_result = list(difflib.Differ().compare(orig_lines, new_lines))
    orig_index, ret = 0, []
    for line in diff_result:
        if line.startswith('  '):
            orig_index += 1
        elif line.startswith('+ '):
            ret.append((orig_index, orig_index, [line[2 : ]]))
        elif line.startswith('- '):
            ret.append((orig_index, orig_index + 1, []))
            orig_index += 1
    return _squash_patch(ret)


class _CursorTransformer(object):
    """Transformer for format of the cursor position.

    In vim, it use (row, col) to represent an cursor's position.
    In UsersTextManager, it use numerical notation (byte distance between the
    first byte in the text).

    Attributes:
        _sum_len: Sum of each row.
    """
    def __init__(self):
        """Constructor."""
        self._sum_len = [0]

    def update_lines(self, lines):
        """Update lines of text.

        Args:
            lines: Lines of text.
        """
        self._sum_len = [0]
        for line in lines:
            delta = len(line) + 1  # "+ 1" is for newline char
            self._sum_len.append(self._sum_len[-1] + delta)

    def rcs_to_nums(self, rcs):
        """Transform row-col format's cursor position to numerical type.

        Args:
            lines: List of line text.
            rcs: List of tuple of row-col format cursor postions

        Return:
            A list of numerical cursor positions.
        """
        ret = []
        for rc in rcs:
            base = self._sum_len[min(rc[0], len(self._sum_len) - 1)]
            ret.append(min(base + rc[1], self._sum_len[-1]))
        return ret


    def nums_to_rcs(self, nums):
        """Transform numerical format's cursor position to row-col format.

        Args:
            lines: List of line text.
            nums: A list of numerical cursor positions.

        Return:
            List of tuple of row-col format cursor postions
        """
        ans, rmin = {}, 0
        for num in sorted(nums):
            row = bisect.bisect(self._sum_len, num, lo=rmin) - 1
            col = (num - self._sum_len[row]) if row < len(self._sum_len) else 0
            rmin = row + 1
            ans[num] = (row, col)
        return [ans[num] for num in nums]


class RequestHandler(object):
    """Handles all kinds of request.

    Attributes:
        _users_text_manager: An instance of UsersTextManager.
        _cursor_transformer: An instance of _CursorTransformer.
    """
    def __init__(self, users_text_manager):
        """Constructor.

        Args:
            users_text_manager: An instance of UsersTextManager.
        """
        super(RequestHandler, self).__init__()
        self._users_text_manager = users_text_manager
        self._cursor_transformer = _CursorTransformer()

    def handle(self, request):
        """Handles the request and returns the response.

        Args:
            request: The request.

        Return
            The respsonse.
        """
        if JSON_TOKEN.IDENTITY not in request:
            return {JSON_TOKEN.ERROR : 'Bad request.'}
        identity = request[JSON_TOKEN.IDENTITY]
        if identity not in self._users_text_manager.get_users_info():
            return {JSON_TOKEN.ERROR: 'Invalid identity.'}
        for handler in [self._try_handle_leave,
                        self._try_handle_sync]:
            response = handler(identity, request)
            if response is not None:
                break
        else:
            return {JSON_TOKEN.ERROR: 'Bad request.'}
        return response

    def _try_handle_leave(self, identity, request):
        """Trying to handle the leaving operation if it is.

        Args:
            identity: The identity of that user.
            request: The request from that user.
        """
        if JSON_TOKEN.BYE in request:
            self._users_text_manager.reset_user(identity)
            return {}

    def _try_handle_sync(self, identity, request):
        """Trying to handle the sync request if it is, otherwise return None.

        Args:
            identity: The identity of that user.
            request: The request from that user.
        """
        if all(key in request for key in [JSON_TOKEN.INIT, JSON_TOKEN.DIFF,
                                          JSON_TOKEN.MODE, JSON_TOKEN.CURSORS]):
            log.info('handle sync-request from %r\n' % identity)
            self._check_init(identity, request)
            self._check_authority(identity, request)
            lines = apply_patch(
                self._users_text_manager.get_user_text(identity).split('\n'),
                request[JSON_TOKEN.DIFF])
            self._cursor_transformer.update_lines(lines)
            cursors = dict(zip(request[JSON_TOKEN.CURSORS].keys(),
                               self._cursor_transformer.rcs_to_nums(
                                   request[JSON_TOKEN.CURSORS].values())))
            new_user_info, new_text = self._users_text_manager.update_user_text(
                identity,
                UserInfo(mode=request[JSON_TOKEN.MODE], cursors=cursors),
                '\n'.join(lines))
            return self._pack_sync_response(
                identity, new_user_info, new_text.split('\n'), lines)

    def _pack_sync_response(self, identity, user_info, lines, old_lines):
        """Packs the response for the sync request by the result from manager.

        Args:
            identity: Identity of that user.
            user_info: Informations of that user.
            lines: New lines of text.
            old_lines: Old lines of text.

        Return:
            The response json object.
        """
        self._cursor_transformer.update_lines(lines)
        return {
            JSON_TOKEN.DIFF : gen_patch(old_lines, lines),
            JSON_TOKEN.CURSORS : dict(zip(
                user_info.cursors.keys(),
                self._cursor_transformer.nums_to_rcs(
                    user_info.cursors.values()))),
            JSON_TOKEN.MODE : user_info.mode,
            JSON_TOKEN.OTHERS : self._pack_sync_others_response(identity)
        }

    def _pack_sync_others_response(self, identity):
        """Packs the response information for other users.

        Args:
            identity: Identity of that user.

        Return:
            The response json object.
        """
        return [
            {
                JSON_TOKEN.NICKNAME : other.nick_name,
                JSON_TOKEN.MODE : other.mode,
                JSON_TOKEN.CURSORS: dict(zip(
                    other.cursors.keys(),
                    self._cursor_transformer.nums_to_rcs(
                        other.cursors.values())))
            } for iden, other in self._users_text_manager.get_users_info(
                without=[identity], must_online=True).items()
        ]

    def _check_init(self, identity, request):
        """Checks whether that user should be initialize or not.

        If yes, it will reset that user and update the request.

        Args:
            identity: The identity of that user.
            request: The request from that user.
        """
        if request[JSON_TOKEN.INIT]:
            log.info('Init the user %r\n' % identity)
            self._users_text_manager.reset_user(identity)
            request[JSON_TOKEN.DIFF] = []
            for mark in request.get(JSON_TOKEN.CURSORS, []):
                request[JSON_TOKEN.CURSORS][mark] = (0, 0)

    def _check_authority(self, identity, request):
        """Checks the authroity and updates the request.

        If the user is not writeable, it will modify the request to let it looks
        like that the user did nothing.

        Args:
            identity: The identity of that user.
            request: The request from that user.
        """
        auth = self._users_text_manager.get_users_info()[identity].authority
        if auth < AUTHORITY.READWRITE:
            request[JSON_TOKEN.DIFF] = []
