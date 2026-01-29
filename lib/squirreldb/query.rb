# frozen_string_literal: true

module SquirrelDB
  # Query builder for SquirrelDB
  # Uses MongoDB-like naming: find/sort/limit
  #
  # @example
  #   query = SquirrelDB.table("users")
  #     .find { |doc| doc.age.gt(21) }
  #     .sort("name")
  #     .limit(10)
  #     .compile
  module Query
    # Field expression for building filters
    class Field
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def eq(value)
        { path => { op: :eq, value: value } }
      end

      def ne(value)
        { path => { op: :ne, value: value } }
      end

      def gt(value)
        { path => { op: :gt, value: value } }
      end

      def gte(value)
        { path => { op: :gte, value: value } }
      end

      def lt(value)
        { path => { op: :lt, value: value } }
      end

      def lte(value)
        { path => { op: :lte, value: value } }
      end

      def in(*values)
        { path => { op: :in, value: values.flatten } }
      end

      def not_in(*values)
        { path => { op: :not_in, value: values.flatten } }
      end

      def contains(value)
        { path => { op: :contains, value: value } }
      end

      def starts_with(value)
        { path => { op: :starts_with, value: value } }
      end

      def ends_with(value)
        { path => { op: :ends_with, value: value } }
      end

      def exists(value = true)
        { path => { op: :exists, value: value } }
      end

      # Allow nested field access: doc.user.profile.name
      def method_missing(name, *args)
        if args.empty?
          Field.new("#{path}.#{name}")
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        true
      end
    end

    # Document proxy for filter blocks
    class DocProxy
      def method_missing(name, *args)
        Field.new(name.to_s)
      end

      def respond_to_missing?(name, include_private = false)
        true
      end
    end

    # Compile filter to JS
    def self.compile_filter(condition)
      parts = []

      condition.each do |field, value|
        case field.to_s
        when "$and"
          sub = value.map { |c| compile_filter(c) }
          parts << "(#{sub.join(' && ')})"
        when "$or"
          sub = value.map { |c| compile_filter(c) }
          parts << "(#{sub.join(' || ')})"
        when "$not"
          parts << "!(#{compile_filter(value)})"
        else
          if value.is_a?(Hash) && value[:op]
            parts << compile_op(field, value[:op], value[:value])
          else
            parts << "doc.#{field} === #{value.to_json}"
          end
        end
      end

      parts.empty? ? "true" : parts.join(" && ")
    end

    def self.compile_op(field, op, value)
      case op
      when :eq then "doc.#{field} === #{value.to_json}"
      when :ne then "doc.#{field} !== #{value.to_json}"
      when :gt then "doc.#{field} > #{value}"
      when :gte then "doc.#{field} >= #{value}"
      when :lt then "doc.#{field} < #{value}"
      when :lte then "doc.#{field} <= #{value}"
      when :in then "#{value.to_json}.includes(doc.#{field})"
      when :not_in then "!#{value.to_json}.includes(doc.#{field})"
      when :contains then "doc.#{field}.includes(#{value.to_json})"
      when :starts_with then "doc.#{field}.startsWith(#{value.to_json})"
      when :ends_with then "doc.#{field}.endsWith(#{value.to_json})"
      when :exists then value ? "doc.#{field} !== undefined" : "doc.#{field} === undefined"
      else "true"
      end
    end

    # Convert filter to structured format (public for SubscriptionBuilder)
    def self.filter_to_structured(condition)
      result = {}

      condition.each do |field, value|
        case field.to_s
        when "$and"
          result["$and"] = value.map { |c| filter_to_structured(c) }
        when "$or"
          result["$or"] = value.map { |c| filter_to_structured(c) }
        when "$not"
          result["$not"] = filter_to_structured(value)
        else
          if value.is_a?(Hash) && value[:op]
            result[field.to_s] = op_to_structured(value[:op], value[:value])
          else
            result[field.to_s] = { "$eq" => value }
          end
        end
      end

      result
    end

    def self.op_to_structured(op, value)
      case op
      when :eq then { "$eq" => value }
      when :ne then { "$ne" => value }
      when :gt then { "$gt" => value }
      when :gte then { "$gte" => value }
      when :lt then { "$lt" => value }
      when :lte then { "$lte" => value }
      when :in then { "$in" => value }
      when :not_in then { "$nin" => value }
      when :contains then { "$contains" => value }
      when :starts_with then { "$startsWith" => value }
      when :ends_with then { "$endsWith" => value }
      when :exists then { "$exists" => value }
      else { "$eq" => value }
      end
    end

    # Query builder
    class Builder
      def initialize(table_name)
        @table_name = table_name
        @filter_expr = nil
        @filter_condition = nil
        @sort_specs = []
        @limit_value = nil
        @skip_value = nil
        @is_changes = false
      end

      # Find documents matching condition
      # @yield [doc] Block with DocProxy for building conditions
      # @param condition [Hash] Direct condition hash
      def find(condition = nil, &block)
        if block_given?
          condition = block.call(DocProxy.new)
        end
        if condition
          @filter_condition = condition
          @filter_expr = Query.compile_filter(condition)
        end
        self
      end

      # Sort by field
      def sort(field, direction = :asc)
        @sort_specs << { field: field.to_s, direction: direction }
        self
      end

      # Limit results
      def limit(n)
        @limit_value = n
        self
      end

      # Skip results (offset)
      def skip(n)
        @skip_value = n
        self
      end

      # Subscribe to changes
      def changes
        @is_changes = true
        self
      end

      # Compile to SquirrelDB JS query (legacy)
      def compile
        query = %Q{db.table("#{@table_name}")}

        query += ".filter(doc => #{@filter_expr})" if @filter_expr

        @sort_specs.each do |spec|
          if spec[:direction] == :desc
            query += %Q{.orderBy("#{spec[:field]}", "desc")}
          else
            query += %Q{.orderBy("#{spec[:field]}")}
          end
        end

        query += ".limit(#{@limit_value})" if @limit_value
        query += ".skip(#{@skip_value})" if @skip_value

        if @is_changes
          query += ".changes()"
        else
          query += ".run()"
        end

        query
      end

      # Compile to structured query object (preferred, no JS evaluation on server)
      def compile_structured
        query = { "table" => @table_name }

        query["filter"] = Query.filter_to_structured(@filter_condition) if @filter_condition

        unless @sort_specs.empty?
          query["sort"] = @sort_specs.map do |spec|
            { "field" => spec[:field], "direction" => spec[:direction].to_s }
          end
        end

        query["limit"] = @limit_value if @limit_value
        query["skip"] = @skip_value if @skip_value

        query["changes"] = { "includeInitial" => false } if @is_changes

        query
      end

      def to_s
        compile
      end
    end
  end

  # Create a table query builder
  def self.table(name)
    Query::Builder.new(name)
  end

  # Create a field expression
  def self.field(name)
    Query::Field.new(name.to_s)
  end

  # Combine conditions with AND
  def self.and(*conditions)
    { "$and" => conditions }
  end

  # Combine conditions with OR
  def self.or(*conditions)
    { "$or" => conditions }
  end

  # Negate a condition
  def self.not(condition)
    { "$not" => condition }
  end
end
