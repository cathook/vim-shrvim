"""TextChain."""

import difflib
import log


class TextChain(object):
    """Text chain to handle various between each commit.

    Attributes:
        _save_filename: Name of the file to stores the content of the buffer.
        _commits: A list of 2-tuple which likes:
            first element: The commit id.
            second element: The instance of _TextCommit.
        _last_commit: An instance of _TextCommit, cache the last commit for
                updating the cursor position after commiting.
    """
    def __init__(self, save_filename):
        """Constructor.

        Args:
            save_filename: Name of the file to save the lastest commit text.
        """
        self._save_filename = save_filename
        content = ''
        try:
            with open(save_filename, 'r') as f:
                content = f.read()
        except IOError:
            log.info('Cannot load the default text.')
        self._commits = [
            (0, _TextCommit('', '')),
            (1, _TextCommit('', content))]
        self._last_commit = None

    def commit(self, orig_id, new_text, cursors):
        """Commits a update.

        Args:
            orig_id: Original commit id.
            new_text: Updated text.
            cursors: Cursors to rebase at the same time.

        Return:
            A 3-tuple for new commit id, new text and the rebased cursors.
        """
        old_index = self._get_commit_index(orig_id)
        commit = _TextCommit(self._commits[old_index][1].text, new_text)
        cursors_info = [commit.get_cursor_info(cur) for cur in cursors]
        commit.apply_commits([cm[1] for cm in self._commits[old_index + 1 :]])
        self._last_commit = commit.copy()
        new_id = self._commits[-1][0] + 1
        for info in cursors_info:
            info.apply_commits([cm[1] for cm in self._commits[old_index + 1 :]])
        new_cursors = [cursor_info.position for cursor_info in cursors_info]
        self._commits.append((new_id, commit))
        self.delete(orig_id)
        self._save()
        return new_id, commit.text, new_cursors

    def update_cursors(self, cursors):
        """Updates the cursors by the last commit.

        Args:
            cursors: List of cursor position.

        Return:
            List of updated cursor position.
        """
        cursors_info = [_CursorInfo_OnOrigText(cursor) for cursor in cursors]
        for cursor_info in cursors_info:
            cursor_info.apply_commits([self._last_commit])
        return [cursor_info.position for cursor_info in cursors_info]

    def new(self):
        """Creates an empty commit.

        Return:
            The commit id of the new commit.
        """
        commit_id = self._commits[0][0]
        self._commits.insert(0, (commit_id - 1, _TextCommit('', '')))
        return commit_id

    def delete(self, commit_id):
        """Deletes a commit.

        Args:
            commit_id: The id of the commit to be delete.
        """
        index = self._get_commit_index(commit_id)
        if index + 1 < len(self._commits):
            pre_text = self._commits[index - 1][1].text
            nxt_text = self._commits[index + 1][1].text
            self._commits[index + 1] = (self._commits[index + 1][0],
                                        _TextCommit(pre_text, nxt_text))
        del self._commits[index]

    def get_text(self, commit_id):
        """Gets the text of a specified commit.

        Args:
            commit_id: Id of that commit.

        Return:
            The text.
        """
        return self._commits[self._get_commit_index(commit_id)][1].text

    def _get_commit_index(self, commit_id):
        """Gets the index of the commits from gived commit id.

        Args:
            commit_id: Commit id.

        Returns:
            Index of the corrosponding commit.
        """
        for index in range(len(self._commits)):
            if self._commits[index][0] == commit_id:
                return index

    def _save(self):
        """Saves the last text to the file."""
        try:
            with open(self._save_filename, 'w') as f:
                f.write(self._commits[-1][1].text)
        except IOError:
            log.info('Cannot save the text to the file.')


