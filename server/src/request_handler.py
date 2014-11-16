"""RequestHandler."""

import log

from users_text_manager import AUTHORITY
from users_text_manager import UserInfo


class JSON_TOKEN:  # pylint:disable=W0232
    """Enumeration the Ttken strings for json object."""
    BYE = 'bye'  # Resets the user and do nothong.
    CURSORS = 'cursors'  # other users' cursor position
    ERROR = 'error'  # error string
    IDENTITY = 'identity'  # identity of myself
    INIT = 'init'  # initialize connect flag
    MODE = 'mode'  # vim mode.
    NICKNAME = 'nickname'  # nick name of the user.
    OTHERS = 'others'  # other users info.
    TEXT = 'text'  # text content in the buffer

class RequestHandler(object):
    """Handles all kinds of request.

    Attributes:
        _users_text_manager: An instance of UsersTextManager.
    """
    def __init__(self, users_text_manager):
        """Constructor.

        Args:
            users_text_manager: An instance of UsersTextManager.
        """
        super(RequestHandler, self).__init__()
        self._users_text_manager = users_text_manager

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
        if all(key in request for key in [JSON_TOKEN.INIT,
                                          JSON_TOKEN.TEXT,
                                          JSON_TOKEN.MODE,
                                          JSON_TOKEN.CURSORS]):
            log.info('handle sync-request from %r\n' % identity)
            self._check_init(identity, request)
            self._check_authority(identity, request)
            new_user_info, new_text = self._users_text_manager.update_user_text(
                identity,
                UserInfo(mode=request[JSON_TOKEN.MODE],
                         cursors=request[JSON_TOKEN.CURSORS]),
                request[JSON_TOKEN.TEXT])
            return self._pack_sync_response(identity, new_user_info, new_text)

    def _pack_sync_response(self, identity, user_info, text):
        """Packs the response for the sync request by the result from manager.

        Args:
            identity: Identity of that user.
            user_info: Informations of that user.
            text: New text.

        Return:
            The response json object.
        """
        return {JSON_TOKEN.TEXT : text,
                JSON_TOKEN.CURSORS : user_info.cursors,
                JSON_TOKEN.MODE : user_info.mode,
                JSON_TOKEN.OTHERS : [
                    {JSON_TOKEN.NICKNAME : other.nick_name,
                     JSON_TOKEN.MODE : other.mode,
                     JSON_TOKEN.CURSORS: other.cursors}
                    for iden, other in self._users_text_manager.get_users_info(
                        without=[identity], must_online=True).items()
                ]}

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
            request[JSON_TOKEN.TEXT] = ''
            for mark in request.get(JSON_TOKEN.CURSORS, []):
                request[JSON_TOKEN.CURSORS][mark] = 0

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
            old_text = self._users_text_manager.get_user_text(identity)
            request[JSON_TOKEN.TEXT] = old_text
