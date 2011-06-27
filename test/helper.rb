require 'rubygems'
require 'bundler/setup'

require File.join(File.dirname(__FILE__), "..", "lib", "em-ftp-client")

require 'test/unit'
require 'mocha'
require 'shoulda'
require 'redgreen' unless '1.9'.respond_to?(:force_encoding)
