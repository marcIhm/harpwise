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
  tms 'cd ~/harp-wizard'
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
  # let typed command appear on screen
  sleep 0.5
  if cmd.is_a?(Symbol)
    sys "tmux send -t ht #{cmd.to_s.tr('_','-')}"
  else
    sys "tmux send -l -t ht \"#{cmd}\""
  end
  sleep 0.5
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
    sys "sox -n /tmp/harp-wizard_testing.wav synth #{secs} sawtooth %#{semi} gain -n -3"
end


$memo_file = "#{Dir.home}/.harp-wizard_test_memo.json"
$memo_count = 0
$memo_seen = Set.new
$memo = File.exist?($memo_file)  ?  JSON.parse(File.read($memo_file))  :  {count: '?', durations: {}}
$memo.transform_keys!(&:to_sym)
$fromon_id_uniq = Set.new

def do_test text
  $memo_count += 1
  if md = text.match(/#{$fromon_id_regex}/)
    id = md[1]
    fail "Test-id #{id} has already appeared" if $fromon_id_uniq.include?(id)
    $fromon_id_uniq << id
  else
    fail "Test '#{text}' should start with an id"
  end
  $within = true if ( $fromon_cnt && $memo_count == $fromon_cnt ) ||
                    ( $fromon_id && text.start_with?($fromon_id))
  ( $fromon && text[$fromon] )
  return unless $within
  puts
  [$testing_dump_file, $testing_log_file].each do |file|
    File.delete(file) if File.exists?(file)
  end
  $memo_seen << text
  maxlen = $memo[:durations].keys.map {|k| k.length}.max || 0
  time = $memo[:durations][text]
  print "  #{text.ljust(maxlen)}    #{$memo_count.to_s.rjust(2)} of #{$memo[:count].to_s.rjust(2)}    #{time ? ('%5.1f' % time) : '?'} secs ... "
  start = Time.now.to_f
  yield
  $memo[:durations][text] = Time.now.to_f - start
end


def read_testing_output
  JSON.parse(File.read($testing_dump_file), symbolize_names: true)
end


def read_testing_log
  File.readlines($testing_log_file)
end


at_exit {
  if $!.nil?
    $memo[:count] = $memo_count
    $memo[:durations].each_key {|k| $memo[:durations].delete(k) unless $memo_seen === k}
  end
  File.write($memo_file, JSON.pretty_generate($memo)) unless $fromon&.length > 0
}
