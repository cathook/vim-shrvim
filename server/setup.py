import sys

from cx_Freeze import setup, Executable


options = {
    'build_exe' : {
        'build_exe' : 'build/',
        'optimize' : 2,
    },
}

setup(name='shared_vim_server',
      version='1.0',
      description='Shared Vim Server',
      options=options,
      executables=[Executable('src/shared_vim_server.py')])
