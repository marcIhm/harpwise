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
      raise ArgumentError.new("Terminal is too small:\n[width, height] = [#{$term_width}, #{$term_height}] (actual) < [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}] (configured minimum)")
    end

    # check if enough room for fonts
    space = $line_hole - $line_display
    if figlet_char_height('mono12') > space
      raise ArgumentError.new("Space of #{space} lines between $line_hole and $line_display is too small")
    end

    space = $line_hint_or_message - $line_comment
    if figlet_char_height($mode == :listen  ?  'big'  : 'smblock') > space
      raise ArgumentError.new("Space of #{space} lines between $line_hint_or_message and $line_comment is too small")
    end
    
    # check for size of chart
    xroom = $term_width - $chart.map {|r| r.join.length}.max
    raise ArgumentError.new("Terminal has not enough columns for chart from #{$chart_file} (by #{-xroom} columns)") if xroom < 0
    yroom = $line_hole - $line_display - $chart.length
    raise ArgumentError.new("Terminal has not enough lines for chart from #{$chart_file} (by #{-yroom} lines)") if yroom < 0

    yoff = ( yroom - 1 ) / 2
    yoff = 0 if yoff < 0
    yoff += 1 if yroom > 1
    $conf[:chart_offset_xyl][0..1] = [ (xroom * 0.5).to_i, yoff ]

    # check for maximum value of $line_xx_ variables
    all_vars = Hash.new
    $bottom_line = bottom_line_var = 0
    global_variables.each do |var|
      if var.to_s.start_with?('$line_')
        val = eval(var.to_s)
        raise ArgumentError.new("Variable #{var} has the same value as #{all_vars[val]} = #{val}") if all_vars[val] && Set.new([var, all_vars[val]]) != Set.new([:$line_help, :$line_comment])
        all_vars[val] = var
        if val > $bottom_line
          $bottom_line = eval(var.to_s)
          bottom_line_var = var
        end
      end
    end
    if $bottom_line > $term_height
      raise ArgumentError.new("Variable #{bottom_line_var} = #{$bottom_line} is larger than terminal height = #{$term_height}")
    end

  rescue ArgumentError => e
    err e.to_s unless graceful
    puts "\e[0m#{e}"
    return false
  end
  return true
end


def sys cmd
  out, stat = Open3.capture2e(cmd)
  stat.success? || fail("Command '#{cmd}' failed with:\n#{out}")
  out
end


$figlet_cache = Hash.new
$figlet_all_fonts = %w(smblock mono12 big)

def do_figlet text, font, width_template = nil, truncate = :left
  fail "Unknown font: #{font}" unless $figlet_all_fonts.include?(font)
  cmd = "figlet -d fonts -w 400 -f #{font} -l \" #{text}\""
  cmdt = cmd + truncate.to_s
  unless $figlet_cache[cmdt]
    out, _ = Open3.capture2e(cmd)
    $figlet_count += 1
    lines = out.lines.map {|l| l.rstrip}

    # strip common spaces at front
    common = lines.select {|l| l.lstrip.length > 0}.
               map {|l| l.length - l.lstrip.length}.min
    lines.map! {|l| l[common .. -1] || ''}

    # overall length from figlet
    maxlen = lines.map {|l| l.length}.max

    # calculate offset from width_template (if available) or from actual output of figlet
    offset_specific = 0.4 * ( $term_width - maxlen )
    if width_template
      if width_template.start_with?('fixed:')
        offset = ( $term_width - figlet_text_width(width_template[6 .. -1], font) ) * 0.5
      else
        twidth = figlet_text_width(width_template, font)
        offset = ( twidth.to_f / $term_width < 0.6  ?  0.4  :  0.8 ) * ( $term_width - twidth )
      end
    else
      offset = offset_specific
    end
    if offset + maxlen < $term_width * 0.3
      offset = 0.3 * $term_width
    end
    if offset + maxlen > 0.9 * $term_width
      offset = offset_specific
    end
    if offset < 0 || offset + maxlen > 0.9 * $term_width
      offset = 0
    end
    $figlet_cache[cmdt] = lines.each_with_index.map do |l,i|
      if maxlen + 2 < $term_width 
        ' ' * offset + l.chomp
      else
        if truncate == :left
          '/\\'[i%2] + '   ' +  sprintf("%-#{maxlen}s", l.chomp)[-$term_width + 6 .. -1]
        else
          (l.chomp + ' ' * maxlen)[0 .. $term_width - 6] + '   ' + '/\\'[i%2]
        end
      end
    end
  end
  if $figlet_cache[cmdt] # could save us after resize
    $figlet_cache[cmdt].each do |line|
      print "#{line.chomp}\e[K\n"
    end
    print"\e[0m"
  end
