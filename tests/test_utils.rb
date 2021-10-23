#
# Utilities for testing with run.rb
#

# override a method loaded from lib
def dbg text
  text
end

def expect found, expected
  if found == expected
    puts "\e[32mOkay\e[0m"
  else
    puts "\e[31mNOT Okay\e[0m"
    puts "Expected '#{expected}' but found '#{found}'"
    exit 1
  end
end

def new_session
  kill_session get_result: false
  sys "tmux -u new-session -d -x #{$sut[:term_min_width]} -y #{$sut[:term_min_height]} -s #{$sname}"
  $tms = "tmux send -t #{$sname}"
  $tmsl = "tmux send -l -t #{$sname}"
  sys "#{$tmsl} 'cd harp_scale_trainer'"
  sys "#{$tms} ENTER"
  end

def kill_session get_result: true
  result = %x(tmux capture-pane -t #{$sname} -p).lines.map!(&:chomp) if get_result
  system "tmux kill-session -t #{$sname} >/dev/null 2>&1"
  result if get_result
end

