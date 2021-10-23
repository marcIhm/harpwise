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


def it
  %x(tmux capture-pane -t hst -p).lines.map!(&:chomp)
end


def expect &block
  if yield
    puts "\e[32mOkay\e[0m"
    kill_session
  else
    pp it
    puts "\e[31mNOT Okay\e[0m"
    puts block.to_source
    kill_session
    exit 1
  end
end


def sound secs, semi
    sys "sox -n tmp/testing.wav synth #{secs} sawtooth %#{semi} gain -n -3"
end
