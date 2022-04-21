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
$testing_dump_file = '/tmp/harp_scale_trainer_dumped_for_testing.json'

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
    expect { screen[9] == '       -10   |     1482 |     1480 |      2 |      2 | ........I........' }
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
    journal_file = "#{Dir.home}/journal_listen.txt"
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
  

  memorize 'listen with merged scale' do
    sound 8, 2
    new_session
    tms './harp_scale_trainer listen testing a blues --merge chord-v,chord-i --testing'
    tms :ENTER
    sleep 4
    expect { screen[12]['(blues,chord-v,chord-i) root'] }
    kill_session
  end
  

  memorize 'listen with removed scale' do
    sound 8, 2
    new_session
    tms './harp_scale_trainer listen testing a all --remove drawbends --testing'
    tms :ENTER
    sleep 4
    tst_out = read_testing_output
    expect { tst_out[:scale_holes] == ['+1','-1','+2','-2+3','-3','+4','-4','+5','-5','+6','-6','-7','+7','-8','+8','-9','+9','-10','+10'] }
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
    
  
  memorize 'Testing transpose scale does work on zero shift' do
    new_session
    tms './harp_scale_trainer listen testing a blues --transpose_scale_to c'
    tms :ENTER
    sleep 2
    expect { screen[0]['Play notes from the scale to get green'] }
    kill_session
  end

  
  memorize 'Testing transpose scale works on non-zero shift' do
    new_session
    tms './harp_scale_trainer listen testing a blues --transpose_scale_to g --testing'
    tms :ENTER
    sleep 2
    tst_out = read_testing_output
    expect { tst_out[:scale_holes] == ['-2+3','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
    kill_session
  end

  
  memorize 'Testing transpose scale not working in some cases' do
    new_session
    tms './harp_scale_trainer listen testing a blues --transpose_scale_to b'
    tms :ENTER
    sleep 2
    expect { screen[7]['ERROR: Transposing scale blues from key of c to b results in hole -2+3'] }
    kill_session
  end
  
  memorize 'Testing play for a scale' do
    new_session
    tms './harp_scale_trainer play testing a blues'
    tms :ENTER
    sleep 2
    expect { screen[7]['-1'] }
    kill_session
  end
  
  memorize 'Testing play for some holes' do
    new_session
    tms './harp_scale_trainer play testing a +1 -1'
    tms :ENTER
    sleep 2
    expect { screen[7]['-1'] }
    kill_session
  end
  
end
FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
puts "\ndone.\n\n"
