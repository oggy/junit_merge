$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'junit_merge/version'

Gem::Specification.new do |gem|
  gem.name          = 'junit_merge'
  gem.version       = JunitMerge::VERSION
  gem.authors       = ['George Ogata']
  gem.email         = ['george.ogata@gmail.com']
  gem.description   = "Tool to merge JUnit XML reports."
  gem.summary       = ""
  gem.homepage      = 'https://github.com/oggy/junit_merge'

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")

  gem.add_runtime_dependency 'nokogiri', '>= 1.5', '< 2.0'
  gem.add_development_dependency 'ritual', '~> 0.4'
end
