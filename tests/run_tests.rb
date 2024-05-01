#!/usr/bin/ruby
# coding: utf-8

#
# run all tests
#

require 'set'
require 'yaml'
require 'fileutils'
require 'open3'
require 'json'
require 'tmpdir'
require 'method_source'
require_relative 'test_utils.rb'

#
# Set vars
#
$fromon = ARGV.join(' ')
if $fromon == '.'
  $fromon = JSON.parse(File.read('/tmp/harpwise_testing_last_tried.json'))['id']
  puts "Continue from last test tried ..."
end
$fromon_cnt = $fromon.to_i if $fromon.match?(/^\d+$/)
$fromon_id_regex = '^(id-[a-z0-9]+):'
if md = ($fromon + ':').match(/#{$fromon_id_regex}/)
  $fromon_id = md[1]
end
$within = ( ARGV.length == 0 )
$testing_dump_template = '/tmp/harpwise_testing_dumped_%s.json'
$testing_output_file = '/tmp/harpwise_testing_output.txt'
$testing_log_file = '/tmp/harpwise_testing.log'
$all_testing_licks = %w(wade st-louis feeling-bad blues mape box1-i box1-iv box1-v box2-i box2-iv box2-v boogie-i boogie-iv boogie-v simple-turn special one two three long)
$pipeline_started = '/tmp/harpwise_pipeline_started'
$installdir = "#{Dir.home}/harpwise"
$started_at = Time.now.to_f

# locations for our test-data; these dirs will be created as full
# will be removed in test id-1
$dotdir_testing = "#{Dir.home}/dot_harpwise"
$config_ini_saved = $dotdir_testing + '/config_ini_saved'
$config_ini_testing = $dotdir_testing + '/config.ini'
$persistent_state_file = "#{$dotdir_testing}/persistent_state.json"
$players_pictures = "#{$dotdir_testing}/players_pictures"
# remove these to get clean even if we do not rebuild completely
Dir["#{$dotdir_testing}/**/starred.yaml"].each {|s| FileUtils::rm s}
# This will make harpwise look into $dotdir_testing
ENV['HARPWISE_TESTING']='1'

Dir.chdir(%x(git rev-parse --show-toplevel).chomp)
# get termsize
File.readlines('libexec/config.rb').each do |line|
  $term_min_width ||= line.match(/^\s*conf\[:term_min_width\]\s*=\s*(\d*?)\s*$/)&.to_a&.at(1)
  $term_min_height ||= line.match(/^\s*conf\[:term_min_height\]\s*=\s*(\d*?)\s*$/)&.to_a&.at(1)
end
fail "Could not parse term size from libexec/config.rb" unless $term_min_width && $term_min_height

#
# Create read-only copy
#
if system("which harpwise >/dev/null 2>&1")
  puts "Found harpwise in path, syncing it"
  system('sudo rm -rf /usr/lib/harpwise 2>&1 >/dev/null')
  sys('sudo rsync -av ~/harpwise/ /usr/lib/harpwise/ --exclude .git')
  sys('sudo chown -R root:root /usr/lib/harpwise')
  sys('sudo chmod -R 644 /usr/lib/harpwise')
  sys('sudo find /usr/lib/harpwise -type d -exec chmod 755 {} +')
  sys('sudo chmod 755 /usr/lib/harpwise/harpwise')
  hw_abs = %x(which harpwise).chomp
  # Check
  content = File.read(hw_abs)
  req_line = '/usr/lib/harpwise/harpwise $@'
  fail "File #{hw_abs} does not contain required line !\ncontent:\n#{content}\nrequired line:\n#{req_line}\n(this is to make su, that the command 'harpwise' invokes the version from this directory)" unless content[req_line]
  system("touch #{hw_abs} 2>/dev/null")
  fail "#{hw_abs} is writeable" if $?.success?
else
  ENV['PATH'] = "#{$installdir}:" + ENV['PATH']
  puts "Adding ~/harpwise to path: #{ENV['PATH']}"
end

#
# Check for needed progs
#
needed_progs = %w( tmux pv )
not_found = needed_progs.reject {|x| system("which #{x} >/dev/null 2>&1")}
fail "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0

#
# Collect usage examples and later check, that none of them produces an error
#
usage_types = [nil, :calibrate, :listen, :quiz, :licks, :play, :print, :tools, :develop].map do |t|
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
known_not = ['supports the daily', 'harpwise tools transcribe wade.mp3', 'harpwise licks a -t starred']
usage_examples.reject! {|l| known_not.any? {|kn| l[kn]}}
# check count, so that we may not break our detection of usage examples unknowingly
num_exp = 86
fail "Unexpected number of examples #{usage_examples.length} instead of #{num_exp}:\n#{usage_examples}" unless usage_examples.length == num_exp

puts "\nPreparing data"
# need a sound file
system("sox -n /tmp/harpwise_testing.wav synth 1000.0 sawtooth 494")
FileUtils.mv '/tmp/harpwise_testing.wav', '/tmp/harpwise_testing.wav_default'
# on error we tend to leave aubiopitch behind
system("killall aubiopitch >/dev/null 2>&1")

puts "Testing"
puts "\n\e[32mTo restart with a failed test use: '#{File.basename($0)} .'\e[0m\n"
do_test 'id-0: man-page should process without errors' do
  mandir = "/tmp/harpwise_man/man1"
  FileUtils.mkdir_p mandir unless File.directory?(mandir)
  FileUtils.cp "#{$installdir}/man/harpwise.1", mandir
  cmd = "MANPATH=#{mandir}/../ man harpwise 2>&1 >/dev/null"
  ste = sys(cmd)
  expect(cmd, ste) {ste == ''}
end

do_test 'id-0a: selftest without user dir' do
  FileUtils.rm_r($dotdir_testing) if File.exist?($dotdir_testing)
  new_session
  tms 'harpwise develop selftest'
  tms :ENTER
  tms 'echo \$?'
  tms :ENTER
  sleep 1
  expect { screen[16]['user config directory has been created'] }
  expect { screen[19]['Selftest okay.'] }
  expect { screen[21]['echo $?'] }
  expect { screen[22]['0'] }
  kill_session
end

do_test 'id-0b: selftest with restricted locale' do
  new_session
  tms 'LANG=C.ASCII harpwise develop selftest'
  tms :ENTER
  sleep 2
  expect { screen[21]['Selftest okay.'] }
  kill_session
end

# Prepare test-data through harpwise and then some
do_test 'id-1: start without dot_harpwise' do
  # keep this within test, so that we only remove, if we also try to recreate
  FileUtils.rm_r($dotdir_testing) if File.exist?($dotdir_testing)
  new_session
  tms 'harpwise'
  tms :ENTER
  expect($dotdir_testing) {File.directory?($dotdir_testing)}
  expect($config_ini_testing) {File.exist?($config_ini_testing)}
  kill_session
  # now we have a user config
  FileUtils.rm $config_ini_saved if File.exist?($config_ini_saved)
  FileUtils.cp $config_ini_testing, $config_ini_saved
end

do_test 'id-9b: mode licks to create simple lick file' do
  lick_dir = "#{$dotdir_testing}/licks/richter"
  lick_file = "#{lick_dir}/licks_with_holes.txt"
  FileUtils.rm_r lick_dir if File.exist?(lick_dir)
  new_session
  tms 'harpwise licks a'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[15]['Going down that road feeling bad'] }
  expect(lick_file) { File.exist?(lick_file) }
  kill_session
  # more test data
  # keep this within test, so that we only add, if we have just created
  File.open("#{$dotdir_testing}/licks/richter/licks_with_holes.txt",'a') do |file|
    file.write(File.read('tests/data/add_to_licks_with_holes.txt'))
  end
  File.write "#{$dotdir_testing}/README.org", "This directory contains test-data for harpwise\nand will be recreated on each run of tests."
end

do_test 'id-9c: create simple lick file for chromatic' do
  lick_dir = "#{$dotdir_testing}/licks/chromatic"
  lick_file = "#{lick_dir}/licks_with_holes.txt"
  FileUtils.rm_r lick_dir if File.exist?(lick_dir)
  new_session
  tms 'harpwise licks chromatic a --add-scales -'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[9]['empty initial version'] }
  expect(lick_file) { File.exist?(lick_file) }
  kill_session
end

%w(g a c d).each_with_index do |key,idx|
  do_test "id-1g#{idx}: auto-calibration key of #{key}" do
    new_session
    tms "harpwise calib #{key} --auto"
    tms :ENTER
    sleep 1
    tms 'y'
    wait_for_end_of_harpwise
    expect { screen[-4]['Recordings done.'] }
    kill_session
  end
end


%w(a c).each_with_index do |key,idx|
  do_test "id-47a#{idx}: chromatic; auto-calibration key of #{key}" do
    new_session
    tms "harpwise calib chromatic #{key} --auto"
    tms :ENTER
    sleep 1
    tms 'y'
    wait_for_end_of_harpwise
    expect { screen[-4]['Recordings done.'] }
    kill_session
  end
end

ensure_config_ini_testing
puts "\n\n\e[32mNow we should have complete data ...\e[0m"

do_test 'id-1a: config.ini, user prevails' do
  File.write $config_ini_testing, <<~end_of_content
  [any-mode]
    key = a    
  end_of_content
  new_session
  # any invocation would be okay too
  tms 'harpwise print licks-history'
  tms :ENTER
  sleep 2
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:key] == 'c' }
  expect(dump[:conf_user]) { dump[:conf_user][:any_mode][:key] == 'a' }
  expect(dump[:key]) { dump[:conf][:key] == 'a' }
  kill_session
end

do_test 'id-1b: config.ini, mode prevails' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    key = a    
  end_of_content
  new_session
  tms 'harpwise quiz blues replay 3'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:key] == 'c' }
  expect(dump[:conf_system]) { dump[:conf_system][:key] == nil }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:key] == 'a' }
  expect(dump[:key]) { dump[:conf][:key] == 'a' }
  kill_session
end

