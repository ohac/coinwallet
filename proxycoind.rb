#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'redis'
require 'bitcoin_rpc'

file = File.new("proxycoind.log", 'a+')
# TODO STDOUT.reopen(file)
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
  BitcoinRPC.new(uri)
end

def poll(rpc, blockhash)
  result = blockhash ? rpc.listsinceblock(blockhash) : rpc.listsinceblock
  lastblock = result['lastblock']
  txs = result['transactions']
  txs.each do |tx|
    cat = tx['category']
    case cat
    when 'receive'
      amount = tx['amount']
      address = tx['address']
      accountid = rpc.getaccount(address)
p [:receive, amount, address, accountid]
    when 'send'
    when 'generate'
    else
      p cat # TODO
    end
  end
  lastblock
end

def main
  interval = 60
  loop do
    begin
      coins = @@config['coins']
      coins.each do |coinid,v|
        blockhash = nil # TODO
        next unless v['proxycoind']
        rpc = getrpc(coinid)
        blockhash = poll(rpc, blockhash)
p blockhash
      end
    rescue => x
      p x
      raise x # TODO
    end
    sleep interval
  end
end

main