def _opers_apply_opers(orig_opers, opers_tobe_applied):
    """Let a list of operations apply another list of operations.

    Args:
        orig_opers: List of instance of _ChgTextOper.
        opers_tobe_applied: List of instance of _ChgTextOper.

    Return:
        A list of instance of _ChgTextOper, which are the ones applied the
        opers_tobe_applied from the orig_opers.
    """
    ret = orig_opers
    for oper_tobe_applied in opers_tobe_applied:
        # The operation might split into multiple operations after rebasing,
        # So here we needs to use another list to stores the new operations.
        updated_opers = []
        for orig_oper in ret:
            updated_opers += orig_oper.apply_oper(oper_tobe_applied)
        ret = updated_opers
    return ret


class _TextCommit(object):
    """Stores a text commit.

    It includes a final text after commited and a sequence of _ChgTextOper for
    changing the original string to the new one.

    Attributes:
        _text: The final text.
        _opers: List of operations for changing the original string to the new
                one.
    """
    def __init__(self, old_text, new_text):
        """Constructor.

        Args:
            old_text: The original text.
            new_text: The final text after commited.
        """
        self._text = new_text
        self._opers = []
        diff = difflib.SequenceMatcher(a=old_text, b=new_text)
        for tag, begin, end, begin2, end2 in diff.get_opcodes():
            if tag in ('replace', 'delete', 'insert'):
                self._opers.append(
                    _ChgTextOper(begin, end, new_text[begin2 : end2]))

    @property
    def text(self):
        """Gets the final text after this commit."""
        return self._text

    @property
    def opers(self):
        """Gets the operations of this commit."""
        return self._opers

    @property
    def increased_length(self):
        """Gets the increased length of this commit."""
        return sum([o.increased_length for o in self._opers])

    def copy(self):
        """Returns a copy of myself.

        Return:
            An instance of _TextCommit.
        """
        ret = _TextCommit('', '')
        ret._text = self.text
        ret._opers = [_ChgTextOper(oper.begin, oper.end, oper.new_text)
                      for oper in self._opers]
        return ret

    def apply_commits(self, commits):
        """Applies a list of commits before this occured.

        Args:
            commits: A list of instance of _TextCommit.
        """
        if commits:
            for commit in commits:
                self._opers = _opers_apply_opers(self._opers, commit._opers)
            self._rebase_text(commits[-1].text)

    def get_cursor_info(self, cursor_pos):
        """Gets the cursor information by gived cursor position.

        If the cursor position is in a place that will be modified at this
        commit, it will return _CursorInfo_OnNewCommit;  Otherwise it will
        return _CursorInfo_OnOrigText.
        Ex:
            The original text with the only oper be "Chage [4, 9) to another
            string":
                0 1 2 3 4 5 6 7 8 91011121314
                a b c d[e f g h i]j k l m n o
               ^ ^ ^ ^ | | | | | | ^ ^ ^ ^ ^ ^
               Then for the "^", they belone to _CursorInfo_OnOrigText;
               Otherwise they belone to _CursorInfo_OnNewCommit.

        Args:
            cursor_pos: Position of the cursor.

        Return:
            A instance of _CursorInfo_OnNewCommit or _CursorInfo_OnOrigText.
        """
        for oper in self._opers:
            if oper.begin <= cursor_pos <= oper.end:
                return _CursorInfo_OnNewCommit(oper, cursor_pos - oper.begin)
        return _CursorInfo_OnOrigText(cursor_pos)

    def _rebase_text(self, new_orig_text):
        """Rebase the original text to another text.

        Args:
            new_orig_text: The new text.
        """
        end_index = 0
        self._text = ''
        for oper in self._opers:
            self._text += new_orig_text[end_index : oper.begin]
            self._text += oper.new_text
            end_index = oper.end
        self._text += new_orig_text[end_index : ]