do_test 'id-1c: config.ini, set loop (example for boolean)' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    loop = false
  end_of_content
  new_session
  tms 'harpwise quiz blues replay 3'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:loop] == true }
  expect(dump[:conf_system]) { dump[:conf_system][:loop] == nil }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:loop] == false }
  expect(dump[:conf]) { dump[:conf][:loop] == false }
  kill_session
end

do_test 'id-1d: config.ini, unset loop with option' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    loop = true
  end_of_content
  new_session
  tms 'harpwise quiz blues replay 3 --no-loop'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:conf_system]) { dump[:conf_system][:any_mode][:loop] == true }
  expect(dump[:conf_user]) { dump[:conf_user][:quiz][:loop] == true }
  expect(dump[:opts]) { dump[:opts][:loop] == false }
  kill_session
end

do_test 'id-1e: config.ini, take default key from config' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    key = a
  end_of_content
  new_session
  tms 'harpwise quiz blues replay 3 --no-loop'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:key]) { dump[:key] == 'a' }
  kill_session
end

do_test 'id-1f: config.ini, take key from commandline' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    key = c
  end_of_content
  new_session
  tms 'harpwise listen a blues'
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:key]) { dump[:key] == 'a' }
  kill_session
end

do_test 'id-1g: config.ini, set value in config and clear again on commandline' do
  File.write $config_ini_testing, <<~end_of_content
  [quiz]
    add_scales = major_pentatonic
  end_of_content
  new_session
  tms 'harpwise quiz blues replay 3 --no-loop --add-scales -'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  ensure_config_ini_testing
  dump = read_testing_dump('start')
  expect(dump[:opts]) { dump[:opts][:add_scales] == nil }
  kill_session
end

usage_types.keys.each_with_index do |mode, idx|
  do_test "id-1h#{idx}: usage screen mode #{mode}" do
    new_session
    tms "harpwise #{usage_types[mode][1]} 2>/dev/null | head -20"
    tms :ENTER
    sleep 2
    expect_usage = { 'none' => [2, "harpwise ('wise' for short) supports the daily"],
                     'calibrate' => [4, 'The wise needs a set of audio-samples'],
                     'listen' => [4, "The mode 'listen' shows information on the notes you play"],
                     'quiz' => [4, "The mode 'quiz' is a quiz on music theory, ear and"],
                     'licks' => [4, "The mode 'licks' helps to learn and memorize licks."],
                     'play' => [4, "The mode 'play' picks from the command line"],
                     'print' => [5, 'and prints their hole-content on the commandline'],
                     'tools' => [4, "The mode 'tools' offers some non-interactive"],
                     'develop' => [4, "This mode is useful only for the maintainer or developer"]}
    
    expect(mode, expect_usage[mode]) { screen[expect_usage[mode][0]][expect_usage[mode][1]] }
    marker = 'harpwise_testing_return_code_is'
    tms "harpwise #{usage_types[mode][1]}"
    tms :ENTER
    sleep 2
    tms 'echo ' + marker + ' \$?'
    tms :ENTER
    expect(marker) { screen.find {|l| l[marker + ' 0']} }
    kill_session
  end
end

usage_types.keys.reject {|k| k == 'none'}.each_with_index do |mode, idx|
  do_test "id-1i#{idx}: options mode #{mode}" do
    new_session
    tms "harpwise #{usage_types[mode][1]} -o 2>/dev/null | tail -20"
    tms :ENTER
    sleep 2
    expect_opts = { 'none' => [2, '???'],
                    'calibrate' => [4, 'prefer sharps'],
                    'listen' => [16, 'on every invocation'],
                    'quiz' => [7, '--transpose-scale KEY_OR_SEMITONES'],
                    'licks' => [5, '--partial 1/3@b, 1/4@x or 1/2@e'],
                    'play' => [8, '--max-holes NUMBER'],
                    'print' => [12, '--scale-over-lick : For modes play'],
                    'tools' => [1, 'starred at some moment in the past'],
                    'develop' => [13, 'If lagging occurs']}
    
    expect(mode, expect_opts[mode]) { screen[expect_opts[mode][0]][expect_opts[mode][1]] }
    marker = 'harpwise_testing_return_code_is'
    tms "harpwise #{usage_types[mode][1]}"
    tms :ENTER
    sleep 2
    tms 'echo ' + marker + ' \$?'
    tms :ENTER
    expect(marker) { screen.find {|l| l[marker + ' 0']} }
    kill_session
  end
end

do_test 'id-2: manual calibration' do
  sound 4, -14
  new_session
  tms 'harpwise calib g'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  tms 'r'
  sleep 18
  expect { screen[-5]['Frequency: 195, ET: 196, diff: -1   -1st:185 [.......I:........] +1st:208'] }
  expect { screen[17]['0.0         0.8          1.6           2.4          3.2         4.0'] }
  kill_session
end

do_test 'id-3: manual calibration summary' do
  new_session
  tms 'harpwise calib a'
  tms :ENTER
  sleep 2
  tms 's'
  sleep 4
  expect { screen[9]['       -10   |     1482 |     1480 |      2 |      2 | ........I........'] }
  kill_session
end

do_test 'id-4: manual calibration starting at hole' do
  sound 1, -14
  new_session
  tms 'harpwise calib a --hole +4'
  tms :ENTER
  sleep 2
  tms 'y'
  sleep 2
  tms 'y'
  sleep 2
  tms 'r'
  sleep 8
  expect { screen[9]['The frequency recorded for  -4/  (note bf4, semi 1) is too different from'] }
  expect { screen[13]['  Difference:             -271.2'] }
  kill_session
end

do_test 'id-5: check against et' do
  sound 1, 10
  new_session
  tms 'harpwise calib c --hole +4'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  tms 'r'
  sleep 10
  expect { screen[11,2] == ['  You played:             784',
                             '  ET expects:             523.3']}
  kill_session
end

do_test 'id-6: listen without journal' do
  sound 8, 2
  journal_file = "#{$dotdir_testing}/journal_richter.txt"
  FileUtils.rm journal_file if File.exist?(journal_file)
  new_session
  tms 'harpwise listen a all'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  expect { screen[12]['b4']}
  tms 'j'
  tms 'q'
  sleep 1
  expect(journal_file) { !File.exist?(journal_file) }
  kill_session
end

do_test 'id-6a: listen and change display and comment' do
  new_session
  tms 'harpwise listen a all --ref +2'
  tms :ENTER
  wait_for_start_of_pipeline
  # just cycle (more than once) through display and comments without errors
  10.times do
    tms 'd'
    tms 'c'
  end
  sleep 1
  tms 'q'
  sleep 1
  expect { screen[-3]['Terminating on user request'] }
  kill_session
end

do_test 'id-6b: listen and change display and comment with menu' do
  new_session
  tms 'harpwise listen a all --ref +2'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'D'
  sleep 1
  tms 'ho'
  tms :ENTER
  sleep 1
  expect { screen[-1]['Display is HOLE'] }
  tms 'C'
  sleep 1
  tms :RIGHT
  tms :ENTER
  sleep 1
  expect { screen[-1]['Comment is INTERVAL'] }
  kill_session
end

do_test 'id-7: change key of harp' do
  new_session
  tms 'harpwise listen richter a all'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'k'
  sleep 1
  tms 'c'
  tms :ENTER
  sleep 1
  expect { screen[1]['listen richter c all'] }
  kill_session
end

do_test 'id-7a: change scale of harp' do
  new_session
  tms 'harpwise listen a all'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'S'
  sleep 1
  tms 'blues'
  tms :ENTER
  tms :ENTER
  sleep 1
  expect { screen[1]['listen richter a blues'] }
  kill_session
end

do_test 'id-7b: rotate scale of harp' do
  new_session
  tms 'harpwise listen a all'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 's'
  sleep 1
  expect { screen[1]['listen richter a chord-i'] }
  kill_session
end

do_test 'id-7c: change key of harp with adjustable pitch' do
  new_session
  tms 'harpwise listen richter c all'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'K'
  sleep 1
  tms :ENTER
  3.times {tms 'S'}
  tms :ENTER
  sleep 1
  expect { screen[1]['listen richter a all'] }
  kill_session
end

do_test 'id-8: listen with merged scale' do
  new_session
  tms 'harpwise listen a blues --add-scales chord-v,chord-i'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['blues,5,1'] }
  kill_session
end

do_test 'id-9: listen with removed scale' do
  new_session
  tms 'harpwise listen a all --remove drawbends'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:scale_holes]) { dump[:scale_holes] == ['+1','-1','+2','-2','-3','+4','-4','+5','-5','+6','-6','-7','+7','-8','+8/','+8','-9','+9/','+9','-10','+10//','+10/','+10'] }
  kill_session
end

do_test 'id-9a: error on ambigous option' do
  new_session
  tms 'harpwise listen a all --r drawbends'
  tms :ENTER
  sleep 1
  expect { screen[2]['ERROR: Argument'] }
  kill_session
end

do_test 'id-9d: error on ambigous scale' do
  new_session
  tms 'harpwise listen a chord'
  tms :ENTER
  sleep 1
  expect { screen[2]["ERROR: Argument from commandline 'chord' should be unique"] }
  kill_session
end

do_test 'id-10: quiz' do
  sound 12, 3
  new_session
  tms 'harpwise quiz c blues replay 2'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['b4    4   b14  b45   4   b14'] }
  kill_session
end

do_test 'id-10a: displays and comments in quiz' do
  sound 40, 2
  new_session
  tms 'harpwise quiz c all replay 2 --ref +2'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  # just cycle (more than once) through display and comments without errors
  10.times do
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
  tms 'harpwise listen a blues --transpose-scale c'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[0]['Play from the scale to get green'] }
  kill_session
end

