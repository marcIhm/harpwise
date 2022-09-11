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
require 'tmpdir'
require 'sys/proctable'
require_relative 'test_utils.rb'

$dotdir_state_unknown = true
# needed in config.rb but not initialized there
$early_conf = Hash.new

$fromon = ARGV.join(' ')
$fromon_cnt = $fromon.to_i if $fromon.match?(/^\d+$/)
$fromon_id_regex = '^(id-[a-z0-9]+):'
if md = ($fromon + ':').match(/#{$fromon_id_regex}/)
  $fromon_id = md[1]
end
$within = ARGV.length == 0
$testing_dump_template = '/tmp/harpwise_testing_dumped_%s.json'
$testing_output_file = '/tmp/harpwise_testing_output.txt'
$testing_log_file = '/tmp/harpwise_testing.log'
$all_testing_licks = %w(juke special blues mape one two three long)
$pipeline_started = '/tmp/harpwise_pipeline_started'
$installdir = "#{Dir.home}/harpwise"
$dotdir = "#{Dir.home}/.harpwise"
$dotdir_saved = "#{Dir.home}/dot_harpwise_saved"
$config_ini = $dotdir + '/config.ini'
check_dotdir_state

Dir.chdir(%x(git rev-parse --show-toplevel).chomp)
# get termsize
File.readlines('config/config.ini').each do |line|
  $term_min_width ||= line.match(/^\s*term_min_width\s*=\s*(\d*?)\s*$/)&.to_a&.at(1)
  $term_min_height ||= line.match(/^\s*term_min_height\s*=\s*(\d*?)\s*$/)&.to_a&.at(1)
end
fail "Could not parse term size from config/config.ini" unless $term_min_width && $term_min_height

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
    usage_examples << l if l.start_with?('harpwise ')
  end
end
usage_examples.map {|l| l.gsub!('\\','')}
# remove known false positives
known_not = ['supports the daily','chrom a major_pentatonic','harpwise play d juke','report chromatic licks -t fav']
usage_examples.reject! {|l| known_not.any? {|kn| l[kn]}}
# replace some, e.g. due to my different set of licks
repl = {'harpwise play c juke' => 'harpwise play c easy'}
usage_examples.map! {|l| repl[l] || l}
# check count, so that we may not break our detection of usage examples unknowingly
num_exp = 25
fail "Unexpected number of examples #{usage_examples.length} instead of #{num_exp}:\n#{usage_examples}" unless usage_examples.length == num_exp

puts "\nPreparing data"
# individual tests may generate their own
system("sox -n /tmp/harpwise_testing.wav synth 200.0 sawtooth 494")
FileUtils.mv '/tmp/harpwise_testing.wav', '/tmp/harpwise_testing.wav_default'
# on error we tend to leave aubiopitch behind
system("killall aubiopitch >/dev/null 2>&1")
[['config/richter', 'config/testing'],
 ['config/chromatic', 'config/testing2']].each do |from, to|
  FileUtils.rm_r to if File.directory?(to)
  FileUtils.cp_r from, to
end

print "Testing"

do_test 'id-01: start without .harpwise' do
  move_dotdir
  new_session
  tms 'harpwise'
  tms :ENTER
  sleep 2
  expect {File.directory?($dotdir) && File.exist?($config_ini)}
  kill_session
  restore_dotdir
end

do_test 'id-01a: config.ini, user prevails' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [any-mode]
    key = a    
  end_of_content
  new_session
  # any invocation would be okay too
  tms 'harpwise report journal --testing'
  tms :ENTER
  sleep 2
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:key] == 'c' }
  expect(dump[:conf_user]) { dump[:conf_user][:any_mode][:key] == 'a' }
  expect(dump[:key]) { dump[:conf][:key] == 'a' }
  kill_session
  restore_dotdir
end

do_test 'id-01b: config.ini, mode prevails' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    key = a    
  end_of_content
  new_session
  tms 'harpwise quiz 3 blues --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:key] == 'c' }
  expect(dump[:conf_system]) { dump[:conf_system][:key] == nil }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:key] == 'a' }
  expect(dump[:key]) { dump[:conf][:key] == 'a' }
  kill_session
  restore_dotdir
