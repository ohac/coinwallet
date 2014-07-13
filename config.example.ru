$LOAD_PATH.unshift File.dirname(__FILE__)
require 's'
#\ --port 4568
#\ --bind 0.0.0.0
use Rack::Session::Cookie, :key => 'my_app_key',
                           :path => '/',
                           :expire_after => 60, # In seconds
                           :secret => 'secret_stuff'
WebWallet::setdebug(true)
run WebWallet
