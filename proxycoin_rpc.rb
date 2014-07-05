class ProxycoinRPC
  def initialize(btcrpc)
    @btcrpc = btcrpc
    @coinid = 'sha1coin' # TODO
    @redis = Redis.new
  end
  def getbalance(accountid = nil, confirms = nil)
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
p [:proxy_move, accountid, moveto, amount]
    # TODO rpc.move(accountid, moveto, amount)
    raise
  end
  def sendfrom(moveto, payoutto, amount)
p [:proxy_sendfrom, moveto, payoutto, amount]
    # TODO rpc.sendfrom(moveto, payoutto, amount)
    raise
  end
  def listtransactions(accountid)
    # TODO rpc.listtransactions(accountid)
    []
  end
end
