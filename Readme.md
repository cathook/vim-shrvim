# ShrVim

## About

It is a vim plugin like google-doc, which allows multiple users to share and
edit a file at the same time, without sharing only one cursor.  This is useful
when a group needs to create a report with plain-text source such as Markdown,
asciidoc, LaTeX, etc.

![Quick look](http://www.csie.ntu.edu.tw/~b01902109/misc/shrvim.gif)

## Features

- Each user has their own cursor, so users can edit different places in the
  file at same time.
- You can see where other cursors are.
- RO/RW authority mechanism allows the owner to restrict a user to read only
  mode.
- Each client can have different encodings.
- Non-ANSI, such as Chinese characters are allowed.
- Live update in Insert mode

## Quick start

### Client

#### Install

Install the vim plugin (in the directory "vim").  Or you can just source the
"shrvim.vim" when you want to use it by:

```
:so <filename_of_shrvim.vim>
```

#### Connect to the server

With server name, port and your own identity gived by the owner (the one who
created the server), you can:

```
:ShrVimConnect <server_name(ip, url, ...)> <port> <identity>
```

#### Sync

By default, ShrVim syncs each time you move the cursor, insert a character, etc.
This might cause your vim be a little bit laggy, so you might set it to only sync
when you type the command (Detail sees below).

```
:ShrVimSync
```

#### Close the connection

```
:ShrVimDisconnect
```

### Server

#### User list

Create a file that stores the user list (you can use /dev/null if you want to skip
this step).  In the file, each row should contain three attributes to represent a
user: ```<identity> <nickname> <authority>``` where <authority> can only be either "RO"
or "RW".  Empty lines are allowed.

Example:
```
sadf83 user1 RW
jc84j5 user2 RW

jkl238 user3 RO
sdjfb8 user4 RO
```

This file is optional because you can add/delete users dynamically after starting the
server, there is a simple command-line ui.

**IMPORTANT:** Each user should have a different identity.

#### Starting the server

```
server/src/shrvim_server.py <port> <user_list_file> <storage_file>
```

Where ```<Storage_file>``` should contain the initial content of the shared
file. Then during editing, the server will store the content of the latest
version into it.  If you do not want such file, you can use /dev/null as again.

After this, you will see a command-line ui.

#### Stop the server

Type the command

```
exit
```

## Prerequisites

### Client

- Vim with +python or +python3
- python or python3

### Server
- python3

## Settings

If your vim supports both +python and +python3, and you want to force ShrVim to
use python2, you can type:

```
:ShrVimTryUsePython2
```

Otherwise, you can type:

```
:ShrVimTryUsePython3
```

To set the frequency of syncing, you can use:

```let [g/b]:shr_vim_auto_sync_level = 3/2/1/0``` (Default 3)

Where 0 means clients should always call ```:ShrVimSync``` by manual.  And it is a
good idea to map a key to this command like:

```:map <F5> :ShrVimSync<CR>```

## Issues
- Server might be inefficient with too many users online.
- If a client uses utf8 to insert an utf8 only character, other clients using big5 or
  something similar will crash.