end


def figlet_char_height font
  fail "Unknown font: #{font}" unless $figlet_all_fonts.include?(font)
  # high and low chars
  out, _ = Open3.capture2e("figlet -d fonts -f #{font} -l Igq")
  $figlet_count += 1
  out.lines.length
end


$figlet_text_width_cache = Hash.new
def figlet_text_width text, font
  unless $figlet_text_width_cache[text + font]
    out, _ = Open3.capture2e("figlet -d fonts -f #{font} -l #{text}")
    $figlet_count += 1
    $figlet_text_width_cache[text + font] = out.lines.map {|l| l.strip.length}.max
  end
  $figlet_text_width_cache[text + font]
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
  @kb_handler = Thread.new do
    loop do
      $ctl_kb_queue.enq STDIN.getc
    end
  end
end


def stop_kb_handler
  @kb_handler.exit
end


def handle_kb_play
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  if char == ' '
    print "\e[0m\e[32m SPACE to continue ..."
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    print "go"
    sleep 0.5
  elsif char == "\t" || char == '+'
    $ctl_skip = true
  elsif char == 'h'
    $ctl_show_help = true
  end
end


def handle_kb_play_recording
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  if char == '.' || char == ','
    $ctl_replay = true
    $ctl_ignore_recording = (char == ',')
    $ctl_ignore_holes = (char == '.')
  elsif char == ' '
    $ctl_pause_continue = true
  elsif char == '<'
    $ctl_slower = true
  elsif char == 'l'
    $ctl_rec_loop = true
  elsif char == 'h'
    $ctl_show_help = true
  elsif char == "\t" || char == '+'
    $ctl_skip = true
  elsif char == '-'
    $ctl_replay = true
  end
end


def handle_kb_listen
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
  elsif char == 'j'
    $ctl_toggle_journal = true
    text = nil
  elsif char == 'k'
    $ctl_change_key = true
    text = nil
  elsif char == 's'
    $ctl_change_scale = true
    text = nil
  elsif char == 'q'
    $ctl_quit = true
    text = nil
  elsif char == '?' or char == 'h'
    $ctl_show_help = true
    text = 'See below for short help'
  elsif char == 'd' || char == "\t"
    $ctl_change_display = true
    text = 'Change display'
  elsif char == 'r'
    $ctl_set_ref = true
    text = 'Set reference'
  elsif ( char == 'c' || char.ord == 90 ) && $ctl_can_change_comment
    $ctl_change_comment = true
    text = 'Change comment'
  elsif (char == '.' || char == ',' || char == ':' || char == 'p') && $ctl_can_next
    $ctl_replay = true
    $ctl_ignore_recording = (char == ',')
    $ctl_ignore_holes = (char == '.')
    $ctl_ignore_partial = (char == ':' || char == 'p')
    text = 'Replay'
  elsif (char == '0' || char == '-') && $ctl_can_next
    $ctl_forget = true
    text = 'Forget'
  elsif char == '#'
    $opts[:no_progress] = !$opts[:no_progress]
    text = $opts[:no_progress] ? 'Do not track progress' : 'Track progress'
  elsif char.ord == 127 && $ctl_can_next
    $ctl_back = true
    text = 'Skip back'
  elsif char.ord == 12
    $ctl_redraw = true
    text = 'redraw'
  elsif char == 'i'
    $opts[:immediate] = !$opts[:immediate]
    text = 'immediate is ' + ( $opts[:immediate] ? 'ON' : 'OFF' )
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
  

