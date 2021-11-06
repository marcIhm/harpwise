#
# Utilities for testing with run.rb
#

def new_session
  kill_session
  sys "tmux -u new-session -d -x #{$sut[:term_min_width]} -y #{$sut[:term_min_height]} -s hst"
  tms 'cd harp_scale_trainer'
  tms :ENTER
end


def kill_session
  system "tmux kill-session -t hst >/dev/null 2>&1"
end


def sys cmd
  out, stat = Open3.capture2e(cmd)
  stat.success? || fail("Command '#{cmd}' failed with:\n#{out}")
end
  

def tms cmd
  if cmd.is_a?(Symbol)
    sys "tmux send -t hst #{cmd.to_s.tr('_','-')}"
  else
    sys "tmux send -l -t hst \"#{cmd}\""
  end
end


def screen
  %x(tmux capture-pane -t hst -p).lines.map!(&:chomp)
end


def expect &block
  if yield
    print "\e[32mOkay \e[0m"
  else
    puts
    source = block.to_source
    pp screen if source['screen']
    puts "\e[31mNOT Okay\e[0m"
    puts source
    kill_session
    exit 1
  end
end


def sound secs, semi
    sys "sox -n /tmp/harp_scale_trainer_testing.wav synth #{secs} sawtooth %#{semi} gain -n -3"
end


$memo_file = "#{Dir.home}/harp_scale_trainer_test_memo.json"
$memo_count = 0
$memo_seen = Set.new
$memo = File.exist?($memo_file)  ?  JSON.parse(File.read($memo_file))  :  {count: '?', times: {}}
$memo.transform_keys!(&:to_sym)

def memorize text
  puts
  $memo_count += 1
  $memo_seen << text
  maxlen = $memo[:times].keys.map {|k| k.length}.max || 0
  time = $memo[:times][text]
  print "  #{text.ljust(maxlen)}    #{$memo_count} of #{$memo[:count]}    #{time ? ('%5.1f' % time) : '?'} secs ... "
  start = Time.now.to_f
  yield
  $memo[:times][text] = Time.now.to_f - start
end

at_exit {
  if $!.nil? || $!.success?
    $memo[:count] = $memo_count
    $memo[:times].each_key {|k| $memo[:times].delete(k) unless $memo_seen === k}
  end
  File.write($memo_file, JSON.pretty_generate($memo))
}