end

do_test 'id-01c: config.ini, set loop (example for boolean)' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    loop = true
  end_of_content
  new_session
  tms 'harpwise quiz 3 blues --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:loop] == false }
  expect(dump[:conf_system]) { dump[:conf_system][:loop] == nil }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:loop] == true }
  expect(dump[:conf]) { dump[:conf][:loop] == true }
  kill_session
  restore_dotdir
end

do_test 'id-01d: config.ini, unset loop with option' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    loop = true
  end_of_content
  new_session
  tms 'harpwise quiz 3 blues --no-loop --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:loop] == false }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:loop] == true }
  expect(dump[:opts]) { dump[:opts][:loop] == false }
  kill_session
  restore_dotdir
end

do_test 'id-01e: config.ini, take default key from config' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    key = a
  end_of_content
  new_session
  tms 'harpwise quiz 3 blues --no-loop --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:key]) { dump[:key] == 'a' }
  kill_session
  restore_dotdir
end

do_test 'id-01f: config.ini, take key from commandline' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    key = c
  end_of_content
  new_session
  tms 'harpwise listen testing a blues --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:key]) { dump[:key] == 'a' }
  kill_session
  restore_dotdir
end

do_test 'id-01g: config.ini, set value in config and clear again on commandline' do
  backup_dotdir
  File.write $config_ini, <<~end_of_content
  [quiz]
    add_scales = major_pentatonic
  end_of_content
  new_session
  tms 'harpwise quiz 3 blues --no-loop --add-scales - --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:opts]) { dump[:opts][:add_scales] == nil }
  kill_session
  restore_dotdir
end

usage_types.keys.each_with_index do |mode, idx|
  do_test "id-u%02d: usage screen mode #{mode}" % idx do
    new_session
    tms "harpwise #{usage_types[mode][1]}"
    tms :ENTER
    sleep 2
    expect_usage = { 'none' => [-12, 'Suggested reading'],
                     'calibrate' => [-8, 'start with calibration'],
                     'listen' => [-8, 'your milage may vary'],
                     'quiz' => [-8, 'your milage may vary'],
                     'licks' => [-8, 'plays nothing initially'],
                     'play' => [-8, 'this number of holes'],
                     'report' => [-6, 'on every invocation']}
    
    expect(mode, expect_usage[mode]) { screen[expect_usage[mode][0]][expect_usage[mode][1]] }
    kill_session
  end
end

%w(a c).each_with_index do |key,idx|
  do_test "id-g#{idx}: auto-calibration key of #{key}" do
    new_session
    tms "harpwise calib testing #{key} --auto --testing"
    tms :ENTER
    sleep 1
    tms 'y'
    wait_for_end_of_harpwise
    expect { screen[-4]['Recordings done.'] }
    kill_session
  end
end

do_test 'id-02: manual calibration' do
  sound 10, -14
  new_session
  tms 'harpwise calib testing g --testing'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  tms 'r'
  sleep 16
  expect { screen[-4]['Frequency: 195, ET: 196, diff: -1   -1st:185 [.......I:........] +1st:208'] }
  kill_session
end

do_test 'id-03: manual calibration summary' do
  new_session
  tms 'harpwise calib testing a --testing'
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
  tms 'harpwise calib testing a --hole +4 --testing'
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
  tms 'harpwise calib testing c --hole +4 --testing'
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
  journal_file = "#{$dotdir}/journal_mode_listen.txt"
  FileUtils.rm journal_file if File.exist?(journal_file)
  new_session
  tms 'harpwise listen testing a all --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'j'
  sleep 1
  expect { screen[12]['b4'] }
  expect { File.exist?(journal_file) }
  kill_session
end

do_test 'id-06a: listen and change display and comment' do
  sound 20, 2
  new_session
  tms 'harpwise listen testing a all --ref +2 --testing'
  tms :ENTER
  wait_for_start_of_pipeline
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

