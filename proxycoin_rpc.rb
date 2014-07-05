class ProxycoinRPC
  def initialize(btcrpc, coinid)
    @btcrpc = btcrpc
    @coinid = coinid
    @redis = Redis.new
  end

  def getbalance(accountid = nil, confirms = nil)
    @btcrpc.getgenerate # check online
    return @btcrpc.getbalance unless accountid
p [:proxy_getbalance, accountid, confirms]
    balancename = "proxycoind:balance:#{@coinid}:#{accountid}"
    balance = @redis.get(balancename) || 0
    # TODO check confirms
p balance.to_f
    balance.to_f
  end

  def getaddressesbyaccount(accountid)
p [:proxy_getaddressesbyaccount, accountid]
    @btcrpc.getaddressesbyaccount(accountid)
  end

  def getnewaddress(accountid)
p [:proxy_getnewaddress, accountid]
    @btcrpc.getnewaddress(accountid)
  end

  def validateaddress(addr)
p [:proxy_validateaddress, addr]
    @btcrpc.validateaddress(addr)
  end

  def move(accountid, moveto, amount)
    @btcrpc.getgenerate # check online
p [:proxy_move, accountid, moveto, amount]
    balancename = "proxycoind:balance:#{@coinid}:#{accountid}"
    @redis.setnx(balancename, 0.0)
    @redis.incrbyfloat(balancename, -amount)
    balancename = "proxycoind:balance:#{@coinid}:#{moveto}"
    @redis.setnx(balancename, 0.0)
    @redis.incrbyfloat(balancename, amount)
    @btcrpc.move(accountid, moveto, amount) # TODO
  end

  def sendfrom(accountid, payoutto, amount)
    @btcrpc.getgenerate # check online
p [:proxy_sendfrom, accountid, payoutto, amount]
    balancename = "proxycoind:balance:#{@coinid}:#{accountid}"
    @redis.setnx(balancename, 0.0)
    @redis.incrbyfloat(balancename, -amount)
    @btcrpc.sendfrom(accountid, payoutto, amount) # TODO
  end

  def listtransactions(accountid)
    @btcrpc.listtransactions(accountid) # TODO
  end
end
