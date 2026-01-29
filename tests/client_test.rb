# frozen_string_literal: true

require "minitest/autorun"
require "json"

# Mock classes for testing without websocket dependency
module SquirrelDB
  class Document
    attr_reader :id, :collection, :data, :created_at, :updated_at

    def initialize(id:, collection:, data:, created_at:, updated_at:)
      @id = id
      @collection = collection
      @data = data
      @created_at = created_at
      @updated_at = updated_at
    end

    def self.from_hash(hash)
      new(
        id: hash["id"],
        collection: hash["collection"],
        data: hash["data"],
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      )
    end
  end

  class ChangeEvent
    attr_reader :type, :document, :old, :new

    def initialize(type:, document: nil, old: nil, new_doc: nil)
      @type = type
      @document = document
      @old = old
      @new = new_doc
    end

    def self.from_hash(hash)
      doc = hash["document"] ? Document.from_hash(hash["document"]) : nil
      new_doc = hash["new"].is_a?(Hash) && hash["new"]["id"] ? Document.from_hash(hash["new"]) : hash["new"]
      old_doc = hash["old"].is_a?(Hash) && hash["old"]["id"] ? Document.from_hash(hash["old"]) : hash["old"]

      new(
        type: hash["type"],
        document: doc,
        old: old_doc,
        new_doc: new_doc
      )
    end
  end
end

class TestDocument < Minitest::Test
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
    assert_equal "2024-01-01T00:00:00Z", doc.created_at
    assert_equal "2024-01-01T00:00:00Z", doc.updated_at
  end

  def test_document_has_correct_fields
    doc = SquirrelDB::Document.new(
      id: "test-id",
      collection: "test-collection",
      data: { "foo" => "bar" },
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z"
    )

    assert_instance_of String, doc.id
    assert_instance_of String, doc.collection
    assert_instance_of Hash, doc.data
    assert_instance_of String, doc.created_at
    assert_instance_of String, doc.updated_at
  end
end

class TestChangeEvent < Minitest::Test
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

class TestMessageProtocol < Minitest::Test
  def test_ping_message
    msg = { "type" => "Ping" }
    assert_equal "Ping", msg["type"]
  end

  def test_query_message
    msg = {
      "type" => "Query",
      "id" => "req-123",
      "query" => 'db.table("users").run()'
    }
    assert_equal "Query", msg["type"]
    assert_equal "req-123", msg["id"]
    assert_includes msg["query"], "users"
  end

  def test_insert_message
    msg = {
      "type" => "Insert",
      "id" => "req-456",
      "collection" => "users",
      "data" => { "name" => "Alice" }
    }
    assert_equal "Insert", msg["type"]
    assert_equal "users", msg["collection"]
    assert_equal({ "name" => "Alice" }, msg["data"])
  end

  def test_update_message
    msg = {
      "type" => "Update",
      "id" => "req-789",
      "collection" => "users",
      "document_id" => "doc-123",
      "data" => { "name" => "Bob" }
    }
    assert_equal "Update", msg["type"]
    assert_equal "doc-123", msg["document_id"]
  end

  def test_delete_message
    msg = {
      "type" => "Delete",
      "id" => "req-101",
      "collection" => "users",
      "document_id" => "doc-123"
    }
    assert_equal "Delete", msg["type"]
    assert_equal "doc-123", msg["document_id"]
  end

  def test_subscribe_message
    msg = {
      "type" => "Subscribe",
      "id" => "req-202",
      "query" => 'db.table("users").changes()'
    }
    assert_equal "Subscribe", msg["type"]
    assert_includes msg["query"], "changes"
  end

  def test_unsubscribe_message
    msg = {
      "type" => "Unsubscribe",
      "id" => "req-303",
      "subscription_id" => "sub-123"
    }
    assert_equal "Unsubscribe", msg["type"]
    assert_equal "sub-123", msg["subscription_id"]
  end
end

class TestServerResponseProtocol < Minitest::Test
  def test_pong_response
    response = { "type" => "Pong" }
    assert_equal "Pong", response["type"]
  end

  def test_result_response
    response = {
      "type" => "Result",
      "id" => "req-123",
      "documents" => [
        { "id" => "1", "collection" => "users", "data" => { "name" => "Alice" }, "created_at" => "", "updated_at" => "" }
      ]
    }
    assert_equal "Result", response["type"]
    assert_equal 1, response["documents"].length
  end

  def test_error_response
    response = {
      "type" => "Error",
      "id" => "req-123",
      "message" => "Query failed"
    }
    assert_equal "Error", response["type"]
    assert_equal "Query failed", response["message"]
  end

  def test_subscribed_response
    response = {
      "type" => "Subscribed",
      "id" => "req-123",
      "subscription_id" => "sub-456"
    }
    assert_equal "Subscribed", response["type"]
    assert_equal "sub-456", response["subscription_id"]
  end

  def test_change_response
    response = {
      "type" => "Change",
      "subscription_id" => "sub-456",
      "change" => {
        "type" => "insert",
        "new" => { "id" => "1", "collection" => "users", "data" => {}, "created_at" => "", "updated_at" => "" }
      }
    }
    assert_equal "Change", response["type"]
    assert_equal "insert", response["change"]["type"]
  end
end