do_test 'id-12: transpose scale works on non-zero shift' do
  new_session
  tms 'harpwise listen a blues --transpose-scale g'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect { dump[:scale_holes] == ['-2','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
  kill_session
end

do_test 'id-13: transpose scale not working in some cases' do
  new_session
  tms 'harpwise listen a blues --transpose-scale b'
  tms :ENTER
  sleep 2
  expect { screen[2]['Transposing scale blues from key of c to b fails for hole -2'] }
  kill_session
end

do_test 'id-13a: transpose scale by 7 semitones' do
  new_session
  tms 'harpwise listen a blues --transpose-scale +7st'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect { dump[:scale_holes] == ['-2','-3///','-3//','+4','-4','-5','+6','-6/','-6','+7','-8','+8/','+8','+9','-10','+10'] }
  kill_session
end

do_test 'id-14: play a lick' do
  new_session
  tms 'harpwise play a mape'
  tms :ENTER
  sleep 2
  expect { screen[5]['-2 -3// -3 -4 +5 +6'] }
  kill_session
end

do_test 'id-14a: play a lick reverse' do
  new_session
  tms 'harpwise play a mape --reverse'
  tms :ENTER
  sleep 2
  expect { screen[5]['+6 +5 -4 -3 -3// -2'] }
  kill_session
end

do_test 'id-14b: check lick processing on tags.add, desc.add and rec.length' do
  new_session
  tms 'harpwise play a mape'
  tms :ENTER
  wait_for_end_of_harpwise
  dump = read_testing_dump('start')
  lick = dump[:licks].find {|l| l[:name] == 'long'}
  expect(lick) {lick[:rec_length] == '-1'}
  # use 'one' twice to make index match name
  licks = %w(one one two three).map do |lname| 
    dump[:licks].find {|l| l[:name] == lname} 
  end
  expect(licks[1]) { licks[1][:tags] == %w(testing x no_rec) }
  expect(licks[2]) { licks[2][:tags] == %w(y no_rec) }
  expect(licks[3]) { licks[3][:tags] == %w(fav favorites testing z no_rec) }
  expect(licks[1]) { licks[1][:desc] == 'a b' }
  expect(licks[2]) { licks[2][:desc] == 'c b' }
  expect(licks[3]) { licks[3][:desc] == 'a d' }
  kill_session
end

do_test 'id-15: play a lick with recording' do
  trace_file = "#{$dotdir_testing}/trace_richter_modes_licks_and_play.txt"
  FileUtils.rm trace_file if File.exist?(trace_file)
  new_session
  tms 'harpwise play a wade'
  tms :ENTER
  sleep 2
  expect { screen[4]['Lick wade'] }
  expect { screen[5]['-2 -3/ -2 -3/ -2 -2 -2 -2/ -1 -2/ -2'] }
  expect { File.exist?(trace_file) }
  kill_session
end

do_test 'id-15a: check history from previous invocation of play' do
  new_session
  tms 'harpwise print licks-history'
  tms :ENTER
  sleep 2
  expect { screen[11][' l: wade'] }
  kill_session
end

do_test 'id-15b: play licks with controls between' do
  new_session
  tms 'harpwise play a wade st-louis feeling-bad'
  tms :ENTER
  sleep 2
  expect { screen[4]['Lick wade'] }
  sleep 4
  expect { screen[10]['any other key for next'] }
  kill_session
end

do_test 'id-16: play some holes and notes' do
  new_session
  # d2 does not correspond to any hole
  tms 'harpwise play a -1 a5 +4 d2'
  tms :ENTER
  sleep 2
  expect { screen[7]['-1 a5 +4'] }
  kill_session
end

do_test 'id-16a: error on mixing licks and notes for play' do
  new_session
  tms 'harpwise play a -1 wade'
  tms :ENTER
  sleep 1
  expect { screen[5]['but ONLY ONE OF THEM'] }
  kill_session
end

do_test 'id-16b: cycle in play' do
  new_session
  tms 'harpwise play a licks --iterate cycle'
  tms :ENTER
  sleep 2
  expect { screen[6]['Lick wade'] }
  tms :ENTER
  sleep 2
  expect { screen[14]['Lick st-louis'] }
  kill_session
end

do_test 'id-16c: play pitch' do
  new_session
  tms 'harpwise play pitch'
  tms :ENTER
  sleep 2
  expect { screen[-6]['key of song: g  ,  matches key of harp: c'] }
  tms 'F'
  sleep 2
  expect { screen[-3]['key of song: c  ,  matches key of harp: f'] }
  tms ' '
  sleep 1
  expect { screen[22] == 'SPACE to continue ...' }
  tms ' '
  sleep 1
  expect { screen[22]['go'] }
  tms 'h'
  sleep 1
  expect { screen[15] == 'Keys available while playing a pitch:'}
  tms 'x'
  sleep 1
  expect { screen[18]['continue'] }
  # still alive after help ?
  tms ' '
  sleep 1
  expect { screen[22] == 'SPACE to continue ...' }
  kill_session
end

do_test 'id-17: mode licks with initial lickfile' do
  new_session
  tms 'harpwise licks a'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  expect(dump[:licks], dump[:licks].length) { dump[:licks].length == 20 }
  expect { screen[1]['licks(20,ran) richter a blues,1,4,5'] }
  kill_session
end

#  Licks with their tags (type 'testing'):
#
#  wade ..... favorites,samples,fav
#  st-louis ..... favorites,samples
#  feeling-bad ..... favorites,samples
#  special ..... advanced,samples
#  blues ..... scales,theory
#  mape ..... scales
#  one ..... testing,x
#  two ..... x,y
#  three ..... testing,z,fav,favorites
#  long ..... testing,x
#
#  Total number of licks:   10

do_test 'id-18: mode licks with licks with tags_any' do
  new_session
  tms 'harpwise licks --tags-any favorites,testing a'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect(dump[:licks]) { dump[:licks].length == 6 }
  kill_session
end

do_test 'id-18a: mode licks with licks with tags_all' do
  new_session
  tms 'harpwise licks --tags-all scales,theory a'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect(dump[:licks], dump[:licks].length) { dump[:licks].length == 2 }
  kill_session
end

do_test 'id-19: mode licks with licks excluding one tag' do
  new_session
  tms 'harpwise licks --no-tags-any scales a'
  tms :ENTER
  wait_for_start_of_pipeline
  dump = read_testing_dump('start')
  # See comments above for verification
  expect(dump[:licks], dump[:licks].length) { dump[:licks].length == 18 }
  kill_session
end

do_test 'id-19a: cycle through displays and comments in licks ' do
  sound 40, 2
  new_session
  tms 'harpwise licks c'
  tms :ENTER
  wait_for_start_of_pipeline
  # just cycle (more than once) through display and comments without errors
  10.times do
    tms 'd'
    tms 'c'
  end
  sleep 1
  tms 'q'
  sleep 1
  expect { screen[-3]['Terminating on user request'] }
  kill_session
end

do_test 'id-19b: prepare and get history of licks' do
  trace_file = "#{$dotdir_testing}/trace_richter_modes_licks_and_play.txt"
  FileUtils.rm trace_file if File.exist?(trace_file)
  new_session
  %w(wade mape blues).each do |lick|
    tms "harpwise licks --start-with #{lick} a"
    tms :ENTER
    wait_for_start_of_pipeline
    tms 'q'
    wait_for_end_of_harpwise
  end
  tms "harpwise print licks-history >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  ["   l: blues\n",
   "  2l: mape\n",
   "  3l: wade\n"].each_with_index do |exp,idx|
    expect(lines.each_with_index.map {|l,i| [i,l]}, exp, idx) { lines[10+idx] == exp }
  end
  kill_session
end

do_test 'id-19c: start with next to last lick' do
  new_session
  tms 'harpwise licks --start-with 2l'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-1]['mape'] }
  kill_session
end

do_test 'id-20: error on unknown names in --tags' do
  new_session
  tms 'harpwise licks --tags-any unknown a'
  tms :ENTER
  sleep 2
  expect { screen[2]['ERROR: Among tags ["unknown"] in option --tags-any, there are some'] }
  kill_session
end

do_test 'id-21: mode licks with --start-with' do
  new_session
  tms 'harpwise licks --start-with wade a'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['wade | fav,favorites,samples'] }
  expect { screen[-1]['Wade in the Water'] }
  kill_session
end

do_test 'id-22: print list of some licks with tags' do
  new_session
  tms 'harpwise print --tags-any favorites licks-with-tags'
  tms :ENTER
  sleep 2
  # for licks that match this tag
  expect { screen[17]['Total number of licks:   4'] }
  kill_session
end

do_test 'id-23: print list of licks with tags' do
  new_session
  tms "harpwise print licks-with-tags >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  ["  wade ..... fav,favorites,samples,has_rec\n",
   "  st-louis,feeling-bad ..... favorites,samples,has_rec\n",
   "  blues,mape ..... scales,theory,no_rec\n",
   "  box1-i ..... box,box1,i-chord,no_rec\n",
   "  box1-iv ..... box,box1,iv-chord,no_rec\n",
   "  box1-v ..... box,box1,v-chord,no_rec\n",
   "  box2-i ..... box,box2,i-chord,no_rec\n",
   "  box2-iv ..... box,box2,iv-chord,no_rec\n",
   "  box2-v ..... box,box2,v-chord,no_rec\n",
   "  boogie-i ..... boogie,i-chord,no_rec\n",
   "  boogie-iv,boogie-v ..... boogie,v-chord,no_rec\n",
   "  simple-turn ..... turn,no_rec\n",
   "  special ..... advanced,samples,no_rec\n",
   "  one ..... testing,x,no_rec\n",
   "  two ..... y,no_rec\n",
   "  three ..... fav,favorites,testing,z,no_rec\n",
   "  long ..... testing,x,has_rec\n"].each_with_index do |exp,idx|
    expect(lines.each_with_index.map {|l,i| [i,l]},exp,12+idx) { lines[12+idx] == exp }
  end
  kill_session
end

