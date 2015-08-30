#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'bitcoin_rpc'

def sub(d, depth = 10)
  uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
  rpc = BitcoinRPC.new(uri)
  info = rpc.getinfo
  balance = info['balance']
  blocks = info['blocks']
  connections = info['connections']
  difficulty = info['difficulty']
  if Hash === difficulty
    difficulty_pow = difficulty['proof-of-work']
    difficulty_pos = difficulty['proof-of-stake']
    difficulty = difficulty_pos
  end
  timeformat = "%Y-%m-%d %H:%M:%S"
  puts "#{Time.now.strftime(timeformat)}"
  puts "Connections: #{connections}, Difficulty: #{difficulty}"
  puts "Height Time                Hash                                                  Transactions Difficulty"
  depth.times do |i|
    height = blocks - i
    hash = rpc.getblockhash(height)
    block = rpc.getblock(hash)
    time = block['time']
    strtime = Time.at(time).strftime(timeformat)
    tx = block['tx']
    #proofhash = (block['proofhash'] || hash)[0, 16]
    #mint = block['mint'] || 0
    difficulty = block['difficulty']
    flags = block['flags']
    #rawblock = rpc.getblock(hash, false)
    #if String === rawblock
      #rawblock = [rawblock].pack("H*")
    #end
    puts "#{height} #{strtime} #{hash} #{tx.size} #{difficulty}"
  end
end

config = YAML.load_file('config.yml')
coinids = config['coins'].keys.sort_by(&:to_s)
coinids.each do |coinid|
  coin = config['coins'][coinid]
  user = coin['user']
  password = coin['password']
  host = coin['host']
  port = coin['port']
  name = coin['name']
  symbol = coin['symbol']
  minconf = coin['minconf'] || 6
  puts
  puts "#{name} #{symbol} #{minconf}"
  begin
    sub({
      'user' => user,
      'password' => password,
      'host' => host,
      'port' => port,
    }, 10)
  rescue
    puts "offline"
  end
end
