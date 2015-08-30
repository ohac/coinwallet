#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'bitcoin_rpc'

def sub(d)
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
  puts "c: #{connections} difficulty: #{difficulty}"
  puts "Height Time Hash Transactions Difficulty"
  1.times do |i|
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

#=begin
sub({ # ringo
    'user' => '1',
    'password' => 'x',
    'host' => 'localhost',
    'port' => 9292,
})
#=end
#=begin
sub({ # bitzeny
    'user' => '1',
    'password' => 'x',
    'host' => 'localhost',
    'port' => 9252,
})
#=end
