#!/usr/bin/ruby
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'rubygems'
require 'redis'

`wget -q https://check.torproject.org/exit-addresses -O exit-addresses`
text = File.open('exit-addresses', 'rb'){|fd| fd.read}
addrs = text.split("\n").map do |line|
  next unless /^ExitAddress / === line
  line.split[1]
end
addrs = addrs.compact.uniq

`wget -q https://www.dan.me.uk/torlist/ -O torlist`
text = File.open('torlist', 'rb'){|fd| fd.read}
addrs2 = text.split("\n").map do |line|
  line.chomp
end
addrs2 = addrs2.uniq

alladdrs = (addrs + addrs2).uniq.join(',')

redis = Redis.new
redis.set('torlist', alladdrs)
