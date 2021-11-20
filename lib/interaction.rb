#
# Handle user-interaction (e.g. printing and reading of input)
#


def prepare_screen
  STDOUT.sync = true
  %x(stty size).split.map(&:to_i)
end


def check_screen graceful: false

  begin
    # check screen-size
    if $term_width < $conf[:term_min_width] || $term_height < $conf[:term_min_height]
      raise ArgumentError.new("Error: Terminal is too small: [width, height] = #{[$term_width, $term_height].inspect} < [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]")
    end

    # check for size of chart
    xroom = $term_width - $chart.map {|r| r.join.length}.max - 2
    raise ArgumentError.new("Terminal has not enough columns for chart from #{$chart_file} (by #{-xroom} columns)") if xroom < 0
    yroom = $line_hole - $line_display - $chart.length
    raise ArgumentError.new("Terminal has not enought lines for chart from #{$chart_file} (by #{-yroom} lines)") if yroom < 0

    yoff = ( yroom - 1 ) / 2
    yoff -= 1 if yoff > 0
    $conf[:chart_offset_xyl][0..1] = [ (xroom * 0.4).to_i, yoff ]

    # check for maximum value of $line_xx_ variables
    bottom_line = bottom_line_var = 0
    global_variables.each do |var|
      if var.to_s.start_with?('$line_') && eval(var.to_s) > bottom_line
        bottom_line = eval(var.to_s)
        bottom_line_var = var
      end
    end
    if bottom_line > $term_height + 1
      raise ArgumentError.new("Variable #{bottom_line_var} = #{bottom_line} is larger than terminal height = #{$term_height}")
    end

  rescue ArgumentError => e
    err_b "Error: #{e}" unless graceful
    puts e
    return false
  end
  return true
end


def sys cmd
  out, stat = Open3.capture2e(dbg cmd)
  stat.success? || fail("Command '#{cmd}' failed with:\n#{out}")
end
  
$figlet_cache = Hash.new
def do_figlet text, font
  cmd = "figlet -d fonts -f #{font} -l \" #{text}\""
  unless $figlet_cache[cmd]
    out, _ = Open3.capture2e(cmd)
    maxline = out.lines.map {|l| l.length}.max
    offset = if maxline > 0.6 * $term_width
               0
             elsif maxline > 0.4 * $term_width
               0.1 * $term_width
             else
               0.2 * $term_width
             end
    $figlet_cache[cmd] = out.lines.map {|l| ' ' * offset + l.chomp}.join("\n")
  end
  $figlet_cache[cmd].lines.each do |line|
    print "#{line.chomp}\e[K\n"
  end
  print"\e[0m"
end


def prepare_term
  system("stty -echo -icanon min 1 time 0")  # no timeout on read, one char is enough
  print "\e[?25l"  # hide cursor
end


def sane_term
  system("stty cooked")
  system("stty sane")
  print "\e[?25h"  # show cursor
end


def start_kb_handler
  Thread.new do
    loop do
      $ctl_kb_queue.enq STDIN.getc
    end
  end
end


def handle_kb_listen
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  if char == ' '
    print "\e[32mSPACE to continue ... \e[0m"
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    print "\e[32mcontinue \e[0m"
  elsif char && char.length > 0 && char.ord == 127
    print "\e[32mback\e[0m "
    $ctl_back = true
  end
end