def read_answer ans2chs_dsc
  klists = Hash.new
  ans2chs_dsc.each do |ans, chs_dsc|
    klists[ans] = chs_dsc[0].join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  i = 0
  ans2chs_dsc.each do |ans, chs_dsc|
    print "  %*s :  %-20s" % [maxlen, klists[ans], chs_dsc[1]]
    puts if (i += 1) % 2 == 0
  end

  begin
    print "\nYour choice ('h' for help): "
    char = one_char
    char = {' ' => 'SPACE', "\r" => 'RETURN'}[char] || char
    puts char
    answer = nil
    ans2chs_dsc.each do |ans, chs_dsc|
      answer = ans if chs_dsc[0].include?(char)
    end
    answer = :help if char == 'h'
    puts "Invalid key: '#{char.match?(/[[:print:]]/) ? char : '?'}' (#{char.ord})" unless answer
    if answer == :help
      puts "Full Help:\n\n"
      ans2chs_dsc.each do |ans, chs_dsc|
        puts '  %*s :  %s' % [maxlen, klists[ans], chs_dsc[2]]
      end
    end
  end while !answer || answer == :help
  answer
end


def draw_data file, marker1, marker2
  sys "sox #{file} #{$tmp_dir}/sound-to-plot.dat"
  cmds = <<EOGPL
set term dumb #{$term_width - 2} #{$term_height - 2}
set datafile commentschars ";"
set xlabel "time (s)"
set ylabel "sample value"
set nokey
%s
%s
plot "#{file}" using 1:2
EOGPL
  IO.write "#{$tmp_dir}/sound.gp", cmds % [marker1 > 0  ?  "set arrow from #{marker1}, graph 0 to #{marker1}, graph 1 nohead"  :  '',
                                           marker2 > 0  ?  "set arrow from #{marker2}, graph 0 to #{marker2}, graph 1 nohead"  :  '']
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
      hole = $note2hole[cell.strip]
      print "\e[0m"
      if dim
        print "\e[2m"
      else
        if $hole2flags[hole].include?(:all)
          print "\e[0m"
        elsif $hole2flags[hole].include?(:main)
          print "\e[32m"
        else
          print "\e[34m"
        end
      end
    
      print cell
    end
    puts "\e[0m\e[2m#{row[-1]}\e[0m"
  end
end


def clear_area_display
  ($line_display .. $line_hole - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$line_display}H"
end


def clear_area_comment
  ($line_comment .. $line_hint_or_message - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$line_display}H"
end


def clear_area_help
  ($line_help .. $line_hint_or_message - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$line_display}H"
end


def update_chart hole, state
  $hole2chart[hole].each do |xy|
    x = $conf[:chart_offset_xyl][0] + xy[0] * $conf[:chart_offset_xyl][2]
    y = $line_display + $conf[:chart_offset_xyl][1] + xy[1]
    cell = $chart[xy[1]][xy[0]]
    pre = case state
          when :good
            if $hole2flags[hole].include?(:all)
              "\e[0m\e[7m"
            elsif $hole2flags[hole].include?(:main)
              "\e[92m\e[7m"
            else
              "\e[94m\e[7m"
            end
          when :was_good
            if $hole2flags[hole].include?(:all)
              "\e[33m\e[7m"
            elsif $hole2flags[hole].include?(:main)
              "\e[32m\e[7m"
            else
              "\e[34m\e[7m"
            end
          when :bad
            "\e[31m\e[7m"
          when :normal
            if $scale_notes.include?(cell.strip)
              if $hole2flags[hole].include?(:all)
                "\e[0m"
              elsif $hole2flags[hole].include?(:main)
                "\e[32m"
              else
                "\e[34m"
              end
            else
              "\e[0m\e[2m"
            end
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
    puts "\e[2m"
    puts "\n\n\e[0mScreensize is not acceptable, see above !"
    puts "\nPlease resize screen right now to continue."
    puts
    puts "(Or press ctrl-c to break out of this checking loop.)"
    $ctl_sig_winch = false
    while !$ctl_sig_winch
      sleep 0.1
    end
    $term_height, $term_width = %x(stty size).split.map(&:to_i)
    calculate_screen_layout
    system('clear')
    puts
  end 
  ctl_issue 'redraw'
  $figlet_cache = Hash.new
  $ctl_redraw = true
  $ctl_sig_winch = false
end
