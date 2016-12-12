# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

require 'rubygems'
require 'bundler'

%w(
  active_record
  pg
  sinatra
  sinatra/static_assets
  slim
  pg_query
  json
  singleton
  anbt-sql-formatter/formatter
).each { |d| require d }
