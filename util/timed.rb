#!/usr/bin/ruby

# This script plays an mp3 and sends keys (e.g. 'l') to harpwise
# (which must be started separately). This can be used e.g. to switch
# the lick, that is displayed in 'harpwise listen', in sync with
# chord-changes of the played mp3.

# The only argument is a json file with all needed informations, e.g.:
# {
#     "sound_file": "some-song.mp3",
#     "lead_for_keys": 0.5,
#     "sleep_before_start": 0.2,
#     "sleep_after_iteration": 0.2,
#     "timestamps_and_keys": [
# 	[5.868409, "l"],
# 	[15.47452, "l"],
# 	[20.209422, "l"],
# 	[24.93715, "l"],
# 	[27.333297, "l"],
# 	[29.6864, "l"],
# 	[30.442824, "l","s"],
# 	[34.442824, "l","s"]
#     ]
# }



require 'timeout'
require 'json'
require 'set'

fifo = "#{Dir.home}/.harpwise/control_fifo"

ARGV[0] || raise("No argument provided; however a json file with parameters is needed; see comments in this script for an example.")
params = JSON.parse(File.read(ARGV[0]))
wanted = %w(timestamps_to_keys sound_file lead_for_keys sleep_before_start sleep_after_iteration)
given = params.keys
raise("Found keys: #{given}, but wanted: #{wanted} in #{ARGV[0]}") if Set[*given] != Set[*wanted]
raise("Value '#{params['timestamps_to_keys']}' should be an array") unless params['timestamps_to_keys'].is_a?(Array)

puts
timestamps_to_keys = params['timestamps_to_keys']
sound_file = params['sound_file']
lead_for_keys = params['lead_for_keys']
sleep_before_start = params['sleep_before_start']
sleep_after_iteration = params['sleep_after_iteration']
raise("Given mp3 #{sound_file} does not exist") unless File.exist?(sound_file)

Thread.new do
  system "play -q #{sound_file}"
  sleep 1
  puts
  puts "Done."
  exit
end
at_exit do
  system "killall play >/dev/null 2>&1"
end
puts

sleep_secs = timestamps_to_keys[0][0] + sleep_before_start
puts "Initial sleep %.2f sec" % sleep_secs
sleep sleep_secs
i = 0
loop do
  i += 1
  puts
  puts "ITERATION #{i}:"
  puts
  timestamps_to_keys.each_cons(2).each_with_index do |pair,j|
    x,y = pair[0][0], pair[1][0]
    keys_to_send = pair[0][1 .. -1]
    puts "Interval #{j+1}/#{timestamps_to_keys.length-1}:"
    puts "sleep %.2f sec" % (y - x)
    this_lead_for_keys = ( y - x > lead_for_keys  ?  lead_for_keys  :  0 )
    sleep y - x - this_lead_for_keys
    keys_to_send.each do |key|
      begin
        Timeout::timeout(1) do
          File.write(fifo, key)
        end
      rescue Timeout::Error
        puts "Error: Could not write '#{key}' to #{fifo}. Is harpwise listening on the other side ?"
        exit
      end
      puts "wrote '#{key}'"
    end
    sleep this_lead_for_keys
    puts
  end
  puts "Sleep after iteration %.2f sec" % sleep_after_iteration
  sleep sleep_after_iteration
end
