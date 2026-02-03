# frozen_string_literal: true

require "minitest/autorun"
require "json"

module SquirrelDB
  class FieldExpr
    attr_reader :field_name

    def initialize(field_name)
      @field_name = field_name
    end

    def eq(value)
      { field: @field_name, operator: "$eq", value: value }
    end

    def ne(value)
      { field: @field_name, operator: "$ne", value: value }
    end

    def gt(value)
      { field: @field_name, operator: "$gt", value: value }
    end

    def gte(value)
      { field: @field_name, operator: "$gte", value: value }
    end

    def lt(value)
      { field: @field_name, operator: "$lt", value: value }
    end

    def lte(value)
      { field: @field_name, operator: "$lte", value: value }
    end

    def in(values)
      { field: @field_name, operator: "$in", value: values }
    end

    def not_in(values)
      { field: @field_name, operator: "$nin", value: values }
    end

    def contains(value)
      { field: @field_name, operator: "$contains", value: value }
    end

    def starts_with(value)
      { field: @field_name, operator: "$startsWith", value: value }
    end

    def ends_with(value)
      { field: @field_name, operator: "$endsWith", value: value }
    end

    def exists(value = true)
      { field: @field_name, operator: "$exists", value: value }
    end
  end

  def self.field(name)
    FieldExpr.new(name)
  end
end

class TestFieldExpr < Minitest::Test
  def test_eq_creates_equal_condition
    cond = SquirrelDB.field("age").eq(25)
    assert_equal({ field: "age", operator: "$eq", value: 25 }, cond)
  end

  def test_ne_creates_not_equal_condition
    cond = SquirrelDB.field("status").ne("inactive")
    assert_equal({ field: "status", operator: "$ne", value: "inactive" }, cond)
  end

  def test_gt_creates_greater_than_condition
    cond = SquirrelDB.field("price").gt(100)
    assert_equal({ field: "price", operator: "$gt", value: 100 }, cond)
  end

  def test_gte_creates_greater_than_or_equal_condition
    cond = SquirrelDB.field("count").gte(10)
    assert_equal({ field: "count", operator: "$gte", value: 10 }, cond)
  end

  def test_lt_creates_less_than_condition
    cond = SquirrelDB.field("age").lt(18)
    assert_equal({ field: "age", operator: "$lt", value: 18 }, cond)
  end

  def test_lte_creates_less_than_or_equal_condition
    cond = SquirrelDB.field("rating").lte(5)
    assert_equal({ field: "rating", operator: "$lte", value: 5 }, cond)
  end

  def test_in_creates_array_inclusion_condition
    cond = SquirrelDB.field("role").in(["admin", "mod"])
    assert_equal({ field: "role", operator: "$in", value: ["admin", "mod"] }, cond)
  end

  def test_not_in_creates_array_exclusion_condition
    cond = SquirrelDB.field("status").not_in(["banned", "deleted"])
    assert_equal({ field: "status", operator: "$nin", value: ["banned", "deleted"] }, cond)
  end

  def test_contains_creates_substring_condition
    cond = SquirrelDB.field("name").contains("test")
    assert_equal({ field: "name", operator: "$contains", value: "test" }, cond)
  end

  def test_starts_with_creates_prefix_condition
    cond = SquirrelDB.field("email").starts_with("admin")
    assert_equal({ field: "email", operator: "$startsWith", value: "admin" }, cond)
  end

  def test_ends_with_creates_suffix_condition
    cond = SquirrelDB.field("email").ends_with(".com")
    assert_equal({ field: "email", operator: "$endsWith", value: ".com" }, cond)
  end

  def test_exists_creates_existence_condition
    cond = SquirrelDB.field("avatar").exists
    assert_equal({ field: "avatar", operator: "$exists", value: true }, cond)
  end

  def test_exists_false_creates_non_existence_condition
    cond = SquirrelDB.field("deleted_at").exists(false)
    assert_equal({ field: "deleted_at", operator: "$exists", value: false }, cond)
  end
end

class TestStructuredQuery < Minitest::Test
  def test_minimal_query
    query = { table: "users" }
    assert_equal "users", query[:table]
    assert_nil query[:filter]
  end

  def test_query_with_filter
    query = {
      table: "users",
      filter: { "age" => { "$gt" => 21 } }
    }
    assert_equal({ "$gt" => 21 }, query[:filter]["age"])
  end

  def test_query_with_sort
    query = {
      table: "users",
      sort: [{ field: "name", direction: "asc" }]
    }
    assert_equal 1, query[:sort].length
    assert_equal "name", query[:sort][0][:field]
    assert_equal "asc", query[:sort][0][:direction]
  end

  def test_query_with_multiple_sorts
    query = {
      table: "posts",
      sort: [
        { field: "pinned", direction: "desc" },
        { field: "created_at", direction: "desc" }
      ]
    }
    assert_equal 2, query[:sort].length
  end

  def test_query_with_limit
    query = { table: "users", limit: 10 }
    assert_equal 10, query[:limit]
  end

  def test_query_with_skip
    query = { table: "users", skip: 20 }
    assert_equal 20, query[:skip]
  end

  def test_query_with_changes
    query = {
      table: "messages",
      changes: { include_initial: true }
    }
    assert query[:changes][:include_initial]
  end

  def test_full_query
    query = {
      table: "users",
      filter: {
        "age" => { "$gte" => 18 },
        "status" => { "$eq" => "active" }
      },
      sort: [{ field: "name", direction: "asc" }],
      limit: 50,
      skip: 100
    }
    assert_equal "users", query[:table]
    assert_equal 18, query[:filter]["age"]["$gte"]
    assert_equal "active", query[:filter]["status"]["$eq"]
    assert_equal 50, query[:limit]
    assert_equal 100, query[:skip]
  end

  def test_compile_to_json
    query = { table: "users", limit: 10 }
    json = JSON.generate(query)
    parsed = JSON.parse(json)
    assert_equal "users", parsed["table"]
    assert_equal 10, parsed["limit"]
  end
end

class TestLogicalOperators < Minitest::Test
  def and_op(*conditions)
    { field: "$and", operator: "$and", value: conditions }
  end

  def or_op(*conditions)
    { field: "$or", operator: "$or", value: conditions }
  end

  def not_op(condition)
    { field: "$not", operator: "$not", value: condition }
  end

  def test_and_combines_conditions
    cond = and_op(
      SquirrelDB.field("age").gte(18),
      SquirrelDB.field("active").eq(true)
    )
    assert_equal "$and", cond[:field]
    assert_equal "$and", cond[:operator]
    assert_equal 2, cond[:value].length
  end

  def test_or_combines_conditions
    cond = or_op(
      SquirrelDB.field("role").eq("admin"),
      SquirrelDB.field("role").eq("moderator")
    )
    assert_equal "$or", cond[:field]
  end

  def test_not_negates_condition
    cond = not_op(SquirrelDB.field("banned").eq(true))
    assert_equal "$not", cond[:field]
  end
end
