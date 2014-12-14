#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'redis'
require 'ripple_rpc'
require 'bitcoin_rpc'
require 'proxycoin_rpc'
require 'digest/md5'

file = File.new("polling.log", 'a+')
STDOUT.reopen(file)
file.sync = true

@@config = YAML.load_file('config.yml')

class Redis
  def setm(k, o)
    set(k, Marshal.dump(o))
  end
  def getm(k)
    m = get(k)
    m ? Marshal.load(m) : nil
  end
end

@@redis = Redis.new

def getrpc(coinname)
  d = @@config['coins'][coinname]
  uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
  btcrpc = BitcoinRPC.new(uri)
  d['proxycoind'] ? ProxycoinRPC.new(btcrpc, coinname) : btcrpc
end

def getripplerpc
  d = @@config['ripple']
  account_id = d['account_id']
  master_seed = d['master_seed']
  uri = "http://#{d['host']}:#{d['port']}"
  RippleRPC.new(uri, account_id, master_seed)
end

def poll(rrpc, interval, min)
  max = -1
  limit = 200
  params = {
    'account' => rrpc.account_id,
    'ledger_index_min' => min,
    'ledger_index_max' => max,
    'limit' => limit,
  }
  result = nil
  loop do
    begin
      result = rrpc.account_tx(params)
p result['status']
      break if result['status'] == 'success'
    rescue => x
p [:errora, x]
    rescue Timeout::Error => x
p [:errore, x]
    end
p :sleep
    sleep 3
  end
  lmin = result['ledger_index_min']
  lmax = result['ledger_index_max']
p [lmin, lmax]
  @@redis.set('polling:ledger_max', lmax)
  txs = result['transactions']
  if txs.empty?
    sleep interval
    return nil
  elsif txs.size >= limit
    raise txs # TODO
  end
  min = lmax + 1
  txs.each do |txo|
    tx = txo['tx']
    type = tx['TransactionType']
    next unless type == 'Payment'
    ledger_index = tx['ledger_index']
    amount = tx['Amount']
    next unless Hash === amount
    ai = amount['issuer']
    next unless rrpc.account_id == ai
    dst = tx['Destination']
    next unless dst == ai
    ac = amount['currency']
    av = amount['value']
    coins = @@config['coins']
    coinid, coin = coins.find{|k,v|v['symbol'] == ac}
    next unless coinid
    from = tx['Account']
    tag = tx['DestinationTag']
    @@redis.keys('id:*').each do |k|
      v = @@redis.getm(k)
      next unless v[:rippleaddr] == from
      tag2 = Digest::MD5.digest(k).unpack('V')[0] & 0x7fffffff
      next unless tag == tag2
      moveto = k
      rpc = getrpc(coinid)
p [:move, coinid, 'iou', moveto, av.to_f]
      coincfg = coins[coinid]
      minconf = coincfg['minconf'] || 6
      begin
        rpc.move('iou', moveto, av.to_f, minconf)
      rescue => x
# TODO error check
p [:errord, x]
      end
    end
  end
  @@redis.set('polling:ledger', min)
  min
end

def getvalue(x)
  case x
  when Hash
    [x['value'].to_f, x['currency']]
  else
    [x.to_f / 1000000, 'XRP']
  end
end

def getprices(rpc, sym)
  issuer = rpc.account_id
  params = {
    'taker_gets' => { 'currency' => sym, 'issuer' => issuer },
    'taker_pays' => { 'currency' => 'XRP' },
  }
  2.times.map do |i|
    result = rpc.book_offers(params)
    return nil unless result['status'] == 'success'
    offers = result['offers']
    offer = offers.first
    gs = getvalue(offer['TakerGets']) rescue [1]
    ps = getvalue(offer['TakerPays']) rescue [0.0]
    price = i == 0 ? ps[0] / gs[0] : gs[0] / ps[0]
    ps = params['taker_pays']
    params['taker_pays'] = params['taker_gets']
    params['taker_gets'] = ps
    price
  end
end

def main
  rrpc = getripplerpc
  interval = 60
  min = @@redis.get('polling:ledger') || "-1"
  min = min.to_i
  loop do
    begin
      rprices = @@redis.getm('polling:prices') || {}
      coins = @@config['coins']
      coins.each do |k,v|
        next unless v['iou']
        sym = v['symbol']
#p sym
        prices = nil
        loop do
          begin
            prices = getprices(rrpc, sym)
            break
          rescue => x
p [:errorc, x]
            sleep 3
          rescue Timeout::Error => x
p [:errorf, x]
            sleep 3
          end
        end
        rprices[sym.to_sym] = { :bid => prices[1], :ask => prices[0] }
      end
      @@redis.setm('polling:prices', rprices)
      nextmin = poll(rrpc, interval, min)
      min = nextmin if nextmin
    rescue => x
p [:errorb, x]
      sleep interval
    end
  end
end

main
