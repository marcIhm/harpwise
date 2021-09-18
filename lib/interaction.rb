#
# Handle user-interaction (e.g. printing and reading of input)
#


def prepare_screen
  h, w = %x(stty size).split.map(&:to_i)
  err_b "Terminal is too small: [width, height] = #{[w,h].inspect} < [84,32]" if w < 84 || h < 32
  STDOUT.sync = true
  [h, w]
end


def err_h text
  puts "ERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  puts
  exit 1
end


def err_b text
  puts "ERROR: #{text} !"
  puts
  exit 1
end


def dbg text
  puts "DEBUG: #{text}" if $opts[:debug] > 1
  text
end


def sys cmd
  out = Open3.capture2e(dbg cmd)
  $? == 0 || fail("Command '#{cmd}' failed with:\n#{out}")
end
  

$figlet_cache = Hash.new
def do_figlet text, font
  cmd = "figlet -d fonts -f #{font} -c \" #{text}\""
  $figlet_cache[cmd], _ = Open3.capture2e(cmd) unless $figlet_cache[cmd]
  $figlet_cache[cmd].lines.each do |line, idx|
    print "#{line.chomp}\e[K\n"
  end
  print"\e[0m"
end


def prepare_term
  system("stty -echo -icanon min 1 time 0")  # no timeout on read, one char is enough
  print "\e[?25l"  # hide cursor
end


def dismiss_term
  system("stty -raw")
  system("stty sane")
  print "\e[?25h"  # show cursor
end


def poll_and_handle_kb_listen
  return unless Time.now.to_f - $ctl_last_poll > 1
  $ctl_last_poll = Time.now.to_f 
  char = ''
  begin
      char = STDIN.read_nonblock(1)
  rescue IO::EAGAINWaitReadable
  end

  if char == ' '
    print "SPACE to continue ... "
    begin
      char = STDIN.getc
    end until char == " "
  elsif char && char.length > 0 && char.ord == 127
    $ctl_back = true
  end
end


def poll_and_handle_kb_play
  return unless Time.now.to_f - $ctl_last_poll > 1
  $ctl_last_poll = Time.now.to_f 
  char = ''
  begin
      char = STDIN.read_nonblock(1)
  rescue IO::EAGAINWaitReadable
  end

  if char == ' '
    ctl_issue "SPACE to continue", hl: true
    begin
      char = STDIN.getc
    end until char == " "
  elsif char == "\n" && $ctl_can_next
    $ctl_next = true
    text = "Skip"
  elsif char && char.length > 0 && char.ord == 127 && $ctl_can_next
    $ctl_back = true
    text = "Skip back"
  elsif char == 'l' && !$opts[:loop] && $ctl_can_next
    $ctl_loop = true
    text = "Loop started"
  elsif char.length > 0
    text = "Invalid char '#{char.match?(/[[:print:]]/) ? char : '?'}'"
  end
  ctl_issue text
end


def ctl_issue text = nil, **opts
  if text
    $ctl_non_def_issue_ts = Time.now.to_f
  elsif $ctl_non_def_issue_ts
    return if Time.now.to_f - $ctl_non_def_issue_ts < 3
  end
  text ||= $ctl_default_issue
  fail "Internal error text '#{text}' is longer (#{text.length} chars) than #{$ctl_issue_width}" if text.length > $ctl_issue_width
  print "\e[1;#{$term_width - $ctl_issue_width}H\e[#{opts[:hl] ? 33 : 2}m#{text.rjust($ctl_issue_width)}\e[0m"
end
  

def read_answer answer2chars_desc
  klists = Hash.new
  answer2chars_desc.each do |an, ks_d|
    klists[an] = ks_d[0].join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  answer2chars_desc.each do |an, ks_d|
    puts "  %*s :  %s" % [maxlen, klists[an], ks_d[1]]
  end

  begin
    print "\nYour choice (press a single key): "
    char = one_char
    char = case char
           when "\r", "\n"
             'RETURN'
           when ' '
             'SPACE'
           else
             char
           end
    puts char
    puts
    answer = nil
    answer2chars_desc.each do |an, ks_d|
      answer = an if ks_d[0].include?(char)
    end
    puts "Invalid key: '#{char.match?(/[[:print:]]/) ? char : '?'}' (#{char.ord})" unless answer
  end while !answer
  answer
end


def draw_data file, from, to, marker
  sys "sox #{file} tmp/sound-to-plot.dat"
  IO.write 'tmp/sound.gp', <<EOGPL
set term dumb #{$term_width - 2} #{$term_height - 2}
set datafile commentschars ";"
set xlabel "time (s)"
set xrange [#{from}:#{to}]
set ylabel "sample value"
set nokey
set arrow from #{marker}, graph 0 to #{marker}, graph 1 nohead
plot "#{file}" using 1:2
EOGPL
  system "gnuplot tmp/sound.gp"
end


def one_char
  system("stty raw -echo")
  char = STDIN.getc
  system("stty -raw echo")
  if char && char[0] && char[0].ord == 3
    puts "\nexit on ctrl-c"
    exit 1
  end
  char
end  
