require 'sqlsh'
require 'pp'

DEFAULT_DB = "mysql://root@localhost/"

def db
  @db ||= Sequel.connect DEFAULT_DB 
end

def exec(params=nil)
  db.fetch(params).to_a
end

def br
  @browser ||= Browser.new DEFAULT_DB
end