#!/usr/bin/ruby

#
# run all tests
#

require 'set'
require 'yaml'
require 'fileutils'
require 'open3'
require_relative '../lib/config.rb'
require_relative '../lib/interaction.rb'
require_relative '../lib/helper.rb'
require_relative 'test_utils.rb'

$sut = load_technical_config

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do

  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing'
  FileUtils.cp_r 'config/richter', 'config/testing'
  sys "sox -n tmp/testing.wav synth 8 sawtooth %2 gain -n -3"

  puts "\nTesting usage screen"
  $sname = 'usage'
  new_session
  sys "#{$tmsl} './harp_scale_trainer'"
  sys "#{$tms} ENTER"
  sleep 1
  expect kill_session[-3].split[0], 'Suggested'

  puts "\nTesting auto-calibration"
  $sname = 'calib'
  new_session
  sys "#{$tmsl} './harp_scale_trainer calib testing --auto --testing'"
  sys "#{$tms} ENTER"
  sys "#{$tms} ENTER"
  sleep 4
  expect kill_session[-4], 'All recordings done.'

  puts "\nTesting listen"
  $sname = 'listen'
  new_session
  sys "#{$tmsl} './harp_scale_trainer listen testing all --testing'"
  sys "#{$tms} ENTER"
  sleep 4
  expect kill_session[-16].split[-1], 'b4'

  puts "\nTesting quiz"
  sys "sox -n tmp/testing.wav synth 8 sawtooth %3 gain -n -3"
  $sname = 'listen'
  new_session
  sys "#{$tmsl} './harp_scale_trainer quiz 2 testing all --testing'"
  sys "#{$tms} ENTER"
  sleep 4
  expect kill_session[-16].split[-1], 'c5'

end
puts
