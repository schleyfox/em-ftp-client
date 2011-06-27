# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "em-ftp-client/version"

Gem::Specification.new do |s|
  s.name        = "em-ftp-client"
  s.version     = Em::Ftp::Client::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ben Hughes"]
  s.email       = ["ben@pixelmachine.org"]
  s.homepage    = ""
  s.summary     = %q{EventMachine FTP client}
  s.description = %q{An FTP client designed to work well with EventMachine}

  s.rubyforge_project = "em-ftp-client"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]


  s.add_dependency('eventmachine')

  s.add_development_dependency('shoulda')
  s.add_development_dependency('mocha')
  s.add_development_dependency('redgreen')
end
