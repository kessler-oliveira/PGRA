class Refactor_where_sub_aco
  class << self

    include Singleton

    @@alias_number = 0
    @@querys = []

    def get_name()
      return "Subconsulta acoplada na cláusula WHERE"
    end

    def get_description()
      return "Refatora subconsultas acopladas que estejam nas cláusula WHERE, apenas para o primeiro nível."
    end

    def identify(query)
      begin
        query['subquerys'].each do |subquery|
          if 'where'.eql?(subquery['type'])
            subquery['query'].each do |subquery_query|
              return identify_step(subquery_query['where'])
            end
          end
        end
        return false
      rescue
        return false
      end
    end

    def rewrite(query)
      begin
        query['tree'].each do |raiz|
          rewrite_select(query, raiz)
          rewrite_where(query, raiz)
        end
        return JSON.parse(Query.new(PgQuery.new("", query['tree']).deparse).to_json)
      rescue
        return nil
      end
    end

    private

    def alias_tmp(query)
      begin
        result = "rw_tmp_#{@@alias_number += 1}"
        query['tables'].each do |table|
          alias_table = (table['alias'].nil?) ? table['name'] : table['alias']
          if result.eql?(alias_table)
            return alias_tmp(query)
          end
        end
        query['subquerys'].each do |subquery|
          if "from".eql?(subquery['type'])
            alias_subquery = subquery['alias']
            if result.eql?(alias_subquery)
              return alias_tmp(query)
            end
          end
        end
        return result
      rescue
        return nil
      end
    end

    def rewrite_select(query, raiz)
      begin
        if PGRA::path_exist?(raiz, ['SelectStmt','targetList'])
          raiz['SelectStmt']['targetList'].each do |target|
            if PGRA::path_exist?(target, ['ResTarget', 'val', 'ColumnRef'])
              if(target['ResTarget']['val']['ColumnRef']['fields'].length == 1)
                value = target['ResTarget']['val']['ColumnRef']['fields'][0]['String']['str']
                query['select'].each do |select|
                  if value.eql?(select['value'])
                    alias_table = (select['alias_table'].nil?) ? select['table'] : select['alias_table']
                    target['ResTarget']['val']['ColumnRef'] = {"fields"=>[{"String"=>{"str"=>alias_table}},{"String"=>{"str"=>value}}],"location"=>7}
                  end
                end
              end
            end
          end
        end
      rescue
         return nil
      end
    end

    def rewrite_where(query, raiz)
      begin
        if PGRA::path_exist?(raiz, ['SelectStmt','whereClause'])
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','A_Expr'])
            rewrite_where_expr(query, raiz, raiz['SelectStmt']['whereClause']['A_Expr'])
          end
          if PGRA::path_exist?(raiz, ['SelectStmt','whereClause','BoolExpr'])
            rewrite_where_boolexpr(query, raiz, raiz['SelectStmt']['whereClause']['BoolExpr'])
          end
        end
        return query
      rescue
         return nil
      end
    end

    def rewrite_where_expr(query, raiz, where)
      begin
        if PGRA::path_exist?(where, ['lexpr'])
          if PGRA::path_exist?(where, ['lexpr','SubLink'])
            rewrite_where_expr_subquery(query, raiz, where, "lexpr")
          end
        end
        if PGRA::path_exist?(where, ['rexpr'])
          if PGRA::path_exist?(where, ['rexpr','SubLink'])
            rewrite_where_expr_subquery(query, raiz, where, "rexpr")
          end
        end
        return query
      rescue
         return nil
      end
    end

    def rewrite_where_boolexpr(query, raiz, where)
      begin
        where['args'].each do |arg|
          if PGRA::path_exist?(arg, ['A_Expr'])
            rewrite_where_expr(query, raiz, arg['A_Expr'])
          end
          if PGRA::path_exist?(arg, ['BoolExpr'])
            rewrite_where_boolexpr(query, raiz, arg['BoolExpr'])
          end
        end
        return query
      rescue
         return nil
      end
    end

    def rewrite_where_expr_subquery(query, raiz, where, pos)
      begin
        flag = true
        text_subquery = PgQuery.new("", Array.new << where[pos]['SubLink']['subselect']).deparse
        query['subquerys'].each_with_index do |subquery,index|
          if text_subquery.eql?(subquery['query'][0]['text']) && identify_step(subquery['query'][0]['where']) && !@@querys.include?("#{index}") && flag
            @@querys << "#{index}"
            flag = false
            value = (subquery['query'][0]['select'][0]['alias'].nil?) ? subquery['query'][0]['select'][0]['value'] : subquery['query'][0]['select'][0]['alias']
            alias_tmp = alias_tmp(query)
            where_rw = Hash.new
            where_rw["fields"] = [{"String"=>{"str"=>alias_tmp}},{"String"=>{"str"=>value}}]
            where_rw["location"] = 34
            raiz['SelectStmt']['fromClause'][raiz['SelectStmt']['fromClause'].length - 1] = rewrite_from(query, raiz, subquery, alias_tmp)
            where[pos] = {"ColumnRef"=>where_rw}
            rewrite_where_expr_table(query, raiz, where, pos)
          end
        end
        return query
      rescue
         return nil
      end
    end

    def rewrite_where_expr_table(query, raiz, where, pos)
      begin
        pos_inverso = "lexpr".eql?(pos) ? "rexpr" : "lexpr"
        if PGRA::path_exist?(where, [pos_inverso,'ColumnRef'])
          value = nil
          where_extend = where[pos_inverso]['ColumnRef']['fields']
          if PGRA::path_exist?(where_extend, [where_extend.length - 1])
            if where_extend.length == 1
              if PGRA::path_exist?(where_extend, [where_extend.length - 1,'String','str'])
                value = where_extend[where_extend.length - 1]['String']['str']
                unless query["tables"].nil?
                  query["tables"].each do |table|
                    table['columns'].each do |column|
                      if value.eql? column['name']
                        where[pos_inverso]['ColumnRef']['fields'] = [{"String"=>{"str"=>((table['alias'].nil?) ? table['name'] : table['alias'])}},{"String"=>{"str"=>value}}]
                      end
                    end
                  end
                end
              end
            end
          end
        end
        return query
      rescue
         return nil
      end
    end

    def rewrite_from(query, raiz, subquery, alias_tmp)
      begin
        if PGRA::path_exist?(raiz, ['SelectStmt','fromClause'])
          larg = raiz['SelectStmt']['fromClause'][raiz['SelectStmt']['fromClause'].length - 1]
          rarg = rewrite_subquery(subquery['query'][0])
          quals = rewrite_subquery_where(subquery['query'][0], alias_tmp)
          subquery['query'][0]['tree'][0]['SelectStmt'].delete('whereClause')
          return {"JoinExpr"=>{"jointype"=>0,"larg"=>larg,"rarg"=>{"RangeSubselect"=>{"subquery"=>rarg,"alias"=>{"Alias"=>{"aliasname"=>alias_tmp}}}},"quals"=>quals}}
        end
      rescue
         return nil
      end
    end

    def rewrite_subquery(subquery)
      begin
        rewrite_subquery_select(subquery).each do |target|
          subquery['tree'][0]['SelectStmt']['targetList'] << target
        end
        return subquery['tree'][0]
      rescue
         return nil
      end
    end

    def rewrite_subquery_select(subquery)
      begin
        targetList = Array.new
        if PGRA::path_exist?(subquery, ['where'])
          rewrite_subquery_select_where(subquery['where']).each do |where|
            targetList << {"ResTarget"=>{"name"=>"rw_#{where['value']}","val"=>{"ColumnRef"=>{"fields"=>[{"String"=>{"str"=>(where['alias_table'].nil?) ? where['table'] : where['alias_table']}},{"String"=>{"str"=>where['value']}}],"location"=>24}},"location"=>24}}
          end
        end
        return targetList
      rescue
         return nil
      end
    end

    def rewrite_subquery_select_where(raiz)
      begin
        where = Array.new
        if PGRA.path_exist?(raiz, ['left_expr'])
          if 'column'.eql?(raiz['left_expr']['type']) && !raiz['left_expr']['table'].nil?
            where << raiz['left_expr']
          end
        end
        if PGRA.path_exist?(raiz, ['right_expr'])
          if 'column'.eql?(raiz['right_expr']['type']) && !raiz['right_expr']['table'].nil?
            where << raiz['right_expr']
          end
        end
        if PGRA.path_exist?(raiz, ['expr'])
          raiz['expr'].each do |expr|
            rewrite_subquery_select_where(expr).each do |w|
              where << w
            end
          end
        end
        return where
      rescue
         return nil
      end
    end

    def rewrite_subquery_where(subquery, alias_tmp)
      begin
        where = Hash.new
        if PGRA::path_exist?(subquery['tree'][0], ['SelectStmt','whereClause','A_Expr'])
          where = rewrite_subquery_where_expr(subquery, subquery['tree'][0]['SelectStmt']['whereClause']['A_Expr'], alias_tmp)
        end
        if PGRA::path_exist?(subquery['tree'][0], ['SelectStmt','whereClause','SubLink'])
          where = rewrite_subquery_where_sublink(subquery, subquery['tree'][0]['SelectStmt']['whereClause']['SubLink'], alias_tmp)
        end
        if PGRA::path_exist?(subquery['tree'][0], ['SelectStmt','whereClause','BoolExpr'])
          where = rewrite_subquery_where_boolexpr(subquery, subquery['tree'][0]['SelectStmt']['whereClause']['BoolExpr'], alias_tmp)
        end
        return where
      rescue
         return nil
      end
    end

    def rewrite_subquery_where_expr(subquery, raiz, alias_tmp)
      begin
        fields = [{"String"=>{"str"=>alias_tmp}}, {}]
        if PGRA::path_exist?(raiz, ['lexpr','ColumnRef'])
          if raiz['lexpr']['ColumnRef']['fields'].length == 1
            value = raiz['lexpr']['ColumnRef']['fields'][raiz['lexpr']['ColumnRef']['fields'].length() - 1]
            value['String']['str'] = "rw_#{value['String']['str']}"
            fields[1] = value
            raiz['lexpr']['ColumnRef']['fields'] = fields
          else
            alias_table = raiz['lexpr']['ColumnRef']['fields'][raiz['lexpr']['ColumnRef']['fields'].length() - 2]['String']['str']
            subquery['tables'].each do |table|
              if alias_table.eql?(table['name']) || alias_table.eql?(table['alias'])
                value = raiz['lexpr']['ColumnRef']['fields'][raiz['lexpr']['ColumnRef']['fields'].length() - 1]
                value['String']['str'] = "rw_#{value['String']['str']}"
                fields[1] = value
                raiz['lexpr']['ColumnRef']['fields'] = fields
              end
            end
          end
        end
        if PGRA::path_exist?(raiz, ['rexpr','ColumnRef'])
          if raiz['rexpr']['ColumnRef']['fields'].length == 1
            value = raiz['rexpr']['ColumnRef']['fields'][raiz['rexpr']['ColumnRef']['fields'].length() - 1]
            value['String']['str'] = "rw_#{value['String']['str']}"
            fields[1] = value
            raiz['rexpr']['ColumnRef']['fields'] = fields
          else
            alias_table = raiz['rexpr']['ColumnRef']['fields'][raiz['rexpr']['ColumnRef']['fields'].length() - 2]['String']['str']
            subquery['tables'].each do |table|
              if alias_table.eql?(table['name']) || alias_table.eql?(table['alias'])
                value = raiz['rexpr']['ColumnRef']['fields'][raiz['rexpr']['ColumnRef']['fields'].length() - 1]
                value['String']['str'] = "rw_#{value['String']['str']}"
                fields[1] = value
                raiz['rexpr']['ColumnRef']['fields'] = fields
              end
            end
          end
        end
        return subquery['tree'][0]['SelectStmt']['whereClause']
      rescue
         return nil
      end
    end

    def rewrite_subquery_where_sublink(subquery, raiz, alias_tmp)
      begin
        if PGRA::path_exist?(raiz, ['testexpr','ColumnRef'])
          return rewrite_subquery_where_expr(subquery, raiz['testexpr']['ColumnRef']['fields'], alias_tmp)
        end
        return subquery['tree'][0]['SelectStmt']['whereClause']
      rescue
         return nil
      end
    end

    def rewrite_subquery_where_boolexpr(subquery, raiz, alias_tmp)
      begin
        raiz['args'].each do |arg|
          if PGRA::path_exist?(arg, ['A_Expr'])
            rewrite_subquery_where_expr(subquery, arg['A_Expr'], alias_tmp)
          end
          if PGRA::path_exist?(arg, ['SubLink'])
            rewrite_subquery_where_sublink(subquery, arg['SubLink'], alias_tmp)
          end
          if PGRA::path_exist?(arg, ['BoolExpr'])
            rewrite_subquery_where_boolexpr(subquery, arg['BoolExpr'], alias_tmp)
          end
        end
        return subquery['tree'][0]['SelectStmt']['whereClause']
      rescue
         return nil
      end
    end

    def identify_step(raiz)
      begin
        if PGRA.path_exist?(raiz, ['left_expr'])
          if 'column'.eql?(raiz['left_expr']['type']) && raiz['left_expr']['table'].nil?
            return true
          end
        end
        if PGRA.path_exist?(raiz, ['right_expr'])
          if 'column'.eql?(raiz['right_expr']['type']) && raiz['right_expr']['table'].nil?
            return true
          end
        end
        if PGRA.path_exist?(raiz, ['expr'])
          raiz['expr'].each do |expr|
            return identify_step(expr)
          end
        end
        return false
      rescue
      #  return false
      end
    end
  end
end
