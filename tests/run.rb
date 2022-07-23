#!/usr/bin/ruby
# coding: utf-8

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
$fromon_cnt = $fromon.to_i if $fromon.match?(/^\d+$/)
$fromon_id_regex = '^(id-[a-z0-9]+):'
if md = ($fromon + ':').match(/#{$fromon_id_regex}/)
  $fromon_id = md[1]
end
$within = ARGV.length == 0
$testing_dump_file = '/tmp/harpwise_dumped_for_testing.json'
$testing_output_file = '/tmp/harpwise_output_for_testing.txt'
$testing_log_file = '/tmp/harpwise_testing.log'
$data_dir = "#{Dir.home}/.harpwise"
$all_testing_licks = %w(juke special blues mape one two)


Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do

  #
  # Collect usage examples and later check, that none of them produces string error
  #
  usage_types = [nil, :calibrate, :listen, :quiz, :licks, :play, :report].map do |t|
    [(t || :none).to_s,
     ['usage' + ( t  ?  '_' + t.to_s  :  '' ), t.to_s]]
  end.to_h
  usage_examples = []

  usage_types.values.map {|p| p[0]}.each do |fname|
    File.read("resources/#{fname}.txt").lines.map(&:strip).each do |l|
      usage_examples[-1] += ' ' + l if (usage_examples[-1] || '')[-1] == '\\'
      usage_examples << l if l.start_with?('harpwise ') || l.start_with?('./harpwise ')
    end
  end
  usage_examples.map {|l| l.gsub!('\\','')}
  # remove known false positives
  known_not = ['supports the daily','chrom a major_pentatonic','harpwise play d juke','report chromatic licks -t fav']
  usage_examples.reject! {|l| known_not.any? {|kn| l[kn]}}
  # replace some, e.g. due to my different set of licks
  repl = {'./harpwise play c juke' => './harpwise play c easy'}
  usage_examples.map! {|l| repl[l] || l}
  # check count, so that we may not break our detection of usage examples unknowingly
  num_exp = 21
  fail "Unexpected number of examples #{usage_examples.length} instead of #{num_exp}:\n#{usage_examples}" unless usage_examples.length == num_exp
  
  puts "\nPreparing data"
  # point 3 of a delicate balance for tests
  system("sox -n /tmp/harpwise_testing.wav synth 200.0 sawtooth 494")
  # on error we tend to leave aubiopitch benind
  system("killall aubiopitch >/dev/null 2>&1")
  FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
  FileUtils.cp_r 'config/richter', 'config/testing'
  
  print "Testing"

  #
  # How to assign ids: either any two uniq hex-digits for tests not in a loop
  # or any letter from 'g' on for a series of numbered tests
  #


  usage_types.keys.each_with_index do |mode, idx|
    do_test "id-u%02d: usage screen mode #{mode}" % idx do
      new_session
      tms "./harpwise #{usage_types[mode][1]}"
      tms :ENTER
      sleep 2
      expect_usage = { 'none' => [-12, 'Suggested reading'],
                       'calibrate' => [-3, 'start with calibration'],
                       'listen' => [-3, 'your milage may vary'],
                       'quiz' => [-3, 'your milage may vary'],
                       'licks' => [-3, 'plays nothing initially'],
                       'play' => [-3, 'this number of holes'],
                       'report' => [2, 'Show what you have played recently']}
      
      expect { screen[expect_usage[mode][0]][expect_usage[mode][1]] }
      kill_session
    end
  end
  
  %w(a c).each_with_index do |key,idx|
    do_test "id-g#{idx}: auto-calibration key of #{key}" do
      sound 8, 2
      new_session
      tms "./harpwise calib testing #{key} --auto --testing"
      tms :ENTER
      sleep 1
      tms 'y'
      sleep 10
      expect { screen[-4]['Recordings done.'] }
      kill_session
    end
  end

  do_test 'id-02: manual calibration' do
    sound 1, -14
    new_session
    tms './harpwise calib testing g --testing'
    tms :ENTER
    sleep 2
    tms :ENTER
    sleep 2
    tms 'r'
    sleep 10
    expect { screen[-4]['Frequency: 195, ET: 196, diff: -1   -1st:185 [.......I:........] +1st:208'] }
    kill_session
  end

  do_test 'id-03: manual calibration summary' do
    sound 1, -14
    new_session
    tms './harpwise calib testing a --testing'
    tms :ENTER
    sleep 2
    tms 's'
    sleep 4
    expect { screen[9]['       -10   |     1482 |     1480 |      2 |      2 | ........I........'] }
    kill_session
  end

  do_test 'id-04: manual calibration starting at hole' do
    sound 1, -14
    new_session
    tms './harpwise calib testing a --hole +4 --testing'
    tms :ENTER
    sleep 2
    tms 'y'
    sleep 2
    tms 'y'
    sleep 2
    tms 'r'
    sleep 8
    expect { screen[-15]['The frequency recorded for -4/ (note bf4, semi 1) is too different from ET'] }
    expect { screen[-11]['  Difference:             -271.2'] }
    kill_session
  end
  
  do_test 'id-05: check against et' do
    sound 1, 10
    new_session
    tms './harpwise calib testing c --hole +4 --testing'
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

  do_test 'id-06: listen' do
    sound 8, 2
    journal_file = "#{$data_dir}/journal_listen.txt"
    FileUtils.rm journal_file if File.exist?(journal_file)
    new_session
    tms './harpwise listen testing a all --testing'
    tms :ENTER
    sleep 4
    tms 'j'
    sleep 1
    expect { screen[12]['b4'] }
    expect { File.exist?(journal_file) }
    kill_session
  end
  
  do_test 'id-06a: listen and change display and comment' do
    sound 20, 2
    new_session
    tms './harpwise listen testing a all --ref +2 --testing'
    tms :ENTER
    sleep 6
    # just cycle (more than once) through display and comments without errors
    8.times do
      tms 'd'
      tms 'c'
    end
    sleep 1
    tms 'q'
    sleep 2
    expect { screen[-3]['Terminating on user request'] }
    kill_session
  end
  
  do_test 'id-07: change key of harp' do
    new_session
    tms './harpwise listen testing a all --testing'
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

  do_test 'id-08: listen with merged scale' do
    sound 8, 2
    new_session
    tms './harpwise listen testing a blues --add-scales chord-v,chord-i --testing'
    tms :ENTER
    sleep 4
    expect { screen[12]['blues,chord-v,chord-i,root'] }
    kill_session
  end

  do_test 'id-09: listen with removed scale' do
    sound 8, 2
    clear_testing_dump
    new_session
    tms './harpwise listen testing a all --remove drawbends --testing'
    tms :ENTER
    sleep 4
    tst_dump = read_testing_dump
    expect { tst_dump[:scale_holes] == ['+1','-1','+2','-2+3','-3','+4','-4','+5','-5','+6','-6','-7','+7','-8','+8/','+8','-9','+9/','+9','-10','+10//','+10/','+10'] }
    kill_session
  end
  
  do_test 'id-09a: error on ambigous option' do
    new_session
    tms './harpwise listen testing a all --r drawbends --testing'
    tms :ENTER
    sleep 1
    expect { screen[4]['ERROR: Argument'] }
    kill_session
  end
  
  do_test 'id-0a: mode licks to create simple lick file' do
    lick_dir = "#{$data_dir}/licks/testing"
    lick_file = "#{lick_dir}/licks_with_holes.txt"
    FileUtils.rm_r lick_dir if File.exist?(lick_dir)
    new_session
    tms './harpwise licks testing a --testing'
    tms :ENTER
    sleep 2
    expect { File.exist?(lick_file) }
    expect { screen[7]['does not exist'] }
    kill_session
  end

  do_test 'id-10: quiz' do
    sound 8, 3
    new_session
    tms './harpwise quiz 2 testing c all --testing'
    tms :ENTER
    sleep 4
    expect { screen[12]['c5'] }
    kill_session
  end
  
  do_test 'id-10a: quiz' do
    sound 20, 2
    new_session
    tms './harpwise quiz 2 testing c all --ref +2 --testing'
    tms :ENTER
    sleep 6
    # just cycle (more than once) through display and comments without errors
    8.times do
      tms 'd'
      tms 'c'
    end
    sleep 1
    tms 'q'
    sleep 1
    expect { screen[-3]['Terminating on user request'] }
    kill_session
  end
  
  do_test 'id-11: transpose scale does work on zero shift' do
    new_session
    tms './harpwise listen testing a blues --transpose_scale_to c'
    tms :ENTER
    sleep 2
    expect { screen[0]['Play notes from the scale to get green'] }
    kill_session
  end
  
  do_test 'id-12: transpose scale works on non-zero shift' do
    clear_testing_dump
    new_session
    tms './harpwise listen testing a blues --transpose_scale_to g --testing'
    tms :ENTER
    sleep 2
    tst_dump = read_testing_dump
    expect { tst_dump[:scale_holes] == ['-2+3','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
    kill_session
  end

  do_test 'id-13: transpose scale not working in some cases' do
    new_session
    tms './harpwise listen testing a blues --transpose_scale_to b'
    tms :ENTER
    sleep 2
    expect { screen[4]['ERROR: Transposing scale blues from key of c to b results in hole -2+3'] }
    kill_session
  end
  
  do_test 'id-14: play a lick' do
    new_session
    tms './harpwise play testing a mape --testing'
    tms :ENTER
    sleep 4
    expect { screen[5]['-1 +2 -2+3'] }
    kill_session
  end
  
  do_test 'id-14a: check lick processing on tags.add and desc.add' do
    clear_testing_dump
    new_session
    tms './harpwise play testing a mape --testing'
    tms :ENTER
    sleep 4
    tst_dump = read_testing_dump
    # use 'one' twice to make index match name
    licks = %w(one one two three).map do |lname| 
      tst_dump[:licks].find {|l| l[:name] == lname} 
    end
    expect { licks[1][:tags] == %w(testing x) }
    expect { licks[2][:tags] == %w(y) }
    expect { licks[3][:tags] == %w(testing z) }
    expect { licks[1][:desc] == 'a b' }
    expect { licks[2][:desc] == 'c b' }
    expect { licks[3][:desc] == 'a d' }
    kill_session
  end
  
  do_test 'id-15: play a lick with recording' do
    journal_file = "#{$data_dir}/journal_licks_play.txt"
    FileUtils.rm journal_file if File.exist?(journal_file)
    new_session
    tms './harpwise play testing a juke --testing'
    tms :ENTER
    sleep 4
    expect { screen[4]['Lick juke'] }
    expect { screen[5]['-1 -2/ -3// -3 -4'] }
    expect { File.exist?(journal_file) }
    kill_session
  end
  
  do_test 'id-15a: check history from previous invocation of play' do
    new_session
    tms './harpwise report testing hist --testing'
    tms :ENTER
    sleep 4
    expect { screen[10][' l: juke'] }
    kill_session
  end
  
  do_test 'id-16: play some holes and notes' do
    new_session
    tms './harpwise play testing a -1 a5 +4 --testing'
    tms :ENTER
    sleep 2
    expect { screen[5]['-1 +7 +4'] }
    kill_session
  end
  
  do_test 'id-16a: error on mixing licks and notes for play' do
    new_session
    tms './harpwise play testing a -1 juke --testing'
    tms :ENTER
    sleep 2
    expect { screen[4]['but ONLY ONE OF THEM'] }
    kill_session
  end
  
  do_test 'id-16b: cycle in play' do
    new_session
    tms './harpwise play testing a cycle --testing'
    tms :ENTER
    sleep 2
    expect { screen[4]['Lick juke'] }
    tms :ENTER
    sleep 2
    expect { screen[13]['Lick special'] }
    kill_session
  end
  
  do_test 'id-17: mode licks with lick file from previous test' do
    clear_testing_dump
    new_session
    tms './harpwise licks testing a --testing'
    tms :ENTER
    sleep 12
    tst_dump = read_testing_dump
    expect { tst_dump[:licks].length == 8 }
    expect { screen[1]['licks(8) testing a all'] }
    kill_session
  end

#  Licks with their tags:
#
#  juke ..... favorites,samples
#  special ..... advanced,samples
#  blues ..... scales,theory
#  mape ..... scales
#  one ..... testing,x
#  two ..... x,y
#  three ..... testing,z
#  long ..... testing,x
#
#  Total number of licks:   8
  
  do_test 'id-18: mode licks with licks with tags_any' do
    clear_testing_dump
    new_session
    tms './harpwise licks testing --tags-any favorites,testing a --testing'
    tms :ENTER
    sleep 2
    tst_dump = read_testing_dump
    # See comments above for verification
    expect { tst_dump[:licks].length == 4 }
    kill_session
  end
  
  do_test 'id-18a: mode licks with licks with tags_all' do
    clear_testing_dump
    new_session
    tms './harpwise licks testing --tags-all scales,theory a --testing'
    tms :ENTER
    sleep 2
    tst_dump = read_testing_dump
    # See comments above for verification
    expect { tst_dump[:licks].length == 1 }
    kill_session
  end

  do_test 'id-19: mode licks with licks excluding one tag' do
    clear_testing_dump
    new_session
    tms './harpwise licks testing --no-tags-any scales a --testing'
    tms :ENTER
    sleep 2
    tst_dump = read_testing_dump
    # See comments above for verification
    expect { tst_dump[:licks].length == 6 }
    kill_session
  end

  do_test 'id-1a: error on unknown --tags' do
    new_session
    tms './harpwise licks testing --tags-any unknown a --testing'
    tms :ENTER
    sleep 2
    expect { screen[4]['ERROR: There are some tags'] }
    kill_session
  end

  do_test 'id-1b: mode licks with --start-with' do
    new_session
    tms './harpwise licks testing --start-with juke a --testing'
    tms :ENTER
    sleep 8
    expect { screen[-2]['juke | favorites,samples | Hint: Play -1'] }
    expect { screen[-1]['a classic lick by Little Walter'] }
    kill_session
  end

  do_test 'id-1c: print list of tags' do
    new_session
    tms './harpwise report testing --tags-any favorites licks'
    tms :ENTER
    sleep 2
    # Six licks in file, four in those two sections, but two of them are identical
    expect { screen[7]['Total number of licks:               8'] }
    expect { screen[-3]['3 ... 86'] }
    kill_session
  end

  do_test 'id-1d: print list of licks' do
    new_session
    tms "./harpwise report testing licks >#{$testing_output_file}"
    tms :ENTER
    sleep 2
    lines = File.read($testing_output_file).lines
    $all_testing_licks.each_with_index do |txt,idx|
      # last two licks are printed on the same line
      expect { lines[10+idx][txt]}
    end
    kill_session
  end

  do_test 'id-1e: iterate through holes' do
    new_session
    tms './harpwise licks testing --start-with iterate --testing'
    tms :ENTER
    sleep 4
    expect { screen[-2][$all_testing_licks[0]] }
    tms :ENTER
    sleep 4
    expect { screen[-2][$all_testing_licks[1]] }
    tms :ENTER
    sleep 6
    expect { screen[-1][$all_testing_licks[2]] }
    tms :ENTER
    kill_session
  end

  do_test 'id-1f: iterate through holes from starting point' do
    new_session
    tms './harpwise licks testing --start-with special,iter --testing'
    tms :ENTER
    sleep 4
    expect { screen[-2]['special'] }
    tms :ENTER
    sleep 6
    expect { screen[-1]['blues'] }
    tms :ENTER
    kill_session
  end

  do_test 'id-20: back one lick' do
    new_session
    tms './harpwise licks testing --start-with juke --testing'
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

  do_test 'id-21: use option --partial' do
    clear_testing_log
    new_session
    tms './harpwise licks testing --start-with juke --partial 1@b --testing'
    tms :ENTER
    sleep 2
    tlog = read_testing_log
    expect { tlog[-1]['play -q -V1 /home/ihm/.harpwise/licks/testing/recordings/juke.mp3 -t alsa trim 2.2 1.0'] }
    kill_session
  end

  do_test 'id-21a: use option --partial at end' do
    clear_testing_log
    new_session
    tms './harpwise licks testing --start-with juke --partial 1/2@e --testing'
    tms :ENTER
    sleep 2
    tlog = read_testing_log
    #
    # Without option --partial, the cmd would be (as the recording
    # itself has start and length):
    #
    #   play -q -V1 /home/ihm/.harpwise/licks/testing/recordings/juke.mp3 -t alsa trim 2.2 4
    #
    expect { tlog[-1]['play -q -V1 /home/ihm/.harpwise/licks/testing/recordings/juke.mp3 -t alsa trim 4.2 2.0'] }
    kill_session
  end

  do_test 'id-22: use option --partial and --holes' do
    clear_testing_log
    new_session
    tms './harpwise licks testing --start-with juke --holes --partial 1@b --testing'
    tms :ENTER
    sleep 2
    tlog = read_testing_log
    expect { tlog[-1]['["-1", "-2/", "-3//", "-3", "-4", "-4"]'] }
    kill_session
  end

  do_test 'id-23: display as chart with scales' do
    new_session
    tms './harpwise listen testing blues:b --add-scales chord-i:1 --display chart-scales --testing'
    tms :ENTER
    sleep 2
    expect { screen[8]['b1   b1    1   b1    b    b    1   b1    b    b'] }
    kill_session
  end

  do_test 'id-23a: error with double shortname for scales' do
    new_session
    tms './harpwise listen testing blues:b --add-scales chord-i:b --display chart-scales --testing'
    tms :ENTER
    sleep 2
    expect { screen[4]['ERROR: Shortname \'b\' has already been used'] }
    kill_session
  end

  do_test 'id-24: comment with scales' do
    new_session
    tms './harpwise licks testing blues:b --add-scales chord-i:1 --comment holes-scales --testing --start-with juke'
    tms :ENTER
    sleep 2
    expect { screen[15]['-1.b1   -2/.    -3//.      -3.1     -4.b1    -4.b1'] }
    kill_session
  end

  do_test 'id-25: comment with all holes' do
    new_session
    tms './harpwise lic testing blues:b --add-scales chord-i:1 --comment holes-all --testing --start-with juke'
    tms :ENTER
    sleep 2
    expect { screen[16]['  ▄▖▜   ▄▖▄▌▐   ▄▖▄▌▐ ▐   ▄▖▄▌  ▄▖▙▌  ▄▖▙▌'] }
    kill_session
  end

  do_test 'id-26: display as chart with intervals' do
    new_session
    tms './harpwise licks testing blues --display chart-intervals --comment holes-intervals --ref -2+3 --start-with juke --testing'
    tms :ENTER
    sleep 4
    expect { screen[4]['pF   3st  REF  5st  9st  Oct'] }
    expect { screen[15]['*-1.Ton   -2/.mT   -3//.3st'] }
    kill_session
  end

  do_test 'id-27: change lick by name' do
    new_session
    tms './harpwise lick testing blues --start-with juke --testing'
    tms :ENTER
    sleep 2
    expect { screen[-2]['juke'] }
    tms 'n'
    tms 'special'
    tms :ENTER
    sleep 2
    expect { screen[-2]['special'] }
    kill_session
  end

  do_test 'id-27a: change tags' do
    new_session
    tms './harpwise lick testing blues --start-with juke --testing'
    tms :ENTER
    sleep 2
    expect { screen[1]['licks(8)'] }
    tms 't'
    tms '1'
    tms :ENTER
    tms 'favorites,iter'
    tms :ENTER
    sleep 1
    expect { screen[1]['licks(1)'] }
    kill_session
  end

  do_test 'id-28: error on ambigous mode' do
    new_session
    tms './harpwise li testing blues'
    tms :ENTER
    sleep 2
    expect { screen[3]['argument can be one of'] }
    kill_session
  end
  
  do_test 'id-29: error on mode memorize' do
    new_session
    tms './harpwise memo testing blues'
    tms :ENTER
    sleep 2
    expect { screen[3]['Mode \'memorize\' is now \'licks\''] }
    kill_session
  end
  
  do_test 'id-30: handling a very long lick' do
    new_session
    tms './harpwise lick testing blues --start-with long --testing --comment holes-all'
    tms :ENTER
    sleep 2
    20.times {
      tms '1'
    }
    expect { screen[-8]['  ▄▖▄▌  ▄▖▄▌  ▄▖▄▌  ▄▖▄▌  ▄▖▄▌  ▄▖▄▌  ▄▖▄▌  ▄▖▙▌  ▄▖▙▌'] }
    tms 'c'
    sleep 1
    expect { screen[-6]['-3.     -4.b    -4.b'] }
    expect { screen[-5]['-5.b    -5.b    -5.b    -5.b'] }
    kill_session
  end

  do_test 'id-31: abbreviated scale' do
    new_session
    tms './harpwise licks testing bl --testing'
    tms :ENTER
    sleep 3
    expect { screen[1]['blues'] }
    kill_session
  end

  usage_examples.each_with_index do |ex,idx|
    do_test "id-e%02d: usage #{ex}" % idx do
      new_session
      tms ex + ' --testing'
      tms :ENTER
      sleep 1
      expect { screen.select {|l| l.downcase['error']}.length == 0 }
      kill_session
    end
  end

  do_test 'id-32: error on history in play' do
    new_session
    tms './harpwise play testing hist --testing'
    tms :ENTER
    sleep 2
    expect { screen[16]['ERROR'] }
    kill_session
  end
  
  do_test 'id-33: error on print in licks' do
    new_session
    tms './harpwise licks testing --tags-any print'
    tms :ENTER
    sleep 2
    expect { screen[3]['ERROR'] }
    kill_session
  end
  
  
end
FileUtils.rm_r 'config/testing' if File.directory?('config/testing')
system("killall aubiopitch >/dev/null 2>&1")
puts "\ndone.\n\n"
