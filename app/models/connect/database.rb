# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

class Database
  class << self

    include Singleton

    def logout()
      begin
        File.open(DB_NAME, 'w') do |file|
          file.close
        end
      rescue
        return nil
      end
    end

    def get_connection_id()
      begin
        return File.open(DB_NAME, 'r').gets.chomp.strip
      rescue
        return nil
      end
    end

    def set_connection_id(id)
      begin
        unless Database::get_connection(id).nil?
          File.open(DB_NAME, 'w') do |file|
            file.write(id)
            file.close
          end
        else
          File.open(DB_NAME, 'w') do |file|
            file.close
          end
        end
      rescue
        return nil
      end
    end

    def get_connection(id)
      begin
        return JSON.parse(File.read(DB_CONFIG))[id]
      rescue
        return nil
      end
    end

    def get_connections(id = nil)
      begin
        unless File.read(DB_CONFIG).blank?
          if id.nil?
            return JSON.parse(File.read(DB_CONFIG))
          else
            return JSON.parse(File.read(DB_CONFIG)).except(id)
          end
        end
        return {}
      rescue
        return {}
      end
    end

    def eval_last_id(dbs)
      begin
        return dbs.keys.last.to_i + 1
      rescue
        return 1
      end
    end

    def query(sql, control = true)
      begin
        ActiveRecord::Base.connection.begin_db_transaction
        result = ActiveRecord::Base.connection.exec_query(sql)
        ActiveRecord::Base.connection.rollback_db_transaction
        return result
        return ActiveRecord::Base.connection.exec_query(sql)
      rescue Exception => e
        ActiveRecord::Base.connection.rollback_db_transaction
        Database::connect(Database::get_connection(Database::get_connection_id()))
        PGRA::add_error(e.message) if control
        return nil
      end
    end

    def eval_schema()
      begin
        return ActiveRecord::Base.connection.current_schema.strip
      rescue
        return nil
      end
    end

    def connect(db)
      begin
        ActiveRecord::Base.establish_connection(db)
      rescue
        return nil
      end
    end

    def valid_connect?(connection)
      begin
        db = {}
        db["database"] = connection["database"]
        db["schema_search_path"] = connection["schema"]
        db["host"] = connection["host"]
        db["username"] = connection["user"]
        db["password"] = connection["password"]
        db["adapter"] = "postgresql"
        db["encoding"] = "unicode"
        db["pool"] = 5
        ActiveRecord::Base.establish_connection(db)
        ActiveRecord::Base.connection
        return true
      rescue
        return false
      end
    end

    def connected?()
      begin
        db = Database::get_connection(Database::get_connection_id())
        return !(db.nil? or db.blank?)
      rescue
        return false
      end
    end

    def add(connection)
      begin
        dbs = get_connections()
        File.open(DB_CONFIG, 'w') do |file|
          db = {}
          db["name"] = connection["name"]
          db["database"] = connection["database"]
          db["schema_search_path"] = connection["schema"]
          db["host"] = connection["host"]
          db["username"] = connection["user"]
          db["password"] = connection["password"]
          db["adapter"] = "postgresql"
          db["encoding"] = "unicode"
          db["pool"] = 5
          dbs[Database::eval_last_id(dbs)] = db
          file.write(dbs.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    def delete(id)
      begin
        dbs = get_connections(id)
        File.open(DB_CONFIG, 'w') do |file|
          file.write(dbs.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    def edit(connection)
      begin
        dbs = get_connections()
        File.open(DB_CONFIG, 'w') do |file|
          db = {}
          db["name"] = connection["name"]
          db["database"] = connection["database"]
          db["schema_search_path"] = connection["schema"]
          db["host"] = connection["host"]
          db["username"] = connection["user"]
          db["password"] = connection["password"]
          db["adapter"] = "postgresql"
          db["encoding"] = "unicode"
          db["pool"] = 5
          dbs[connection["id"]] = db
          file.write(dbs.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    private

  end
end