do_test 'id-23a: overview for all licks' do
  new_session
  tms "harpwise print licks-tags-stats >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  ["  Tag                              Count\n",
   " -----------------------------------------\n",
   "  advanced                             1\n",
   "  boogie                               3\n",
   "  box                                  6\n",
   "  box1                                 3\n",
   "  box2                                 3\n",
   "  fav                                  2\n",
   "  favorites                            4\n",
   "  has_rec                              4\n",
   "  i-chord                              3\n",
   "  iv-chord                             2\n",
   "  no_rec                              16\n",
   "  samples                              4\n",
   "  scales                               2\n",
   "  testing                              3\n",
   "  theory                               2\n",
   "  turn                                 1\n",
   "  v-chord                              4\n",
   "  x                                    2\n",
   "  y                                    1\n",
   "  z                                    1\n",
   " -----------------------------------------\n",
   "  Total number of tags:               67\n",
   "  Total number of different tags:     20\n",
   " -----------------------------------------\n",
   "  Total number of licks:              20\n"].each_with_index do |exp,idx|
    expect(lines[10+idx],exp,idx,lines) { lines[12+idx] == exp }
  end
  kill_session
end

do_test 'id-24: cycle through licks' do
  new_session
  tms 'harpwise licks --iterate cycle'
  tms :ENTER
  wait_for_start_of_pipeline
  expect($all_testing_licks[0]) { screen[-2][$all_testing_licks[0]] }
  tms :ENTER
  sleep 4
  expect { screen[-2][$all_testing_licks[1]] }
  tms :ENTER
  sleep 4
  expect { screen[-2][$all_testing_licks[2]] }
  tms :ENTER
  kill_session
end

do_test 'id-25: cycle through licks back to start' do
  new_session
  tms 'harpwise licks --iterate cycle'
  tms :ENTER
  wait_for_start_of_pipeline
  (0 .. $all_testing_licks.length + 2).to_a.each do |i|
    lickname = $all_testing_licks[i % $all_testing_licks.length]
    expect(lickname,i) { screen[-1][lickname] || screen[-2][lickname] }
    tms :ENTER
    sleep 4
  end
  kill_session
end

do_test 'id-27: cycle through licks from starting point' do
  new_session
  tms 'harpwise licks --start-with special --iterate cycle'
  tms :ENTER
  wait_for_start_of_pipeline
  (0 .. $all_testing_licks.length + 2).to_a.each do |i|
    lickname = $all_testing_licks[(i + 15) % $all_testing_licks.length]
    expect(lickname,i) { screen[-1][lickname] || screen[-2][lickname] }
    tms :ENTER
    sleep 4
  end
  kill_session
end

do_test 'id-29: back one lick' do
  new_session
  tms 'harpwise licks --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['st-louis'] }
  tms :ENTER
  sleep 4
  expect { !screen[-2]['st-louis'] }
  tms :BSPACE
  sleep 4
  expect { screen[-2]['st-louis'] }
  kill_session
end

do_test 'id-30: use option --partial for wade' do
  new_session
  tms 'harpwise licks --start-with wade --partial 1@b'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect(tlog[-1]) { tlog[-1]["play --norm=-6 -q -V1 #{Dir.home}/dot_harpwise/licks/richter/recordings/wade.mp3 trim 0.0 1.0 pitch 300"] }
  kill_session
end

do_test 'id-31: use option --partial for st-louis' do
  new_session
  tms 'harpwise licks --start-with st-louis --partial 1@e'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect(tlog[-1]) { tlog[-1]["play --norm=-6 -q -V1 #{Dir.home}/dot_harpwise/licks/richter/recordings/st-louis.mp3 trim 3.0 1.0 pitch 300"] }
  kill_session
end

do_test 'id-32: use option --partial and --holes' do
  new_session
  tms 'harpwise licks --start-with wade --holes --partial 1@b'
  tms :ENTER
  wait_for_start_of_pipeline
  tlog = read_testing_log
  expect(tlog[-1]) { tlog[-1]['["-2", "-3/", "-2", "-3/", "-2", "-2", "-2", "-2/", "-1", "-2/", "-2"]'] }
  kill_session
end

do_test 'id-33: display as chart with scales' do
  new_session
  tms 'harpwise listen blues:b --add-scales chord-i:1 --display chart-scales'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[8]['b1   b1    1   b1   b1    b    1   b1   b1    b'] }
  kill_session
end

do_test 'id-33a: warning with double shortname for scales' do
  new_session
  tms 'harpwise listen blues:b --add-scales chord-i:b --display chart-scales'
  tms :ENTER
  sleep 20
  tms 'q'
  wait_for_end_of_harpwise
  dump = read_testing_dump('end')
  expect(dump[:messages_printed]) { dump[:messages_printed][0][0]["Shortname 'b' is used for two scales"]}
  kill_session
end

do_test 'id-33b: display chart where -2 equals +3' do
  new_session
  tms 'harpwise listen blues:b --add-scales chord-i:1,chord-iv:4,chord-v:5 --display chart-scales'
  tms :ENTER
  wait_for_start_of_pipeline
  # ends on +3 ; change 8 into correct line
  expect { screen[4]['b4    4   b14']}
  # ends on -2 ; change 12 into correct line
  expect { screen[8]['b15  b14']}
  kill_session
end

do_test 'id-34: comment with scales and octave shifts' do
  new_session
  tms 'harpwise licks blues:b --add-scales chord-i:1 --comment holes-scales --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[15]['-1.b1    +2     -2.b1   -3/.b     +3.b1   -3/.b   -3//'] }
  tms '>'
  sleep 2
  expect { screen[15]['-4.b1   +5    +6.b1  (*)    +6.b1  (*)    -6.b    +6.b1'] }
  tms '<'
  sleep 2
  tms '<'
  sleep 2
  expect { screen[-2]['Shifting lick by (one more) octave does not produce any playable notes.'] }
  kill_session
end

do_test 'id-34b: comment with reverted lick' do
  new_session
  tms 'harpwise licks --comment holes-scales --add-scales - --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[15]['-2.b  -3/.b   -2.b  -3/.b   -2.b   -2.b   -2.b  -2/    -1.b'] }
  tms '!'
  sleep 2
  expect { screen[15]['-2.b  -2/    -1.b  -2/    -2.b   -2.b   -2.b  -3/.b   -2.b'] }
  kill_session
end

do_test 'id-35: comment with all holes' do
  new_session
  tms 'harpwise lic blues:b --add-scales chord-i:1 --comment holes-all --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[16]['  ▄▄▖▌   ▄▙▖ ▗▘  ▄▄▖▗▘  ▄▄▖▄▘ ▞   ▄▙▖ ▄▘  ▄▄▖▄▘ ▞   ▄▄▖▄▘ ▞ ▞   ▄▄▖▗▘'] }
  kill_session
end

do_test 'id-36: display as chart with intervals as names' do
  new_session
  tms 'harpwise licks blues --display chart-intervals --comment holes-intervals --ref -2 --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['-7st Si-O  REF  5st  Si   Oct'] }
  expect { screen[15]['-2.Ton   -3/.3st    -2.Si-O  -3/.3st    -2.Si-O   -2.Ton'] }
  kill_session
end

do_test 'id-36a: display as chart with intervals as semitones' do
  new_session
  tms 'harpwise licks blues --display chart-inter-semis --comment holes-inter-semis --ref -2 --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['-7st -3st  REF  5st  9st 12st'] }
  expect { screen[15]['-2.0st   -3/.3st    -2.-3st  -3/.3st    -2.-3st   -2.0st'] }
  kill_session
end

do_test 'id-36b: display as chart with notes' do
  new_session
  tms 'harpwise licks blues --display chart-intervals --comment holes-notes --ref -2 --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[4]['-7st Si-O  REF  5st  Si   Oct'] }
  expect { screen[15]['-1.d4     +2.e4     -2.g4    -3/.bf4    +3.g4    -3/.bf4'] }
  kill_session
end

do_test 'id-37: change lick by name' do
  new_session
  tms 'harpwise lick blues --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['wade'] }
  tms 'l'
  tms 'special'
  tms :ENTER
  sleep 2
  expect { screen[-2]['special |'] }
  kill_session
end

do_test 'id-37a: change lick by name with cursor keys' do
  new_session
  tms 'harpwise lick blues --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-2]['wade'] }
  tms 'l'
  tms :RIGHT
  tms :RIGHT
  tms :ENTER
  sleep 2
  expect { screen[-2]['st-louis |'] }
  kill_session
end

do_test 'id-37b: change option --tags' do
  new_session
  tms 'harpwise lick blues --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 't'
  tms 'fa'
  tms :BSPACE
  tms 'avo'
  tms :ENTER
  tms 'cyc'
  tms :ENTER
  tms 'q'
  wait_for_end_of_harpwise
  dump = read_testing_dump('end')
  expect(dump[:file_from], dump[:opts]) { dump[:opts][:tags_any] == 'favorites'}
  expect(dump[:file_from], dump[:opts]) { dump[:opts][:iterate] == 'cycle'}
  kill_session
end

do_test 'id-37c: change option --tags with cursor keys' do
  new_session
  tms 'harpwise lick blues --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 't'
  4.times {tms :RIGHT}
  tms :ENTER
  tms :DOWN
  tms :ENTER
  tms 'q'
  wait_for_end_of_harpwise
  dump = read_testing_dump('end')
  expect(dump[:file_from], dump[:opts]) { dump[:opts][:tags_any] == 'advanced'}
  expect(dump[:file_from], dump[:opts]) { dump[:opts][:iterate] == 'random'}
  kill_session
end

do_test 'id-37d: change partial' do
  new_session
  tms 'harpwise lick blues --start-with st-louis'
  tms :ENTER
  wait_for_start_of_pipeline
  tms '@'
  tms '1@e'
  tms :ENTER
  sleep 1
  tms 'q'
  wait_for_end_of_harpwise
  dump = read_testing_dump('end')
  expect(dump[:opts]) { dump[:opts][:partial] == '1@e' }
  kill_session
end

do_test 'id-38: error on ambigous mode' do
  new_session
  tms 'harpwise li blues'
  tms :ENTER
  sleep 2
  expect { screen[2]['argument can be one of'] }
  kill_session
end

do_test 'id-39: error on unknown extra argument' do
  new_session
  tms 'harpwise print hi'
  tms :ENTER
  sleep 2
  expect { screen[13]["First argument for mode print should be one of those listed above"] }
  kill_session
end

