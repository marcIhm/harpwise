#!/usr/bin/ruby

# This script plays an mp3 and sends keys (e.g. 'l') to harpwise
# (which must be started separately). This can be used e.g. to switch
# the lick, that is displayed in 'harpwise listen', in sync with
# chord-changes of the played mp3.

# The only argument is a json file with all needed informations, e.g. timed_sample.json

require 'timeout'
require 'json'
require 'set'
require 'pp'

$fifo = "#{Dir.home}/.harpwise/remote_fifo"
$message = "#{Dir.home}/.harpwise/remote_message"
$usage = "\n\nUSAGE:\n         #{$0}  PARAM-FILE.json\n\n,where timed_sample.json would be an example for a param-file.\n\n"

def err txt
  puts "\nERROR: #{txt}\n\n"
  exit 1
end

def send_keys keys
  keys.each do |key|
    begin
      Timeout::timeout(0.5) do
        File.write($fifo, key + "\n")
      end
    rescue Timeout::Error, Errno::EINTR
      err "Could not write '#{key}' to #{$fifo}. Is harpwise listening on the other side ?"
    end
    puts "sent key '#{key}'"
  end
end

def do_action action, iter, noop: false
  if action[0] == 'message' || action[0] == 'loop-start'
    if action.length != 3 || !action[1].is_a?(String) || !action[2].is_a?(Numeric)
      err("Need exactly one string and a number after 'message'; not #{action}")
    end
    if action[1].lines.length > 1
      err("Message to be sent can only be one line, but this has more: #{action[1]}")
    end
    return if noop
    File.write($message, ( action[1].chomp % iter ) + "\n" + action[2].to_s + "\n")
    puts "sent message '#{action[1].chomp % iter}'"
    send_keys ["ALT-m"]
  elsif action[0] == 'keys'
    return if noop
    send_keys action[1 .. -1]
  else
    err("Unknown type '#{action[0]}'")
    return if noop
  end
end

err("No argument provided; however a json file with parameters is needed; see comments in this script for an example." + $usage) if !ARGV[0]
err("Only one or two argument allowed, not #{ARGV}" + $usage) if ARGV.length > 2

num_command = if ARGV[1]
                begin 
                  Integer(ARGV[1])
                rescue ArgumentError
                  err("Provided second argument  '#{ARGV[1]}'  is not a number" + $usage)
                end
              else
                0
              end
puts

