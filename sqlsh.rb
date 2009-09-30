#!/usr/bin/ruby

###########################################################################
# SQL Shell :: A shell for your SQL!
# -------------------------------------
#
# Usage:
# 
#    sqlsh.rb mysql://<username>:<password>@<hostname>/
#
# Refactoring:
# ---------------------
# * Steal jed's display-in-colums thingy
# * Browser#for(path) returns a new browser in that path
#   => ls("/what/lala") is implemented by @browser.for("/what/lala").ls
#   => can all commands work without "use"?
#   => #context method uses path info, not "USE"
# * option parser
# * path parser (make paths the standard db interface)
#   => path.up
#   => path.database_name
#   => path.=
#   => path.table_name
#   => path.column_name
#
# Feature todos:
# ---------------------
# * shell style commands:
#   => "open" command (auto-prompt for username/password)
#   => "rm" command (drop database/table/column/index)
#   => "mkdir" or "new" command (creates databases, tables, and columns)
#   => "mv" or "rename" (for table, column, etc.)
#   => "edit <thing>" pops up a curses dialog w/ types and stuff (nano/vim/pico?)
#   => "ls -l" shows {db: sizes/tables, table: columns/types/indexes, column: }. 
# => remember last connection and auto-connect next session
# => less-style results (scroll left/right/up/down)
# => make a reuslt object that can display in short (column)
#    long (ls -l) formats.
# => pager for long results (less?)
# => assigning result sets, and _ for last set (history of results?)
# => browser.root = argv[0]
# => log sql commands without ugly timestamps
# => a way to do joins (set intersection?)
#    |_ table1<=column=>table2
# => compact table display mode (truncate) fields
# => use URI (or addressable) to parse uris 
# => bookmarks

###########################################################################
# Required modules
%w(rubygems sequel logger pp readline colorize).each{|mod| require mod}
###########################################################################



###########################################################################
# Helpers (aka. MonkeyPatches)
#
class Symbol
  def to_proc
    Proc.new { |*args| args.shift.__send__(self, *args) }
  end
end