class _CursorInfo_OnNewCommit(object):
    """About the cursor position who is at the place changed in the new commit.

    Attributes:
        _opers: The duplicated operation of the original operation.
        _delta: The offset between the cursor position and the begin of the
                operation's range.
    """
    def __init__(self, oper, delta):
        """Constructor.

        Args:
            oper: The operation which this cursor position is in.
            delta: The offset the cursor position and the begin of the
                    operation.
        """
        # We need to store it in a list because after applying other commits, it
        # might split into multiple operations.
        self._opers = [_ChgTextOper(oper.begin, oper.end, oper.new_text)]
        self._delta = delta

    def apply_commits(self, commits):
        """Applies commits.

        Does something very similar in commit, because we needs to applies each
        operations to other commits too.

        Args:
            commits: List of commits to be applied.
        """
        for commit in commits:
            self._opers = _opers_apply_opers(self._opers, commit.opers)

    @property
    def position(self):
        """Calculates and returns the final cursor position."""
        dt = self._delta
        for oper in self._opers:
            if oper.begin + dt <= oper.end:
                return oper.begin + dt
            dt -= len(oper.new_text)


class _CursorInfo_OnOrigText(object):
    """About the cursor position who is at the place based on the original text.

    Attributes:
        _position: The position of the cursor.
    """
    def __init__(self, position):
        """Constructor.

        Args:
            position: The cursor position.
        """
        self._position = position

    def apply_commits(self, commits):
        """Applies the commit's change on it.

        Args:
            commits: List of commits to be applied.
        """
        for commit in commits:
            for oper in commit.opers:
                if self._position <= oper.begin:
                    # Remain changeless when the operation is after the cursor
                    # position.
                    pass
                elif oper.end - 1 <= self._position:
                    # Just offset to the right place if the operation occures
                    # totally at the left side of the cursor.
                    self._position += oper.increased_length
                else:
                    # Moves the position to the begin of this operation when the
                    # cursor is inside the operation.
                    self._position = oper.begin

    @property
    def position(self):
        """Returns the final cursor position."""
        return self._position


