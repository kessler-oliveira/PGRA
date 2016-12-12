module Sinatra
  module Home
    def self.registered(app)

      app.enable :sessions
      app.set :session_secret, 'pgra'
      app.set :views, "app/views"
      app.set :public_folder, "app/assets"
      app.set :partial_template_engine, :slim

      app.get '/' do
        slim :'home/index'
      end

      app.get '/error' do
        return PGRA::list_errors().to_json
      end

      app.get '/error/clean' do
        PGRA::clean_errors()
      end

      app.get '/show' do
        @json = PGRA::load(session['show']).to_json
        slim :'home/show', :layout => false
      end

      app.get '/pgquery' do
        PGRA::save('pgquery', PgQuery::parse("SELECT * FROM TABELA1 T1 WHERE T1.CAMPO1 IN (SELECT T2.CAMPO1 FROM TABELA2 T2)").tree)
        session['show'] = 'pgquery'
        slim :'home/index', :layout => false
      end

      app.not_found do
        redirect '/'
      end

    end
  end
  register Home
end
