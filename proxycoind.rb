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

def newaccount(accounts, accountid)
  accounts[accountid] ||= {
    'balance' => 0.0,
  }
end

def poll(rpc, blockhash, accounts, pendingtxs, pendingflag)
  confirmedheight = 6 # TODO
  params = [blockhash]
  params << 400 if pendingflag # TODO
  result = rpc.listsinceblock(*params)
  lastblock = result['lastblock']
  txs = result['transactions']
p txs.size
  completedtxs = []
  txs.each do |tx|
    confirmations = tx['confirmations']
    txid = tx['txid']
    confirmed = confirmations >= confirmedheight
    if pendingflag
      next if !pendingtxs.include?(txid)
p [:pending2, txid[0,6], confirmations]
      next if !confirmed
      completedtxs << txid
    elsif !confirmed
p [:pending1, txid[0,6], confirmations]
      pendingtxs << txid unless pendingtxs.include?(txid)
      next
    end
    amount = tx['amount']
    cat = tx['category']
    case cat
    when 'receive'
      accountaddr = tx['address']
      accountid = rpc.getaccount(accountaddr)
      account = newaccount(accounts, accountid)
      account['balance'] += amount
p [:receive, amount, accountid, confirmations]
    when 'send'
      accountid = tx['account']
      fee = tx['fee']
      amount += fee
      account = newaccount(accounts, accountid)
      account['balance'] += amount
p [:send, amount, accountid]
    when 'generate'
      accountid = tx['account']
      account = newaccount(accounts, accountid)
      account['balance'] += amount
p [:generate, amount, accountid, confirmations]
    when 'immature'
      accountid = tx['account']
      account = newaccount(accounts, accountid)
      account['balance'] += amount
p [:immature, amount, accountid, confirmations]
    when 'orphan'
      p :orphan # TODO
    else
      p cat # TODO
    end
  end
  completedtxs.uniq.each do |txid|
    pendingtxs.delete(txid)
  end
  lastblock
end

def main
  interval = 60
  loop do
    begin
      coins = @@config['coins']
      coins.each do |coinid,v|
        next unless v['proxycoind']
        rpc = getrpc(coinid)
        coindbname = "proxycoind:#{coinid}"
        coininfo = @@redis.getm(coindbname) || {
          'blockhash' => '',
          'accounts' => {},
          'pendingtxs' => [],
          'pendingblockhash' => '',
        }
        blockhash = coininfo['blockhash']
        accounts = coininfo['accounts']
        pendingtxs = coininfo['pendingtxs']
        blockhash = poll(rpc, blockhash, accounts, pendingtxs, false)
        coininfo['blockhash'] = blockhash
        pendingblockhash = coininfo['pendingblockhash']
        pendingblockhash = poll(rpc, pendingblockhash, accounts, pendingtxs,
            true)
        coininfo['pendingtxs'] = pendingtxs
        coininfo['pendingblockhash'] = pendingblockhash
        @@redis.setm(coindbname, coininfo)
p accounts
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