do_test 'id-40: handling a very long lick' do
  new_session
  tms 'harpwise lick blues --start-with long --comment holes-all'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[-8]['  ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▌   ▄▄▖▗▘  ▄▄▖▗▘'] }
  20.times {
    tms '1'
  }
  sleep 2
  expect { screen[-8]['  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▄▘  ▄▄▖▚▄▌  ▄▄▖▚▄▌  ▄▄▖▚▄▌  ▄▄▖▚▄▌'] }
  tms 'c'
  tms '1'
  sleep 2
  expect { screen[18]['-3.1     -3.1     -3.1     -3.1     -4.b15   -4.b15   -4.b15'] }
  kill_session
end

do_test 'id-41: abbreviated scale' do
  new_session
  tms 'harpwise licks mid'
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['middle'] }
  kill_session
end

do_test 'id-44: switch between modes licks and listen' do
  new_session
  tms 'harpwise licks a'
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

do_test 'id-44a: switch between modes quiz and listen' do
  new_session
  tms 'harpwise quiz blues replay 3'
  tms :ENTER
  sleep 2
  tms :ENTER
  wait_for_start_of_pipeline
  expect { screen[1]['quiz'] }
  tms 'm'
  sleep 4
  expect { screen[1]['listen'] }
  tms 'm'
  sleep 4
  expect { screen[1]['quiz'] }
  kill_session
end

do_test 'id-45: star and unstar a lick' do
  starred_file = Dir.home + '/dot_harpwise/licks/richter/starred.yaml'
  FileUtils.rm starred_file if File.exist?(starred_file)  
  new_session
  tms 'harpwise licks a --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  5.times do
    tms '*'
    sleep 1
  end
  3.times do
    tms '/'
    sleep 1
  end
  tms 'q'
  sleep 1
  kill_session
  stars = YAML.load_file(starred_file)
  expect(stars) { stars['wade'] == 2 }
end

# start at test before if rerun
do_test 'id-46: show lick starred in previous invocation' do
  new_session
  tms 'harpwise print licks-starred'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[6]['wade:    2'] }
  kill_session
end

do_test 'id-46a: verify persistent tag "starred"' do
  new_session
  tms 'harpwise print licks-with-tags 2>/dev/null | head -20'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[13]['wade ..... fav,favorites,samples,starred,has_rec'] }
  kill_session
end

usage_examples.each_with_index do |ex,idx|
  do_test "id-41a%d: usage #{ex}" % idx do
    new_session
    ex.gsub!(/#.*/,'')
    tms ex + " >#{$testing_output_file} 2>&1"
    tms :ENTER
    sleep 1
    # if the program keeps running, than it had no errors; otherwise
    # test its return code and scan its output
    if wait_for_end_of_harpwise(4)
      marker = 'harpwise_testing_return_code_is'
      output = File.read($testing_output_file).lines
      tms 'echo ' + marker + ' \$?'
      tms :ENTER
      expect(marker) { screen.find {|l| l[marker + ' 0']} }
      expect(output) { output.select {|l| l.downcase['error']}.length == 0 }
    else
      # just create an OKAY-marker
      expect {true}
    end
    kill_session
  end
end

do_test 'id-48: chromatic in c; listen' do
  sound 8, 2
  new_session 92, 30
  tms 'harpwise listen chromatic c all --add-scales - --display chart-notes'
  tms :ENTER
  wait_for_start_of_pipeline
  # adjust lines 
  expect { screen[4]['c4  e4  g4  c5  c5  e5  g5  c6  c6  e6  g6  c7'] }
  expect { screen[6]['d4  f4  a4  b4  d5  f5  a5  b5  d6  f6  a6  b6'] }
  expect { screen[10]['df4  f4 af4 df5 df5  f5 af5 df6 df6  f6 af6 df7'] }
  kill_session
end

do_test 'id-48a: chromatic in a; listen' do
  sound 8, 2
  new_session 92, 30
  tms 'harpwise listen chromatic a all --display chart-notes'
  tms :ENTER
  wait_for_start_of_pipeline
  # adjust lines 
  expect { screen[4]['a3 df4  e4  a4  a4 df5  e5  a5  a5 df6  e6  a6'] }
  kill_session
end

do_test 'id-48b: chromatic in a, scale blues; listen; creation of derived' do
  sound 8, 2
  derived = "#{$dotdir_testing}/derived/chromatic/derived_scale_chord-i_with_holes.yaml"
  FileUtils.rm derived if File.exist?(derived)
  new_session 92, 30
  tms 'harpwise listen chromatic a blues --display chart-scales'
  tms :ENTER
  wait_for_start_of_pipeline
  # adjust lines 
  expect { screen[4]['b4  4  b14  b4  b4  4  b14  b4'] }
  expect { screen[8]['==1===2===3===4===5===6===7===8===9==10==11==12========'] }
  expect(derived) { File.exist?(derived) }
  kill_session
end

do_test 'id-49: edit lickfile' do
  ENV['EDITOR']='vi'
  new_session
  tms 'EDITOR=vi harpwise licks blues --start-with wade'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'e'
  sleep 1
  expect { screen[17]['[wade]'] }
  kill_session
end

do_test 'id-50a: tools keys' do
  new_session
  tms 'harpwise tools keys b'
  tms :ENTER
  expect { screen[1]['-3'] }
  kill_session
end

do_test 'id-51: tools transpose' do
  new_session
  tms 'harpwise tools transpose c g -1'
  tms :ENTER
  expect { screen[11]['Holes transposed:   -2'] }
  kill_session
end

do_test 'id-51a: tools shift by interval' do
  new_session
  tms 'harpwise tools shift mt -1 +2'
  tms :ENTER
  expect { screen[9]['Holes shifted:   -2/  -3///'] }
  kill_session
end

do_test 'id-51b: tools shift by semitones' do
  new_session
  tms 'harpwise tools shift +7st -1 +2'
  tms :ENTER
  expect { screen[9]['  Holes shifted:   -3//  -3'] }
  kill_session
end

do_test 'id-51c: tools chords' do
  new_session
  tms 'harpwise tools g chords'
  tms :ENTER
  expect { screen[10]['g3  b3  d4'] }
  kill_session
end

do_test 'id-52: tools chart' do
  new_session
  tms 'harpwise tools chart g'
  tms :ENTER
  expect { screen[5]['a3   d4   gf4  a4   c5   e5   gf5  a5   c6   e6'] }
  kill_session
end

do_test 'id-52a: tools chart, explicit flat' do
  new_session
  tms 'harpwise tools chart g --flat'
  tms :ENTER
  expect { screen[5]['a3   d4   gf4  a4   c5   e5   gf5  a5   c6   e6'] }
  kill_session
end

do_test 'id-52b: tools chart, explicit sharp' do
  new_session
  tms 'harpwise tools chart g --sharp'
  tms :ENTER
  expect { screen[5]['a3   d4   fs4  a4   c5   e5   fs5  a5   c6   e6'] }
  kill_session
end

do_test 'id-53: print' do
  new_session
  tms "harpwise print st-louis --sharps >#{$testing_output_file}"
  tms :ENTER
  sleep 1
  lines = File.read($testing_output_file).lines
  {17 => 'd4  e4  g4  as4  g4  as4  a4  g4',
   20 => '-1.-      +2.-      -2.-     -3/.-      +3.-     -3/.-',
   29 => '-1.Ton      +2.fT       -2.3st     -3/.3st      +3.Si-O',
   33 => '-1.0st     +2.2st     -2.3st    -3/.3st     +3.-3st   -3/.3st',
   37 => '-1.Ton    +2.fT     -2.5st   -3/.8st    +3.5st   -3/.8st',
   41 => '-1.0st    +2.2st    -2.5st   -3/.8st    +3.5st   -3/.8st',
   45 => '-7  -5  -2   1  -2   1   0  -2',
   50 => 'Description: St. Louis Blues'}.each do |lno, exp|
    expect(lines.each_with_index.map {|l,i| [i,l]}, lno, exp) {lines[lno][exp]}
  end
  kill_session
end

do_test 'id-53a: print' do
  new_session
  tms "harpwise print st-louis --flats>#{$testing_output_file}"
  tms :ENTER
  sleep 1
  lines = File.read($testing_output_file).lines
  expect(17, lines) {lines[17]['d4  e4  g4  bf4  g4  bf4  a4  g4']}
  kill_session
end

do_test 'id-53b: print' do
  new_session
  tms "harpwise print st-louis >#{$testing_output_file}"
  tms :ENTER
  sleep 1
  lines = File.read($testing_output_file).lines
  expect(17, lines) {lines[17]['d4  e4  g4  bf4  g4  bf4  a4  g4']}
  kill_session
end

do_test 'id-53c: print' do
  new_session
  tms "harpwise print a4 b4 c4 >#{$testing_output_file}"
  tms :ENTER
  sleep 1
  lines = File.read($testing_output_file).lines
  expect(lines) {lines[10]['a4.5   b4.1   c4.b4']}
  kill_session
end

do_test 'id-53d: print with scale' do
  # need some content that would otherwise scroll out of screen
  new_session 120, 40
  tms 'harpwise print chord-i st-louis --add-scales chord-iv,chord-v'
  tms :ENTER
  expect { screen[3]['-1.15    +2.4     -2.14   -3/.4     +3.14   -3/.4   -3//.5     -2.14'] }
  kill_session
end

do_test 'id-53e: print with scales but terse' do
  new_session
  tms 'harpwise print chord-i st-louis --add-scales chord-iv,chord-v --terse'
  tms :ENTER
  expect { screen[15] == '$' }
  kill_session
end

do_test 'id-53f: print with multiple scales' do
  new_session
  # chord-i is taken as scale and only chord-iv and chord-v are handled
  tms 'harpwise print chord-i chord-iv chord-v --add-scales chord-iv,chord-v'
  tms :ENTER
  expect { screen[21]['2 scales printed.'] }
  kill_session
end

i = 0
%w(richter chromatic).each do |type|
  glob = $installdir + "/config/#{type}/scale_*_with_holes.yaml"
  star_at = glob.index('*')
  Dir[glob].each do |sfile|
    scale = sfile[star_at .. star_at - glob.length]
    i += 1
    do_test "id-54a#{i}: tools print type #{type}, scale #{scale}" do
      new_session
      tms "harpwise print #{type} #{scale} --add-scales -"
      tms :ENTER
      wait_for_end_of_harpwise
      expect { screen.select {|l| l.downcase['error']}.length == 0 }
      kill_session
    end
  end
end


do_test 'id-54b: print list of all licks' do
  new_session
  tms "harpwise print licks-list-all >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  [" wade        :  11\n",
   " st-louis    :   8\n",
   " feeling-bad :   9\n",].each_with_index do |exp,idx|
    expect(lines,exp,idx) { lines[8+idx] == exp }
  end
  kill_session
