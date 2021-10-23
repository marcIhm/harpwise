#!/usr/bin/ruby

#
# run all tests
#

require 'set'
require 'yaml'
require 'fileutils'
require 'open3'
require 'sourcify'
require_relative '../lib/config.rb'
require_relative '../lib/interaction.rb'
require_relative '../lib/helper.rb'
require_relative 'test_utils.rb'

$sut = load_technical_config

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do

  
  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing'
  FileUtils.cp_r 'config/richter', 'config/testing'

  
  puts "\nTesting usage screen"
  new_session
  tms './harp_scale_trainer'
  tms :ENTER
  sleep 1
  expect { it[-3].start_with? 'Suggested reading' }


  puts "\nTesting auto-calibration"
  sound 8, 2
  new_session
  tms './harp_scale_trainer calib testing --auto --testing'
  tms :ENTER
  tms :ENTER
  sleep 4
  expect { it[-4] == 'All recordings done.' }


  puts "\nTesting manual calibration"
  sound 1, 2
  new_session
  tms './harp_scale_trainer calib testing --testing'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  tms 'r'
  sleep 6
  expect { it[-7] == 'Frequency: 494' }


  puts "\nTesting listen"
  sound 8, 2
  new_session
  tms './harp_scale_trainer listen testing all --testing'
  tms :ENTER
  sleep 4
  expect { it[-16].end_with? 'b4' }
  

  puts "\nTesting quiz"
  sound 8, 3
  new_session
  tms './harp_scale_trainer quiz 2 testing all --testing'
  tms :ENTER
  sleep 4
  expect { it[-16].end_with? 'c5' }

  
end
puts
