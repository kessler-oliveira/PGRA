# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

class Refactor_col_sub_aco
  class << self

    include Singleton

    @@alias_number = 0

    def get_name()
      return "Subconsulta acoplada na lista de parâmetros"
    end

    def get_description()
      return "Refatora subconsultas acopladas que estejam na lista de parâmetros de retorno, apenas para o primeiro nível."
    end

    def identify(query)
      begin
        query['subquerys'].each do |subquery|
          if 'column'.eql?(subquery['type'])
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
        end
        @@alias_number = 0
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
        querys = []
        if PGRA::path_exist?(raiz, ['SelectStmt','targetList'])
          raiz['SelectStmt']['targetList'].each_with_index do |target|
            flag = true
            if PGRA::path_exist?(target, ['ResTarget','val','SubLink','subselect'])
              text_subquery = PgQuery.new("", Array.new << target['ResTarget']['val']['SubLink']['subselect']).deparse
              query['subquerys'].each_with_index do |subquery,index|
                if text_subquery.eql?(subquery['query'][0]['text']) && identify_step(subquery['query'][0]['where']) && !querys.include?("#{index}") && flag
                  querys << "#{index}"
                  flag = false
                  value = (subquery['query'][0]['select'][0]['alias'].nil?) ? subquery['query'][0]['select'][0]['value'] : subquery['query'][0]['select'][0]['alias']
                  alias_tmp = alias_tmp(query)
                  select_rw = Hash.new
                  select_rw["name"] = target['ResTarget']['name'] unless target['ResTarget']['name'].nil?
                  select_rw["val"] = {"ColumnRef"=>{"fields"=>[{"String"=>{"str"=>alias_tmp}},{"String"=>{"str"=>value}}],"location"=>7}}
                  select_rw["location"] = 7
                  raiz['SelectStmt']['fromClause'][raiz['SelectStmt']['fromClause'].length - 1] = rewrite_from(query, raiz, subquery, alias_tmp)
                  target['ResTarget'] = select_rw
                end
              end
            end
          end
        end
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
          return {"JoinExpr"=>{"jointype"=>1,"larg"=>larg,"rarg"=>{"RangeSubselect"=>{"subquery"=>rarg,"alias"=>{"Alias"=>{"aliasname"=>alias_tmp}}}},"quals"=>quals}}
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
        return false
      end
    end
  end
end
