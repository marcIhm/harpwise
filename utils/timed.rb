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


def send_keys keys
  keys.each do |key|
    begin
      Timeout::timeout(1) do
        File.write($fifo, key + "\n")
      end
    rescue Timeout::Error
      puts "Error: Could not write '#{key}' to #{$fifo}. Is harpwise listening on the other side ?"
      exit
    end
    puts "sent key '#{key}'"
  end
end

def do_action action, iter
  if action[0] == 'message' || action[0] == 'start'
    raise("Need exactly one string and a number after 'message'; not #{action}") if action.length != 3 || !action[1].is_a?(String) || !action[2].is_a?(Numeric)
    raise("Message to be sent can only be one line, but this has more: #{action[1]}") if action[1].lines.length > 1
    File.write($message, ( action[1].chomp % iter ) + "\n" + action[2].to_s + "\n")
    puts "sent message '#{action[1].chomp % iter}'"
    send_keys ["ALT-m"]
  elsif action[0] == 'keys'
    send_keys action[1 .. -1]
  elsif action[0] == 'again'
    # this is the last timestamp; do nothing and continue with next
    # iteration
    raise("No other arguments allowed after 'again'; not #{action}") if action.length != 1
  else
    fail("Internal error: unknown type '#{action[0]}', but this should have been noticed above already")
  end
end


ARGV[0] || raise("No argument provided; however a json file with parameters is needed; see comments in this script for an example.")
raise("Ony one argument allowed, not #{ARGV}") if ARGV.length > 1
params = JSON.parse(File.read(ARGV[0]))
wanted = Set.new(%w(timestamps_to_actions sound_file offset sleep_initially sleep_after_iteration sox_opts multiply comment))
given = Set.new(params.keys)
raise("Found keys:\n\n#{given.pretty_inspect}\n\n, but wanted:\n\n#{wanted.pretty_inspect}\n\nin #{ARGV[0]}, symmetrical diff is:\n\n#{(given ^ wanted).pretty_inspect}\n") if given != wanted
raise("Value '#{params['timestamps_to_actions']}' should be an array") unless params['timestamps_to_actions'].is_a?(Array)

puts
timestamps_to_actions = params['timestamps_to_actions']
sound_file = params['sound_file']
offset = params['offset']
sleep_after_iteration = params['sleep_after_iteration']
multiply = params['multiply']
comment = params['comment']
sleep_initially = params['sleep_initially']
raise("Given mp3 #{sound_file} does not exist") unless File.exist?(sound_file)

# preprocess to allow negative timestamps as relative to preceding ones
while i_neg = (0 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] < 0}
  loc_neg = "negative timestamp at position #{i_neg}, content #{timestamps_to_actions[i_neg]}"
  i_pos_after_neg = (i_neg + 1 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] > 0}
  raise("#{loc_neg.capitalize} is not followed by positive timestamp") unless i_pos_after_neg
  loc_pos_after_neg = "following positive timestamp at position #{i_pos_after_neg}, content #{timestamps_to_actions[i_pos_after_neg]}"
  ts_abs = timestamps_to_actions[i_pos_after_neg][0] + timestamps_to_actions[i_neg][0]
  raise("When adding   #{loc_neg}   to   #{loc_pos_after_neg}   we come up with a negative absolute time: #{ts_abs}") if ts_abs < 0
  timestamps_to_actions[i_neg][0] = ts_abs
end

timestamps_to_actions.sort_by! {|ta| ta[0]}
act_at = Hash.new
timestamps_to_actions.each_with_index do |ta,idx|
  raise("First word after timestamp must either be 'message', 'start' or 'keys', but here (index #{idx}) it is '#{ta[1]}':  #{ta}") unless %w(message start keys again).include?(ta[1])
  raise("Timestamp #{ta[0]} (index #{idx}, #{ta}) is less than zero") if ta[0] < 0
  %w(start again).each do |act|
    if ta[1] == act
      raise("Action '#{act}' already appeared with index #{act_at[act]}: #{timestamps_to_actions[act_at[act]]}, cannot appear again with index #{idx}: #{ta}") if act_at[act]
      act_at[act] = idx
    end
  end
end
raise("Need at least one timestamp with action 'start'") unless act_at['start']
raise("Action 'again', if it appears at all, must be last action, not #{act_at['again']}") if act_at['again'] && act_at['again'] != timestamps_to_actions.length - 1

timestamps_to_actions.each_with_index do |ta,idx|
  ta[0] *= multiply
  ta[0] += offset
  ta[0] = 0.0 if ta[0] < 0
end

if comment.length > 0
  puts "Comment: " + comment
  puts
end

if sleep_initially > 0
  do_action ['message',
             'sleep initially for %.1d secs' % sleep_initially,
             [0.0, sleep_initially - 0.2].max.round(1)],
            0
  sleep sleep_initially
end

cmd = "play -q #{sound_file} #{params['sox_opts']}"
puts cmd
puts
Thread.new do
  system cmd
  sleep 1
  puts
  puts "Backing track has ended."
  puts
  exit
end

at_exit do
  system "killall play >/dev/null 2>&1"
end

sleep_secs = timestamps_to_actions[0][0]
puts "Initial sleep %.2f sec" % sleep_secs
sleep sleep_secs

(1 .. ).each do |iter|
  puts
  puts "ITERATION #{iter}:"
  puts
  pp timestamps_to_actions
  puts
  timestamps_to_actions.each_cons(2).each_with_index do |pair,j|

    tsx, tsy = pair[0][0], pair[1][0]
    action = pair[0][1 .. -1]
    puts "Action #{j + 1}/#{timestamps_to_actions.length - 1}:"

    do_action action, iter

    sleep_between = tsy - tsx
    puts "sleep %.2f sec" % sleep_between
    sleep sleep_between
    puts

  end

  do_action timestamps_to_actions[-1][1 .. -1], iter
  
  puts "Sleep after iteration %.2f sec" % ( sleep_after_iteration * multiply )
  sleep sleep_after_iteration * multiply

  if iter == 1
    while timestamps_to_actions[0][1] != 'start'
      timestamps_to_actions.shift
    end
  end
end
