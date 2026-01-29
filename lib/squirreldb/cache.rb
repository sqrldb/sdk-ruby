# frozen_string_literal: true

require "socket"

module SquirrelDB
  # Redis-compatible cache client using RESP protocol over TCP
  class Cache
    CRLF = "\r\n"

    attr_reader :host, :port

    def initialize(host: "localhost", port: 6379)
      @host = host
      @port = port
      @socket = nil
      @mutex = Mutex.new
    end

    # Connect to cache server
    def self.connect(host: "localhost", port: 6379)
      client = new(host: host, port: port)
      client.send(:do_connect)
      client
    end

    # Get a value by key
    def get(key)
      result = command("GET", key)
      result
    end

    # Set a value with optional TTL
    def set(key, value, ttl: nil)
      if ttl
        result = command("SET", key, value.to_s, "EX", ttl.to_s)
      else
        result = command("SET", key, value.to_s)
      end
      result == "OK"
    end

    # Delete a key
    def del(key)
      result = command("DEL", key)
      result.to_i
    end

    # Check if key exists
    def exists(key)
      result = command("EXISTS", key)
      result.to_i > 0
    end

    # Set TTL on existing key
    def expire(key, seconds)
      result = command("EXPIRE", key, seconds.to_s)
      result.to_i == 1
    end

    # Get remaining TTL for key
    def ttl(key)
      result = command("TTL", key)
      result.to_i
    end

    # Remove TTL from key
    def persist(key)
      result = command("PERSIST", key)
      result.to_i == 1
    end

    # Increment key by 1
    def incr(key)
      result = command("INCR", key)
      result.to_i
    end

    # Decrement key by 1
    def decr(key)
      result = command("DECR", key)
      result.to_i
    end

    # Increment key by amount
    def incrby(key, amount)
      result = command("INCRBY", key, amount.to_s)
      result.to_i
    end

    # Get keys matching pattern
    def keys(pattern = "*")
      result = command("KEYS", pattern)
      result.is_a?(Array) ? result : []
    end

    # Get multiple keys
    def mget(*keys)
      keys = keys.flatten
      result = command("MGET", *keys)
      result.is_a?(Array) ? result : []
    end

    # Set multiple key-value pairs
    def mset(pairs)
      args = pairs.flat_map { |k, v| [k.to_s, v.to_s] }
      result = command("MSET", *args)
      result == "OK"
    end

    # Get number of keys in database
    def dbsize
      result = command("DBSIZE")
      result.to_i
    end

    # Flush all keys
    def flush
      result = command("FLUSHDB")
      result == "OK"
    end

    # Get server info
    def info
      result = command("INFO")
      result.to_s
    end

    # Ping server
    def ping
      result = command("PING")
      result == "PONG"
    end

    # Close connection
    def close
      @mutex.synchronize do
        @socket&.close
        @socket = nil
      end
    end

    # Check if connected
    def connected?
      @mutex.synchronize { !@socket.nil? && !@socket.closed? }
    end

    private

    def do_connect
      @mutex.synchronize do
        @socket = TCPSocket.new(@host, @port)
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
    end

    def ensure_connected
      do_connect unless connected?
    end

    def command(*args)
      @mutex.synchronize do
        ensure_connected
        send_command(args)
        read_response
      end
    end

    # RESP protocol encoding
    def send_command(args)
      data = encode_command(args)
      @socket.write(data)
    end

    def encode_command(args)
      result = "*#{args.length}#{CRLF}"
      args.each do |arg|
        str = arg.to_s
        result += "$#{str.bytesize}#{CRLF}#{str}#{CRLF}"
      end
      result
    end

    # RESP protocol decoding
    def read_response
      line = read_line
      return nil if line.nil? || line.empty?

      type = line[0]
      data = line[1..]

      case type
      when "+"
        # Simple string
        data
      when "-"
        # Error
        raise "Redis error: #{data}"
      when ":"
        # Integer
        data.to_i
      when "$"
        # Bulk string
        read_bulk_string(data.to_i)
      when "*"
        # Array
        read_array(data.to_i)
      else
        raise "Unknown RESP type: #{type}"
      end
    end

    def read_line
      line = @socket.gets(CRLF)
      line&.chomp(CRLF)
    end

    def read_bulk_string(length)
      return nil if length == -1

      data = @socket.read(length)
      @socket.read(2) # consume CRLF
      data
    end

    def read_array(length)
      return nil if length == -1

      Array.new(length) { read_response }
    end
  end
end
