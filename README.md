# SQL Shell (A shell for your SQL!) 

Lets you navigate your SQL databases as if they were directories. Use familiar commands like "cd", "ls", "rm", "mkdir", and "mv" to list/rename/remove/create databases, tables, and columns.

Also lets you execute queries on databases using Ruby's Sequel syntax.

![sqlsh screenshot](http://chris.ill-logic.com/images/sqlsh.png)

# Usage

> sqlsh.rb mysql://&lt;username&gt;:&lt;password&gt;@&lt;hostname&gt;/

# Planned Features

## Commands

* "open" command (auto-prompt for username/password)
* "rm" command (drop database/table/column/index)
* "mkdir" or "new" command (creates databases, tables, and columns)
* "mv" or "rename" (for table, column, etc.)
* "edit <thing>" pops up a curses dialog w/ types and stuff (nano/vim/pico?)
* "ls -l" shows {db: sizes/tables, table: columns/types/indexes, column: ? }

## Refactoring

* Steal jed's display-in-colums thingy
* Browser#for(path) returns a new browser in that path
  * ls("/what/lala") is implemented by @browser.for("/what/lala").ls
  * can all commands work without "use"?
  * `#context` method uses path info, not "USE"
* option parser
* path parser (make paths the standard db interface)
  * path.up
  * path.database_name
  * path.=
  * path.table_name
  * path.column_name

## Ideas

* remember last connection and auto-connect next session
* less-style results (scroll left/right/up/down)
* make a reuslt object that can display in short (column)
* pager for long results (less?)
* assigning result sets, and _ for last set (history of results?)
* browser.root = argv[0]
* log sql commands without ugly timestamps
* a way to do joins (set intersection?)
  * table1&lt;=column=&gt;table2
* compact table display mode (truncate) fields
* use URI (or addressable) to parse uris
* bookmarks
