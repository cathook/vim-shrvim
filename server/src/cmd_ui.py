"""Command line user interface"""

import cmd
import re
import threading

import authority_string_transformer

INTRO = 'Type the command "help" for help document.'
PROMPT = '> '


class CmdUI(cmd.Cmd):  # pylint: disable=R0904
    """Command line user interface.

    It's a simple UI for doing operation on server, supplied commands:
        - Add/delete/reset a user
        - List (online) users
        - Save/load the user list to/from a file.
        - Exit.
        - Prints the help document.

    And it is also the main output interface of the whole program.

    Attributes:
        _users_text_manager: An instance of UsersTextManager.
        _tcp_server: An instance of TcpServer.
        _shared_vim_server: An instance of SharedVimServer.
        _exit_flag: Whether this UI should stop or not.
        _thread: Instance of Thread.
        _init_cmds: Initialize commands.
    """
    def __init__(self,
                 init_cmds, users_text_manager, tcp_server, shared_vim_server):
        """Constructor.

        Args:
            init_cmds: Lists of commands to run after startup.
            users_text_manager: An instance of UsersTextManager.
            tcp_server: An instance of TCPServer.
            shared_vim_server: An instance of SharedVimServer.
        """
        super(CmdUI, self).__init__(INTRO)
        self.prompt = PROMPT
        self._users_text_manager = users_text_manager
        self._tcp_server = tcp_server
        self._shared_vim_server = shared_vim_server
        self._stop_flag = False
        self._thread = None
        self._init_cmds = init_cmds

    def do_add(self, text):
        """Adds a user, [usage] add <identity> <nickname> <authority>"""
        try:
            identity, nickname, authority_str = _split_text(text, 3)
            if identity in self._users_text_manager.get_users_info():
                self.write('The identity %r is already in used.\n' % identity)
                return
            authority = authority_string_transformer.to_number(authority_str)
            self._users_text_manager.add_user(identity, nickname, authority)
            user_info = self._users_text_manager.get_users_info()[identity]
            self.write('Added %s => %s\n' % (identity, str(user_info)))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] add <identity> <nickname> <authority>\n')
        except authority_string_transformer.Error as e:
            self.write('Fail: %r\n' % e)

    def do_delete(self, text):
        """Deletes a user, [usage] delete <identity>"""
        try:
            identity = _split_text(text, 1)[0]
            if identity not in self._users_text_manager.get_users_info():
                self.write('The identity %r is not in used.\n' % identity)
                return
            self._users_text_manager.delete_user(identity)
            self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] delete <identity>\n')

    def do_deleteall(self, text):
        """Deletes all users, [usage] deleteall"""
        try:
            _split_text(text, 0)
            for identity in self._users_text_manager.get_users_info():
                self._users_text_manager.delete_user(identity)
            self.write('Done\n')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] deleteall\n')

    def do_reset(self, text):
        """Resets a user, [usage] reset <identity>"""
        try:
            iden = _split_text(text, 1)[0]
            if iden not in self._users_text_manager.get_users_info():
                self.write('The User with identity %r is not exist.\n' % iden)
                return
            self._users_text_manager.reset_user(iden)
            user_info = self._users_text_manager.get_users_info()[iden]
            self.write('Reseted %s ==> %s\n' % (iden, str(user_info)))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] reset <identity>\n')

    def do_list(self, text):
        """Lists users, [usage] list"""
        try:
            _split_text(text, 0)
            infos = self._users_text_manager.get_users_info().items()
            for iden, user in sorted(infos, key=lambda x: x[0]):
                self.write('%-10s => %s' % (iden, str(user)))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] list\n')

    def do_online(self, text):
        """Lists online users, [usage] online"""
        try:
            _split_text(text, 0)
            infos = self._users_text_manager.get_users_info(
                must_online=True).items()
            for iden, user in sorted(infos, key=lambda x: x[0]):
                self.write('%-10s => %s' % (iden, str(user)))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] online\n')

    def do_load(self, text):
        """Loads users from a file, [usage] load <filename>"""
        try:
            filename = _split_text(text, 1)[0]
            with open(filename, 'r') as f:
                for line in f.readlines():
                    line = line if not line.endswith('\n') else line[ : -1]
                    if not line:
                        continue
                    self.do_add(line)
            self.write('Done')
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] load <filename>\n')
        except IOError as e:
            self.write('Error occured when opening the file: %r' % e)

    def do_save(self, text):
        """Saves users list to file, [usage] save <filename>"""
        try:
            filename = _split_text(text, 1)[0]
            with open(filename, 'w') as f:
                users_info = self._users_text_manager.get_users_info().items()
                for iden, user in sorted(users_info, key=lambda x: x[0]):
                    auth_str = authority_string_transformer.to_string(
                        user.authority)
                    f.write('%s %s %s\n' % (iden, user.nick_name, auth_str))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] save <filename>\n')
        except IOError as e:
            self.write('Cannot open file? %s' % str(e))

    def do_port(self, text):
        """Print the server's port."""
        try:
            _split_text(text, 0)
            self.write('Server port = %r\n' % self._tcp_server.port)
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] port\n')

    def do_exit(self, text):
        """Exits the program."""
        try:
            _split_text(text, 0)
            self._shared_vim_server.stop()
        except _SplitTextError:
            self.write('Format error!\n'
                       '[usage] exit\n')

    def do_echo(self, text):  # pylint: disable=R0201
        """Echo."""
        print(text)

    def do_help(self, text):
        """Prints the help document, [usage] help"""
        try:
            _split_text(text, 0)
            commands = [m[3 : ] for m in dir(self) if m.startswith('do_')]
            self.write('Commands: \n' + ' '.join(commands))
        except _SplitTextError:
            self.write('Format error!\n' +
                       '[usage] help\n')

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
        for line in text.splitlines():
            self.onecmd('echo ' + line)

    def preloop(self):
        for c in self._init_cmds:
            self.onecmd(c)

    def start(self):
        """Starts this CmdUI."""
        self._thread = threading.Thread(target=self.cmdloop,
                                        args=(INTRO,))
        self._thread.start()

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
        num: Number of elements in the result tuple.

    Return:
        A <num>-tuple.
    """
    words = [word for word in re.split(r'[ \t]', text) if word]
    if len(words) != num:
        raise _SplitTextError()
    return tuple(words)