end


do_test 'id-54c: print list of selected licks' do
  new_session
  tms "harpwise print licks-list --tags-any favorites"
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[10] == ' st-louis    :   8' }
  kill_session
end


do_test 'id-54d: print selected licks' do
  new_session
  tms "harpwise print licks-details --tags-any favorites"
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[10] == 'With intervals to first:' }
  expect { screen[16] == 'As absolute semitones (a4 = 0):' }
  kill_session
end


do_test 'id-54e: print list of all scales' do
  new_session
  tms "harpwise print scales >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  [" all              :  32\n",
   "   \e[2mShort: A\e[0m\n",
   " arabic           :  15\n",
   "   \e[2mShort: a\e[0m\n",   
   " blues            :  18\n",
   "   \e[2mShort: b\e[0m   \e[2mDesc: the full blues scales over all octaves\e[0m\n",
   " blues-middle     :   7\n",
   "   \e[2mShort: b\e[0m   \e[2mDesc: middle octave of the blues scale\e[0m\n",
   " chord-i          :  11\n",
   "   \e[2mShort: 1\e[0m\n"].each_with_index do |exp,idx|
    expect(lines.each_with_index.map {|l,i| [i,l]}, idx+8, exp) { lines[8+idx] == exp }
  end
  kill_session
end


do_test 'id-54f: print scale with sharps' do
  new_session
  tms "harpwise print blues --sharp >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  expect(16, lines.each_with_index.map {|l,i| [i,l]}) {lines[16]['g4  as4  c5  cs5  d5  f5  g5']}
  kill_session
end


do_test 'id-54g: print scale with flats' do
  new_session
  tms "harpwise print blues --flats >#{$testing_output_file}"
  tms :ENTER
  wait_for_end_of_harpwise
  lines = File.read($testing_output_file).lines
  expect(16, lines.each_with_index.map {|l,i| [i,l]}) {lines[16]['g4  bf4  c5  df5  d5  f5  g5']}
  kill_session
end


do_test 'id-55: check persistence of volume' do
  FileUtils.rm $persistent_state_file if File.exist?($persistent_state_file)
  first_vol = -9
  new_session
  tms 'harpwise play pitch'
  tms :ENTER
  sleep 2
  tms 'v'
  expect { screen[-5]["#{first_vol}dB"] }
  tms 'v'
  sleep 2
  expect { screen[-4]["#{first_vol - 3}dB"] }
  tms 'q'
  sleep 2
  tms 'harpwise play pitch'
  tms :ENTER
  sleep 2
  tms 'v'
  sleep 2
  expect { screen[-2]["#{first_vol - 6}dB"] }
  tms 'q'
  sleep 2
  pers_data = JSON.parse(File.read($persistent_state_file))
  expect(pers_data) { pers_data['volume'] == first_vol - 6 }
  kill_session
end


do_test 'id-56: forward and back in help' do
  new_session
  tms 'harpwise licks c'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'h'
  expect { screen[5]['pause and continue'] }
  tms :ENTER 
  expect { screen[4]['next sequence or lick'] }
  tms :BSPACE
  expect { screen[5]['pause and continue'] }
  kill_session
end

help_samples = {'harpwise listen d' => [[9,'change key of harp']],
                'harpwise quiz a replay 3' => [[9,'change key of harp'],[9,'forget holes played']],
                'harpwise licks c' => [[9,'change key of harp'],[16,'select them later by tag']]}

help_samples.keys.each_with_index do |cmd, idx|
  do_test "id-57#{%w{a b c}[idx]}: show help for #{cmd}" do
    new_session
    tms cmd
    tms :ENTER
    if idx == 1
      sleep 2
      tms :ENTER
    end
    wait_for_start_of_pipeline
    tms 'h'
    help_samples[cmd].each do |line,text|
      expect(line,text) { screen[line][text] }
      tms :ENTER
    end
    kill_session
  end
end

do_test 'id-58: listen with journal on request, recall later' do
  sound 40, 2
  ENV['EDITOR']='vi'
  journal_file = "#{$dotdir_testing}/journal_richter.txt"
  FileUtils.rm journal_file if File.exist?(journal_file)
  new_session
  tms 'EDITOR=vi harpwise listen a all'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  tms 'j'
  sleep 2
  tms 'q'
  tms :ENTER
  tms :ENTER
  tms :ENTER
  tms :BSPACE
  sleep 1
  expect { screen[-8] == '     -4     -4' }
  tms 'j'
  sleep 2
  tms 'w'
  tms :ENTER
  sleep 1
  expect { File.exist?(journal_file) }
  tms 'j'
  sleep 2
  tms 'c'
  tms 'c'
  sleep 1
  expect { screen[-7]['No journal yet to show'] }
  tms 'j'
  sleep 2
  tms 'r'
  expect { screen[-7]['-- 2 holes in key of a'] }
  ENV.delete('EDITOR')
  kill_session
end

do_test 'id-59: listen and edit journal' do
  ENV['EDITOR']='vi'
  sound 40, 2
  new_session
  # dont know why we need to set it here too (at least ubuntu)
  tms 'EDITOR=vi harpwise listen a all --comment journal'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  tms :ENTER
  tms :ENTER
  sleep 1
  expect { screen[-8] == '     -4     -4' }
  tms 'j'
  tms 'e'
  sleep 1
  tms 'i'
  tms '+1 '
  tms :ESCAPE
  tms ':wq'
  tms :ENTER
  sleep 1
  expect { screen[-8] == '     +1     -4     -4' }
  kill_session
  ENV.delete('EDITOR')
end

do_test 'id-60: listen with auto journal' do
  ENV['EDITOR']='vi'
  two_sounds 10, 2, 16, 8
  new_session
  tms 'EDITOR=vi harpwise listen a all --comment journal'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  tms 'j'
  sleep 1
  tms 'j'
  expect { screen[1]['journal-all'] }
  sleep 6
  # allow for varying duration
  expect { (screen[16]['-4 (3'] ||
            screen[16]['-4 (4'] ||
            screen[16]['-4 (5'] ||
            screen[16]['-4 (6']) &&
           screen[16]['-6/'] }
  tms 'm'
  sleep 4
  expect { screen[1]['licks(1,ran)'] }
  expect { screen[-1]['journal'] }
  kill_session
  ENV.delete('EDITOR')
end

do_test 'id-60a: set reference from sound' do
  sound 16, 8
  new_session
  tms 'harpwise listen a all'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  tms 'r'
  expect { screen[12]['Ref:   -6/'] }
  tms 'D'
  tms 'inter'
  tms :ENTER
  expect { screen[9]['-19st-14stfT-O -7st       REF'] }
  kill_session
end

do_test 'id-61: error on double diff spec for play inter' do
  new_session
  tms 'harpwise play interval 2st 2st'
  tms :ENTER
  sleep 1
  expect { screen[5]['ERROR: You specified two semitone-differences but no base note'] }
  kill_session
end

do_test 'id-62: play interval' do
  new_session
  tms 'harpwise play inter c4 12st'
  tms :ENTER
  sleep 2
  expect { screen[10]['from:  -9st ,   +1 ,   c4'] }
  tms '>'
  sleep 2
  expect { screen[18]['from:  -8st ,  -1/ ,  df4'] }
  expect { screen[19]['to:   4st ,  -4/ ,  df5'] }
  tms '+'
  sleep 2
  expect { screen[19]['to:   5st ,   -4 ,   d5'] }
  tms ' '
  sleep 1
  expect { screen[22] == 'SPACE to continue ...' }
  tms ' '
  sleep 1
  expect { screen[22]['go'] }
  tms 'h'
  sleep 1
  expect { screen[15]['Keys available while playing an interval:'] }
  tms 'x'
  sleep 1
  expect { screen[21] == 'continue' }
  # still alive after help ?
  tms ' '
  sleep 1
  expect { screen[22] == 'SPACE to continue ...' }
end

do_test 'id-63: calculate interval' do
  new_session
  tms 'harpwise tools inter d4 e5'
  tms :ENTER
  sleep 2
  expect { screen[2]['Interval 14st:'] }
  kill_session
end

do_test 'id-64: calculate progression' do
  new_session
  tms 'harpwise tools prog a3 5st 9st oct'
  tms :ENTER
  sleep 2
  expect { screen[11]['a3      d4     gf4      a4'] }
  expect { screen[19]['0       5       9      12'] }
  kill_session
end

do_test 'id-64a: print some holes and notes' do
  new_session
  # a5 and d2 do not correspond to any hole
  tms 'harpwise print a -1 a5 +4 d2'
  tms :ENTER
  sleep 2
  expect { screen[0]['-1.-   a5.+7  +4.-   d2.-'] }
  expect { screen[12]['-1.Ton    a5.22st   +4.fSe    d2.-21st'] }
  kill_session
end

do_test 'id-65: play progression' do
  new_session
  tms 'harpwise play prog a3 5st 9st oct'
  tms :ENTER
  sleep 1
  tms '5'
  sleep 0.5
  tms 's'
  sleep 1
  wait_for_end_of_harpwise
  expect { screen[5]['|---------|---------|---------|---------|'] }
  expect { screen[6]['|      -- |      a3 |     -12 |       0 |'] }
  expect { screen[16]['|---------|---------|---------|---------|'] }
  expect { screen[17]['|      -1 |      d4 |      -7 |       0 |'] }
  kill_session
end

do_test 'id-66: tool search-in-licks' do
  new_session
  tms 'harpwise tool search-in-licks +1 -1'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[7]['2 matches'] }
  kill_session
