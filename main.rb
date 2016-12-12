# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

require './dependencies'

DB_NAME = 'config/connect/database.db'
DB_CONFIG = 'config/connect/database.json'
DIR_DATA = 'config/data/'

class Main < Sinatra::Base

  (Dir['./app/helpers/*.rb'].sort + Dir['./app/models/**/*.rb'].sort  + Dir['./app/controllers/**/*.rb'].sort).each do |file|
    require file
  end

  Slim::Engine.options[:disable_escape] = true

  Database::connect(Database::get_connection(Database::get_connection_id()))

end