#
# Process parameters
#
params = JSON.parse(File.read(ARGV[0]).lines.reject {|l| l.match?(/^\s*\/\//)}.join)
timestamps_to_actions = params['timestamps_to_actions']
sleep_after_iteration = params['sleep_after_iteration']
timestamps_multiply = params['timestamps_multiply']
comment = params['comment']
example = params['example_harpwise']
sleep_initially = params['sleep_initially']
play_command = params['play_command']

# under wsl2 we may actually use explorer.exe (windows-command !) to start playing
play_with_win = play_command['explorer.exe'] || play_command['wslview']

# check if all parameters present
wanted = Set.new(%w(timestamps_to_actions sleep_initially sleep_after_iteration play_command timestamps_multiply comment example_harpwise))
given = Set.new(params.keys)
err("Found keys:\n\n#{given.pretty_inspect}\n\n, but wanted:\n\n#{wanted.pretty_inspect}\n\nin #{ARGV[0]}, symmetrical diff is:\n\n#{(given ^ wanted).pretty_inspect}\n") if given != wanted
err("Value '#{params['timestamps_to_actions']}' should be an array") unless params['timestamps_to_actions'].is_a?(Array)

#
# preprocess and check list of timestamps
#

# preprocess to allow negative timestamps as relative to preceding ones
while i_neg = (0 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] < 0}
  loc_neg = "negative timestamp at position #{i_neg}, content #{timestamps_to_actions[i_neg]}"
  i_pos_after_neg = (i_neg + 1 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] > 0}
  err("#{loc_neg.capitalize} is not followed by positive timestamp") unless i_pos_after_neg
  loc_pos_after_neg = "following positive timestamp at position #{i_pos_after_neg}, content #{timestamps_to_actions[i_pos_after_neg]}"
  ts_abs = timestamps_to_actions[i_pos_after_neg][0] + timestamps_to_actions[i_neg][0]
  err("When adding   #{loc_neg}   to   #{loc_pos_after_neg}   we come up with a negative absolute time: #{ts_abs}") if ts_abs < 0
  timestamps_to_actions[i_neg][0] = ts_abs
end

# check syntax of timestamps before actually starting
timestamps_to_actions.sort_by! {|ta| ta[0]}
loop_start_at = nil
timestamps_to_actions.each_with_index do |ta,idx|
  err("First word after timestamp must either be 'message', 'keys' or 'loop-start', but here (index #{idx}) it is '#{ta[1]}':  #{ta}") unless %w(message keys loop-start).include?(ta[1])
  err("Timestamp #{ta[0]} (index #{idx}, #{ta}) is less than zero") if ta[0] < 0
  # test action
  do_action(ta[1 ..], 0, noop: true)
  if ta[1] == 'loop-start'
    err("Action 'loop-start' already appeared with index #{loop_start_at}: #{timestamps_to_actions[loop_start_at]}, cannot appear again with index #{idx}: #{ta}") if loop_start_at
    loop_start_at = idx
  end
end
err("Need at least one timestamp with action 'loop-start'") unless loop_start_at

# transformations
timestamps_to_actions.each_with_index do |ta,idx|
  ta[0] *= timestamps_multiply
  ta[0] = 0.0 if ta[0] < 0
end

#
# Start doing user-visible things
#

if comment.length > 0
  puts "Comment:\n\n  \e[32m" + comment + "\e[0m\n\n"
  puts
end

if example.length > 0
  puts "Invoke harpwise like this:\n\n  \e[32m" + example + "\e[0m\n\n"
  puts
end

# allow for testing
if ENV["HARPWISE_TESTING"]
  puts "Environment variable 'HARPWISE_TESTING' is set; exiting before play."
  exit 0
end

# try to figure out file and check if present even before first sleep
endings = %w(.mp3 .wav .ogg)
file = play_command.split.find {|word| endings.any? {|ending| word.end_with?(ending)}} || err("Couldn't find filename in play_command  '#{play_command}'\nno word ends on any of: #{endings.join(' ')}")
err("File mentioned in play-command does not exist:  #{file}") unless File.exist?(file)

# make some room below to have initial error (if any) without scrolling
print "\n\n\n\n\e[4A"

if sleep_initially > 0
  do_action ['message',
             'sleep initially for %.1d secs' % sleep_initially,
             [0.0, sleep_initially - 0.2].max.round(1)],
            0
  sleep sleep_initially
end

puts play_command
puts

# start playing
Thread.new do
  puts "\n\nStarting:\n\n    #{play_command}\n\n"
  if play_with_win
    # avoid spurious output of e.g. media-player
    system "#{play_command} >/dev/null 2>&1"
  else
    system play_command
  end
  puts
  if play_with_win
    puts "Assuming this is played with windows-programs, not waiting for its end.\n\n"
  else
    sleep 1
    puts
    puts "Backing track has ended."
    puts
    exit 0
  end
end

at_exit do
  system "killall play >/dev/null 2>&1" unless play_with_win
end

sleep_secs = timestamps_to_actions[0][0]
puts "Initial sleep %.2f sec" % sleep_secs
sleep sleep_secs
ts_prog_start = Time.now.to_f
ts_iter_start = nil

# endless loop one iteration after the other
(1 .. ).each do |iter|
  ts_iter_start_prev = ts_iter_start
  ts_iter_start = Time.now.to_f
  puts
  puts "ITERATION #{iter}"
  if ts_iter_start_prev
    puts "%.1f secs after startup, last iteration took %.1f secs" %
         [ts_iter_start - ts_prog_start, ts_iter_start - ts_iter_start_prev ]
  end
  puts
  pp timestamps_to_actions
  puts

  # one action after the other
  timestamps_to_actions.each_cons(2).each_with_index do |pair,j|

    tsx, tsy = pair[0][0], pair[1][0]
    action = pair[0][1 .. -1]
    puts "Action #{j + 1}/#{timestamps_to_actions.length - 1}:"

    do_action action, iter

    sleep_between = tsy - tsx
    puts "at ts %.2f sec" % tsx
    puts "sleep %.2f sec" % sleep_between
    if j + 1 == timestamps_to_actions.length - 1
      # This allows sleep_after_iteration to be negative; we may simply add
      # sleep_after_iteration to the last timestamp, but we want to make it explicit in
      # output
      puts "and sleep after iteration %.2f sec" % ( sleep_after_iteration * timestamps_multiply )
      sleep sleep_between + ( sleep_after_iteration * timestamps_multiply )
    else
      sleep sleep_between
    end
    puts

  end  ## one action after the other

  do_action timestamps_to_actions[-1][1 .. -1], iter
  
  if iter == 1
    while timestamps_to_actions[0][1] != 'loop-start'
      timestamps_to_actions.shift
    end
  end
end  ## endless loop one iteration after the other
