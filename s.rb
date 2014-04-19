#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra/base'
require 'sinatra/partial'
require 'haml'
require 'omniauth-twitter'
require 'omniauth-github'
require 'omniauth-google-oauth2'
require 'bitcoin_rpc'
require 'ripple_rpc'
require 'redis'
require 'logger'
require 'digest/md5'

class Redis
  def setm(k, o)
    set(k, Marshal.dump(o))
  end
  def getm(k)
    m = get(k)
    m ? Marshal.load(m) : nil
  end
end

class WebWallet < Sinatra::Base

  register Sinatra::Partial

  @@config = YAML.load_file('config.yml')
  @@coinids = @@config['coins'].keys.map{|id|id.to_sym}.sort_by(&:to_s)
  @@mutex = Mutex.new
  @@debug = false

  def getrpc(coinname)
    d = @@config['coins'][coinname]
    uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
    BitcoinRPC.new(uri)
  end

  def getripplerpc(type = nil)
    d = @@config['ripple']
    x = type ? d[type] : d
    account_id = x['account_id']
    master_seed = x['master_seed']
    uri = "http://#{d['host']}:#{d['port']}"
    RippleRPC.new(uri, account_id, master_seed)
  end

  def getaddress(rpc, accountid)
    rpc.getaddressesbyaccount(accountid).first || rpc.getnewaddress(accountid)
  end

  def checkaddress(rpc, addr)
    return true if addr.size == 0
    raise unless addr.size == 34
    raise unless /\A[a-km-zA-HJ-NP-Z1-9]{34}\z/ === addr
    return true unless rpc
    addr && rpc.validateaddress(addr)['isvalid']
  end

  def checktrust(rpc, to, amount, sym)
    params = {
      'account' => to,
      'peer' => rpc.account_id,
    }
    result = rpc.account_lines(params) rescue {}
    if result['status'] == 'success'
      lines = result['lines']
      lines.each do |line|
        currency = line['currency']
        next unless currency == sym
        balance = line['balance']
        limit = line['limit']
        v = limit.to_f - balance.to_f
        return v >= amount
      end
    end
    false
  end

  configure do
    enable :logging
    file = File.new("webwallet.log", 'a+')
    STDERR.reopen(file)
    file.sync = true
    use Rack::CommonLogger, file
    set :sessions, true
    set :inline_templates, true
    set :session_secret, @@config['session_secret']
    disable :show_exceptions
    use OmniAuth::Builder do
      providers = @@config['providers']
      providerid = :twitter
      config = providers[providerid.to_s]
      provider providerid, config['consumer_key'], config['consumer_secret']
      providerid = :github
      config = providers[providerid.to_s]
      provider providerid, config['consumer_key'], config['consumer_secret']
      providerid = :google_oauth2
      config = providers[providerid.to_s]
      provider providerid, config['consumer_key'], config['consumer_secret']
      if @@debug
        providerid = :developer
        provider providerid
      end
    end
  end

  helpers do
    def current_user
      !session[:accountid].nil?
    end
    def h(text)
      Rack::Utils.escape_html(text)
    end
  end

  before do
    pass if request.path_info =~ /^\/$/
    pass if request.path_info =~ /^\/auth\//
    redirect to('/') unless current_user
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

  post '/auth/developer/callback' do
    raise unless @@debug
    provider = 'developer'
    uid = params['name']
    email = params['email']
    providers = @@config['providers']
    config = providers[provider]
    raise unless config['uid'] == uid
    raise unless config['email'] == email
    accountid = "id:#{uid}@#{provider}"
    account = @@redis.getm(accountid) || {}
    account[:provider] = provider
    account[:nickname] = uid
    account[:name] = uid
    @@redis.setm(accountid, account)
    session[:accountid] = accountid
    redirect to('/')
  end

  get '/auth/:provider/callback' do
    auth = env['omniauth.auth']
    uid = auth['uid']
    provider = params[:provider]
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
    erb "<h1>Authentication Failed:</h1><h3>message:<h3> <pre>#{params}</pre>"
  end

  get '/auth/:provider/deauthorized' do
    erb "#{params[:provider]} has deauthorized this app."
  end

  get '/protected' do
    throw(:halt, [401, "Not authorized\n"])
  end

  get '/logout' do
    session[:accountid] = nil
    redirect '/'
  end

  get '/' do
    message = session[:message]
    session[:message] = nil
    accountid = session[:accountid]
    accounts = getaccounts
    balances = getbalances rescue {}
    prices = @@redis.getm('polling:prices') || {}
    unless accountid
      haml :guest, :locals => {
        :accounts => accounts,
        :balances => balances,
        :coins => @@config['coins'],
        :prices => prices,
        :providers => @@config['providers'],
      }
    else
      account = @@redis.getm(accountid)
      nickname = account[:nickname]
      logger.info("account: #{accountid}, #{nickname}")
      rippleaddr = account[:rippleaddr]
      coins = @@coinids.inject({}) do |v, coinid|
        rpc = getrpc(coinid.to_s)
        balance = rpc.getbalance(accountid, 6) rescue 0.0
        balance0 = rpc.getbalance(accountid, 0) rescue 0.0
        addr = getaddress(rpc, accountid) rescue nil
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
        :coinids => @@coinids,
        :rippleaddr => rippleaddr,
        :rippleiou => @@config['ripple']['account_id'],
        :ripplefaucet => @@config['ripple']['faucet']['account_id'],
        :message => message,
        :prices => prices,
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
        :rippleaddr => account[:rippleaddr] || '',
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
      rippleaddr = params['rippleaddr']
      if checkaddress(nil, rippleaddr)
        account[:rippleaddr] = rippleaddr
      end
      @@redis.setm(accountid, account)
    end
    redirect '/'
  end

  get '/deposit' do
    accountid = session[:accountid]
    redirect '/' unless accountid
    coinid = params['coinid']
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    rpc = getrpc(coinid)
    addr = getaddress(rpc, accountid) rescue nil
    haml :deposit, :locals => {
      :nickname => nickname,
      :coinid => coinid,
      :addr => addr,
    }
  end

  get '/withdraw' do
    accountid = session[:accountid]
    unless accountid
      redirect '/'
    else
      coinid = params['coinid']
      balance = params['balance'].to_f
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
        :balance => balance,
      }
    end
  end

  post '/withdraw' do
    accountid = session[:accountid]
    redirect '/' unless accountid
    message = 'Success'
    coinid = params['coinid']
    rpc = getrpc(coinid)
    payoutto = params['payoutto']
    if checkaddress(rpc, payoutto)
      amount = params['amount'].to_f
      if amount > 0.1
        balance = rpc.getbalance(accountid, 6)
        fee = 0.05
        if balance < amount + fee
          message = 'Failed'
        else
          rpc.sendfrom(accountid, payoutto, amount)
          moveto = 'income'
          rpc.move(accountid, moveto, fee - 0.01)
        end
      else
        message = 'less_than_0.1'
      end
    end
    session[:message] = message
    redirect '/'
  end

  get '/history' do
    accountid = session[:accountid]
    coinid = params['coinid']
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    rpc = getrpc(coinid)
    history = rpc.listtransactions(accountid)
    haml :history, :locals => {
      :nickname => nickname,
      :coinid => coinid,
      :symbol => @@config['coins'][coinid]['symbol'],
      :history => history,
    }
  end

  get '/donate' do
    accountid = session[:accountid]
    coinid = params['coinid']
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    haml :donate, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => coinid,
      :symbol => @@config['coins'][coinid]['symbol'],
    }
  end

  post '/donate' do
    accountid = session[:accountid]
    coinid = params['coinid']
    amount = params['amount'].to_f
    if amount > 0.001
      rpc = getrpc(coinid)
      balance = rpc.getbalance(accountid, 6)
      if balance > amount
        faucetid = 'faucet'
        rpc.move(accountid, faucetid, amount)
      end
    end
    redirect '/'
  end

  get '/faucet' do
    accountid = session[:accountid]
    faucettimeid = "faucet:#{accountid}"
    coinid = params['coinid']
    rpc = getrpc(coinid)
    account = @@redis.getm(accountid)
    faucettime = @@redis.getm(faucettimeid) || 0
    nickname = account[:nickname]
    faucetid = 'faucet'
    begin
      @@mutex.lock
      balance = rpc.getbalance(faucetid, 6)
      amount = [balance * 0.01, 0.01].max
      now = Time.now.to_i
      faucetlocktime = 1 * 60 * 60
      if amount < 0.01 || balance < amount || faucettime + faucetlocktime > now
        amount = 0
      else
        result = rpc.move(faucetid, accountid, amount)
        @@redis.setm(faucettimeid, now)
        amount = 0 unless result
      end
    ensure
      @@mutex.unlock
    end
    haml :faucet, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => coinid,
      :amount => amount,
      :balance => balance,
      :symbol => @@config['coins'][coinid]['symbol'],
    }
  end

  get '/faucetxrp' do
    accountid = session[:accountid]
    faucettimeid = "faucet:#{accountid}"
    rpc = getripplerpc('faucet')
    account = @@redis.getm(accountid)
    faucettime = @@redis.getm(faucettimeid) || 0
    nickname = account[:nickname]
    rippleaddr = account[:rippleaddr]
    params = {
      'account' => rpc.account_id,
    }
    result = rpc.account_info(params) rescue {}
    reserve = 20000000 # 20 XRP
    if result['status'] == 'success'
      balance = result['account_data']['Balance'].to_i - reserve
    else
      balance = 0
    end
    amount = 50000 # 0.05 XRP
    now = Time.now.to_i
    faucetlocktime = 1 * 60 * 60
    if rippleaddr.nil? || rippleaddr.empty? ||
        !checkaddress(nil, rippleaddr) || balance < amount ||
        faucettime + faucetlocktime > now
      logger.info("failed: #{rippleaddr}, #{balance}, #{amount}")
      amount = 0
    else
      params = {
        'account' => rippleaddr,
      }
      result = rpc.account_info(params) rescue {}
      if result['status'] == 'success'
        params = {
          'tx_json' => {
            'TransactionType' => 'Payment',
            'Account' => rpc.account_id,
            'Amount' => amount,
            'Destination' => rippleaddr,
          },
          'secret' => rpc.masterseed,
        }
        result = rpc.submit(params)
        if result['status'] == 'success'
          @@redis.setm(faucettimeid, now)
        else
          logger.info("failed: #{result['status']}")
          amount = 0
        end
      else
        amount = 0
      end
    end
    haml :faucet, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => 'ripple',
      :amount => amount / 1000000.0,
      :balance => balance / 1000000.0,
      :symbol => 'XRP',
    }
  end

  get '/buyxrp' do
    accountid = session[:accountid]
    rpc = getripplerpc
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    haml :buyxrp, :locals => {
      :nickname => nickname,
      :coins => @@config['coins'],
      :coinids => @@coinids,
    }
  end

  post '/buyxrp' do
    message = 'success'
    coinid = params['coinid']
    coin = @@config['coins'][coinid]
    redirect '/' unless coin
    accountid = session[:accountid]
    rrpc = getripplerpc
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    rippleaddr = account[:rippleaddr]
    params = {
      'account' => rrpc.account_id,
    }
    result = rrpc.account_info(params) rescue {}
    reserve = 25000000 # 25 XRP
    if result['status'] == 'success'
      rbalance = result['account_data']['Balance'].to_i - reserve
    else
      message = result['status']
      rbalance = 0
    end
    ramount = 25000000 # 25.0 XRP
    if rippleaddr.nil? || rippleaddr.empty? ||
        !checkaddress(nil, rippleaddr) || rbalance < ramount
      logger.info("failed1: #{rippleaddr}, #{rbalance}, #{ramount}")
      message = 'failed1'
      ramount = 0
    else
      coin = @@config['coins'][coinid]
      amount = 0
      rpc = nil

      begin
        @@mutex.lock
        if coin
          amount = coin['price'] * 25.0 # 25.0 XRP
          rpc = getrpc(coinid)
          balance = rpc.getbalance(accountid, 6)
          if balance < amount
            logger.info("failed2: #{accountid}, #{balance}")
            message = 'failed2'
            amount = 0
          end
        end
        params = {
          'account' => rippleaddr,
        }
        if amount > 0
          params = {
            'tx_json' => {
              'TransactionType' => 'Payment',
              'Account' => rrpc.account_id,
              'Amount' => ramount,
              'Destination' => rippleaddr,
            },
            'secret' => rrpc.masterseed,
          }
          result = rrpc.submit(params)
          if result['status'] == 'success'
            moveto = 'income'
            rpc.move(accountid, moveto, amount)
          else
            logger.info("failed4: #{result['status']}")
            message = 'failed4'
          end
        else
          logger.info("failed4: #{amount}, #{result['status']}")
          message = 'failed3'
        end
      ensure
        @@mutex.unlock
      end
    end
    session[:message] = message
    redirect '/'
  end

  get '/coin2iou' do
    balance = params['balance'].to_f
    accountid = session[:accountid]
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    haml :coin2iou, :locals => {
      :nickname => nickname,
      :coins => @@config['coins'],
      :coinid => params['coinid'],
      :balance => balance,
    }
  end

  post '/coin2iou' do
    accountid = session[:accountid]
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    rrpc = getripplerpc
    coinid = params[:coinid]
    coin = @@config['coins'][coinid]
    sym = coin['symbol']
    amountstr = params['amount']
    rippleaddr = account[:rippleaddr]
    if rippleaddr.nil? or rippleaddr.empty?
      session[:message] = 'Empty Address'
      redirect '/'
    end
    unless checkaddress(nil, rippleaddr)
      session[:message] = 'Invalid Address'
      redirect '/'
    end
    if amountstr.to_f < 0.1
      session[:message] = 'Too little'
      redirect '/'
    end
    unless checktrust(rrpc, rippleaddr, amountstr.to_f, sym)
      session[:message] = 'Need trust'
      redirect '/'
    end
    begin
      @@mutex.lock
      rpcparams = {
        'tx_json' => {
          'TransactionType' => 'Payment',
          'Account' => rrpc.account_id,
          'Amount' => {
            'currency' => sym,
            'value' => amountstr,
            'issuer' => rrpc.account_id,
          },
          'Destination' => rippleaddr,
        },
        'secret' => rrpc.masterseed,
      }
      rpc = getrpc(coinid)
      balance = rpc.getbalance(accountid, 6)
      amount = amountstr.to_f
      message = 'lowbalance'
      if balance >= amount + 0.0001
        result = rrpc.submit(rpcparams)
        message = result['status']
        if result['status'] == 'success'
          iouid = 'iou'
          rpc.move(accountid, iouid, amount)
        end
      end
    ensure
      @@mutex.unlock
    end
    session[:message] = message
    redirect '/'
  end

  get '/iou2coin' do
    accountid = session[:accountid]
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    haml :iou2coin, :locals => {
      :nickname => nickname,
      :coins => @@config['coins'],
      :coinid => params['coinid'],
    }
  end

  get '/iou2coin' do
    # TODO views/iou2coin.haml
p params
    rrpc = getripplerpc
    redirect '/'
  end

  if app_file == $0
    if ARGV[0] == '-d'
      set :port, 4568
      set :bind, '0.0.0.0'
      @@debug = true
    else
      set :bind, '127.0.0.1'
    end
    run!
  end

end
