# frozen_string_literal: true

require "json"
require "securerandom"
require "websocket-client-simple"
require "thread"

module SquirrelDB
  VERSION = "0.0.1"

  # Document stored in SquirrelDB
  Document = Struct.new(:id, :collection, :data, :created_at, :updated_at, keyword_init: true) do
    def self.from_hash(h)
      new(
        id: h["id"],
        collection: h["collection"],
        data: h["data"],
        created_at: h["created_at"],
        updated_at: h["updated_at"]
      )
    end
  end

  # Change event from subscription
  ChangeEvent = Struct.new(:type, :document, :new, :old, keyword_init: true) do
    def self.from_hash(h)
      case h["type"]
      when "initial"
        new(type: "initial", document: Document.from_hash(h["document"]))
      when "insert"
        new(type: "insert", new: Document.from_hash(h["new"]))
      when "update"
        new(type: "update", old: h["old"], new: Document.from_hash(h["new"]))
      when "delete"
        new(type: "delete", old: Document.from_hash(h["old"]))
      else
        new(type: h["type"])
      end
    end
  end

  # Client for connecting to SquirrelDB
  class Client
    def initialize(url, reconnect: true, max_reconnect_attempts: 10, reconnect_delay: 1.0)
      @url = url.start_with?("ws://", "wss://") ? url : "ws://#{url}"
      @reconnect = reconnect
      @max_reconnect_attempts = max_reconnect_attempts
      @reconnect_delay = reconnect_delay
      @pending = {}
      @subscriptions = {}
      @mutex = Mutex.new
      @closed = false
      @reconnect_attempts = 0
    end

    def self.connect(url, **options)
      client = new(url, **options)
      client.send(:do_connect)
      client
    end

    def query(q)
      resp = send_message({ type: "query", id: generate_id, query: q })
      raise resp["error"] if resp["type"] == "error"
      resp["data"].map { |d| Document.from_hash(d) }
    end

    def subscribe(q, &callback)
      sub_id = generate_id
      resp = send_message({ type: "subscribe", id: sub_id, query: q })
      raise resp["error"] if resp["type"] == "error"
      @mutex.synchronize { @subscriptions[sub_id] = callback }
      sub_id
    end

    def unsubscribe(subscription_id)
      send_message({ type: "unsubscribe", id: subscription_id })
      @mutex.synchronize { @subscriptions.delete(subscription_id) }
      nil
    end

    def insert(collection, data)
      resp = send_message({
        type: "insert",
        id: generate_id,
        collection: collection,
        data: data
      })
      raise resp["error"] if resp["type"] == "error"
      Document.from_hash(resp["data"])
    end

    def update(collection, document_id, data)
      resp = send_message({
        type: "update",
        id: generate_id,
        collection: collection,
        document_id: document_id,
        data: data
      })
      raise resp["error"] if resp["type"] == "error"
      Document.from_hash(resp["data"])
    end

    def delete(collection, document_id)
      resp = send_message({
        type: "delete",
        id: generate_id,
        collection: collection,
        document_id: document_id
      })
      raise resp["error"] if resp["type"] == "error"
      Document.from_hash(resp["data"])
    end

    def list_collections
      resp = send_message({ type: "listcollections", id: generate_id })
      raise resp["error"] if resp["type"] == "error"
      resp["data"]
    end

    def ping
      resp = send_message({ type: "ping", id: generate_id })
      raise "Unexpected response" unless resp["type"] == "pong"
      nil
    end

    def close
      @closed = true
      @mutex.synchronize { @subscriptions.clear }
      @ws&.close
    end

    private

    def do_connect
      @ws = WebSocket::Client::Simple.connect(@url)
      client = self

      @ws.on :message do |msg|
        client.send(:handle_message, msg.data)
      end

      @ws.on :close do
        client.send(:handle_disconnect)
      end

      @ws.on :error do |e|
        # Handle error silently
      end

      # Wait for connection
      sleep 0.1 until @ws.open?
      @reconnect_attempts = 0
    end

    def handle_message(data)
      msg = JSON.parse(data)
      msg_type = msg["type"]
      msg_id = msg["id"]

      if msg_type == "change"
        callback = @mutex.synchronize { @subscriptions[msg_id] }
        callback&.call(ChangeEvent.from_hash(msg["change"]))
        return
      end

      queue = @mutex.synchronize { @pending.delete(msg_id) }
      queue&.push(msg)
    rescue JSON::ParserError
      # Ignore malformed messages
    end

    def handle_disconnect
      return if @closed

      # Reject pending requests
      @mutex.synchronize do
        @pending.each_value { |q| q.push({ "type" => "error", "error" => "Connection closed" }) }
        @pending.clear
      end

      # Attempt reconnection
      if @reconnect && @reconnect_attempts < @max_reconnect_attempts
        @reconnect_attempts += 1
        delay = @reconnect_delay * (2 ** (@reconnect_attempts - 1))
        sleep delay
        do_connect rescue nil
      end
    end

    def send_message(msg)
      raise "Not connected" unless @ws&.open?

      queue = Queue.new
      @mutex.synchronize { @pending[msg[:id]] = queue }

      @ws.send(msg.to_json)
      queue.pop
    end

    def generate_id
      SecureRandom.uuid
    end
  end

  def self.connect(url, **options)
    Client.connect(url, **options)
  end
end
