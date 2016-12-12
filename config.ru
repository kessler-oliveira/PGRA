require './dependencies'
require './main'

map '/' do
  run Sinatra::Application
end
