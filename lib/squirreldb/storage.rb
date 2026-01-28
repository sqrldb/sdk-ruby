# frozen_string_literal: true

require "net/http"
require "uri"
require "openssl"
require "base64"
require "time"
require "rexml/document"

module SquirrelDB
  # Object storage client for SquirrelDB
  # S3-compatible API
  class Storage
    Bucket = Struct.new(:name, :created_at, keyword_init: true)
    StorageObject = Struct.new(:key, :size, :etag, :last_modified, :content_type, keyword_init: true)
    MultipartUpload = Struct.new(:upload_id, :bucket, :key, keyword_init: true)
    UploadPart = Struct.new(:part_number, :etag, keyword_init: true)

    attr_reader :endpoint, :region

    def initialize(endpoint:, access_key: nil, secret_key: nil, region: "us-east-1")
      @endpoint = endpoint.chomp("/")
      @access_key = access_key
      @secret_key = secret_key
      @region = region
    end

    # List all buckets
    def list_buckets
      resp = request(:get, "/")
      doc = REXML::Document.new(resp.body)
      buckets = []
      doc.elements.each("//Bucket") do |el|
        buckets << Bucket.new(
          name: el.elements["Name"]&.text,
          created_at: Time.parse(el.elements["CreationDate"]&.text || Time.now.iso8601)
        )
      end
      buckets
    end

    # Create a bucket
    def create_bucket(name)
      request(:put, "/#{name}")
      true
    end

    # Delete a bucket
    def delete_bucket(name)
      request(:delete, "/#{name}")
      true
    end

    # Check if bucket exists
    def bucket_exists?(name)
      request(:head, "/#{name}")
      true
    rescue StandardError
      false
    end

    # List objects in a bucket
    def list_objects(bucket, prefix: nil, max_keys: 1000)
      params = { "max-keys" => max_keys.to_s }
      params["prefix"] = prefix if prefix

      query = params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join("&")
      resp = request(:get, "/#{bucket}?#{query}")

      doc = REXML::Document.new(resp.body)
      objects = []
      doc.elements.each("//Contents") do |el|
        objects << StorageObject.new(
          key: el.elements["Key"]&.text,
          size: el.elements["Size"]&.text&.to_i || 0,
          etag: el.elements["ETag"]&.text&.tr('"', ""),
          last_modified: Time.parse(el.elements["LastModified"]&.text || Time.now.iso8601)
        )
      end
      objects
    end

    # Get object content
    def get_object(bucket, key)
      resp = request(:get, "/#{bucket}/#{key}")
      resp.body
    end

    # Put object
    def put_object(bucket, key, data, content_type: "application/octet-stream")
      resp = request(:put, "/#{bucket}/#{key}", body: data, content_type: content_type)
      resp["etag"]&.tr('"', "") || ""
    end

    # Delete object
    def delete_object(bucket, key)
      request(:delete, "/#{bucket}/#{key}")
      true
    end

    # Copy object
    def copy_object(src_bucket, src_key, dst_bucket, dst_key)
      headers = { "x-amz-copy-source" => "/#{src_bucket}/#{src_key}" }
      resp = request(:put, "/#{dst_bucket}/#{dst_key}", headers: headers)
      resp["etag"]&.tr('"', "") || ""
    end

    # Check if object exists
    def object_exists?(bucket, key)
      request(:head, "/#{bucket}/#{key}")
      true
    rescue StandardError
      false
    end

    # Create multipart upload
    def create_multipart_upload(bucket, key, content_type: "application/octet-stream")
      resp = request(:post, "/#{bucket}/#{key}?uploads", content_type: content_type)
      doc = REXML::Document.new(resp.body)
      upload_id = doc.elements["//UploadId"]&.text
      MultipartUpload.new(upload_id: upload_id, bucket: bucket, key: key)
    end

    # Upload part
    def upload_part(bucket, key, upload_id, part_number, data)
      resp = request(:put, "/#{bucket}/#{key}?partNumber=#{part_number}&uploadId=#{upload_id}", body: data)
      UploadPart.new(part_number: part_number, etag: resp["etag"]&.tr('"', "") || "")
    end

    # Complete multipart upload
    def complete_multipart_upload(bucket, key, upload_id, parts)
      parts_xml = parts.sort_by(&:part_number).map do |p|
        "<Part><PartNumber>#{p.part_number}</PartNumber><ETag>#{p.etag}</ETag></Part>"
      end.join
      body = "<CompleteMultipartUpload>#{parts_xml}</CompleteMultipartUpload>"

      resp = request(:post, "/#{bucket}/#{key}?uploadId=#{upload_id}", body: body, content_type: "application/xml")
      resp["etag"]&.tr('"', "") || ""
    end

    # Abort multipart upload
    def abort_multipart_upload(bucket, key, upload_id)
      request(:delete, "/#{bucket}/#{key}?uploadId=#{upload_id}")
      true
    end

    # Upload large object using multipart
    def upload_large_object(bucket, key, data, part_size: 5 * 1024 * 1024, content_type: "application/octet-stream")
      return put_object(bucket, key, data, content_type: content_type) if data.bytesize <= part_size

      upload = create_multipart_upload(bucket, key, content_type: content_type)
      parts = []

      begin
        part_number = 1
        offset = 0
        while offset < data.bytesize
          chunk = data.byteslice(offset, part_size)
          part = upload_part(bucket, key, upload.upload_id, part_number, chunk)
          parts << part
          part_number += 1
          offset += part_size
        end

        complete_multipart_upload(bucket, key, upload.upload_id, parts)
      rescue StandardError
        abort_multipart_upload(bucket, key, upload.upload_id)
        raise
      end
    end

    private

    def request(method, path, body: nil, headers: {}, content_type: nil)
      uri = URI("#{@endpoint}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      req = case method
            when :get then Net::HTTP::Get.new(uri)
            when :put then Net::HTTP::Put.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            when :delete then Net::HTTP::Delete.new(uri)
            when :head then Net::HTTP::Head.new(uri)
            end

      req.body = body if body
      req["Content-Type"] = content_type if content_type
      headers.each { |k, v| req[k] = v }

      sign_request(req, uri, body) if @access_key && @secret_key

      resp = http.request(req)
      raise "HTTP #{resp.code}: #{resp.body}" unless resp.is_a?(Net::HTTPSuccess) || resp.is_a?(Net::HTTPNoContent)

      resp
    end

    def sign_request(req, uri, body)
      now = Time.now.utc
      date_stamp = now.strftime("%Y%m%d")
      amz_date = now.strftime("%Y%m%dT%H%M%SZ")

      payload_hash = body ? OpenSSL::Digest::SHA256.hexdigest(body) : "UNSIGNED-PAYLOAD"

      req["x-amz-date"] = amz_date
      req["x-amz-content-sha256"] = payload_hash
      req["Host"] = uri.host

      signed_headers = req.to_hash.keys.select { |h| h.start_with?("x-amz") || h == "host" || h == "content-type" }
      signed_headers.sort!
      signed_headers_str = signed_headers.join(";")

      canonical_headers = signed_headers.map { |h| "#{h}:#{req[h]}\n" }.join
      canonical_request = [
        req.method,
        uri.path.empty? ? "/" : uri.path,
        uri.query || "",
        canonical_headers,
        signed_headers_str,
        payload_hash
      ].join("\n")

      algorithm = "AWS4-HMAC-SHA256"
      credential_scope = "#{date_stamp}/#{@region}/s3/aws4_request"
      string_to_sign = [
        algorithm,
        amz_date,
        credential_scope,
        OpenSSL::Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      k_date = hmac_sha256("AWS4#{@secret_key}", date_stamp)
      k_region = hmac_sha256(k_date, @region)
      k_service = hmac_sha256(k_region, "s3")
      k_signing = hmac_sha256(k_service, "aws4_request")
      signature = OpenSSL::HMAC.hexdigest("SHA256", k_signing, string_to_sign)

      req["Authorization"] = "#{algorithm} Credential=#{@access_key}/#{credential_scope}, SignedHeaders=#{signed_headers_str}, Signature=#{signature}"
    end

    def hmac_sha256(key, data)
      OpenSSL::HMAC.digest("SHA256", key, data)
    end
  end
end
