# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/squirreldb"

TEST_URL = ENV.fetch("SQUIRRELDB_URL", "localhost:8080")

class TestConnection < Minitest::Test
  def test_connect_without_prefix
    db = SquirrelDB.connect(TEST_URL)
    db.ping
    db.close
  end

  def test_connect_with_ws_prefix
    db = SquirrelDB.connect("ws://#{TEST_URL}")
    db.ping
    db.close
  end

  def test_ping
    db = SquirrelDB.connect(TEST_URL)
    assert_nil db.ping
    db.close
  end
end

class TestCRUD < Minitest::Test
  def setup
    @db = SquirrelDB.connect(TEST_URL)
  end

  def teardown
    @db&.close
  end

  def test_insert_document
    doc = @db.insert("rb_test_users", { name: "Alice", age: 30 })

    assert_instance_of SquirrelDB::Document, doc
    refute_nil doc.id
    assert_equal "rb_test_users", doc.collection
    assert_equal({ "name" => "Alice", "age" => 30 }, doc.data)
    refute_nil doc.created_at
    refute_nil doc.updated_at
  end

  def test_query_documents
    # Insert a document first
    @db.insert("rb_test_query", { name: "Bob", age: 25 })

    docs = @db.query('db.table("rb_test_query").run()')

    assert_instance_of Array, docs
    refute_empty docs
    assert docs.all? { |d| d.is_a?(SquirrelDB::Document) }
  end

  def test_update_document
    inserted = @db.insert("rb_test_update", { name: "Charlie", age: 35 })
    updated = @db.update("rb_test_update", inserted.id, { name: "Charlie", age: 36 })

    assert_equal inserted.id, updated.id
    assert_equal({ "name" => "Charlie", "age" => 36 }, updated.data)
  end

  def test_delete_document
    inserted = @db.insert("rb_test_delete", { name: "Dave", age: 40 })
    deleted = @db.delete("rb_test_delete", inserted.id)

    assert_equal inserted.id, deleted.id
  end

  def test_list_collections
    # Ensure at least one collection exists
    @db.insert("rb_test_list", { test: true })

    collections = @db.list_collections

    assert_instance_of Array, collections
    refute_empty collections
    assert collections.all? { |c| c.is_a?(String) }
  end
end

class TestSubscriptions < Minitest::Test
  def setup
    @db = SquirrelDB.connect(TEST_URL)
  end

  def teardown
    @db&.close
  end

  def test_subscribe_and_unsubscribe
    changes = []

    sub_id = @db.subscribe('db.table("rb_test_sub").changes()') do |change|
      changes << change
    end

    refute_nil sub_id
    assert_instance_of String, sub_id

    # Insert a document to trigger a change
    @db.insert("rb_test_sub", { name: "Eve", age: 28 })

    # Wait for change to arrive
    sleep 0.1

    # Unsubscribe
    @db.unsubscribe(sub_id)

    # Should have received at least one change
    refute_empty changes
    assert changes.all? { |c| c.is_a?(SquirrelDB::ChangeEvent) }
  end
end

class TestErrors < Minitest::Test
  def setup
    @db = SquirrelDB.connect(TEST_URL)
  end

  def teardown
    @db&.close
  end

  def test_invalid_query_raises_exception
    assert_raises(RuntimeError) do
      @db.query("invalid query syntax")
    end
  end
end

class TestTypes < Minitest::Test
  def test_document_from_hash
    data = {
      "id" => "123",
      "collection" => "users",
      "data" => { "name" => "Test" },
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-01T00:00:00Z"
    }
    doc = SquirrelDB::Document.from_hash(data)

    assert_equal "123", doc.id
    assert_equal "users", doc.collection
    assert_equal({ "name" => "Test" }, doc.data)
  end

  def test_change_event_initial
    data = {
      "type" => "initial",
      "document" => {
        "id" => "123",
        "collection" => "users",
        "data" => { "name" => "Test" },
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    }
    event = SquirrelDB::ChangeEvent.from_hash(data)

    assert_equal "initial", event.type
    refute_nil event.document
    assert_equal "123", event.document.id
  end

  def test_change_event_insert
    data = {
      "type" => "insert",
      "new" => {
        "id" => "123",
        "collection" => "users",
        "data" => { "name" => "Test" },
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    }
    event = SquirrelDB::ChangeEvent.from_hash(data)

    assert_equal "insert", event.type
    refute_nil event.new
  end

  def test_change_event_update
    data = {
      "type" => "update",
      "old" => { "name" => "Old" },
      "new" => {
        "id" => "123",
        "collection" => "users",
        "data" => { "name" => "New" },
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    }
    event = SquirrelDB::ChangeEvent.from_hash(data)

    assert_equal "update", event.type
    assert_equal({ "name" => "Old" }, event.old)
    refute_nil event.new
  end

  def test_change_event_delete
    data = {
      "type" => "delete",
      "old" => {
        "id" => "123",
        "collection" => "users",
        "data" => { "name" => "Test" },
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    }
    event = SquirrelDB::ChangeEvent.from_hash(data)

    assert_equal "delete", event.type
    refute_nil event.old
  end
end
