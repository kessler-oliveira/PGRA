class Column

  attr_accessor :name, :is_nullable, :data_type

  def initialize(name, is_nullable, data_type)
    @name = name
    @is_nullable = is_nullable
    @data_type = data_type
  end

  def self.eval_columns(table, schema)
    begin
      text_columns = Database::query("SELECT column_name as name, is_nullable, data_type FROM information_schema.columns WHERE table_name = '#{table}' AND table_schema = '#{schema}'", false)
      columns = []
      text_columns.each do |text_column|
        columns << Column.new(text_column['name'], text_column['is_nullable'], text_column['data_type'])
      end
      return columns
    rescue
      return nil
    end
  end
end
