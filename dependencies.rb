require 'rubygems'
require 'bundler'

%w(
  active_support
  active_record
  pg
  sinatra
  sinatra/flash
  sinatra/partial
  sinatra/static_assets
  slim
  pg_query
  json
  singleton
  anbt-sql-formatter/formatter
).each { |d| require d }
