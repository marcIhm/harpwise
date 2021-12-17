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
$fromon = ARGV[0]
$within = !$fromon

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do
  
  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
  FileUtils.cp_r 'config/richter', 'config/testing'
  
  print "Testing"
  memorize 'usage screen' do
    new_session
    tms './harp_scale_trainer'
    tms :ENTER
    sleep 2
    expect { screen[-6].start_with? 'Suggested reading' }
    kill_session
  end

  
  %w(a c).each do |key|
    memorize "auto-calibration key of #{key}" do
      sound 8, 2
      new_session
      tms "./harp_scale_trainer calib testing #{key} --auto --testing"
      tms :ENTER
      tms 'y'
      sleep 10
      expect { screen[-4] == 'Recordings done.' }
      kill_session
    end
  end


  memorize 'manual calibration' do
    sound 1, -14
    new_session
    tms './harp_scale_trainer calib testing g --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    sleep 2
    tms 'r'
    sleep 10
    expect { screen[-4] == 'Frequency: 195, ET: 196, diff: -1   -1st:185 [.......I:........] +1st:208' }
    kill_session
  end
  

  memorize 'manual calibration summary' do
    sound 1, -14
    new_session
    tms './harp_scale_trainer calib testing a --testing'
    tms :ENTER
    sleep 2
    tms 's'
    sleep 4
    expect { screen[-12] == '       -10   |     1482 |     1480 |      2 |' }
    kill_session
  end
  

  memorize 'manual calibration starting at hole' do
    sound 1, -14
    new_session
    tms './harp_scale_trainer calib testing a --hole +4 --testing'
    tms :ENTER
    sleep 2
    tms 'y'
    sleep 2
    tms 'y'
    sleep 2
    tms 'r'
    sleep 8
    expect { screen[-15] == 'The frequency recorded for -4/ (note bf4, semi 1) is too different from ET' }
    expect { screen[-11] == '  Difference:             -271.2' }
    kill_session
  end
  

  memorize 'check against et' do
    sound 1, 10
    new_session
    tms './harp_scale_trainer calib testing c --hole +4 --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    sleep 2
    tms 'r'
    sleep 10
    expect { screen[-13,2] == ['  You played:             784',
                             '  ET expects:             523.3']}
    kill_session
  end
  

  memorize 'listen' do
    sound 8, 2
    journal_file = "#{Dir.home}/.harp_scale_trainer/journal.txt"
    FileUtils.rm journal_file if File.exist?(journal_file)
    new_session
    tms './harp_scale_trainer listen testing a all --testing'
    tms :ENTER
    sleep 4
    tms 'j'
    sleep 1
    expect { File.exist?(journal_file) }
    expect { screen[12]['b4'] }
    kill_session
  end
  

  memorize 'quiz' do
    sound 8, 3
    new_session
    tms './harp_scale_trainer quiz 2 testing c all --testing'
    tms :ENTER
    sleep 8
    expect { screen[12]['c5'] }
    kill_session
  end
    
  
  memorize 'Testing transpose_scale_not_working' do
    new_session
    tms './harp_scale_trainer listen testing a blues --transpose_scale_to g'
    tms :ENTER
    sleep 1
    expect { screen[6]['ERROR: Transposing scale blues to g results in hole -6/, note c6 (semi = 15'] }
    kill_session
  end
  
end
FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
puts "\ndone.\n\n"
