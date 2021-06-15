class Clickhouse
  class Query
    def self.build
      qb = QueryBuilder.new
      yield(qb)
      qb.build
    end
  end

  enum QueryType
    SELECT
    COUNT
  end

  module QueryVerbs
    def where(stmt, args : Array)
      args = args.map{|v|
        case v
        when Int, Float
          v.to_s
        else
          quote_str(v.to_s)
        end
      }
      conds << (stmt.gsub("?", "%s") % args)
    end

    def by_name(v : Array(String) | String | Nil, not = false)
      return if name_fields.empty?
      names = v.is_a?(Array) ? v : v.to_s.gsub(/　/, " ").split(/\s+/)
      names.each do |name|
        name = name.strip
        next if name.empty?
        field = (name_fields.size == 1) ? name_fields.first : ("concat(%s)" % name_fields.join(","))
        contains(field, name, not: not)
      end
    end

    def contains(field, value, not = false)
      op = not ? "=" : ">"
      conds << "positionCaseInsensitiveUTF8(%s, %s) #{op} 0" % [field, quote_str(value)]
    end
  end

  class QueryBuilder
    var table         : String
    var ids           : Array(String)
    var fields        : Array(String) = ["*"]
    var name_fields   = Array(String).new
    var conds         = Array(String).new
    var orders        = Array(String).new
    var limit         : Int32?
    var format        : String = "JSONCompact"
    var type          : QueryType = QueryType::SELECT

    include QueryVerbs

    def select
      build(QueryType::SELECT)
    end

    def count
      build(QueryType::COUNT)
    end

    def where : String
      conds.map{|c| "(#{c})"}.join("\n  AND ")
    end

    def build(type = nil)
      type ||= self.type()
      field = fields.join(", ")
      field = "count(*)" if type.count?
      String.build do |s|
        s << "SELECT #{field}\n"
        s << "FROM #{table}\n"
        if conds.any?
          s << "WHERE " << where << "\n"
        end
        if ! type.count?
          if orders.any?
            s << "ORDER BY " << orders.join(", ") << "\n"
          end
          s << "LIMIT #{limit}\n" if limit?
        end
        s << "FORMAT #{format}\n"
      end
    end

    def quote_str(v : String)
      char = '\''
      char + v.gsub(char, "#{char}#{char}") + char
    end
  end
end
