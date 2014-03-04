require 'net/http'
require 'uri'
require 'json'
require 'yaml'

class BitcoinRPC
  def initialize(service_url)
    @uri = URI.parse(service_url)
  end

  def method_missing(name, *args)
    post_body = {:method => name,
                 :params => args,
                 :id => 'jsonrpc'}.to_json
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

if $0 == __FILE__
  config = YAML.load_file('config.yml')['bitcoind']
  # bitcoind REPL
  rpc = BitcoinRPC.new("http://#{config['user']}:#{config['password']}@#{config['host']}:#{config['port']}")
  while true
    print '> '
    command = gets.split.map do |arg|
      case arg
      when /^true$/i
        true
      when /^false$/i
        false
      when /^-?\d+$/
        arg.to_i
      when /^-?\d*\.\d+$/
        arg.to_f
      else
        arg
      end
    end
    break if command.empty?
    response = rpc.send(*command)
    if response.is_a? String
      puts response
    else
      puts response.to_yaml
    end
  end
end