class _ChgTextOper(object):
    """An operation of changing a text to a new one.

    Here we define changing a text to a new one contains a lot of operations.
    Each operation will replace a substring in the original text to another
    text.

    In this class, we will handles that if we want to apply an operation to a
    text before another operation happened, how to merge and prevent the
    confliction.

    Attributes:
        _begin: The begin of the range of the substring in the original string.
        _end: The end of the range of the substring in the original string.
        _new_text: The string to replace on.

    Notes:
        1. The range is an open range [_begin, _end)
    """

    def __init__(self, beg, end, new_text):
        self._begin = beg
        self._end = end
        self._new_text = new_text

    def apply_oper(self, oper):  # pylint: disable=R0911,R0912
        """Applies an operation before me.

        Args:
            oper: An instance of _ChgTextOper.

        Return:
            A list of instance of _ChgTextOper which contains the equivalent
            operations after applying the gived operation before it.
            The reason that it returns a list instead of just an element is that
            it may be split into multiple operations.
        """
        if oper.begin < self._begin:
            if oper.end <= self._begin:
                return self._apply_left_seperate(oper)
            elif oper.end < self._end:
                return self._apply_left_intersection(oper)
            elif oper.end == self._end:
                return self._apply_left_exact_cover(oper)
            else:
                return self._apply_total_cover(oper)
        elif oper.begin == self._begin:
            if oper.end < self._end:
                return self._apply_left_exact_inside(oper)
            elif oper.end == self._end:
                return self._apply_exact_same(oper)
            else:
                return self._apply_right_exact_cover(oper)
        elif oper.begin < self._end:
            if oper.end < self._end:
                return self._apply_exact_inside(oper)
            elif oper.end == self._end:
                return self._apply_right_exact_inside(oper)
            else:
                return self._apply_right_intersection(oper)
        else:
            return self._apply_right_seperate(oper)

    @property
    def begin(self):
        """Gets the begin of the range."""
        return self._begin

    @property
    def end(self):
        """Gets the end of the range."""
        return self._end

    @property
    def new_text(self):
        """Gets the string to replace."""
        return self._new_text

    @property
    def increased_length(self):
        """Gets the increased length after done this operation."""
        return len(self._new_text) - (self._end - self._begin)

    def _apply_left_seperate(self, oper):
        """Applies the case that,

        The operation:       [     )
        Me:                           [       )
        Description: Just offset to the right position, because after that
                operation done, the length of the new string might be changed.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        offset = oper.increased_length
        return [_ChgTextOper(self._begin + offset, self._end + offset,
                             self._new_text)]

    def _apply_left_intersection(self, oper):
        """Applies the case that,

        The operation:       [     )
        Me:                      [       )
        Result:                    [     )
        Method: Offset the begin of my operaiton to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        offset = oper.increased_length
        return [_ChgTextOper(oper.end + offset, self._end + offset,
                             self._new_text)]

    def _apply_left_exact_cover(self, oper):
        """Applies the case that,

        The operation:       [           )
        Me:                      [       )
        Result:                          |
                (Here "|" means that [ and ) are at the same place)
        Method: Offset the begin of my operaiton to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        end_pos = oper.end + oper.increased_length
        return [_ChgTextOper(end_pos, end_pos, self._new_text)]

    def _apply_total_cover(self, oper):
        """Applies the case that,

        The operation:       [               )
        Me:                      [       )
        Result:                              |
                (Here "|" means that [ and ) are at the same place)
        Method: Offset the begin of my operaiton to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        end_pos = oper.end + oper.increased_length
        return [_ChgTextOper(end_pos, end_pos, self._new_text)]

    def _apply_left_exact_inside(self, oper):
        """Applies the case that,

        The operation:           [   )
        Me:                      [       )
        Result:                      [   )
        Method: Offset the begin of my operaiton to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        offset = oper.increased_length
        return [_ChgTextOper(oper.end + offset, self._end + offset,
                             self._new_text)]

    def _apply_exact_same(self, oper):
        """Applies the case that,

        The operation:           [       )
        Me:                      [       )
        Result:                          |
                (Here "|" means that [ and ) are at the same place)
        Method: Offset the begin of my operaiton to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        offset = oper.increased_length
        return [_ChgTextOper(oper.end + offset, self._end + offset,
                             self._new_text)]

    def _apply_right_exact_cover(self, oper):
        """Applies the case that,

        The operation:           [          )
        Me:                      [       )
        Result:                             |
                (Here "|" means that [ and ) are at the same place)
        Method: Offset the begin/end of my operation to the end of the that
                operaiont's end.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        pos = oper.end + oper.increased_length
        return [_ChgTextOper(pos, pos, self._new_text)]

    def _apply_exact_inside(self, oper):
        """Applies the case that,

        The operation:              [   )
        Me:                      [         )
        Result:                  [  )   [xx)
                (Here "[xx)" means that it an operation to replace a range of
                 string with an empty string.)
        Method: Splits me into two part, the left side remain the original text
                to replace and the right part will just delete a substring.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        offset = oper.increased_length
        return [_ChgTextOper(self._begin, oper.begin, self._new_text),
                _ChgTextOper(oper.end + offset, self._end + offset, '')]

    def _apply_right_exact_inside(self, oper):
        """Applies the case that,

        The operation:              [      )
        Me:                      [         )
        Result:                  [  )
        Method: Modifies the end of my operation to the begin of that operation.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        return [_ChgTextOper(self._begin, oper._begin, self._new_text)]

    def _apply_right_intersection(self, oper):
        """Applies the case that,

        The operation:              [         )
        Me:                      [         )
        Result:                  [  )
        Method: Modifies the end of my operation to the begin of that operation.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        return [_ChgTextOper(self._begin, oper._begin, self._new_text)]

    def _apply_right_seperate(self, oper):
        """Applies the case that,

        The operation:                       [       )
        Me:                      [         )
        Result:                  [         )
        Method: Remain unchanged.

        Args:
            oper: Instance of the _ChgTextOper.
        Return:
            A list of instance of _ChgTextOper.
        """
        return [_ChgTextOper(self._begin, self._end, self._new_text)]
