#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra'
require 'haml'
require 'omniauth-twitter'
require 'bitcoin_rpc'
require 'redis'

@@config = YAML.load_file('config.yml')

def getrpc(coinname)
  d = @@config[coinname]
  uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
  BitcoinRPC.new(uri)
end

configure do
  enable :sessions
  set :session_secret, ENV['SESSION_SECRET']
  use OmniAuth::Builder do
    provider :twitter, ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET']
  end
end

helpers do
  def current_user
    !session[:account].nil?
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
  account = "id:#{uid}@#{provider}"
  @@redis.setm(account, {
    :provider => provider,
    :nickname => auth['info']['nickname'],
    :name => auth['info']['name'],
  })
  session[:account] = account
  redirect to('/')
end

get '/auth/failure' do
end

get '/' do
  account = session[:account]
  haml :index, :locals => { :account => account }
end

get '/hello' do
  account = session[:account]
  cache = @@redis.getm(account)
  unless cache
    redirect '/'
  else
    coinname = 'sakuracoind'
    rpc = getrpc(coinname)
    balance = rpc.getinfo['balance']
    "hello #{account} #{cache[:nickname]} #{balance}"
  end
end

get '/logout' do
  session[:account] = nil
  redirect '/'
end
