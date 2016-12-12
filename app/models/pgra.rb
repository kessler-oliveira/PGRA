class PGRA
  class << self

    include Singleton

    def save(file, data)
      begin
        File.open("#{DIR_DATA}#{file}.json", 'w') do |file|
          file.write(data.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    def load(file)
      begin
        return JSON.parse(File.read("#{DIR_DATA}#{file}.json"))
      rescue
        return nil
      end
    end

    def add_error(erro)
      begin
        errors = list_errors()["feedback"]
        File.open("#{DIR_DATA}error.json", 'w') do |file|
          result = {"feedback" => errors << erro}
          file.write(result.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    def list_errors()
      begin
        return (File.read("#{DIR_DATA}error.json").blank?) ? {"feedback" => []} : JSON.parse(File.read("#{DIR_DATA}error.json"))
      rescue
        return {"feedback" => []}
      end
    end

    def clean_errors()
      begin
        File.open("#{DIR_DATA}error.json", 'w') do |file|
          file.write({"feedback" => []}.to_json)
          file.close
        end
      rescue
        return nil
      end
    end

    def path_exist?(base, paths)
      begin
        flag = true
        paths.each do |path|
          if flag
            unless base[path].nil?
              base = base[path]
            else
              flag = false
            end
          end
        end
        return flag
      rescue
        return nil
      end
    end

    def identify(query)
      begin
        objects = []
        Dir['./app/models/modules/*.rb'].sort.each do |item|
          type_rewrite = item.gsub('.rb', '').split('/').pop.capitalize
          classe = Object.const_get(type_rewrite)
          objects << {type_rewrite.to_sym => classe.identify(query)}
        end
        return objects
      rescue
        return []
      end
    end

    def rewrite(query, identify)

      rewrite = [{"name" => "Original", "description" => "-", "query" => query, "performance" => 0, "reescrever" => false}]
      identify.each do |item|
        item.each do |key, value|
          if value == true
            classe = Object.const_get(key)
            rewrite_query = classe.rewrite(JSON.parse(JSON.generate(query)))
            rewrite << {"name" => classe.get_name, "description" => classe.get_description, "query" => rewrite_query, "performance" => (100 - ((rewrite_query["cost"] * 100) / query["cost"])).round(2), "reescrever" => identify_any(rewrite_query)}
          end
        end
      end

      rewrite.sort! {|x,y| y["performance"] <=> x["performance"]}

      rank = 1
      rewrite.each_with_index.map{|e, i|
        e["rank"] = (rewrite[i-1]["performance"] == e["performance"]) ? rank : rank = i + 1
      }

      return rewrite

    end

    def get_query(query_id)
      begin
        rule = AnbtSql::Rule.new
        rule.keyword = AnbtSql::Rule::KEYWORD_UPPER_CASE
        %w(count sum substr date).each{|func_name|
          rule.function_names << func_name.upcase
        }
        rule.indent_string = "   "
        formatter = AnbtSql::Formatter.new(rule)
        return formatter.format(PGRA::load('rewrite')[query_id.to_i]["query"]["text"])
      rescue
        return nil
      end
    end

    private

    def identify_any(query)
      begin
        Dir['./app/models/modules/*.rb'].sort.each do |item|
          type_rewrite = item.gsub('.rb', '').split('/').pop.capitalize
          classe = Object.const_get(type_rewrite)
          return true if classe.identify(query)
        end
        return false
      rescue
        return false
      end
    end
  end
end

class Array
  def deep_dup
    map {|x| x.deep_dup}
  end
end

class Object
  def deep_dup
    dup
  end
end

class Numeric
  def deep_dup
    self
  end
end
