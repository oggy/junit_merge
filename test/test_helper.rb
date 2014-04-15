ROOT = File.expand_path('..', File.dirname(__FILE__))
$:.unshift "#{ROOT}/lib"

require 'junit_merge'
require 'minitest/spec'
require 'temporaries'
require 'byebug'
require 'looksee'
