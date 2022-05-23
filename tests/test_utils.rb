#
# Utilities for testing with run.rb
#

def new_session
  kill_session
  #
  # The simple command below does not work because of a bug in tmux 3.2a:
  # (use 'tmux -V' to get version)
  #
  #   sys "tmux -u new-session -d -x #{$sut[:term_min_width]} -y #{$sut[:term_min_height]} -s ht"
  #
  # So we use a workaround according to https://unix.stackexchange.com/questions/359088/how-do-i-force-a-tmux-window-to-be-a-given-size
  #
  sys "tmux new-session -d -x #{$sut[:term_min_width]} -y #{$sut[:term_min_height]} -s ht \\; new-window bash \\; kill-window -t 0"
  tms 'cd harp_trainer'
  tms :ENTER
end


def kill_session
  system "tmux kill-session -t ht >/dev/null 2>&1"
end


def sys cmd
  out, stat = Open3.capture2e(cmd)
  stat.success? || fail("Command '#{cmd}' failed with:\n#{out}")
end
  

def tms cmd
  if cmd.is_a?(Symbol)
    sys "tmux send -t ht #{cmd.to_s.tr('_','-')}"
  else
    sys "tmux send -l -t ht \"#{cmd}\""
  end
end


def screen
  %x(tmux capture-pane -t ht -p).lines.map!(&:chomp)
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
    sys "sox -n /tmp/harp_trainer_testing.wav synth #{secs} sawtooth %#{semi} gain -n -3"
end


$memo_file = "#{Dir.home}/.harp_trainer_test_memo.json"
$memo_count = 0
$memo_seen = Set.new
$memo = File.exist?($memo_file)  ?  JSON.parse(File.read($memo_file))  :  {count: '?', times: {}}
$memo.transform_keys!(&:to_sym)

def do_test text
  $memo_count += 1
  $within = true if ( $fromon_idx && $memo_count == $fromon_idx ) ||
                    ( $fromon && text[$fromon] )
  return unless $within
  puts
  File.delete($testing_dump_file) if File.exists?($testing_dump_file)
  $memo_seen << text
  maxlen = $memo[:times].keys.map {|k| k.length}.max || 0
  time = $memo[:times][text]
  print "  #{text.ljust(maxlen)}    #{$memo_count.to_s.rjust(2)} of #{$memo[:count].to_s.rjust(2)}    #{time ? ('%5.1f' % time) : '?'} secs ... "
  start = Time.now.to_f
  yield
  $memo[:times][text] = Time.now.to_f - start
end

def read_testing_output
  fail "Dump with data to test does not exist: #{$testing_dump_file}" unless File.exists?($testing_dump_file)
  JSON.parse(File.read($testing_dump_file), symbolize_names: true)
end

at_exit {
  if $!.nil? || $!.success?
    $memo[:count] = $memo_count
    $memo[:times].each_key {|k| $memo[:times].delete(k) unless $memo_seen === k}
  end
  File.write($memo_file, JSON.pretty_generate($memo)) unless $fromon
}
