#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'sinatra/base'
require 'slim'
require 'omniauth-twitter'
require 'omniauth-github'
require 'omniauth-google-oauth2'
require 'bitcoin_rpc'
require 'electrum_rpc'
require 'proxycoin_rpc'
require 'ripple_rpc'
require 'redis'
require 'logger'
require 'digest/md5'
require 'i18n'
require 'i18n/backend/fallbacks'

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

  @@config = YAML.load_file('config.yml')
  @@coinids = @@config['coins'].keys.map{|id|id.to_sym}.sort_by(&:to_s)
  @@mutex = Mutex.new
  @@debug = false
  @@cache = {}
  @@locales = nil

  def getrpc(coinname)
    d = @@config['coins'][coinname]
    uri = "http://#{d['user']}:#{d['password']}@#{d['host']}:#{d['port']}"
    btcrpc = (d['electrum'] ? ElectrumRPC : BitcoinRPC).new(uri)
    d['proxycoind'] ? ProxycoinRPC.new(btcrpc, coinname) : btcrpc
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
    rpc.getaddressesbyaccount(accountid).first
  end

  def checkaddress(rpc, addr)
    return true if addr.size == 0
    raise unless addr.size == 34 || addr.size == 33
    raise unless /\A[a-km-zA-HJ-NP-Z1-9]{34}\z/ === addr
    return true unless rpc
    addr && rpc.validateaddress(addr)['isvalid']
  end

  def checkrippleaddress(addr)
    return true if addr.size == 0
    raise if addr.size < 33 || addr.size > 34
    raise unless /\A[a-km-zA-HJ-NP-Z1-9]{33,34}\z/ === addr
    return true
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

  def getaccountbalance(rpc, coinid, accountid)
    key = "#{coinid} #{accountid}"
    cache = @@cache[key]
    if cache
      b, b0, expires = cache
      return cache if Time.now.to_i < expires
    end
    balance = rpc.getbalance(accountid, getminconf(coinid)) rescue 0.0
    balance0 = rpc.getbalance(accountid, 1) rescue 0.0 # trim orphan block
    @@cache[key] = [balance, balance0, Time.now.to_i + 60 + rand(60)]
  end

  def clearcache(coinid, accountid)
    key = "#{coinid} #{accountid}"
    @@cache[key] = nil
  end

  configure do
    enable :logging
    file = File.new("webwallet.log", 'a+')
    STDERR.reopen(file)
    file.sync = true
    use Rack::CommonLogger, file
    set :inline_templates, true
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
      provider providerid, config['consumer_key'], config['consumer_secret'], {
        :scope => 'email',
      }
      if @@debug
        providerid = :developer
        provider providerid
      end
    end
    I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
    locales = Dir[File.join(settings.root, 'locales', '*.yml')]
    I18n.load_path = locales
    @@locales = locales.map{|locale| File.basename(locale).split('.')[0]}
    I18n.backend.load_translations
  end

  helpers do
    def current_user
      id = session[:accountid]
      banned = [
        'id:8041321@github',
        'id:8042273@github',
        'id:8066133@github',
        'id:8066220@github',
        'id:8066360@github',
        'id:8066496@github',
        'id:8066553@github',
        'id:8072168@github',
        'id:8050087@github',
        'id:8050819@github',
        'id:8072168@github',
      ]
      raise if banned.include?(id)
      !id.nil?
    end
    def h(text)
      Rack::Utils.escape_html(text)
    end
    def t(text)
      I18n.t(text)
    end
    def setlocale(account)
      locale = account[:locale] || @@config['locale']
      I18n.locale = locale
    end
    def getminconf(coinid)
      coin = @@config['coins'][coinid]
      coin['minconf'] || 6
    end
  end

  @@redis = Redis.new

  before do
    torlist = @@redis.get('torlist')
    if torlist
      ip = request.ip
      if torlist.index(ip)
