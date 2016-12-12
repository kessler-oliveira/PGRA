class Query

  attr_accessor :text, :tree, :explain, :work, :cost, :count, :type, :tables, :select, :where, :subquerys

  def initialize(text_query, is_subquery = false)
    @text = self.eval_text(text_query)
    @tree = self.eval_tree(@text)
    @explain = self.eval_explain(@text)
    @work = self.eval_work(@text, is_subquery)
    @cost = self.eval_cost(@explain)
    @count = self.eval_count(@tree)
    @type = self.eval_type(@tree)
    @tables = self.eval_tables(@tree)
    @select = self.eval_select(@tree)
    @where = self.eval_where(@tree)
    @subquerys = self.eval_subquerys(@tree)

    unless @type == 'SELECT' or !@work
      PGRA::add_error('Consulta submetida não suportada')
    end
  end

  def eval_text(text_query)
    begin
      return text_query.strip
    rescue
      return nil
    end
  end

  def eval_tree(text)
    begin
      return PgQuery::parse(text).tree
    rescue
      return nil
    end
  end

  def eval_explain(text)
    begin
      return JSON.parse(Database::query("EXPLAIN (FORMAT JSON) #{text}", false)[0]['QUERY PLAN'])
    rescue
      return nil
    end
  end

  def eval_work(text, is_subquery = false)
    begin
      return !Database::query("#{text}", !is_subquery).nil?
    rescue
      return false
    end
  end

  def eval_cost(explain)
    begin
      return explain[0]['Plan']['Total Cost']
    rescue
      return nil
    end
  end

  def eval_count(tree)
    begin
      tree.deep_dup.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','targetList'])
          raiz['SelectStmt']['targetList'] = [{"ResTarget"=>{"val"=>{"FuncCall"=>{"funcname"=>[{"String"=>{"str" => "count"}}],"args"=>[{"A_Const"=>{"val"=>{"Integer"=>{"ival"=>1}},"location"=>13}}],"location"=>7}},"location"=>7}}]
          return Database::query(PgQuery.new("", Array.new << raiz).deparse, false)[0]['count']
        end
      end
      return nil
    rescue
      return nil
    end
  end

  def eval_type(tree)
    begin
      return tree[0].keys[0].upcase.sub('STMT', '')
    rescue
      return nil
    end
  end

  def eval_tables(tree)
    begin
      tables = Array.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','fromClause'])
          raiz['SelectStmt']['fromClause'].each do |target|
            if PGRA::path_exist?(target, ['RangeVar'])
              eval_tables_base(target['RangeVar']).each do |table|
                tables << table
              end
            end
            if PGRA::path_exist?(target, ['JoinExpr'])
              eval_tables_join(target['JoinExpr']).each do |table|
                tables << table
              end
            end
          end
        end
      end
      return tables unless tables.empty?
    rescue
      return nil
    end
  end

  def eval_tables_base(raiz)
    begin
      tables = Array.new
      if PGRA::path_exist?(raiz,['alias','Alias','aliasname'])
        alias_table = raiz['alias']['Alias']['aliasname']
      end
      if PGRA::path_exist?(raiz,['schemaname'])
        schema = raiz['schemaname']
      end
      if PGRA::path_exist?(raiz, ['relname'])
        tables << Table.new(schema, raiz['relname'], alias_table)
      end
      return tables
    rescue
      return nil
    end
  end

  def eval_tables_join(raiz)
    begin
      tables = Array.new
      if PGRA::path_exist?(raiz, ['larg','RangeVar'])
        eval_tables_base(raiz['larg']['RangeVar']).each do |table|
          tables << table
        end
      end
      if PGRA::path_exist?(raiz, ['rarg','RangeVar'])
        eval_tables_base(raiz['rarg']['RangeVar']).each do |table|
          tables << table
        end
      end
      return tables
    rescue
      return nil
    end
  end

  def eval_select(tree)
    begin
      select = Array.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt'])
          if PGRA::path_exist?(raiz, ['SelectStmt','targetList'])
            raiz['SelectStmt']['targetList'].each do |target|
              if PGRA::path_exist?(target, ['ResTarget','val','A_Const','val'])
                select << eval_select_const(target['ResTarget'])
              end
              if PGRA::path_exist?(target, ['ResTarget','val','ColumnRef','fields'])
                select << eval_select_column(target['ResTarget'])
              end
              if PGRA::path_exist?(target, ['ResTarget','val','SubLink','subselect'])
                select << eval_select_sublink(target['ResTarget'])
              end
            end
          end
        end
      end
      return select unless select.empty?
    rescue
      return nil
    end
  end

  def eval_select_const(raiz)
    begin
      if PGRA::path_exist?(raiz, ['val','A_Const','val','String','str'])
        return {:"value" => raiz['val']['A_Const']['val']['String']['str'], :alias => raiz['name'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'String', :type => 'constant'}
      end
      if PGRA::path_exist?(raiz, ['val','A_Const','val','Integer','ival'])
        return {:value => raiz['val']['A_Const']['val']['Integer']['ival'], :alias => raiz['name'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'Integer', :type => 'constant'}
      end
      if PGRA::path_exist?(raiz, ['val','A_Const','val','Float','str'])
        return {:value => raiz['val']['A_Const']['val']['Float']['str'], :alias => raiz['name'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'Float', :type => 'constant'}
      end
    rescue
      return nil
    end
  end

  def eval_select_column(raiz)
    begin
      value = nil
      table_name = nil
      alias_table = nil
      schema = nil
      data_type = nil
      raiz_extend = raiz['val']['ColumnRef']['fields']
      if PGRA::path_exist?(raiz_extend, [raiz_extend.length - 1])
        if raiz_extend.length > 0
          if PGRA::path_exist?(raiz_extend, [raiz_extend.length - 1,'String','str'])
            value = raiz_extend[raiz_extend.length - 1]['String']['str']
          end
          if PGRA::path_exist?(raiz_extend, [raiz_extend.length - 1,'A_Star'])
            value = '*'
          end
          if raiz_extend.length > 1
            alias_table = raiz_extend[raiz_extend.length - 2]['String']['str']
            if raiz_extend.length > 2
              schema = raiz_extend[raiz_extend.length - 3]['String']['str']
            end
          end
        end

        unless @tables.nil?
          @tables.as_json.each do |table|
            if schema.nil?
              if (alias_table.eql?(table['name']) && !table['name'].nil?) || (alias_table.eql?(table['alias']) && !table['alias'].nil?) || (raiz_extend.length == 1 && !value.eql?('*'))
                table['columns'].each do |column|
                  table_name = table['name']
                  alias_table = table['alias']
                  schema = table['schema']
                  if value.eql? column['name']
                    data_type = column['data_type']
                  end
                end
              end
            else
              if (alias_table.eql?(table['name']) && schema.eql?(table['schema'])) || (alias_table.eql?(table['alias']) && schema.eql?(table['schema']))
                table['columns'].each do |column|
                  table_name = table['name']
                  alias_table = table['alias']
                  schema = table['schema']
                  if value.eql? column['name']
                    data_type = column['data_type']
                  end
                end
              end
            end
          end
        end
      end
      return {:value => value, :alias => raiz['name'], :table => table_name, :alias_table => alias_table, :schema => schema, :data_type => data_type, :type => 'column'}
    rescue
      return nil
    end
  end

  def eval_select_sublink(raiz)
    begin
      return {:value => PgQuery.new("", Array.new << raiz['val']['SubLink']['subselect']).deparse, :alias => raiz['name'], :table => nil, :alias_table => nil, :schema => nil, :data_type => nil, :type => 'subquery'}
    rescue
      return nil
    end
  end

  def eval_where(tree)
    begin
      where = Hash.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','whereClause'])
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','A_Expr'])
            where = eval_where_expr(raiz['SelectStmt']['whereClause']['A_Expr'])
          end
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','SubLink'])
            where = eval_where_sublink(raiz['SelectStmt']['whereClause']['SubLink'])
          end
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','BoolExpr'])
            where = eval_where_boolexpr(raiz['SelectStmt']['whereClause']['BoolExpr'])
          end
        end
      end
      return where unless where.empty?
    rescue
      return nil
    end
  end

  def eval_where_expr(raiz)
    begin
      where = Hash.new
      if PGRA::path_exist?(raiz, ['name'])
        where["operator"] = raiz['name'][0]['String']['str']
      end
      if PGRA::path_exist?(raiz, ['lexpr'])
        if PGRA::path_exist?(raiz, ['lexpr','A_Const'])
          where["left_expr"] = eval_where_expr_const(raiz['lexpr']['A_Const']['val'])
        end
        if PGRA::path_exist?(raiz, ['lexpr','ColumnRef'])
          where["left_expr"] = eval_where_expr_column(raiz['lexpr']['ColumnRef']['fields'])
        end
        if PGRA::path_exist?(raiz, ['lexpr','SubLink'])
          where["left_expr"] = eval_where_expr_sublink(raiz['lexpr']['SubLink']['subselect'])
        end
      end
      if PGRA::path_exist?(raiz, ['rexpr'])
        if PGRA::path_exist?(raiz, ['rexpr','A_Const'])
          where["right_expr"] = eval_where_expr_const(raiz['rexpr']['A_Const']['val'])
        end
        if PGRA::path_exist?(raiz, ['rexpr','ColumnRef'])
          where["right_expr"] = eval_where_expr_column(raiz['rexpr']['ColumnRef']['fields'])
        end
        if PGRA::path_exist?(raiz, ['rexpr','SubLink'])
          where["right_expr"] = eval_where_expr_sublink(raiz['rexpr']['SubLink']['subselect'])
        end
      end
      return where
    rescue
      return nil
    end
  end

  def eval_where_expr_const(raiz)
    begin
      if PGRA::path_exist?(raiz, ['String','str'])
        return {:value => raiz['String']['str'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'String', :type => 'constant'}
      end
      if PGRA::path_exist?(raiz, ['Integer','ival'])
        return {:value => raiz['Integer']['ival'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'Integer', :type => 'constant'}
      end
      if PGRA::path_exist?(raiz, ['Float','str'])
        return {:value => raiz['Float']['str'], :table => nil, :alias_table => nil, :schema => nil, :data_type => 'Float', :type => 'constant'}
      end
    rescue
      return nil
    end
  end

  def eval_where_expr_column(raiz)
    begin
      value = nil
      table_name = nil
      alias_table = nil
      schema = nil
      data_type = nil
      if raiz.length > 0
        value = raiz[raiz.length - 1]['String']['str']
        if raiz.length > 1
          alias_table = raiz[raiz.length - 2]['String']['str']
          if raiz.length > 2
            schema = raiz[raiz.length - 3]['String']['str']
          end
        end
      end
      unless @tables.nil?
        @tables.as_json.each do |table|
          if alias_table.eql?(table['name']) || alias_table.eql?(table['alias']) || raiz.length == 1
            table['columns'].each do |column|
              if value.eql? column['name']
                table_name = table['name']
                alias_table = table['alias']
                schema = table['schema']
                data_type = column['data_type']
              end
            end
          end
        end
      end
      return {:value => value, :table => table_name, :alias_table => alias_table, :schema => schema, :data_type => data_type, :type => 'column'}
    rescue
      return nil
    end
  end

  def eval_where_expr_sublink(raiz)
    begin
      return {:value => PgQuery.new("", Array.new << raiz).deparse, :table => nil, :alias_table => nil, :schema => nil, :data_type => nil, :type => 'subquery'}
    rescue
      return nil
    end
  end

  def eval_where_sublink(raiz)
    begin
      where = Hash.new
      where["operator"] = 'IN'
      if PGRA::path_exist?(raiz, ['testexpr'])
        if PGRA::path_exist?(raiz, ['testexpr','A_Const'])
          where["left_expr"] = eval_where_expr_const(raiz['testexpr']['A_Const']['val'])
        end
        if PGRA::path_exist?(raiz, ['testexpr','ColumnRef'])
          where["left_expr"] = eval_where_expr_column(raiz['testexpr']['ColumnRef']['fields'])
        end
        if PGRA::path_exist?(raiz, ['testexpr','SubLink'])
          where["left_expr"] = eval_where_expr_sublink(raiz['testexpr']['SubLink']['subselect'])
        end
      end
      if PGRA::path_exist?(raiz, ['subselect'])
        where["right_expr"] = eval_where_expr_sublink(raiz['subselect'])
      end
      return where
    rescue
      return nil
    end
  end

  def eval_where_boolexpr(raiz)
    begin
      where = Hash.new
      case raiz['boolop']
      when 0
        where["operator"] = 'AND'
      when 1
        where["operator"] = 'OR'
      when 2
        where["operator"] = 'NOT'
      end
      exprs = Array.new
      raiz['args'].each do |arg|
        if PGRA::path_exist?(arg, ['A_Expr'])
          exprs << eval_where_expr(arg['A_Expr'])
        end
        if PGRA::path_exist?(arg, ['SubLink'])
          exprs << eval_where_sublink(arg['SubLink'])
        end
        if PGRA::path_exist?(arg, ['BoolExpr'])
          exprs << eval_where_boolexpr(arg['BoolExpr'])
        end
      end
      where["expr"] = exprs
      return where
    rescue
      return nil
    end
  end

  def eval_subquerys(tree)
    begin
      subquerys = Array.new
      eval_subquerys_column(tree).each do |subquery|
        subquerys << subquery
      end
      eval_subquerys_from(tree).each do |subquery|
        subquerys << subquery
      end
      eval_subquerys_where(tree).each do |subquery|
        subquerys << subquery
      end
      return subquerys unless subquerys.empty?
    rescue
      return nil
    end
  end

  def eval_subquerys_column(tree)
    begin
      subquerys = Array.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','targetList'])
          raiz['SelectStmt']['targetList'].each do |target|
            if PGRA::path_exist?(target, ['ResTarget','val','SubLink','subselect','SelectStmt','op'])
              alias_subquery = target['ResTarget']['name']
              if target['ResTarget']['val']['SubLink']['subselect']['SelectStmt']['op'] == 0
                subquerys << {:type => 'column', :alias => alias_subquery, :query => [Query.new(PgQuery.new("", Array.new << target['ResTarget']['val']['SubLink']['subselect']).deparse, true)]}
              elsif target['ResTarget']['val']['SubLink']['subselect']['SelectStmt']['op'] == 1
                l = Query.new(PgQuery.new("", Array.new << target['ResTarget']['val']['SubLink']['subselect']['SelectStmt']['larg']).deparse, true)
                r = Query.new(PgQuery.new("", Array.new << target['ResTarget']['val']['SubLink']['subselect']['SelectStmt']['rarg']).deparse, true)
                subquerys << {:type => 'column', :alias => alias_subquery, :query => [l, r]}
              end
            end
          end
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_from(tree)
    begin
      subquerys = Array.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','fromClause'])
          raiz['SelectStmt']['fromClause'].each do |target|
            if PGRA::path_exist?(target, ['RangeSubselect'])
              eval_subquerys_from_base(target['RangeSubselect']).each do |subquery|
                subquerys << subquery
              end
            end
            if PGRA::path_exist?(target, ['JoinExpr'])
              eval_subquerys_from_join(target['JoinExpr']).each do |subquery|
                subquerys << subquery
              end
            end
          end
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_from_base(raiz)
    begin
      subquerys = Array.new
      alias_subquery = raiz['alias']['Alias']['aliasname']
      if PGRA::path_exist?(raiz, ['subquery','SelectStmt','op'])
        if raiz['subquery']['SelectStmt']['op'] == 0
          subquerys << {:type => 'from', :alias => alias_subquery, :query => [Query.new(PgQuery.new("", Array.new << raiz['subquery']).deparse, true)]}
        elsif raiz['subquery']['SelectStmt']['op'] == 1
          l = Query.new(PgQuery.new("", Array.new << raiz['subquery']['SelectStmt']['larg']).deparse, true)
          r = Query.new(PgQuery.new("", Array.new << raiz['subquery']['SelectStmt']['rarg']).deparse, true)
          subquerys << {:type => 'from', :alias => alias_subquery, :query => [l, r]}
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_from_join(raiz)
    begin
      subquerys = Array.new
      if PGRA::path_exist?(raiz, ['larg','RangeSubselect'])
        eval_subquerys_from_base(raiz['larg']['RangeSubselect']).each do |subquery|
          subquerys << subquery
        end
      end
      if PGRA::path_exist?(raiz, ['rarg','RangeSubselect'])
        eval_subquerys_from_base(raiz['rarg']['RangeSubselect']).each do |subquery|
          subquerys << subquery
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_where(tree)
    begin
      subquerys = Array.new
      tree.each do |raiz|
        if PGRA::path_exist?(raiz, ['SelectStmt','whereClause'])
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','A_Expr'])
            eval_subquerys_where_expr(raiz['SelectStmt']['whereClause']['A_Expr']).each do |subquery|
              subquerys << subquery
            end
          end
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','SubLink'])
            eval_subquerys_where_sublink(raiz['SelectStmt']['whereClause']['SubLink']).each do |subquery|
              subquerys << subquery
            end
          end
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','BoolExpr'])
            eval_subquerys_where_boolexpr(raiz['SelectStmt']['whereClause']['BoolExpr']).each do |subquery|
              subquerys << subquery
            end
          end
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_where_expr(raiz)
    begin
      subquerys = Array.new
      if PGRA::path_exist?(raiz, ['lexpr','SubLink'])
        if PGRA::path_exist?(raiz, ['lexpr','SubLink','subselect','SelectStmt','op'])
          if raiz['lexpr']['SubLink']['subselect']['SelectStmt']['op'] == 0
            subquerys << {:type => 'where', :query => [Query.new(PgQuery.new("", Array.new << raiz['lexpr']['SubLink']['subselect']).deparse, true)]}
          elsif raiz['lexpr']['SubLink']['subselect']['SelectStmt']['op'] == 1
            l = Query.new(PgQuery.new("", Array.new << raiz['lexpr']['SubLink']['subselect']['SelectStmt']['larg']).deparse, true)
            r = Query.new(PgQuery.new("", Array.new << raiz['lexpr']['SubLink']['subselect']['SelectStmt']['rarg']).deparse, true)
            subquerys << {:type => 'where', :alias => nil, :query => [l, r]}
          end
        end
      end
      if PGRA::path_exist?(raiz, ['rexpr','SubLink'])
        if PGRA::path_exist?(raiz, ['rexpr','SubLink','subselect','SelectStmt','op'])
          if raiz['rexpr']['SubLink']['subselect']['SelectStmt']['op'] == 0
            subquerys << {:type => 'where', :query => [Query.new(PgQuery.new("", Array.new << raiz['rexpr']['SubLink']['subselect']).deparse, true)]}
          elsif raiz['rexpr']['SubLink']['subselect']['SelectStmt']['op'] == 1
            l = Query.new(PgQuery.new("", Array.new << raiz['rexpr']['SubLink']['subselect']['SelectStmt']['larg']).deparse, true)
            r = Query.new(PgQuery.new("", Array.new << raiz['rexpr']['SubLink']['subselect']['SelectStmt']['rarg']).deparse, true)
            subquerys << {:type => 'where', :alias => nil, :query => [l, r]}
          end
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_where_sublink(raiz)
    begin
      subquerys = Array.new
      if PGRA::path_exist?(raiz, ['subselect','SelectStmt','op'])
        if raiz['subselect']['SelectStmt']['op'] == 0
          subquerys << {:type => 'where', :alias => nil, :query => [Query.new(PgQuery.new("", Array.new << raiz['subselect']).deparse, true)]}
        elsif raiz['subselect']['SelectStmt']['op'] == 1
          l = Query.new(PgQuery.new("", Array.new << raiz['subselect']['SelectStmt']['larg']).deparse, true)
          r = Query.new(PgQuery.new("", Array.new << raiz['subselect']['SelectStmt']['rarg']).deparse, true)
          subquerys << {:type => 'where', :alias => nil, :query => [l, r]}
        end
      end
      return subquerys
    rescue
      return nil
    end
  end

  def eval_subquerys_where_boolexpr(raiz)
    begin
      subquerys = Array.new
      raiz['args'].each do |arg|
        if PGRA::path_exist?(arg, ['A_Expr'])
          eval_subquerys_where_expr(arg['A_Expr']).each do |subquery|
            subquerys << subquery
          end
        end
        if PGRA::path_exist?(arg, ['SubLink'])
          eval_subquerys_where_sublink(arg['SubLink']).each do |subquery|
            subquerys << subquery
          end
        end
        if PGRA::path_exist?(arg, ['BoolExpr'])
          eval_subquerys_where_boolexpr(arg['BoolExpr']).each do |subquery|
            subquerys << subquery
          end
        end
      end
      return subquerys
    rescue
      return nil
    end
  end
end
