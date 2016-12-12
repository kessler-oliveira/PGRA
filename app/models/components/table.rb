# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

class Table

  attr_accessor :name, :schema, :alias, :columns

  def initialize(text_schema, text_table, text_alias)
    @name = self.eval_name(text_table)
    @schema = self.eval_schema(text_schema)
    @alias = self.eval_alias(text_alias)
    @columns = Column::eval_columns(@name, @schema)
  end

  def eval_name(text_table)
    begin
      return text_table.strip
    rescue
      return nil
    end
  end

  def eval_schema(text_schema)
    begin
      return (text_schema.nil?) ? Database::eval_schema : text_schema.strip
    rescue
      return nil
    end
  end

  def eval_alias(text_alias)
    begin
      return text_alias.strip
    rescue
      return nil
    end
  end
end
