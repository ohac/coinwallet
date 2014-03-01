#!/usr/bin/ruby
require 'rubygems'
require 'sinatra'
require 'omniauth-twitter'

configure do
  enable :sessions
  set :session_secret, ENV['SESSION_SECRET']

  use OmniAuth::Builder do
    provider :twitter, ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET']
  end
end

helpers do
  # define a current_user method, so we can be sure if an user is authenticated
  def current_user
    !session[:uid].nil?
  end
end

before do
  # we do not want to redirect to twitter when the path info starts
  # with /auth/
  pass if request.path_info =~ /^\/auth\//

  # /auth/twitter is captured by omniauth:
  # when the path info matches /auth/twitter, omniauth will redirect to twitter
  redirect to('/auth/twitter') unless current_user
end

@@cache = {}

get '/auth/twitter/callback' do
  # probably you will need to create a user in the database too...
  auth = env['omniauth.auth']
  uid = auth['uid']
  @@cache[uid] = {
    :provider => auth['provider'],
    :nickname => auth['info']['nickname'],
    :name => auth['info']['name'],
  }
  session[:uid] = uid
  # this is the main endpoint to your application
  redirect to('/')
end

get '/auth/failure' do
  # omniauth redirects to /auth/failure when it encounters a problem
  # so you can implement this as you please
end

get '/' do
  uid = session[:uid]
  cache = @@cache[uid] || {}
  "hello #{uid} #{cache[:nickname]}"
end

get '/logout' do
  uid = session[:uid]
  cache = @@cache[uid] || {}
  "logout #{uid} #{cache[:nickname]}"
  session[:uid] = nil
end