do_test 'id-07: change key of harp' do
  new_session
  tms 'harpwise listen testing a all --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'k'
  sleep 1
  tms 'c'
  tms :ENTER
  sleep 1
  expect { screen[1]['listen testing c all'] }
  kill_session
end

do_test 'id-08: listen with merged scale' do
  new_session
  tms 'harpwise listen testing a blues --add-scales chord-v,chord-i --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['blues,5,1,all'] }
  kill_session
end

do_test 'id-09: listen with removed scale' do
  new_session
  tms 'harpwise listen testing a all --remove drawbends --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect { dump[:scale_holes] == ['+1','-1','+2','-2','-3','+4','-4','+5','-5','+6','-6','-7','+7','-8','+8/','+8','-9','+9/','+9','-10','+10//','+10/','+10'] }
  kill_session
end

do_test 'id-09a: error on ambigous option' do
  new_session
  tms 'harpwise listen testing a all --r drawbends --testing'
  tms :ENTER
  sleep 1
  expect { screen[2]['ERROR: Argument'] }
  kill_session
end

do_test 'id-0a: mode licks to create simple lick file' do
  lick_dir = "#{$dotdir}/licks/testing"
  lick_file = "#{lick_dir}/licks_with_holes.txt"
  FileUtils.rm_r lick_dir if File.exist?(lick_dir)
  new_session
  tms 'harpwise licks testing a --testing'
  tms :ENTER
  sleep 2
  expect { screen[6]['does not exist'] }
  expect { File.exist?(lick_file) }
  kill_session
end

do_test 'id-10: quiz' do
  sound 12, 3
  new_session
  tms 'harpwise quiz 2 testing c all --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[12]['c5'] }
  kill_session
end

do_test 'id-10a: quiz' do
  sound 20, 2
  new_session
  tms 'harpwise quiz 2 testing c all --ref +2 --testing'
  tms :ENTER
  wait_for_start_of_pipeline
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

do_test 'id-11: transpose scale works on zero shift' do
  new_session
  tms 'harpwise listen testing a blues --transpose-scale-to c --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[0]['Play notes from the scale to get green'] }
  kill_session
end

do_test 'id-12: transpose scale works on non-zero shift' do
  new_session
  tms 'harpwise listen testing a blues --transpose-scale-to g --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect { dump[:scale_holes] == ['-2','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
  kill_session
end

do_test 'id-13: transpose scale not working in some cases' do
  new_session
  tms 'harpwise listen testing a blues --transpose-scale-to b'
  tms :ENTER
  sleep 2
  expect { screen[2]['ERROR: Transposing scale blues from key of c to b results in hole -2'] }
  kill_session
end

do_test 'id-14: play a lick' do
  new_session
  tms 'harpwise play testing a mape --testing'
  tms :ENTER
  sleep 2
  expect { screen[4]['-1 +2 -2'] }
  kill_session
end

do_test 'id-14a: check lick processing on tags.add and desc.add' do
  new_session
  tms 'harpwise play testing a mape --testing'
  tms :ENTER
  wait_for_end_of_harpwise
  dump = read_testing_dump('start')
  # use 'one' twice to make index match name
  licks = %w(one one two three).map do |lname| 
    dump[:licks].find {|l| l[:name] == lname} 
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
  journal_file = "#{$dotdir}/journal_modes_licks_and_play.txt"
  FileUtils.rm journal_file if File.exist?(journal_file)
  new_session
  tms 'harpwise play testing a juke --testing'
  tms :ENTER
  sleep 2
  expect { screen[3]['Lick juke'] }
  expect { screen[4]['-1 -2/ -3// -3 -4'] }
  expect { File.exist?(journal_file) }
  kill_session
end

do_test 'id-15a: check journal from previous invocation of play' do
  new_session
  tms 'harpwise report testing jour --testing'
  tms :ENTER
  sleep 2
  expect { screen[9][' l: juke'] }
  kill_session
end

