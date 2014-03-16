#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra'
require 'haml'
require 'omniauth-twitter'
require 'bitcoin_rpc'
require 'redis'

set :bind, '127.0.0.1'

@@config = YAML.load_file('config.yml')
@@coinids = @@config['coins'].keys.map{|id|id.to_sym}

def getrpc(coinname)
  d = @@config['coins'][coinname]
  uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
  BitcoinRPC.new(uri)
end

def getaddress(rpc, accountid)
  rpc.getaddressesbyaccount(accountid).first || rpc.getnewaddress(accountid)
end

def checkaddress(rpc, addr)
  return true if addr.size == 0
  raise unless addr.size == 34
  raise unless /\A[a-km-zA-HJ-NP-Z1-9]{34}\z/ === addr
  addr && rpc.validateaddress(addr)['isvalid']
end

configure do
  enable :sessions
  set :session_secret, @@config['session_secret']
  use OmniAuth::Builder do
    providers = @@config['providers']
    providerid = :twitter
    config = providers[providerid.to_s]
    provider providerid, config['consumer_key'], config['consumer_secret']
  end
end

helpers do
  def current_user
    !session[:accountid].nil?
  end
end

before do
  pass if request.path_info =~ /^\/$/
  pass if request.path_info =~ /^\/auth\//
  redirect to('/auth/twitter') unless current_user
end

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

def getaccounts
  @@redis.keys('id:*').map do |k|
    [k, @@redis.getm(k)]
  end
end

def getbalances
  @@coinids.inject({}) do |h, coinid|
    rpc = getrpc(coinid.to_s)
    balance = rpc.getbalance
    h[coinid] = balance
    h
  end
end

get '/auth/twitter/callback' do
  auth = env['omniauth.auth']
  uid = auth['uid']
  provider = auth['provider']
  accountid = "id:#{uid}@#{provider}"
  account = @@redis.getm(accountid) || {}
  account[:provider] = provider
  account[:nickname] = auth['info']['nickname']
  account[:name] = auth['info']['name']
  @@redis.setm(accountid, account)
  session[:accountid] = accountid
  redirect to('/')
end

get '/auth/failure' do
  'failure'
end

get '/' do
  accountid = session[:accountid]
  accounts = getaccounts
  balances = getbalances
  unless accountid
    haml :guest, :locals => {
      :accounts => accounts,
      :balances => balances,
    }
  else
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    coins = @@coinids.inject({}) do |v, coinid|
      rpc = getrpc(coinid.to_s)
      balance = rpc.getbalance(accountid, 6)
      balance0 = rpc.getbalance(accountid, 0)
      addr = getaddress(rpc, accountid)
      v[coinid] = {
        :balance => balance,
        :balance0 => balance0,
        :addr => addr,
        :symbol => @@config['coins'][coinid.to_s]['symbol'],
      }
      v
    end
    haml :index, :locals => {
      :accounts => accounts,
      :balances => balances,
      :accountid => accountid,
      :nickname => nickname,
      :coins => coins,
    }
  end
end

get '/profile' do
  accountid = session[:accountid]
  unless accountid
    redirect '/'
  else
    account = @@redis.getm(accountid)
    coins = account[:coins] || {}
    nickname = account[:nickname]
    haml :profile, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinids => @@coinids,
      :coins => coins,
    }
  end
end

post '/profile' do
  accountid = session[:accountid]
  if accountid
    account = @@redis.getm(accountid)
    account[:coins] ||= {}
    @@coinids.each do |coinid|
      rpc = getrpc(coinid.to_s)
      payoutto = params["#{coinid}_payoutto"]
      if checkaddress(rpc, payoutto)
        account[:coins][coinid] ||= {}
        account[:coins][coinid][:payoutto] = payoutto
      else
p :invalid # TODO
      end
    end
    @@redis.setm(accountid, account)
  end
  redirect '/'
end

get '/withdraw' do
  accountid = session[:accountid]
  unless accountid
    redirect '/'
  else
    coinid = params['coinid']
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    coins = account[:coins] || {}
    coin = coins[coinid.to_sym] || {}
    payoutto = coin[:payoutto]
    haml :withdraw, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => coinid,
      :payoutto => payoutto,
      :symbol => @@config['coins'][coinid]['symbol'],
    }
  end
end

post '/withdraw' do
  accountid = session[:accountid]
  if accountid
    coinid = params['coinid']
    rpc = getrpc(coinid)
    payoutto = params['payoutto']
    if checkaddress(rpc, payoutto)
      amount = params['amount'].to_f
      if amount > 0.001
        rpc.sendfrom(accountid, payoutto, amount)
      end
    end
  end
  redirect '/'
end

get '/logout' do
  session[:accountid] = nil
  redirect '/'
end
