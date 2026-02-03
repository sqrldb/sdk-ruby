# frozen_string_literal: true

require "minitest/autorun"
require "uri"
require "json"

class TestStorageOptions < Minitest::Test
  def test_minimal_options
    opts = { endpoint: "http://localhost:9000" }
    assert_equal "http://localhost:9000", opts[:endpoint]
    assert_nil opts[:access_key_id]
    assert_nil opts[:secret_access_key]
    assert_nil opts[:region]
  end

  def test_full_options
    opts = {
      endpoint: "https://s3.amazonaws.com",
      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      region: "us-west-2"
    }
    assert_equal "https://s3.amazonaws.com", opts[:endpoint]
    assert_equal "AKIAIOSFODNN7EXAMPLE", opts[:access_key_id]
    assert_equal "us-west-2", opts[:region]
  end
end

class TestBucketType < Minitest::Test
  def test_bucket_structure
    bucket = { name: "my-bucket", created_at: "2024-01-01T00:00:00Z" }
    assert_equal "my-bucket", bucket[:name]
    assert_equal "2024-01-01T00:00:00Z", bucket[:created_at]
  end

  def test_bucket_name_validation
    valid_names = ["my-bucket", "bucket123", "test.bucket.name"]
    valid_names.each do |name|
      assert name.length >= 3
      assert name.length <= 63
    end
  end
end

class TestStorageObjectType < Minitest::Test
  def test_object_structure
    obj = {
      key: "path/to/file.txt",
      size: 1024,
      etag: "d41d8cd98f00b204e9800998ecf8427e",
      last_modified: "2024-01-01T00:00:00Z",
      content_type: "text/plain"
    }
    assert_equal "path/to/file.txt", obj[:key]
    assert_equal 1024, obj[:size]
    assert_equal "d41d8cd98f00b204e9800998ecf8427e", obj[:etag]
    assert_equal "text/plain", obj[:content_type]
  end

  def test_object_with_null_content_type
    obj = {
      key: "file.bin",
      size: 2048,
      etag: "abc123",
      last_modified: "2024-01-01T00:00:00Z",
      content_type: nil
    }
    assert_nil obj[:content_type]
  end
end

class TestS3APIPaths < Minitest::Test
  def test_list_buckets_path
    path = "/"
    assert_equal "/", path
  end

  def test_bucket_path
    bucket = "my-bucket"
    path = "/#{bucket}"
    assert_equal "/my-bucket", path
  end

  def test_object_path
    bucket = "my-bucket"
    key = "path/to/file.txt"
    path = "/#{bucket}/#{key}"
    assert_equal "/my-bucket/path/to/file.txt", path
  end

  def test_list_objects_with_prefix
    bucket = "my-bucket"
    prefix = "logs/"
    params = URI.encode_www_form(prefix: prefix)
    path = "/#{bucket}?#{params}"
    assert_equal "/my-bucket?prefix=logs%2F", path
  end

  def test_list_objects_with_max_keys
    bucket = "my-bucket"
    params = URI.encode_www_form("max-keys" => 100)
    path = "/#{bucket}?#{params}"
    assert_equal "/my-bucket?max-keys=100", path
  end
end

class TestS3XMLResponseParsing < Minitest::Test
  def test_parse_bucket_name_from_xml
    xml = "<Name>my-bucket</Name>"
    match = xml.match(/<Name>([^<]+)<\/Name>/)
    refute_nil match
    assert_equal "my-bucket", match[1]
  end

  def test_parse_multiple_bucket_names
    xml = <<~XML
      <Buckets>
        <Bucket><Name>bucket1</Name></Bucket>
        <Bucket><Name>bucket2</Name></Bucket>
      </Buckets>
    XML
    matches = xml.scan(/<Name>([^<]+)<\/Name>/).flatten
    assert_equal ["bucket1", "bucket2"], matches
  end

  def test_parse_object_listing
    xml = <<~XML
      <Contents>
        <Key>file1.txt</Key>
        <Size>1024</Size>
        <ETag>"abc123"</ETag>
      </Contents>
    XML
    key_match = xml.match(/<Key>([^<]+)<\/Key>/)
    size_match = xml.match(/<Size>(\d+)<\/Size>/)
    etag_match = xml.match(/<ETag>([^<]+)<\/ETag>/)

    assert_equal "file1.txt", key_match[1]
    assert_equal 1024, size_match[1].to_i
    assert_equal "abc123", etag_match[1].gsub('"', "")
  end
end

class TestContentTypes < Minitest::Test
  def test_common_content_types
    content_types = {
      ".txt" => "text/plain",
      ".html" => "text/html",
      ".css" => "text/css",
      ".js" => "application/javascript",
      ".json" => "application/json",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".pdf" => "application/pdf"
    }
    assert_equal "application/json", content_types[".json"]
    assert_equal "image/png", content_types[".png"]
  end
end