do_test 'id-16: play some holes and notes' do
  new_session
  tms 'harpwise play testing a -1 a5 +4 --testing'
  tms :ENTER
  sleep 2
  expect { screen[3]['-1 +7 +4'] }
  kill_session
end

do_test 'id-16a: error on mixing licks and notes for play' do
  new_session
  tms 'harpwise play testing a -1 juke --testing'
  tms :ENTER
  sleep 1
  expect { screen[3]['but ONLY ONE OF THEM'] }
  kill_session
end

do_test 'id-16b: cycle in play' do
  new_session
  tms 'harpwise play testing a cycle --testing'
  tms :ENTER
  sleep 2
  expect { screen[3]['Lick juke'] }
  tms :ENTER
  sleep 2
  expect { screen[12]['Lick special'] }
  kill_session
end

do_test 'id-17: mode licks with lick file from previous test' do
  new_session
  tms 'harpwise licks testing a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect { dump[:licks].length == 8 }
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
  new_session
  tms 'harpwise licks testing --tags-any favorites,testing a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect { dump[:licks].length == 4 }
  kill_session
end

do_test 'id-18a: mode licks with licks with tags_all' do
  new_session
  tms 'harpwise licks testing --tags-all scales,theory a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect { dump[:licks].length == 1 }
  kill_session
end

do_test 'id-19: mode licks with licks excluding one tag' do
  new_session
  tms 'harpwise licks testing --no-tags-any scales a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect { dump[:licks].length == 6 }
  kill_session
end

do_test 'id-1a: error on unknown --tags' do
  new_session
  tms 'harpwise licks testing --tags-any unknown a --testing'
  tms :ENTER
  sleep 2
  expect { screen[2]['ERROR: Among tags ["unknown"] in option --tags-any, there are some'] }
  kill_session
end

do_test 'id-1b: mode licks with --start-with' do
  new_session
  tms 'harpwise licks testing --start-with juke a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['juke | favorites,samples'] }
  expect { screen[-1]['a classic lick by Little Walter'] }
  kill_session
end

do_test 'id-1c: print list of tags' do
  new_session
  tms 'harpwise report testing --tags-any favorites licks'
  tms :ENTER
  sleep 2
  # Six licks in file, four in those two sections, but two of them are identical
  expect { screen[7]['Total number of licks:               8'] }
  expect { screen[-3]['3 ... 86'] }
  kill_session
end

do_test 'id-1d: print list of licks' do
  new_session
  tms "harpwise report testing licks --testing >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  $all_testing_licks.each_with_index do |txt,idx|
    # last two licks are printed on the same line
    expect { lines[10+idx][txt]}
  end
  kill_session
end

do_test 'id-1e: iterate through licks' do
  new_session
  tms 'harpwise licks testing --start-with iterate --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2][$all_testing_licks[0]] }
  tms :ENTER
  sleep 4
  expect { screen[-2][$all_testing_licks[1]] }
  tms :ENTER
  sleep 4
  expect { screen[-1][$all_testing_licks[2]] }
  tms :ENTER
  kill_session
end

do_test 'id-1f: cycle through licks' do
  new_session
  tms 'harpwise licks testing --start-with cycle --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  (0 .. $all_testing_licks.length + 2).to_a.each do |i|
    lickname = $all_testing_licks[i % $all_testing_licks.length]
    expect(4,[lickname,i]) { screen[-1][lickname] || screen[-2][lickname] }
    tms :ENTER
    sleep 4
  end
  kill_session
end

do_test 'id-1g: iterate from one lick through to end' do
  new_session
  tms 'harpwise licks testing --start-with special,iter --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['special'] }
  tms :ENTER
  sleep 4
  expect { screen[-1]['blues'] }
  (0 .. $all_testing_licks.length + 2).to_a.each do |i|
    tms :ENTER
    sleep 4
  end
  expect { screen[-8]['Iterated through licks'] }
  kill_session
end

do_test 'id-1h: cycle through licks from starting point' do
  new_session
  tms 'harpwise licks testing --start-with special,cycle --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  (0 .. $all_testing_licks.length + 2).to_a.each do |i|
    lickname = $all_testing_licks[(i + 1) % $all_testing_licks.length]
    expect(4,[lickname,i]) { screen[-1][lickname] || screen[-2][lickname] }
    tms :ENTER
    sleep 4
  end
  kill_session
