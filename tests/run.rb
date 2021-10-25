#!/usr/bin/ruby

#
# run all tests
#

require 'set'
require 'yaml'
require 'fileutils'
require 'open3'
require 'sourcify'
require 'json'
require_relative '../lib/config.rb'
require_relative '../lib/interaction.rb'
require_relative '../lib/helper.rb'
require_relative 'test_utils.rb'

$sut = load_technical_config

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do
  
  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing'
  FileUtils.cp_r 'config/richter', 'config/testing'
  
  puts "Testing"
  timer 'usage screen' do
    new_session
    tms './harp_scale_trainer'
    tms :ENTER
    sleep 1
    expect { screen[-5].start_with? 'Suggested reading' }
  end

  
  %w(a c).each do |key|
    timer "auto-calibration key of #{key}" do
      sound 8, 2
      new_session
      tms "./harp_scale_trainer calib testing #{key} --auto --testing"
      tms :ENTER
      tms :ENTER
      sleep 4
      expect { screen[-4] == 'All recordings done.' }
    end
  end


  timer 'manual calibration' do
    sound 1, 2
    new_session
    tms './harp_scale_trainer calib testing c --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    sleep 2
    tms 'r'
    sleep 6
    expect { screen[-7] == 'Frequency: 494' }
  end
  

  timer 'listen' do
    sound 8, 2
    new_session
    tms './harp_scale_trainer listen testing a all --testing'
    tms :ENTER
    sleep 4
    expect { screen[-16].end_with? 'b4' }
  end
  

  timer 'quiz' do
    sound 8, 3
    new_session
    tms './harp_scale_trainer quiz 2 testing c all --testing'
    tms :ENTER
    sleep 4
    expect { screen[-16].end_with? 'c5' }
  end
    
  
  timer 'Testing transpose_scale_not_working' do
    new_session
    tms './harp_scale_trainer listen testing a blues --transpose_scale_to g'
    tms :ENTER
    sleep 1
    expect { screen[8]['Maybe choose another value for --transpose_scale_to'] }
  end
  
end
puts "done.\n\n"