p ip 
        list = torlist.split(',')
        raise if list.include?(ip)
      end
    end
    pass if request.path_info =~ /^\/$/
    pass if request.path_info =~ /^\/auth\//
    redirect to('/') unless current_user
  end

  def getaccounts
    @@redis.keys('id:*').map do |k|
      [k, @@redis.getm(k)]
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

  get '/api/:version/:coinid/:action' do
    if params[:version] == 'v1'
      case params[:action]
      when 'balance'
        accountid = session[:accountid]
        coinid = params[:coinid]
        rpc = getrpc(coinid)
        balance, balance0, expires = getaccountbalance(rpc, coinid, accountid)
        {
          :status => :success,
          :balance => balance,
          :balance0 => balance0,
        }.to_json
      else
        {:status => :error}.to_json
      end
    else
      {:status => :error}.to_json
    end
  end

  get '/' do
    message = session[:message]
    session[:message] = nil
    accountid = session[:accountid]
    prices = @@redis.getm('polling:prices') || {}
    ledger = @@redis.get('polling:ledger_max') || 0
    unless accountid
      accounts = getaccounts
      slim :guest, :locals => {
        :accounts => accounts,
        :coins => @@config['coins'],
        :prices => prices,
        :providers => @@config['providers'],
        :ledger => ledger,
      }
    else
      account = @@redis.getm(accountid)
      setlocale(account)
      nickname = account[:nickname]
      logger.info("account: #{accountid}, #{nickname}")
      rippleaddr = account[:rippleaddr]
      coins = @@coinids.inject({}) do |v, coinid|
        rpc = getrpc(coinid.to_s)
        addr = nil
        begin
          addr = getaddress(rpc, accountid)
          addr = '' unless addr
        rescue
        end
        v[coinid] = {
          :addr => addr,
          :symbol => @@config['coins'][coinid.to_s]['symbol'],
          :name => @@config['coins'][coinid.to_s]['name'],
          :iou => @@config['coins'][coinid.to_s]['iou'],
          :electrum => @@config['coins'][coinid.to_s]['electrum'],
        }
        v
      end
      slim :index, :locals => {
        :accountid => accountid,
        :nickname => nickname,
        :coins => coins,
        :coinids => @@coinids,
        :rippleaddr => rippleaddr,
        :rippleiou => @@config['ripple']['account_id'],
        :ripplefaucet => @@config['ripple']['faucet']['account_id'],
        :message => message,
        :prices => prices,
        :ledger => ledger,
      }
    end
  end

  get '/newaddr' do
    accountid = session[:accountid]
    redirect '/' unless accountid
    coinid = params['coinid']
    rpc = getrpc(coinid.to_s)
    raise if rpc.getaddressesbyaccount(accountid).size > 0
    rpc.getnewaddress(accountid)
    redirect "/#/#{coinid}"
  end

  get '/profile' do
    accountid = session[:accountid]
    unless accountid
      redirect '/'
    else
      account = @@redis.getm(accountid)
      coins = account[:coins] || {}
      nickname = account[:nickname]
      slim :profile, :locals => {
        :accountid => accountid,
        :nickname => nickname,
        :locale => account[:locale],
        :locales => @@locales,
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
      account[:locale] = params['locale']
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
      if checkrippleaddress(rippleaddr)
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
    minconf = getminconf(coinid)
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    rpc = getrpc(coinid)
    addr = getaddress(rpc, accountid) rescue nil
    slim :deposit, :locals => {
      :nickname => nickname,
      :coinid => coinid,
      :minconf => minconf,
      :addr => addr,
    }
  end

  get '/withdraw' do
    accountid = session[:accountid]
    unless accountid
      redirect '/'
    else
      coinid = params['coinid']
      coinconf = @@config['coins'][coinid]
      fee = coinconf['fee'] || 0.1
      balance = params['balance'].to_f
      account = @@redis.getm(accountid)
      nickname = account[:nickname]
      coins = account[:coins] || {}
      coin = coins[coinid.to_sym] || {}
      payoutto = coin[:payoutto]
      csrftoken = accountid # TODO
      slim :withdraw, :locals => {
        :accountid => accountid,
        :nickname => nickname,
        :coinid => coinid,
        :payoutto => payoutto,
        :symbol => @@config['coins'][coinid]['symbol'],
        :balance => balance,
        :fee => fee,
        :csrftoken => csrftoken,
      }
    end
  end

  post '/withdraw' do
    accountid = session[:accountid]
    redirect '/' unless accountid
    csrftoken = accountid # TODO
    if params['csrftoken'] != csrftoken
      session[:message] = 'Invalid CSRF Token'
      redirect '/'
    end
    lastwithdrawid = "lastwithdraw:#{accountid}"
    lastwithdrawtime = @@redis.getm(lastwithdrawid) || 0
    now = Time.now.to_i
    amount = params['amount'].to_f
    coinid = params['coinid']
    coinconf = @@config['coins'][coinid]
    fee = coinconf['fee'] || 0.1
    maxamount = fee * 20000 # TODO
    withdrawlocktime = amount * 5 * 60 / maxamount # TODO
    if lastwithdrawtime + withdrawlocktime > now
      session[:message] = 'Withdraw locked. Please wait for a while.'
      redirect '/'
    end
    message = 'Success'
    rpc = getrpc(coinid)
    payoutto = params['payoutto']
    if checkaddress(rpc, payoutto)
      if amount > maxamount
        message = 'Too large: %.4f' % maxamount
      elsif amount > fee * 2
        begin
          @@mutex.lock
          minconf = getminconf(coinid)
          minconf *= 2 if amount * 4 > maxamount # TODO
          balance = rpc.getbalance(accountid, minconf)
          if balance < amount + fee
            message = 'Low Balance'
          else
            clearcache(coinid, accountid)
            moveto = 'income'
            rpc.move(accountid, moveto, amount + fee, getminconf(coinid))
            rpc.sendfrom(moveto, payoutto, amount, getminconf(coinid))
            @@redis.setm(lastwithdrawid, now)
          end
        ensure
          @@mutex.unlock
        end
      else
        message = 'Less than %.4f' % (fee * 2)
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
    slim :history, :locals => {
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
    slim :donate, :locals => {
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
      begin
        @@mutex.lock
        balance = rpc.getbalance(accountid, getminconf(coinid))
        if balance > amount
          faucetid = 'faucet'
          clearcache(coinid, accountid)
          rpc.move(accountid, faucetid, amount, getminconf(coinid))
        end
      ensure
        @@mutex.unlock
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
      balance = rpc.getbalance(faucetid, getminconf(coinid))
      amount = [balance * 0.01, 0.01].max
      now = Time.now.to_i
      faucetlocktime = 23 * 60 * 60
      nexttime = faucettime + faucetlocktime - now
      if amount < 0.01 || balance < amount || nexttime > 0
        amount = 0
      else
        clearcache(coinid, accountid)
        result = rpc.move(faucetid, accountid, amount, getminconf(coinid))
        @@redis.setm(faucettimeid, now)
        amount = 0 unless result
      end
    ensure
      @@mutex.unlock
    end
    slim :faucet, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => coinid,
      :amount => amount,
      :balance => balance,
      :symbol => @@config['coins'][coinid]['symbol'],
      :nexttime => nexttime,
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
    reserve = 30000000 # 20 XRP + 0.01 XRP * 1000 times tx
    if result['status'] == 'success'
      balance = result['account_data']['Balance'].to_i - reserve
    else
      balance = 0
    end
    amount = 100000 # 0.1 XRP
    now = Time.now.to_i
    faucetlocktime = 23 * 60 * 60
    nexttime = faucettime + faucetlocktime - now
    if rippleaddr.nil? || rippleaddr.empty? ||
        !checkrippleaddress(rippleaddr) || balance < amount || nexttime > 0
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
          'fee_mult_max' => 1000, # TODO 0.01 XRP?
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
    slim :faucet, :locals => {
      :accountid => accountid,
      :nickname => nickname,
      :coinid => 'ripple',
      :amount => amount / 1000000.0,
      :balance => balance / 1000000.0,
      :symbol => 'XRP',
      :nexttime => nexttime,
    }
  end

  get '/coin2iou' do
    balance = params['balance'].to_f
    accountid = session[:accountid]
    account = @@redis.getm(accountid)
    nickname = account[:nickname]
    slim :coin2iou, :locals => {
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
    unless checkrippleaddress(rippleaddr)
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
        'fee_mult_max' => 1000, # TODO 0.01 XRP?
        'secret' => rrpc.masterseed,
      }
      rpc = getrpc(coinid)
      balance = rpc.getbalance(accountid, getminconf(coinid))
      amount = amountstr.to_f
      fee = coin['fee'] || 0.1
logger.info("coin2iou debug: amount = #{amount}, fee = #{fee}")
      message = 'lowbalance'
      if balance >= amount + fee
        result = rrpc.submit(rpcparams)
logger.info("coin2iou debug: message = #{message}")
        message = result['status']
logger.info("coin2iou debug: result[status] = #{result['status']}")
        if result['status'] == 'success'
          iouid = 'iou'
          clearcache(coinid, accountid)
logger.info("coin2iou debug: move")
          rpc.move(accountid, iouid, amount, getminconf(coinid))
logger.info("coin2iou debug: moved")
          moveto = 'income'
logger.info("coin2iou debug: fee = #{fee}")
          rpc.move(accountid, moveto, fee, getminconf(coinid))
logger.info("coin2iou debug: moved 2")
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
    slim :iou2coin, :locals => {
      :nickname => nickname,
      :coins => @@config['coins'],
      :coinid => params['coinid'],
    }
  end

  get '/iou2coin' do
    # TODO views/iou2coin.slim
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

  def self.setdebug(v)
    @@debug = v
  end

end