end

do_test 'id-20: back one lick' do
  new_session
  tms 'harpwise licks testing --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
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
  new_session
  tms 'harpwise licks testing --start-with juke --partial 1@b --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect { tlog[-1]['play -q -V1 ' + Dir.home + '/.harpwise/licks/testing/recordings/juke.mp3 -t alsa trim 2.2 1.0'] }
  kill_session
end

do_test 'id-21a: use option --partial' do
  new_session
  tms 'harpwise licks testing --start-with juke --partial 1@b --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect { tlog[-1]['play -q -V1 ' + Dir.home + '/.harpwise/licks/testing/recordings/juke.mp3 -t alsa trim 2.2 1.0'] }
  kill_session
end

do_test 'id-22: use option --partial and --holes' do
  new_session
  tms 'harpwise licks testing --start-with juke --holes --partial 1@b --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect { tlog[-1]['["-1", "-2/", "-3//", "-3", "-4", "-4"]'] }
  kill_session
end

do_test 'id-23: display as chart with scales' do
  new_session
  tms 'harpwise listen testing blues:b --add-scales chord-i:1 --display chart-scales --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[8]['b1   b1    1   b1    b    b    1   b1    b    b'] }
  kill_session
end

do_test 'id-23a: error with double shortname for scales' do
  new_session
  tms 'harpwise listen testing blues:b --add-scales chord-i:b --display chart-scales --testing'
  tms :ENTER
  sleep 2
  expect { screen[3]['ERROR: Shortname \'b\' has already been used'] }
  kill_session
end

do_test 'id-24: comment with scales and octave shifts' do
  new_session
  tms 'harpwise licks testing blues:b --add-scales chord-i:1 --comment holes-scales --testing --start-with juke'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[15]['-1.b1   -2/.    -3//.      -3.1     -4.b1    -4.b1'] }
  tms '>'
  sleep 2
  expect { screen[15]['*-4.b1  -6.b   -7.1   -8.b1  -8.b1'] }
  tms '<'
  sleep 2
  tms '<'
  sleep 2
  expect { screen[15]['-1.b1  -1.b1'] }
  kill_session
end

do_test 'id-25: comment with all holes' do
  new_session
  tms 'harpwise lic testing blues:b --add-scales chord-i:1 --comment holes-all --testing --start-with juke'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[16]['  ▄▄▖▌   ▄▄▖▗▘ ▞   ▄▄▖▄▘ ▞ ▞   ▄▄▖▄▘  ▄▄▖▚▄▌  ▄▄▖▚▄▌'] }
  kill_session
end

do_test 'id-26: display as chart with intervals' do
  new_session
  tms 'harpwise licks testing blues --display chart-intervals --comment holes-intervals --ref -2 --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['pF   3st  REF  5st  9st  Oct'] }
  expect { screen[15]['*-1.Ton   -2/.mT   -3//.3st'] }
  kill_session
end

do_test 'id-26a: display as chart with notes' do
  new_session
  tms 'harpwise licks testing blues --display chart-intervals --comment holes-notes --ref -2 --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['pF   3st  REF  5st  9st  Oct'] }
  expect { screen[15]['*-1.d4    -2/.gf4  -3//.a4     -3.b4     -4.d5     -4.d5'] }
  kill_session
end

do_test 'id-27: change lick by name' do
  new_session
  tms 'harpwise lick testing blues --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['juke'] }
  tms 'n'
  tms 'special'
  tms :ENTER
  sleep 2
  expect { screen[-2]['special'] }
  kill_session
end

do_test 'id-27a: change first of options --tags' do
  new_session
  tms 'harpwise lick testing blues --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 't'
  tms 'favorites'
  tms :ENTER
  tms 'q'
  sleep 1
  dump = read_testing_dump('end')
  expect(dump[:opts]) { dump[:opts][:tags_any] == 'favorites'}
  kill_session