def handle_kb_play
  return unless $ctl_kb_queue.length > 0
  char = $ctl_kb_queue.deq
  waited = false
  
  if char == ' '
    ctl_issue 'SPACE to continue', hl: true
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    ctl_issue 'continue', hl: true
    waited = true
  elsif char == "\n" && $ctl_can_next
    $ctl_next = true
    text = 'Skip'
  elsif char == 'j' && $ctl_can_journal
    $ctl_toggle_journal = true
    text = nil
  elsif char == '?' or char == 'h'
    $ctl_show_help = true
    text = 'See below for short help'
  elsif char == 'd' || char == "\t"
    $ctl_change_display = true
    text = 'Change display'
  elsif char == "r"
    $ctl_set_ref = true
    text = 'Set reference'
  elsif ( char == 'c' || char.ord == 90 ) && $ctl_can_change_comment
    $ctl_change_comment = true
    text = 'Change comment'
  elsif char.ord == 127 && $ctl_can_next
    $ctl_back = true
    text = 'Skip back'
  elsif char.ord == 12
    $ctl_redraw = true
    text = 'redraw'
  elsif char == 'l' && $ctl_can_loop && $ctl_can_next
    $ctl_start_loop = true
    text = 'Loop started'
  elsif char.length > 0
    text = "Invalid char '#{char.match?(/[[:print:]]/) ? char : '?'}' (#{char.ord}), h for help"
  end
  ctl_issue text if text && !waited
  waited
end


def ctl_issue text = nil, **opts
  if text
    $ctl_non_def_issue_ts = Time.now.to_f 
  else
    return if $ctl_non_def_issue_ts && Time.now.to_f - $ctl_non_def_issue_ts < 3
    text = $ctl_default_issue
  end
  fail "Internal error text '#{text}' is longer (#{text.length} chars) than #{$ctl_issue_width}" if text.length > $ctl_issue_width
  print "\e[1;#{$term_width - $ctl_issue_width}H\e[0m\e[#{opts[:hl] ? 32 : 2}m#{text.rjust($ctl_issue_width)}\e[0m"
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
  sys "sox #{file} #{$tmp_dir}/sound-to-plot.dat"
  IO.write "#{$tmp_dir}/sound.gp", <<EOGPL
set term dumb #{$term_width - 2} #{$term_height - 2}
set datafile commentschars ";"
set xlabel "time (s)"
set xrange [#{from}:#{to}]
set ylabel "sample value"
set nokey
set arrow from #{marker}, graph 0 to #{marker}, graph 1 nohead
plot "#{file}" using 1:2
EOGPL
  system "gnuplot #{$tmp_dir}/sound.gp"
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


def print_chart
  xoff, yoff, len = $conf[:chart_offset_xyl]
  print "\e[#{$line_display + yoff}H"
  $chart.each do |row|
    print ' ' * ( xoff - 1)
    row[0 .. -2].each do |cell|
      dim = comment_in_chart?(cell) || !$scale_notes.include?(cell.strip)
      print "\e[#{dim ? 2 : 0}m#{cell}"
    end
    puts "\e[2m#{row[-1]}\e[0m"
  end
end


def clear_area_display
  ($line_display .. $line_hole - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$line_display}H"
end


def clear_area_comment
  ($line_comment_big .. $line_comment_small).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$line_display}H"
end


def update_chart hole, state
  $hole2chart[hole].each do |xy|
    x = $conf[:chart_offset_xyl][0] + xy[0] * $conf[:chart_offset_xyl][2]
    y = $line_display + $conf[:chart_offset_xyl][1] + xy[1]
    cell = $chart[xy[1]][xy[0]]
    pre = case state
          when :good
            "\e[92m\e[7m"
          when :bad
            "\e[31m\e[7m"
          when :normal
            $scale_notes.include?(cell.strip) ? "" : "\e[2m"
          else
            fail "Internal error"
          end
            
    print "\e[#{y};#{x}H\e[0m#{pre}#{cell}\e[0m"
  end
end


def handle_win_change
  $term_height, $term_width = %x(stty size).split.map(&:to_i)
  calculate_screen_layout
  system('clear')
  puts
  while !check_screen(graceful: true)
    $ctl_kb_queue.clear
    puts "\n\n\e[0mScreensize is NOT acceptable, see above !"
    puts "\nPlease resize screen NOW (if possible); to exit"
    puts "this checking loop."
    puts "\nAfter resize, type any key to continue ..."
    $ctl_kb_queue.deq
    puts "checking again ..."
    $term_height, $term_width = %x(stty size).split.map(&:to_i)
    calculate_screen_layout
    sleep 1
    puts
  end
  ctl_issue 'redraw'
  $figlet_cache = Hash.new
  $ctl_redraw = true
end
