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
$fromon = ARGV.join(' ')
$fromon_idx = $fromon.to_i if $fromon.match?(/^\d+$/)
$within = ARGV.length == 0
$testing_dump_file = '/tmp/harp_trainer_dumped_for_testing.json'
$data_dir = "#{Dir.home}/.harp_trainer"
$all_testing_licks = %w(juke special blues mape one two)
system("sox -n /tmp/harp_trainer_testing.wav synth 40.0 sawtooth 494")

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do
  
  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
  FileUtils.cp_r 'config/richter', 'config/testing'
  
  print "Testing"

  do_test 'usage screen' do
    new_session
    tms './harp_trainer'
    tms :ENTER
    sleep 2
    expect { screen[-6].start_with? 'Suggested reading' }
    kill_session
  end
  
  %w(a c).each do |key|
    do_test "auto-calibration key of #{key}" do
      sound 8, 2
      new_session
      tms "./harp_trainer calib testing #{key} --auto --testing"
      tms :ENTER
      tms 'y'
      sleep 10
      expect { screen[-4] == 'Recordings done.' }
      kill_session
    end
  end

  do_test 'manual calibration' do
    sound 1, -14
    new_session
    tms './harp_trainer calib testing g --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    sleep 2
    tms 'r'
    sleep 10
    expect { screen[-4] == 'Frequency: 195, ET: 196, diff: -1   -1st:185 [.......I:........] +1st:208' }
    kill_session
  end
  
  do_test 'manual calibration summary' do
    sound 1, -14
    new_session
    tms './harp_trainer calib testing a --testing'
    tms :ENTER
    sleep 2
    tms 's'
    sleep 4
    expect { screen[9] == '       -10   |     1482 |     1480 |      2 |      2 | ........I........' }
    kill_session
  end

  do_test 'manual calibration starting at hole' do
    sound 1, -14
    new_session
    tms './harp_trainer calib testing a --hole +4 --testing'
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
  
  do_test 'check against et' do
    sound 1, 10
    new_session
    tms './harp_trainer calib testing c --hole +4 --testing'
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

  do_test 'listen' do
    sound 8, 2
    journal_file = "#{$data_dir}/journal_listen.txt"
    FileUtils.rm journal_file if File.exist?(journal_file)
    new_session
    tms './harp_trainer listen testing a all --testing'
    tms :ENTER
    sleep 4
    tms 'j'
    sleep 1
    expect { File.exist?(journal_file) }
    expect { screen[12]['b4'] }
    kill_session
  end
  
  do_test 'change key of harp' do
    new_session
    tms './harp_trainer listen testing a all --testing'
    tms :ENTER
    sleep 2
    tms 'k'
    sleep 1
    tms 'c'
    tms :ENTER
    sleep 1
    expect { screen[1]['listen testing c all'] }
    kill_session
  end

  do_test 'listen with merged scale' do
    sound 8, 2
    new_session
    tms './harp_trainer listen testing a blues --merge chord-v,chord-i --testing'
    tms :ENTER
    sleep 4
    expect { screen[12]['blues,chord-v,chord-i;root'] }
    kill_session
  end

  do_test 'listen with removed scale' do
    sound 8, 2
    new_session
    tms './harp_trainer listen testing a all --remove drawbends --testing'
    tms :ENTER
    sleep 4
    tst_out = read_testing_output
    expect { tst_out[:scale_holes] == ['+1','-1','+2','-2+3','-3','+4','-4','+5','-5','+6','-6','-7','+7','-8','+8/','+8','-9','+9/','+9','-10','+10//','+10/','+10'] }
    kill_session
  end
  
  do_test 'memorize to create simple lick file' do
    lick_dir = "#{$data_dir}/licks/testing"
    lick_file = "#{lick_dir}/licks_with_holes.txt"
    FileUtils.rm_r lick_dir if File.exist?(lick_dir)
    new_session
    tms './harp_trainer memo testing a --testing'
    tms :ENTER
    sleep 2
    expect { File.exist?(lick_file) }
    expect { screen[10]['does not exist'] }
    kill_session
  end

  do_test 'quiz' do
    sound 8, 3
    new_session
    tms './harp_trainer quiz 2 testing c all --testing'
    tms :ENTER
    sleep 8
    expect { screen[12]['c5'] }
    kill_session
  end
  
  do_test 'transpose scale does work on zero shift' do
    new_session
    tms './harp_trainer listen testing a blues --transpose_scale_to c'
    tms :ENTER
    sleep 2
    expect { screen[0]['Play notes from the scale to get green'] }
    kill_session
  end
  
  do_test 'transpose scale works on non-zero shift' do
    new_session
    tms './harp_trainer listen testing a blues --transpose_scale_to g --testing'
    tms :ENTER
    sleep 2
    tst_out = read_testing_output
    expect { tst_out[:scale_holes] == ['-2+3','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
    kill_session
  end

  do_test 'transpose scale not working in some cases' do
    new_session
    tms './harp_trainer listen testing a blues --transpose_scale_to b'
    tms :ENTER
    sleep 2
    expect { screen[7]['ERROR: Transposing scale blues from key of c to b results in hole -2+3'] }
    kill_session
  end
  
  do_test 'play a lick' do
    new_session
    tms './harp_trainer play testing a mape --testing'
    tms :ENTER
    sleep 4
    expect { screen[7]['-1 +2 -2+3'] }
    kill_session
  end
  
  do_test 'play a lick with recording' do
    new_session
    tms './harp_trainer play testing a juke --testing'
    tms :ENTER
    sleep 4
    expect { screen[7]['Lick juke,samples,favorites'] }
    expect { screen[8]['-1 -2/ -3// -3 -4'] }
    kill_session
  end
  
  do_test 'play some holes and notes' do
    new_session
    tms './harp_trainer play testing a -1 a5 +4 --testing'
    tms :ENTER
    sleep 2
    expect { screen[7]['-1 +7 +4'] }
    kill_session
  end
  
  do_test 'memorize with lick file from previous test' do
    new_session
    tms './harp_trainer memo testing a --testing'
    tms :ENTER
    sleep 12
    tst_out = read_testing_output
    expect { tst_out[:licks].length == 6 }
    expect { screen[1]['Mode: memorize testing a all'] }
    kill_session
  end

  do_test 'memorize with licks with tags' do
    new_session
    tms './harp_trainer memo testing --tags favorites,testing a --testing'
    tms :ENTER
    sleep 2
    tst_out = read_testing_output
    # Six licks in file, four in those two sections, but two of them are identical
    expect { tst_out[:licks].length == 3 }
    kill_session
  end

  do_test 'memorize with licks excluding one tag' do
    new_session
    tms './harp_trainer memo testing --no-tags scales a --testing'
    tms :ENTER
    sleep 2
    tst_out = read_testing_output
    # Seven licks in file minus one scale with two licks minus one double
    expect { tst_out[:licks].length == 4 }
    kill_session
  end

  do_test 'error on unknown --tags' do
    new_session
    tms './harp_trainer memo testing --tags unknown a --testing'
    tms :ENTER
    sleep 2
    expect { screen[7]['ERROR: There are some tags'] }
    kill_session
  end

  do_test 'memorize with --start-with' do
    new_session
    tms './harp_trainer memo testing --start-with juke a --testing'
    tms :ENTER
    sleep 2
    expect { screen[-2]['(juke)'] }
    kill_session
  end

  do_test 'print list of tags' do
    new_session
    tms './harp_trainer memo testing --tags print'
    tms :ENTER
    sleep 2
    # Six licks in file, four in those two sections, but two of them are identical
    expect { screen[-6]['Total number of licks:               7'] }
    kill_session
  end

  do_test 'print list of licks' do
    new_session
    tms './harp_trainer play testing print'
    tms :ENTER
    sleep 2
    $all_testing_licks.each_with_index do |txt,idx|
      expect { screen[8+idx][txt]}
    end
    kill_session
  end

  do_test 'iterate through holes' do
    new_session
    tms './harp_trainer memo testing --start-with iterate --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    expect { screen[-2][$all_testing_licks[0]] }
    sleep 4
    tms :ENTER
    expect { screen[-2][$all_testing_licks[1]] }
    sleep 6
    tms :ENTER
    expect { screen[-2][$all_testing_licks[2]] }
    kill_session
  end

  do_test 'iterate through holes from starting point' do
    new_session
    tms './harp_trainer memo testing --start-with special,iter --testing'
    tms :ENTER
    sleep 4
    tms :ENTER
    expect { screen[-2]['special'] }
    sleep 4
    tms :ENTER
    expect { screen[-2]['blues'] }
    kill_session
  end

  do_test 'back one lick' do
    new_session
    tms './harp_trainer memo testing --start-with juke --testing'
    tms :ENTER
    sleep 4
    expect { screen[-2]['juke'] }
    tms :ENTER
    sleep 4
    expect { !screen[-2]['juke'] }
    tms :BSPACE
    sleep 4
    expect { screen[-2]['juke'] }
    kill_session
  end

  do_test 'use option --partial' do
    new_session
    tms './harp_trainer memo testing --start-with juke --partial 1@b --testing'
    tms :ENTER
    sleep 2
    # Six licks in file, four in those two sections, but two of them are identical
    expect { screen[1]['partial: 1@b'] }
    kill_session
  end

  do_test 'use option --partial and --holes' do
    new_session
    tms './harp_trainer memo testing --start-with juke --holes --partial 1@b --testing'
    tms :ENTER
    sleep 2
    # Six licks in file, four in those two sections, but two of them are identical
    expect { screen[1]['partial: 1@b'] }
    kill_session
  end

end
FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
puts "\ndone.\n\n"
