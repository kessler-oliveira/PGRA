module Sinatra
  module Connect
    def self.registered(app)

      app.get '/connect/menu' do
        if Database::connected?
          @db = Database::get_connection(Database::get_connection_id())
          @dbs = Database::get_connections(Database::get_connection_id())
          slim :'connect/menu/in', :layout => false
        else
          @dbs = Database::get_connections()
          slim :'connect/menu/out', :layout => false
        end
      end

      app.get '/connect/get/:id' do
        db = Database::get_connection(params[:id])
        db["id"] = params[:id]
        return db.to_json
      end

      app.get '/connect/add' do
        slim :'connect/add', :layout => false
      end

      app.post '/connect/add' do
        connection = {}
        connection["name"] = params[:name]
        connection["database"] = params[:database]
        connection["host"] = params[:host]
        connection["schema"] = params[:schema]
        connection["user"] = params[:user]
        connection["password"] = params[:password]
        return status 500 unless Database::valid_connect?(connection)
        Database::add(connection)
      end

      app.get '/connect/edit' do
        slim :'connect/edit', :layout => false
      end

      app.put '/connect/edit' do
        connection = {}
        connection["id"] = params[:id]
        connection["name"] = params[:name]
        connection["database"] = params[:database]
        connection["host"] = params[:host]
        connection["schema"] = params[:schema]
        connection["user"] = params[:user]
        connection["password"] = params[:password]
        return status 500 unless Database::valid_connect?(connection)
        Database::edit(connection)
      end

      app.delete '/connect/delete/:id' do
        Database::delete(params[:id].strip)
      end

      app.get '/connect/logout' do
        Database::logout()
      end

      app.get '/connect/database/:id' do
        Database::set_connection_id(params[:id].strip)
      end

      app.get '/connect/valid' do
        connection = {}
        connection["name"] = params[:name]
        connection["database"] = params[:database]
        connection["host"] = params[:host]
        connection["schema"] = params[:schema]
        connection["user"] = params[:user]
        connection["password"] = params[:password]
        return status 500 unless Database::valid_connect?(connection)
      end
    end
  end
  register Connect
end
