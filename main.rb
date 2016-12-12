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
