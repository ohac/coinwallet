#!/usr/bin/ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'redis'

class ElectrumRPC

  KEY_ADDRESSES = 'ww:electrum:addrs' # TODO with coinid?

  def initialize(service_url)
    @uri = URI.parse(service_url)
    @redis = Redis.new
  end

  def accountid2addr(accountid)
    @redis.hget(KEY_ADDRESSES, accountid)
  end

  def validateaddress(addr)
    { 'isvalid' => rpc_call('validateaddress', addr) }
  end

  def getbalance(accountid = nil, confirms = nil)
    if accountid.nil?
      balance = rpc_call('getbalance')
      balance['confirmed'].to_f
    else
      addr = accountid2addr(accountid)
      return 0 unless addr
      # TODO ignore confirms
      addrs = rpc_call('listaddresses', {'show_balance' => true})
      line = addrs.find{|l|l.index(addr)}
      return 0 unless line
      line.split(', ')[1].to_f # TODO to_f is not accurate
    end
  end

  def getaddressesbyaccount(accountid)
    addr = accountid2addr(accountid)
    addr ? [addr] : []
  end

  def getnewaddress(accountid)
    addr = accountid2addr(accountid)
    return addr if addr
    cands = rpc_call('listaddresses', {'unused' => true})
    funded = rpc_call('listaddresses', {'funded' => true})
    cands -= funded
    used = @redis.hvals(KEY_ADDRESSES)
    cands = cands - used
    addr = cands.first
    return nil unless addr # TODO create new wallet
    @redis.hsetnx(KEY_ADDRESSES, accountid, addr)
    addr
  end

  # withdraw, donate, faucet, coin2iou
  def move(accountid, moveto, amount, confirms = 6)
    raise # TODO
  end

  # withdraw
  def sendfrom(accountid, payoutto, amount, confirms = 6)
    raise # TODO
  end

  def listtransactions(accountid)
    [] # TODO
  end

  def rpc_call(name, *args)
    args = args[0] if args.size == 1 and args[0].class == Hash
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

end

if $0 == __FILE__
  # electrum daemon start
  config = YAML.load_file('config.yml')['coins']['bitcoin']
  rpc = ElectrumRPC.new("http://#{config['host']}:#{config['port']}")

  # test 1
  p rpc.getbalance()

  # test 2
  accountid = 'id:foo@developer'
  addr = rpc.getaddressesbyaccount(accountid).first
  p addr

  # test 3
  addr = rpc.getnewaddress(accountid)

  # test 3
  p rpc.validateaddress(addr)

  # test 4
  p rpc.getbalance(accountid, 1)

end