class String
  def pad(n)
    amount = [0,(n-size)].max   # clip negative values to 0
    self + ' '*amount
  end
  
  def startswith(sub)
    (self =~ /^#{Regexp.escape(sub.to_s)}/) != nil
  end
end

class Array
  alias_method :filter, :select
end
###########################################################################


###########################################################################
# Database Browser
#
class Browser

  ##
  ##  Aborted attempt at abstraction (awful attempt, and awesome alliteration).
  ##
  #@@contexts = {}
  #
  #def self.in_context(ctxname, &block)
  #  @@contexts[ctxname] ||= BaseBrowser.new
  #  @@contexts[ctxname].class_eval(&block)
  #end
  
  attr_accessor :db, :context
  
  def initialize(uri)
    @root = uri
    @db = Sequel.connect(@root)
    @table = nil
  end

  def database?
    #@db.opts[:database].any?
    not current_db.nil?
  end
  
  def table?
    not @table.nil?
  end
  
  def exec(params=nil)
    db.fetch(params).to_a
  end
  
  def current_db
    exec("SELECT DATABASE()").first[:"DATABASE()"]
  end
  
  def path
    @db.uri + (database? ? "#{current_db}/": "" ) + (table? ? "#{@table}/" : '')
  end
  
  def databases
    @db["SHOW DATABASES"].map(&:values).flatten.sort
  end
  
  def tables
    @db.tables.map(&:to_s).sort
  end
  
  def columns
    @db[@table].columns.map(&:to_s).sort
  end
  
  def use_table!(table)
    if table_exists? table
      @table = table.to_sym
    else
      puts "#{table.inspect} doesn't exist."
    end
  end
  
  def table_exists?(name)
    @db.tables.include? name.to_sym
  end

  def tables_for(dbname)
    @db.fetch("SHOW TABLES FROM `#{dbname}`").map{|tbl| tbl.values}.flatten
  end

  #  
  # http://dev.mysql.com/doc/refman/5.1/en/show-table-status.html
  #
  def table_stats_for(dbname)
    results = {}
    @db.fetch("SHOW TABLE STATUS FROM `#{dbname}`").map do |tbl|
      results[tbl[:Name]] = {
        :data_size    => tbl[:Data_length], 
        :index_size   => tbl[:Index_length],
        :avg_row_size => tbl[:Avg_row_length],
        :data_unused  => tbl[:Data_free],
        :rows         => tbl[:Rows],
        :engine       => tbl[:Engine],
        :row_format   => tbl[:Row_format],
        :created_at   => tbl[:Create_time],
        :updated_at   => tbl[:Update_time],
        :encoding     => tbl[:Collation],
      }
    end
  end
      
  
  def database_size_for(dbname)
    db_size = 0
    #p [:database_size_for, dbname]
    table_stats_for(dbname).each do |table, stats|
      #p [:table_sizes_for, dbname, table, stats]
      db_size += stats[:data_size] + stats[:index_size]
    end
    db_size
  end

  #################################################################
  
  def ls(params=nil)
    case context
      when :columns
        columns
      when :tables
        tables
      when :databases
        databases
    end
  end
  
  def ls_l(params=nil)
    case context
      when :columns
        # schema
        @db.fetch("describe `#{@table}`")
      when :tables
        # tables w/ rows, index size, etc.
        
      when :databases
        # database size, table count, etc.
        list = databases.map { |dbname| [dbname, {:tables=>tables_for(dbname).size}] }
        list = Hash[ *list.flatten ]
        list.keys.each do |dbname|
          list[dbname][:size] = database_size_for(dbname)
        end
        list
    end
  end

  def mkdir(param)
    case context
      when :columns
        # new column
        # params:
        #   <name>        => create string column
        #   <name>:<type> => create typed column
        if param =~ /(.+):(.+)/
          param = $1
          type = $2
        else
          type = "varchar(255)"
        end
        @db << "ALTER TABLE `#{@table}` ADD `#{param}` #{type}"
      when :tables
        # new table
        @db << "CREATE TABLE `#{param}` (id int primary key);"
      when :databases
        @db << "CREATE DATABASE `#{param}`;"
    end
  end

  def mv(src, dest)
    case context
      when :columns
        column_type = ? # INTEGER, VARCHAR(255), etc.
        @db << "ALTER TABLE `#{@table}` CHANGE `#{src}` `#{dest}` #{column_type}"
      when :tables
        @db << "RENAME TABLE `#{src}` TO `#{dest}`"
      when :databases
        @db << "RENAME DATABASE `#{src}` TO `#{dest}`"
    end
  end
  alias_method :rename, :mv
    
  def root!
    @table = nil
    @db = Sequel.connect(@root)
  end    
  
  def rm(param)
    case context
      when :columns
        @db << "ALTER TABLE `#{@table}` DROP `#{param}`"
      when :tables
        @db << "DROP TABLE `#{param}`"
      when :databases
        @db << "DROP DATABASE `#{param}`"
    end
  end  
  
  def cd(param)
    if param == '/'
      root!; return
    end
    
    case context
      when :columns
        if param == '..'
          @table = nil
        else
          puts "Can't change to #{param}"
        end
      when :tables
        if param == '..'
          root!
        else
          use_table! param
        end
      when :databases
        if param != '..'
          @db.use param
        end
    end
  end
  
  def raw(expr, table=nil)
    if table and not table_exists?(table)
      puts "Executing raw command #{expr}, couldn't find table: #{table}"
      return
    end
    
    case context
      when :columns
        @db[table ? table : @table].instance_eval(expr)
      when :tables
        @db[table].instance_eval(expr)
      when :databases
        return
    end
  end
  
  def context
    if table?
      :columns
    elsif database?
      :tables
    else
      :databases
    end
  end
  
  def ls_color
    {
      :columns=>:magenta, 
      :tables=>:yellow, 
      :databases=>:cyan
    }[context]
  end  
  
  
  def completions(sub)
    ls.filter{|x| x.startswith(sub) }
  end
  
end
###########################################################################


###########################################################################
# Command-line Interface
#
class CLI

  attr_accessor :browser
  
  def initialize(url)
    # setup our database browser
    @browser = Browser.new url
    
    Readline::completer_quote_characters = %{'"}
    Readline::completion_proc = proc do |sub|
      @browser.completions(sub)
    end
    
    #@browser.db.logger = Logger.new($stdout)
  end
  
  def welcome
    puts "welcome to sqlsh".green
    puts "---------------------------------------------------".yellow
    puts "('?' or 'help' will tell you what to do)"
    puts
  end  

  def help
    puts "HELP:".green
    puts "--------------------------------------------------".yellow
    puts %{
      ls                : display things
      cd                : change to directories and stuff
      print             : display everything in current table
      <ruby expression> : execute a sequel expression on the current path
                          (see http://sequel.rubyforge.org/ for commands)    
      quit/exit         : get outta here
                          
    }.gsub("  ",'')
  end

  #[:magenta, :black, :cyan, :red, :default, :white, :green, :yellow, :blue]

  def column_print(things, color=:white)
    return unless things.any?
    sizes = things.map{|x|x.size}
    col_width = sizes.max
    cols = 80 / (col_width+3)
    cols = 4 if cols > 4
    
    if things.size % cols != 0
      things += [''] * (cols - (things.size % cols))
    end
    
    things.map!{|thing| thing.pad(col_width)}
    
    things.each_slice(cols) do |slice|
      puts slice.join(' | ').colorize(color)
    end
  end
  
  def display_results(results)
    if results.is_a? Sequel::Dataset
      results.print
    else
      pp results
    end
  end
  
  def quit
    puts "Thanks for playing!"
    exit
  end    
  
  def parse(line)
    case line
      when /^(\?|help)$/i
        help
      when /^ls$/i
        puts "ls"
        column_print @browser.ls, @browser.ls_color
      when /^ls -l$/i
        display_results @browser.ls_l
      when /^ls -l (\S+)|ls (\S+) -l$/i
        display_results @browser.ls_l($1 || $2)
      when /^ls ([^-]\S+)$/i
        @browser.ls($1)
      when /^mkdir (\S+)$/i
        @browser.mkdir($1)
      when /^(?:mv|rename|ren) (\S+) (\S+)$/i
        @browser.mv($1, $2)
      when /^cd (\S+)/i
        @browser.cd($1)
      when /^rm -r (\S+)/i
        @browser.rm_r($1)
      when /^rm (\S+)/i
        @browser.rm($1)
      when nil
        puts
        quit
      when /^(quit|exit)/i
        quit
      when /^(\w+)\.(.+)/i
        display_results @browser.raw($2, $1)
      when /^\w.+/
        display_results @browser.raw(line)
      else
        puts "Don't know how to handle: #{line.inspect}"
    end
  end

  def mainloop
    welcome
    loop do
      line = Readline::readline("#{@browser.path} (#{@browser.context})> ", true)
      #Readline::HISTORY.push(line)
      begin
        parse line
      rescue => e
        puts "#{e.class} => #{e.inspect}"
        puts e.backtrace
      end
    end
  end
end
###########################################################################


###########################################################################
# Main
#
if $0 == __FILE__
  url = ARGV[0] || "mysql://root@localhost/"
  cli = CLI.new url
  cli.mainloop
end
###########################################################################
