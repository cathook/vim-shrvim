"""Command line user interface."""

import cmd
import re
import threading

from authority_string_transformer import AuthorityStringTransformer
from authority_string_transformer import AuthorityStringTransformerError
from users_text_manager import UNKNOWN
from users_text_manager import UsersTextManagerError

INTRO = ''
PROMPT = '> '


class CmdUI(cmd.Cmd):  # pylint: disable=R0904
    """Command line user interface.

    Attributes:
        _users_text_manager: An instance of UsersTextManager.
        _tcp_server: An instance of TcpServer.
        _shared_vim_server: An instance of SharedVimServer.
        _exit_flag: Whether this UI should stop or not.
        _thread: Instance of Thread.
    """
    def __init__(self, users_text_manager, tcp_server, shared_vim_server):
        """Constructor.

        Args:
            users_text_manager: An instance of UsersTextManager.
            shared_vim_server: An instance of SharedVimServer.
        """
        super(CmdUI, self).__init__(INTRO)
        self.prompt = PROMPT
        self._users_text_manager = users_text_manager
        self._tcp_server = tcp_server
        self._shared_vim_server = shared_vim_server
        self._stop_flag = False
        self._thread = None

    def do_add(self, text):
        """Adds a user, [usage] add <identity> <nickname> <authority>"""
        try:
            identity, nickname, authority_str = _split_text(text, 3)
            authority = AuthorityStringTransformer.to_number(authority_str)
            self._users_text_manager.add_user(identity, nickname, authority)
            self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] add <identity> <nickname> <authority>\n')
        except AuthorityStringTransformerError as e:
            self.write('Fail: %r\n' % e)
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_delete(self, text):
        """Deletes a user, [usage] delete <identity>"""
        try:
            identity = _split_text(text, 1)[0]
            self._users_text_manager.delete_user(identity)
            self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] delete <identity>\n')
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_deleteall(self, text):
        """Deletes all users, [usage] deleteall"""
        try:
            _split_text(text, 0)
            for identity in self._users_text_manager.get_users_info().keys():
                self._users_text_manager.delete_user(identity)
            self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] deleteall\n')
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_reset(self, text):
        """Resets a user, [usage] reset <identity>"""
        try:
            iden = _split_text(text, 1)[0]
            if iden not in self._users_text_manager.get_users_info():
                self.write('Fail: Identity %r not found\n' % iden)
            else:
                self._users_text_manager.reset_user(iden)
                self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] reset <identity>\n')
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_list(self, text):
        """Lists users, [usage] list"""
        try:
            _split_text(text, 0)
            for iden, user in self._users_text_manager.get_users_info().items():
                self.write('%r => %s' % (iden, user))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] list\n')
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_online(self, text):
        """Lists online users, [usage] online"""
        try:
            _split_text(text, 0)
            for iden, user in self._users_text_manager.get_users_info().items():
                if user.mode == UNKNOWN:
                    continue
                self.write('%r => %s' % (iden, user))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] online\n')
        except UsersTextManagerError as e:
            self.write('Fail: %r\n' % e)

    def do_load(self, text):
        """Loads users from a file, [usage] load <filename>"""
        try:
            filename = _split_text(text, 1)[0]
            with open(filename, 'r') as f:
                while True:
                    line = f.readline()
                    if line.endswith('\n'):
                        line = line[:-1]
                    if not line:
                        break
                    try:
                        iden, nick, auth_str = _split_text(line, 3)
                        auth = AuthorityStringTransformer.to_number(auth_str)
                        self._users_text_manager.add_user(iden, nick, auth)
                        self.write('Done %s %s %s' % (iden, nick, auth))
                    except _SplitTextError:
                        self.write('Error format in the file.')
                    except AuthorityStringTransformerError as e:
                        self.write('Fail: %r\n' % e)
                    except UsersTextManagerError as e:
                        self.write('Fail: %r\n' % e)
            self.write('Done')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] load <filename>\n')
        except IOError as e:
            self.write('Cannot open file? %s' % str(e))

    def do_save(self, text):
        """Saves users list to file, [usage] save <filename>"""
        try:
            filename = _split_text(text, 1)[0]
            with open(filename, 'w') as f:
                users_info = self._users_text_manager.get_users_info()
                for iden, user in users_info.items():
                    auth = AuthorityStringTransformer.to_string(user.authority)
                    f.write('%s %s %s\n' % (iden, user.nick_name, auth))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] save <filename>\n')
        except IOError as e:
            self.write('Cannot open file? %s' % str(e))

    def do_port(self, text):
        """Print the server's port."""
        _split_text(text, 0)
        self.write('server port = %r' % self._tcp_server.port)

    def do_exit(self, text):
        """Exits the program."""
        self._shared_vim_server.stop()

    def do_echo(self, text):  # pylint: disable=R0201
        """Echo."""
        print(text)

    def do_help(self, text):
        """Prints the help document, [usage] help"""
        commands = ['add', 'delete', 'list', 'load', 'save', 'exit', 'echo',
                    'help']
        self.write('commands: \n' + ' '.join(commands))

    def do_EOF(self, text):  # pylint: disable=C0103
        """Same as exit"""
        self.do_exit(text)

    def emptyline(self):
        """Do nothing."""
        pass

    def postcmd(self, unused_stop, unused_text):
        """Checks whether it should be stop or not."""
        return self._stop_flag

    def write(self, text):
        """Writes text by this UI.

        It will call the "do_echo" command.

        Args:
            text: String to be printed.
        """
        self.onecmd('echo ' + text)

    def start(self, init_cmds=None):
        """Starts this CmdUI.

        Args:
            init_cmds: Lists of commands to run after startup.
        """
        def run_cmdloop(cmd_ui):
            """Calls the method cmdloop()

            Args:
                cmd_ui: An instnace of CmdUI.
            """
            cmd_ui.cmdloop()
        self._thread = threading.Thread(target=run_cmdloop, args=(self,))
        self._thread.start()
        for c in init_cmds if init_cmds else []:
            self.onecmd(c)

    def stop(self):
        """Stops the command line UI."""
        self._stop_flag = True
        self.onecmd('echo bye~\n')

    def join(self):
        """Joins this thread."""
        self._thread.join()

    def flush(self):
        """Flush the screen."""
        pass


class _SplitTextError(Exception):
    """Error raised by the function _split_text()."""
    pass

def _split_text(text, num):
    """Split the text into tuple.

    Args:
        text: The string to be splitted.
        num: Length of the tuple.

    Return:
        A num-tuple.
    """
    words = [word for word in re.split(r'[ \t]', text) if word]
    if len(words) != num:
        raise _SplitTextError()
    return tuple(words)