end

do_test 'id-66a: tool search-in-scales' do
  new_session
  tms 'harpwise tool search-in-scales wade'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[10]['all   blues   minor    minor-pentatonic'] }
  kill_session
end

do_test 'id-67: step through a lick with musical events' do
  new_session
  tms 'harpwise licks --start-with two --comment holes-notes'
  tms :ENTER
  wait_for_start_of_pipeline
  3.times {
    tms '1'
  }
  sleep 1
  expect { screen[15]['+1.c4  [ev1]      +1.c4     -1.d4  [ev2]     *+1.c4'] }
  kill_session
end

[['', 0.07, (7 .. 9), (6 .. 8)],
 [' --time-slice short', 0.03, (16 .. 20), (16 .. 20)]].each_with_index do |vals, idx|
  extra_args, wplayed, wsensed_short, wsensed_long = vals
  do_test "id-68a#{idx}: warbling at #{wsensed_short}, #{wsensed_long} with extra args '#{extra_args}'" do
    warble 400, wplayed, 3, 7
    new_session
    tms "harpwise listen c --comment warbles #{extra_args}"
    tms :ENTER
    wait_for_start_of_pipeline
    sleep 8
    {16 => [/^   1s avg +(\d+\.\d) =====/, wsensed_short],
     17 => [/^  max avg +(\d+\.\d) =====/, wsensed_short],
     19 => [/^   3s avg +(\d+\.\d) =====/, wsensed_long],
     20 => [/^  max avg +(\d+\.\d) =====/, wsensed_long]}.each do |lno, rr|
      regex, range = rr
      expect(lno, regex, range) { ( md = screen[lno].match(regex) ) && range.include?(md[1].to_f) }
    end
    kill_session
  end
end

do_test 'id-68b: set warble holes explicitly' do
  new_session
  tms 'harpwise listen --comment warbles'
  tms :ENTER
  wait_for_start_of_pipeline
  tms 'w'
  tms :ENTER
  sleep 2
  tms :RIGHT
  tms :ENTER
  sleep 2
  expect { screen[23]['Warbling between holes +1 and -1/'] }
  kill_session
end

do_test 'id-69: detect lag' do
  sound 20, 8
  # must be before new_session
  ENV['HARPWISE_TESTING']='lag'
  new_session
  tms 'harpwise listen a'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 8
  tms 'q'
  ENV['HARPWISE_TESTING']='1'
  expect { screen[10]['harpwise has been lagging behind at least once'] }
  kill_session
end

do_test 'id-69b: detect jitter' do
  sound 20, 8
  # must be before new_session
  ENV['HARPWISE_TESTING']='jitter'
  new_session
  tms 'harpwise listen a'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 8
  tms 'q'
  ENV['HARPWISE_TESTING']='1'
  expect { screen[9]['Jitter detected'] }
  kill_session
end

[['', (30 .. 50)],
 [' --time-slice medium', (30 .. 50)],
 [' --time-slice short', (90 .. 110)],
 [' --time-slice long', (10 .. 30)]].each_with_index do |vals, idx|
  extra_args, lpsrange = vals
  do_test "id-70a#{idx}: check loops per sec in #{lpsrange} with #{extra_args == '' ? 'defaults' : extra_args}" do
    sound 12, 8
    new_session
    tms 'harpwise listen a --debug ' + extra_args
    tms :ENTER
    wait_for_start_of_pipeline
    sleep 6
    tms 'q'
    expect { ( md = screen[20].match(/handle_holes_this_loops_per_second=>(\d+\.\d+)/) ) &&
             lpsrange.include?(md[1].to_f) }
    kill_session
  end
end

do_test 'id-72: record user in licks' do
  rfile = "#{$dotdir_testing}/usr_lick_rec.wav"
  FileUtils.rm(rfile) if File.exist?(rfile)
  sound 40, 2
  ENV['HARPWISE_TESTING']='player'
  new_session
  tms 'harpwise licks a --start-with mape'
  tms :ENTER
  wait_for_start_of_pipeline
  tms :C_R
  expect { screen[0]['-rec-'] }
  tms '1'
  sleep 1
  expect { screen[0]['-REC-'] }
  5.times {
    tms '1'
    sleep 1
  }
  sleep 2
  expect(rfile) { File.exist?(rfile) }
  expect { screen[-2][rfile] }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-72a: play user recording' do
  rfile = "#{$dotdir_testing}/usr_lick_rec.wav"
  new_session
  tms 'harpwise play user'
  tms :ENTER
  sleep 2
  expect { screen[4]["Playing #{rfile}"] }
  kill_session
end

do_test 'id-73: advance in licks by played sound' do
  sound 40, -5
  new_session
  tms 'harpwise licks a --start-with mape'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  expect { screen[0]['at 2 of 6 notes'] }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-74: player for licks' do
  FileUtils.rm $persistent_state_file if File.exist?($persistent_state_file)
  sound 40, 2
  ENV['HARPWISE_TESTING']='player'
  new_session
  tms 'harpwise licks a --start-with wade'
  tms :ENTER
  sleep 1
  tms ' '
  sleep 1
  expect { screen[8]['SPACE'] && screen[9] == ' to continue ...' }
  tms ' '
  sleep 1
  expect { screen[9]['go'] }
  tms '-'
  sleep 1
  expect { screen[9]['go replay'] }
  tms 'v'
  sleep 1
  expect { screen[9]['go replay -9dB'] }
  tms '<'
  sleep 1
  expect { screen[9]['x0.9'] }
  tms 'h'
  sleep 1
  expect { screen[11]['Keys available while playing a recording:'] }
  tms 'q'
  sleep 1
  expect { screen[19]['continue'] }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-75: player for user recording' do
  ENV['HARPWISE_TESTING']='player'
  new_session
  tms 'harpwise play user'
  tms :ENTER
  sleep 1
  tms ' '
  sleep 1
  expect { screen[6] == ' SPACE to continue ...' }
  tms ' '
  sleep 1
  expect { screen[6]['SPACE to continue ... go'] }
  tms 'h'
  sleep 1
  expect { screen[8] == 'Keys available while playing a recording:' }
  tms 'x'
  sleep 1
  expect { screen[14]['continue'] }
  # still alive after help ?
  tms ' '
  sleep 1
  expect { screen[16] == ' SPACE to continue ...' }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-76: transcribe a lick' do
  ENV['HARPWISE_TESTING']='player'
  new_session
  tms 'harpwise tools transcribe wade'
  tms :ENTER
  sleep 5
  expect { screen[11]['0.7: -2   1.9: -3/   2.8: -2   3.4: -2'] }
  expect { screen[14]['Playing (as recorded, for a a-harp): -2 (0.2)   -3/ (0.3)   -2 (0.4)'] }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-76a: print notes of scale g major' do
  new_session
  tms 'harpwise tools notes g'
  tms :ENTER
  sleep 5
  expect { screen[5]['c   d   e   f   g   a   b   c'] }
  expect { screen[10]['g   a   b   c   d   e   gf   g'] }
  expect { screen[11]['2   2   1   2   2   2    1'] }
  kill_session
end

ENV['HARPWISE_TESTING']='1'

do_test 'id-76b: helpful error message on unknown tool' do
  new_session
  tms 'harpwise tools x'
  tms :ENTER
  sleep 5
  expect { screen[13]['First argument for mode tools should be one of those listed above'] }
  kill_session
end

do_test 'id-77: print for chromatic' do
  new_session
  tms "harpwise print chromatic c4 e4 g4 c5 e5 g5 c6 --add-scales -"
  tms :ENTER
  sleep 1
  expect { screen[0]['c4.+1  e4.+2  g4.+3  c5.+4  e5.+6  g5.+7  c6.+8'] }
  kill_session
end

do_test 'id-77a: error on abbreviated type' do
  new_session
  tms "harpwise print chrom c4 e4 g4 c5 e5 g5 c6 --add-scales -"
  tms :ENTER
  sleep 1
  expect { screen[14]["ot 'chrom'"] }
  kill_session
end

do_test 'id-78: detect interval' do
  warble 40, 2, 3, 7
  new_session
  tms "harpwise listen c"
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 4
  expect { screen[14]['Interval:   +4  to   +5  is -4 st'] }
  kill_session
end

[[-5, 4, "\e[7m\e[94m e4  \e[0m\e[32m\e[49m g4"],
 [-2, 4, "\e[34m c4   e4  \e[7m\e[92m g4"]].each_with_index do |vals, idx|
  semi, line, text = vals
  do_test "id-79a#{idx}: check against semitone played #{semi}" do
    sound 10, semi
    new_session
    tms 'harpwise listen c chord-i --add-scales chord-iv,chord-v --display chart-notes'
    tms :ENTER
    wait_for_start_of_pipeline
    sleep 1
    expect { screen_col[line][text] }
    kill_session
  end
end

do_test 'id-80: play chord' do
  new_session
  tms 'harpwise play chord +1 +2 +3 -3/'
  tms :ENTER
  sleep 2
  expect { screen[8]['+1 (-9st)  +2 (-5st)  +3 (-2st)  -3/ (1st)'] }
  expect { screen[10]['Wave: sawtooth, Gap: 0.2, Len: 6'] }
  tms 'w'
  sleep 2
  expect { screen[12]['pluck'] }
  tms 'L'
  sleep 2
  expect { screen[13]['Len: 7'] }
  tms 'G'
  sleep 2
  expect { screen[14]['Gap: 0.3'] }
  tms 'h'
  sleep 2
  expect { screen[16]['Keys available while playing a chord'] }
  kill_session
end

do_test "id-81: listen with adhoc scale" do
  new_session
  tms 'harpwise listen c +1 +2 +3'
  tms :ENTER
  wait_for_start_of_pipeline
  sleep 1
  expect { screen_col[4]["\e[32m h4   h4   h14 \e[34m"] }
  expect { screen_col[8]["\e[32m h14 \e[7m\e[94m"] }
  kill_session
end

