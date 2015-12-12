#!/usr/bin/ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'redis'

class ElectrumRPC

  KEY_ADDRESSES = 'ww:electrum:addrs:'

  def initialize(service_url, coinid)
    @uri = URI.parse(service_url)
    @redis = Redis.new
    @dbkey = KEY_ADDRESSES + coinid
    @coinid = coinid
  end

  def accountid2addr(accountid)
    @redis.hget(@dbkey, accountid)
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
    getbalance() # check online
    addr = accountid2addr(accountid)
    addr ? [addr] : []
  end

  def getnewaddress(accountid)
    addr = accountid2addr(accountid)
    return addr if addr
    cands = rpc_call('listaddresses', {'unused' => true})
    funded = rpc_call('listaddresses', {'funded' => true})
    cands -= funded
    used = @redis.hvals(@dbkey)
    cands = cands - used
    addr = cands.first
    return nil unless addr
    # Please create new wallet manually.
    # http://docs.electrum.org/en/latest/faq.html#how-can-i-pre-generate-new-addresses
    @redis.hsetnx(@dbkey, accountid, addr)
    addr
  end

  # withdraw, donate, faucet, coin2iou
  def move(accountid, moveto, amount, confirms = 6)
    raise # TODO
  end

  # withdraw
  def sendfrom(accountid, payoutto, amount, confirms = 6)
    # ignore confirms
    addr = accountid2addr(accountid)
    txfee = @coinid == 'bitcoin' ? 0.0001 : 0.001 # TODO
    result = payto(payoutto, amount, txfee, addr)
    raise unless result['complete']
    hex = result['hex']
    txid = broadcast(hex)
    txid
  end

  def payto(toaddr, amount, txfee = 0.001, fromaddr = nil, changeaddr = nil)
    changeaddr ||= fromaddr
    rpc_call('payto', {
        'destination' => toaddr,
        'amount' => amount,
        'tx_fee' => txfee,
        'from_addr' => fromaddr,
        'change_addr' => changeaddr})
  end

  def paytomany(outputs, txfee = 0.001, fromaddr = nil, changeaddr = nil)
    changeaddr ||= fromaddr
    rpc_call('paytomany', {
        'outputs' => outputs,
        'tx_fee' => txfee,
        'from_addr' => fromaddr,
        'change_addr' => changeaddr})
  end

  def broadcast(hex)
    rpc_call('broadcast', { 'tx' => hex })
  end

  def history()
    rpc_call('history', {})
  end

  def getaddresshistory(addr)
    rpc_call('getaddresshistory', {'address' => addr})
  end

  def listtransactions(accountid = nil)
    hist = history()
    txs = hist.map do |item|
      timestamp = item['timestamp'] || 0
      value = item['value']
      {
        'account' => 'unknown',
        'address' => 'unknown',
        'category' => value > 0 ? 'receive' : 'send',
        'amount' => value.abs,
        'confirmations' => item['confirmations'],
        'blockhash' => 'unknown', # TODO
        'blockindex' => -1,
        'blocktime' => timestamp,
        'txid' => item['txid'],
        'time' => timestamp,
        'timereceived' => timestamp
      }
    end
    if accountid
      addr = accountid2addr(accountid)
      hist2 = getaddresshistory(addr)
      hist3 = {}
      hist2.each do |item|
        hist3[item['tx_hash']] = item['height']
      end
      txids = hist3.keys
      txs = txs.select do |item|
        txids.include?(item['txid'])
      end
      txs.each do |tx|
        tx['account'] = accountid
        tx['address'] = addr
        tx['category'] = 'send/receive' # TODO
        tx['amount'] = Float::NAN # TODO
      end
    end
    txs
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

  class JSONRPCError < RuntimeError; end
end

if $0 == __FILE__
  # electrum daemon start
  #coinid = 'bitcoin'
  coinid = 'litecoin'
  config = YAML.load_file('config.yml')['coins'][coinid]
  rpc = ElectrumRPC.new("http://#{config['host']}:#{config['port']}", coinid)

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

  # test 5
  payto_test = false
  if payto_test
    fromaddr = 'L...'
    toaddr1 = 'L...'
    toaddr2 = 'L...'
    outputs = [[toaddr1, 0.01], [toaddr2, 0.01]]
    #result = rpc.payto(toaddr1, 0.01, 0.001, fromaddr)
    result = rpc.paytomany(outputs, 0.001, fromaddr)
    p result
    if result['complete']
      hex = result['hex']
      p hex
      txid = rpc.broadcast(hex)
      p txid
    end
  end

  # test 6
  p rpc.history()

  # test 7
  addr = nil # 'L...'
  if addr
    p rpc.getaddresshistory(addr)
  end

  # test 8
  p rpc.listtransactions()
  p rpc.listtransactions(accountid)

end
