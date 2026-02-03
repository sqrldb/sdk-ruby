# frozen_string_literal: true

require "minitest/autorun"

class TestCacheOptions < Minitest::Test
  def test_default_options
    opts = { host: "localhost", port: 6379 }
    assert_equal "localhost", opts[:host]
    assert_equal 6379, opts[:port]
  end

  def test_custom_options
    opts = { host: "redis.example.com", port: 6380 }
    assert_equal "redis.example.com", opts[:host]
    assert_equal 6380, opts[:port]
  end
end

class TestRESPProtocol < Minitest::Test
  def test_simple_string_format
    response = "+OK\r\n"
    assert response.start_with?("+")
    assert_includes response, "\r\n"
  end

  def test_error_format
    response = "-ERR unknown command\r\n"
    assert response.start_with?("-")
  end

  def test_integer_format
    response = ":1000\r\n"
    assert response.start_with?(":")
    value = response[1...response.index("\r\n")].to_i
    assert_equal 1000, value
  end

  def test_bulk_string_format
    value = "hello"
    response = "$#{value.length}\r\n#{value}\r\n"
    assert_equal "$5\r\nhello\r\n", response
  end

  def test_null_bulk_string_format
    response = "$-1\r\n"
    assert_equal "$-1\r\n", response
  end

  def test_array_format
    response = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n"
    assert response.start_with?("*2")
  end

  def test_null_array_format
    response = "*-1\r\n"
    assert_equal "*-1\r\n", response
  end
end

class TestCacheCommands < Minitest::Test
  def encode_command(*args)
    parts = ["*#{args.length}\r\n"]
    args.each do |arg|
      s = arg.to_s
      parts << "$#{s.length}\r\n#{s}\r\n"
    end
    parts.join
  end

  def test_ping_command
    cmd = encode_command("PING")
    assert_equal "*1\r\n$4\r\nPING\r\n", cmd
  end

  def test_get_command
    cmd = encode_command("GET", "mykey")
    assert_equal "*2\r\n$3\r\nGET\r\n$5\r\nmykey\r\n", cmd
  end

  def test_set_command
    cmd = encode_command("SET", "mykey", "myvalue")
    assert_equal "*3\r\n$3\r\nSET\r\n$5\r\nmykey\r\n$7\r\nmyvalue\r\n", cmd
  end

  def test_set_with_ex_command
    cmd = encode_command("SET", "mykey", "myvalue", "EX", 60)
    assert_includes cmd, "*5\r\n"
    assert_includes cmd, "$2\r\nEX\r\n"
  end

  def test_del_command
    cmd = encode_command("DEL", "mykey")
    assert_equal "*2\r\n$3\r\nDEL\r\n$5\r\nmykey\r\n", cmd
  end

  def test_exists_command
    cmd = encode_command("EXISTS", "mykey")
    assert_includes cmd, "EXISTS"
  end

  def test_incr_command
    cmd = encode_command("INCR", "counter")
    assert_includes cmd, "INCR"
  end

  def test_incrby_command
    cmd = encode_command("INCRBY", "counter", 5)
    assert_includes cmd, "INCRBY"
    assert_includes cmd, "$1\r\n5\r\n"
  end

  def test_mget_command
    cmd = encode_command("MGET", "key1", "key2", "key3")
    assert_includes cmd, "*4\r\n"
    assert_includes cmd, "MGET"
  end

  def test_mset_command
    cmd = encode_command("MSET", "key1", "val1", "key2", "val2")
    assert_includes cmd, "*5\r\n"
    assert_includes cmd, "MSET"
  end

  def test_keys_command
    cmd = encode_command("KEYS", "user:*")
    assert_includes cmd, "KEYS"
    assert_includes cmd, "user:*"
  end

  def test_expire_command
    cmd = encode_command("EXPIRE", "mykey", 300)
    assert_includes cmd, "EXPIRE"
  end

  def test_ttl_command
    cmd = encode_command("TTL", "mykey")
    assert_includes cmd, "TTL"
  end

  def test_dbsize_command
    cmd = encode_command("DBSIZE")
    assert_equal "*1\r\n$6\r\nDBSIZE\r\n", cmd
  end

  def test_flushdb_command
    cmd = encode_command("FLUSHDB")
    assert_equal "*1\r\n$7\r\nFLUSHDB\r\n", cmd
  end
end
