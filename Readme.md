# ShrVim

## About

It is a vim plugin like google-doc, which allows multiple users sharing and
editing a file at the same time without sharing only one cursor.  This is useful
when a group needs to create a report with plain-text source such as Markdown,
asciidoc, LaTex, etc.

![Quick look](http://www.csie.ntu.edu.tw/~b01902109/misc/shrvim.gif)

## Features

- Each user has its own cursor, so usres can edit the different place in the
  file at same time.
- You can see where other cursors are.
- RO/RW authority mechanism let the owner be able to restrict a user being read
  only mode.
- Each client can have different encodings.
- Non-ANSI, such as chinese characters are allowed.
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

Default it will do sync each time you move the cursor, insert a character, etc,
but it might cause your vim be a little bit lag.  So you might set it to be only
sync when you type the command (Detail sees below).

```
:ShrVimSync
```

#### Close the connection

```
:ShrVimDisconnect
```

### Server

#### User list

Create an file stores the user list (you can use /dev/null if you want to skip
this step).  In the file, each row should contains three word to represent a
user: ```<identity> <nickname> <authorith>``` where authority can be only "RO"
or "RW".  Empty line is allowed.

Example:
```
sadf83 user1 RW
jc84j5 user2 RW

jkl238 user3 RO
sdjfb8 user4 RO
```

This file is optional because you can add/delete the user after starting the
server, it has an simple command-line ui.

**IMPORTANT:** Each user should have different identity.

#### Start the server

```
server/src/shrvim_server.py <port> <user_list_file> <storage_file>
```

Where ```<Storage_file>``` should contains the initial context of the shared
file, and during editing, the server will stores the context of the latest
version into it.  If you do not want such the file, you can use /dev/null again.

After this, you will see a command-line ui.

#### Stop the server

Type the command

```
exit
```

## Prerequisite

### Client

- Vim with +python or +python3
- python or python3

### Server
- python3

## Settings

If your vim supports both +python and +python3, and you want to force this
plugin use python2, you can type:

```
:ShrVimTryUsePython2
```

On the opposite, there is a command:

```
:ShrVimTryUsePython3
```

About the frequency of syncing, you can setup it by:

```let [g/b]:shr_vim_auto_sync_level = 3/2/1/0``` (Default 3)

Where 0 means you shoul always call ```:ShrVimSync``` by manual.  And it is a
good idea to map a key to this command like:

```:map <F5> :ShrVimSync<CR>```

## Issues
- Server might be inefficient when too much users online.
- If someone use utf8 to insert an utf8 only character, the one use big5 or
  something similar will crash.
