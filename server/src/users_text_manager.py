"""UsersTextManager."""

import threading

from text_chain import TextChain


UNKNOWN = -1

class AUTHORITY:  # pylint:disable=W0232
    """Enumeration the types of authority."""
    READONLY = 1  # can only read.
    READWRITE = 2  # can read and write.


class UserInfo(object):
    """A structure for storing a user's information.

    Attributes:
        authority: Authority of this user.
        nick_name: Nick name.
        mode: Vim mode.
        cursors: A dict stores cursor positions of each mark.
        last_commit_id: Last commit's id.
    """
    def __init__(self, authority=UNKNOWN, nick_name='', mode=UNKNOWN,
                 cursors=None):
        """Constructor.

        Args:
            authority: Default authority
            nick_name: Default nick name.
        """
        self.authority = authority
        self.nick_name = nick_name
        self.mode = mode
        self.cursors = {} if cursors is None else cursors
        self.last_commit_id = UNKNOWN

    def __str__(self):
        return 'authorith = %r, nickname = %r, mode = %r, last_commit = %r' % (
            self.authority, self.nick_name, self.mode, self.last_commit_id)


class UsersTextManager(object):
    """Handles query/operations about users and texts.

    It main interface between CmdUI/TCPServer and TextChain.

    Attributes:
        _users: A dict to stores users.
            key: User identity.
            value: An instance of UserInfo.
        _text_chain: An instance of TextChain.
        _rlock: A threading.RLock to prevent multi-threads access this class at
                the same time.
    """
    def __init__(self, saved_filename):
        """Constructor.

        Args:
            saved_filename: Name of the file for TextChain to save the last
                    commit.
        """
        self._users = {}
        self._text_chain = TextChain(saved_filename)
        self._rlock = threading.RLock()

    def add_user(self, identity, nick_name, authority):
        """Adds a user.

        Args:
            identity: Identity of this user.
            nick_name: Nick name of this user.
            authority: Authority of this user.
        """
        with self._rlock:
            self._users[identity] = UserInfo(authority, nick_name)
            self._users[identity].last_commit_id = self._text_chain.new()

    def delete_user(self, identity):
        """Deletes a user.

        Args:
            identity: Identity of this user.
        """
        with self._rlock:
            self._text_chain.delete(self._users[identity].last_commit_id)
            del self._users[identity]

    def reset_user(self, identity):
        """Resets a user to the initial value.

        Args:
            identity: Identity of this user.
        """
        with self._rlock:
            authority = self._users[identity].authority
            nick_name = self._users[identity].nick_name
            self.delete_user(identity)
            self.add_user(identity, nick_name, authority)

    def get_users_info(self, without=None, must_online=False):
        """Gets the users informations.

        Args:
            without: Blacklist.
            must_online: A flag for whether just returns the one online or not.

        Return:
            A dict with key=authority, value=instance of UserInfo.
        """
        with self._rlock:
            without = without if without is not None else []
            online_check = lambda x: (x != UNKNOWN if must_online else True)
            return dict([pair for pair in self._users.items()
                         if pair[0] not in without and \
                             online_check(pair[1].mode)])

    def update_user_text(self, identity, new_user_info, new_text):
        """Updates a user's information with new information and text.

        Args:
            new_user_info: An instance of UserInfo.
            new_text: New text.

        Return:
            A 2-tuple for a instance of UserInfo and a string.
        """
        with self._rlock:
            curmarks = new_user_info.cursors.keys()
            curs = [new_user_info.cursors[mark] for mark in curmarks]
            new_commit_id, new_text, new_curs = self._text_chain.commit(
                self._users[identity].last_commit_id, new_text, curs)
            self._users[identity].last_commit_id = new_commit_id
            self._users[identity].mode = new_user_info.mode
            self._users[identity].cursors = _lists_to_dict(curmarks, new_curs)
            for iden, user in self._users.items():
                if iden == identity:
                    continue
                curmarks = user.cursors.keys()
                curs = [user.cursors[mark] for mark in curmarks]
                new_curs = self._text_chain.update_cursors(curs)
                user.cursors = _lists_to_dict(curmarks, new_curs)
            return (self._users[identity], new_text)

    def get_user_text(self, identity):
        """Gets the last commit text of a specified user.

        Args:
            identity: The identity of that user.

        Return:
            The text.
        """
        with self._rlock:
            return self._text_chain.get_text(
                self._users[identity].last_commit_id)


def _lists_to_dict(list1, list2):
    """Combines each element in two lists.

    Args:
        list1: The first list.
        list2: The second list.

    Return:
        A list with each element be a tuple of two element in list1 and list2.
    """
    l1, l2 = list(list1), list(list2)
    return {l1[index] : l2[index] for index in range(len(l1))}