do_test "id-82: screen too small" do
  new_session 60,20
  tms 'harpwise listen c'
  tms :ENTER
  sleep 1
  expect { screen[5]['ERROR: Terminal is too small'] }
  kill_session
end

do_test 'id-83: unittest' do
  new_session
  tms 'harpwise develop unittest'
  tms :ENTER
  sleep 8
  expect { screen[21]['All unittests okay.'] }
  kill_session
end

do_test 'id-84: print list of players' do
  FileUtils.rm_r($players_pictures) if File.exist?($players_pictures)
  new_session
  tms 'harpwise print players'
  tms :ENTER
  sleep 8
  expect { screen[20][' players with details. Specify a single name'] }
  expect($players_pictures) {File.directory?($players_pictures)}
  kill_session
end

do_test 'id-85: print info about a specifc player' do
  new_session
  tms 'harpwise print player sonny'
  tms :ENTER
  sleep 2
  tms '1'
  sleep 2
  expect { screen[7]['Aleck Rice Miller'] }
  kill_session
end

do_test 'id-86: print details of players' do
  new_session
  tms 'harpwise print players all'
  tms :ENTER
  sleep 8
  expect { screen[21]['players with their details'] }
  kill_session
end

do_test 'id-87: player info in listen' do
  new_session
  tms 'harpwise listen c'
  tms :ENTER
  sleep 60
  tms 'p'
  sleep 1
  expect { screen.any? {|l| l["Press any key to go back to mode 'listen'"] }}
  kill_session
end

do_test 'id-88: read from fifo' do
  new_session
  tms 'harpwise listen c --read-fifo'
  tms :ENTER
  sleep 2
  File.write("#{$dotdir_testing}/control_fifo", 'q')
  sleep 1
  expect { screen.any? {|l| l['Terminating on user request'] }}
  kill_session
end

do_test 'id-89: quiz-flavour random' do
  new_session
  tms 'harpwise quiz random'
  tms :ENTER
  sleep 2
  expect { screen.any? {|l| l['Quiz Flavour is:'] }}
  expect { screen.any? {|l| l['Press any key to start'] }}
  kill_session
end

do_test 'id-90: quiz-flavour play-scale' do
  new_session
  tms 'harpwise quiz play-scale'
  tms :ENTER
  sleep 3
  expect { screen[11]['Quiz Flavour is:   play-scale'] }
  kill_session
end

do_test 'id-91: quiz-flavour play-inter' do
  new_session
  tms 'harpwise quiz play-inter'
  tms :ENTER
  sleep 3
  expect { screen[11]['Quiz Flavour is:   play-inter'] }
  kill_session
end

do_test 'id-92: quiz-flavour hear-scale easy' do
  new_session
  tms 'harpwise quiz hear-scale --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  expect { screen[8]["difficulty is 'EASY', taking 4 scales out of 19"] }
  expect { screen[16]['Choose the scale you have heard:'] }  
  tms 'HELP'
  tms :ENTER
  expect { screen[10]['Removing some choices'] }
  kill_session
end

do_test 'id-92a: quiz-flavour hear-scale hard' do
  new_session
  tms 'harpwise quiz hear-scale --difficulty hard'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 6
  expect { screen[8]["The difficulty is 'HARD', taking 7 scales out of 19"] }
  expect { screen[16]['Choose the scale you have heard:'] }
  kill_session
end

do_test 'id-92b: quiz-flavour chromatic hear-scale' do
  new_session
  tms 'harpwise quiz chromatic hear-scale'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 12
  expect { screen[16]['Choose the scale you have heard:'] }
  kill_session
end

do_test 'id-93: quiz-flavour hear-inter' do
  new_session
  tms 'harpwise quiz hear-inter --difficulty 0'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  expect { screen[16]['Choose the Interval you have heard:'] }
  tms 'SKIP'
  tms :ENTER
  sleep 1
  expect { screen[12]['The correct answer is'] }
  tms :ENTER
  sleep 1
  tms 'PLAY-ALL'
  tms :ENTER
  sleep 8
  expect { screen[11]['Octave'] }
  tms 'SOLVE'
  tms :ENTER
  expect { screen[13]['Playing interval of'] }
  kill_session
end

do_test 'id-94: quiz-flavour add-inter' do
  new_session
  tms 'harpwise quiz add-inter'
  tms :ENTER
  sleep 2
  tms :ENTER
  expect { screen[10]['and add interval'] || screen[10]['and subtract interval'] }
  tms 'SHOW-SEMIS'
  tms :enter
  expect { screen[6]['--1----2----3--'] }
  kill_session
end

do_test 'id-95: quiz-flavour key-harp-song' do
  new_session
  tms 'harpwise quiz key-harp-song'
  tms :ENTER
  sleep 2
  tms :ENTER
  expect { screen[9]['Given a HARP with key of'] || screen[9]['Given a SONG with key of'] }
  sleep 1
  tms 'help-play-answer'
  tms :ENTER
  expect { screen[9]['for answer-key of'] }  
  tms 'solve'
  tms :ENTER
  sleep 1
  tms :BSPACE
  expect { screen[6]['Same question again'] }  
  kill_session
end

# screen looks different, if a chord is played or a sequence of notes
do_test 'id-96: quiz-flavour hear-key' do
  new_session
  tms 'harpwise quiz hear-key --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 10
  txt = 'asks for this key'
  expect { screen.any? {|l| l[txt] }}
  tms 'help-other-seq'
  tms :ENTER
  txt = 'Sequence of notes changed'
  expect { screen.any? {|l| l[txt] }}
  sleep 10
  tms 'help-pitch'
  tms :ENTER
  sleep 1
  tms '+'
  tms 'q'
  sleep 4
  expect { screen.any? {|l| l['Please note, that this key'] }}
  expect { screen.any? {|l| l['Now compare key'] }}
  kill_session
end

do_test 'id-96b: quiz-flavour match-scale' do
  new_session
  tms 'harpwise quiz match-scale --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  expect { screen[16]['that contains all the holes'] }
  tms 'help-print-scales'
  tms :ENTER
  expect { screen[5]['mipe:   -2  -3/  +4  -4  -5  +6'] }  
  kill_session
end

do_test 'id-96c: quiz-flavour keep-tempo' do
  new_session
  sound 8, 2
  tms 'harpwise quiz keep-tempo --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  expect { screen[19]['Ready to play ?'] }
  tms :ENTER
  sleep 12
  expect { screen[4]['no beats found'] }
  kill_session
end

do_test 'id-96d: quiz-flavour hear-tempo' do
  new_session
  tms 'harpwise quiz hear-tempo --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  expect { screen[9]['Playing 6 beats of Tempo to find'] }
  tms 'compare'
  tms :ENTER
  sleep 1
  tms :ENTER
  sleep 4
  expect { screen[11]['Done with compare, BACK to original question.'] }  
  kill_session
end

do_test 'id-96e: quiz-flavour not-in-scale' do
  new_session
  tms 'harpwise quiz not-in-scale --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  expect { screen[11]['h1 h2 h3 h4'] }
  expect { screen[16]['Which hole does not belong to'] }
  tms 'show'
  tms :ENTER
  sleep 1
  tms :ENTER
  sleep 4
  expect { screen[9]['Play and show original scale shuffled'] }  
  kill_session
end

do_test 'id-97: hint in quiz-flavour replay' do
  new_session
  tms 'harpwise quiz replay --difficulty easy'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 1
  tms 'H'
  sleep 1
  tms 'solve-print'
  tms :ENTER
  sleep 1
  expect { screen[19].split.length == 4 }
  kill_session
end

do_test 'id-98: loop via signal' do
  new_session
  tms 'harpwise quiz ran'
  tms :ENTER
  sleep 2
  tms :ENTER
  sleep 2
  pid = %x(ps -ef).lines.find {|l| l['harpwise'] && l['ruby']}.split[1]
  system("kill -s SIGTSTP #{pid}")
  sleep 2
  expect { screen.any? {|l| l['Starting over with a different flavour'] }}
  kill_session
end

do_test 'id-99: widgets' do
  new_session
  tms 'harpwise dev wt'
  tms :ENTER
  sleep 1
  tms :RIGHT
  expect { screen[7]['Input #1: -?-'] }
  tms :ENTER
  expect { screen[8]['Input #2: -RETURN-'] }
  tms :TAB
  expect { screen[9]['Input #3: -TAB-'] }
  tms :BSPACE
  expect { screen[10]['Input #4: -BACKSPACE-'] }
  tms 'q'
  sleep 1
  tms :TAB
  tms :LEFT
  tms :RIGHT
  tms :ENTER
  expect { screen[15]['Answer: 2'] }
  kill_session
end

do_test 'id-100: tool diagnosis' do
  new_session
  tms 'harpwise tool diag'
  tms :ENTER
  sleep 2
  expect { screen[17]['Make some sound'] }
  tms :ENTER
  sleep 5
  expect { screen[18]['Listen and check'] }
  tms :ENTER
  sleep 5
  expect { screen[12]['Get hints on troubleshooting sox ?'] }
  tms 'y'
  sleep 2
  expect { screen[16]['Other options necessary for sox might be'] }
  kill_session
end

do_test 'id-101: change quiz flavour via TAB' do
  new_session
  tms 'harpwise quiz hear-key'
  tms :ENTER
  sleep 2
  tms :TAB
  sleep 1
  tms 'hear-inter'
  tms :ENTER
  expect { screen[17]['Quiz Flavour is:   hear-inter'] }
  kill_session
end

do_test 'id-102: help on flavours via TAB' do
  new_session
  tms 'harpwise quiz hear-key'
  tms :ENTER
  sleep 2
  tms :TAB
  sleep 1
  tms 'describe-all'
  tms :ENTER
  expect { screen[20]['harpwise plays a sequence'] }
  kill_session
end

do_test 'id-103: tool search-scale-in-licks' do
  new_session
  tms 'harpwise tool search-scale-in-licks blues-middle'
  tms :ENTER
  wait_for_end_of_harpwise
  expect { screen[16]['blues  box1-i  box2-i'] }
  expect { screen[20]['feeling-bad  box1-iv  box2-iv  three'] }
  kill_session
end

puts
puts
