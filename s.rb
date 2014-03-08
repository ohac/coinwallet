#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra'
require 'haml'
require 'omniauth-twitter'
require 'bitcoin_rpc'
require 'redis'

@@config = YAML.load_file('config.yml')
@@coinids = [ :sakuracoin ]

def getrpc(coinname)
  d = @@config[coinname]
  uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
  BitcoinRPC.new(uri)
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

get '/auth/twitter/callback' do
  auth = env['omniauth.auth']
  uid = auth['uid']
  provider = auth['provider']
  accountid = "id:#{uid}@#{provider}"
  @@redis.setm(accountid, {
    :provider => provider,
    :nickname => auth['info']['nickname'],
    :name => auth['info']['name'],
  })
  session[:accountid] = accountid
  redirect to('/')
end

get '/auth/failure' do
  'failure'
end

get '/' do
  accountid = session[:accountid]
  unless accountid
    haml :guest
  else
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    coinname = 'sakuracoind'
    rpc = getrpc(coinname)
    balance = rpc.getbalance(accountid, 6)
    balance0 = rpc.getbalance(accountid, 0)
    addr = rpc.getaddressesbyaccount(accountid).first ||
        rpc.getnewaddress(accountid)
    haml :index, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :balance => balance,
      :balance0 => balance0,
      :addr => addr,
    }
  end
end

get '/profile' do
  accountid = session[:accountid]
  unless accountid
    redirect '/'
  else
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    haml :profile, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinids => @@coinids,
    }
  end
end

post '/profile' do
p params
  @@coinids.each do |coinid|
    payoutto = params["#{coinid}_payoutto"]
p payoutto
  end
  redirect '/'
end

get '/logout' do
  session[:accountid] = nil
  redirect '/'
end
