#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra'
require 'haml'
require 'omniauth-twitter'
require 'bitcoin_rpc'

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
    !session[:uid].nil?
  end
end

before do
  pass if request.path_info =~ /^\/$/
  pass if request.path_info =~ /^\/auth\//
  redirect to('/auth/twitter') unless current_user
end

@@cache = {}

get '/auth/twitter/callback' do
  auth = env['omniauth.auth']
  uid = auth['uid']
  @@cache[uid] = {
    :provider => auth['provider'],
    :nickname => auth['info']['nickname'],
    :name => auth['info']['name'],
  }
  session[:uid] = uid
  redirect to('/')
end

get '/auth/failure' do
end

get '/' do
  uid = session[:uid]
  haml :index, :locals => { :uid => uid }
end

get '/hello' do
  uid = session[:uid]
  cache = @@cache[uid] || {}
  coinname = 'sakuracoind'
  rpc = getrpc(coinname)
  balance = rpc.getinfo['balance']
  "hello #{uid} #{cache[:nickname]} #{balance}"
end

get '/logout' do
  uid = session[:uid]
  cache = @@cache[uid] || {}
  "logout #{uid} #{cache[:nickname]}"
  session[:uid] = nil
  redirect '/'
end
