module Sinatra
  module Pgra

    def self.registered(app)

      app.get '/pgra/submit' do
        if Database::connected?
          slim :'pgra/submit', :layout => false
        else
          slim :'home/index', :layout => false
        end
      end

      app.get '/pgra/init' do
        session["query"] = params[:text_query]
        slim :'pgra/init', :layout => false
      end

      app.get '/pgra/init/:query' do
        session["query"] = PGRA::get_query(params[:query])
        slim :'pgra/init', :layout => false
      end

      app.get '/pgra/analyze' do
        PGRA::save('query', Query.new(session["query"]))
        return status 500 if PGRA::list_errors()['feedback'].length > 0
        session['show'] = 'query'
        slim :'pgra/analyze', :layout => false
      end

      app.get '/pgra/identify' do
        PGRA::save('identify', PGRA::identify(PGRA::load('query')))
        session['show'] = 'identify'
        return status 500 if PGRA::list_errors()['feedback'].length > 0
        slim :'pgra/identify', :layout => false
      end

      app.get '/pgra/rewrite' do
        PGRA::save('rewrite', PGRA::rewrite(PGRA::load('query'), PGRA::load('identify')))
        return status 500 if PGRA::list_errors()['feedback'].length > 0
        session['show'] = 'rewrite'
        slim :'pgra/rewrite', :layout => false
      end

      app.get '/pgra/show' do
        @rewrite = PGRA::load('rewrite')
        return status 500 if PGRA::list_errors()['feedback'].length > 0
        slim :'pgra/show', :layout => false
      end

      app.get '/pgra/query/:query' do
        @query = PGRA::get_query(params[:query])
        slim :'pgra/query', :layout => false
      end
    end
  end
  register Pgra
end