end

do_test 'id-27b: change one of four of options --tags' do
  new_session
  tms 'harpwise lick testing blues --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['licks(8)'] }
  tms 'T'
  tms '2'
  tms :ENTER
  tms 'favorites,iter'
  tms :ENTER
  tms 'q'
  sleep 1
  dump = read_testing_dump('end')
  expect(dump[:opts]) { dump[:opts][:tags_all] == 'favorites'}
  kill_session
end

do_test 'id-27c: change partial' do
  new_session
  tms 'harpwise lick testing blues --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tms '@'
  tms '1@e'
  tms :ENTER
  sleep 1
  tms 'q'
  sleep 1
  dump = read_testing_dump('end')
  expect { dump[:opts][:partial] == '1@e' }
  kill_session
end

do_test 'id-28: error on ambigous mode' do
  new_session
  tms 'harpwise li testing blues --testing'
  tms :ENTER
  sleep 2
  expect { screen[2]['argument can be one of'] }
  kill_session
end

do_test 'id-29: error on mode memorize' do
  new_session
  tms 'harpwise memo testing blues --testing'
  tms :ENTER
  sleep 2
  expect { screen[2]['Mode \'memorize\' is now \'licks\''] }
  kill_session
end

do_test 'id-30: handling a very long lick' do
  new_session
  tms 'harpwise lick testing blues --start-with long --testing --comment holes-all'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-8]['  ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▗▘  ▄▄▖▗▘'] }
  20.times {
    tms '1'
  }
  expect { screen[-8]['  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▚▄▌  ▄▄▖▚▄▌  ▄▄▖▚▄▌  ▄▄▖▚▄▌'] }
  tms 'c'
  tms '1'
  sleep 1
  expect { screen[-5]['-4.b15  *-4.b15   -4.b15   -5.b'] }
  kill_session
end

do_test 'id-31: abbreviated scale' do
  new_session
  tms 'harpwise licks testing bl --testing'
  tms :ENTER
  wait_for_start_of_pipeline
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

do_test 'id-32: error on journal in play' do
  new_session
  tms 'harpwise play testing journal --testing'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[16]['ERROR'] }
  kill_session
end

do_test 'id-33: error on print in licks' do
  new_session
  tms 'harpwise licks testing --tags-any print --testing'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[2]['ERROR'] }
  kill_session
end

do_test 'id-34: switch between modes' do
  new_session
  tms 'harpwise licks testing a --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['licks'] }
  tms 'm'
  sleep 4
  expect { screen[1]['listen'] }
  tms 'm'
  sleep 4
  expect { screen[1]['licks'] }
  kill_session
end

do_test 'id-35: star a lick' do
  starred_file = Dir.home + '/.harpwise/licks/testing/starred.yaml'
  FileUtils.rm starred_file if File.exist?(starred_file)  
  new_session
  tms 'harpwise licks testing a --start-with juke --testing'
  tms :ENTER
  wait_for_start_of_pipeline
  tms '*'
  sleep 1
  tms 'q'
  sleep 1
  kill_session
  expect { File.exist?(starred_file) }
end

do_test 'id-36: show lick starred in previous invocation' do
  new_session
  tms 'harpwise report testing starred'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[4]['juke:    1'] }
  kill_session
end

do_test "id-37: chromatic; auto-calibration key of a" do
  new_session
  tms "harpwise calib testing2 a --auto --testing"
  tms :ENTER
  sleep 1
  tms 'y'
  wait_for_end_of_harpwise
  expect { screen[-4]['Recordings done.'] }
  kill_session
end

do_test 'id-38: chromatic; listen' do
  sound 8, 2
  new_session 92, 30
  tms 'harpwise listen testing2 a all --testing --add-scales - --display chart-notes'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['a3   df4    e4    a4    a4   df5'] }
  kill_session
end

FileUtils.rm_r 'config/testing' if File.directory?("#{$installdir}/config/testing")
system("killall aubiopitch >/dev/null 2>&1")
puts "\ndone.\n\n"
