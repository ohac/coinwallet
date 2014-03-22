require 'net/http'
require 'uri'
require 'json'
require 'yaml'

class RippleRPC
  def initialize(service_url, account_id, masterseed)
    @uri = URI.parse(service_url)
    @account_id = account_id
    @masterseed = masterseed
  end

  def account_id
    @account_id
  end

  def masterseed
    @masterseed
  end

  def method_missing(name, *args)
    post_body = {:method => name, :params => args} .to_json
    begin
      raw = http_post_request(post_body)
      resp = JSON.parse(raw)
    rescue JSON::ParserError
      raise JSONRPCError, "Invalid JSON: \"#{raw}\""
    end
    raise JSONRPCError, resp['error']['message'] if resp['error']
    resp['result']
  end

  def http_post_request(post_body)
    http = Net::HTTP.new(@uri.host, @uri.port)
    request = Net::HTTP::Post.new(@uri.request_uri)
    request.basic_auth @uri.user, @uri.password
    request.content_type = 'application/json'
    request.body = post_body
    http.request(request).body
  end

  class JSONRPCError < RuntimeError; end
end
