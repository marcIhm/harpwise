#
# Handle user-interaction (e.g. printing and reading of input)
#


def prepare_screen
  return [24, 80] unless STDIN.isatty
  STDOUT.sync = true
  %x(stty size).split.map(&:to_i)
end


def check_screen graceful: false, hint_on_large_term: false
  begin
    # check screen-size
    if $term_width < $conf[:term_min_width] || $term_height < $conf[:term_min_height]
      raise ArgumentError.new("Terminal is too small:\n[#{$term_width}, #{$term_height}] (actual)  <  [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}] (configured minimum)")
    end

    # check if enough room between lines for various fonts
    [[:display, :hole,
      figlet_char_height('mono12')],
     [:comment, :hint_or_message, 
      figlet_char_height($mode == :listen  ?  'mono9'  : 'smblock')]
    ].each do |l1, l2, height|
      space = $lines[l2] - $lines[l1]
      if height > space
        raise ArgumentError.new("Space of #{space} lines between $lines[#{l1}] and $lines[#{l2}] is less than needed #{height}")
      end
    end
    
    # check for size of chart
    xroom = $term_width - $charts[:chart_notes].map {|r| r.join.length}.max
    raise ArgumentError.new("Terminal has not enough columns for chart from #{$chart_file} (by #{-xroom} columns)") if xroom < 0
    yroom = $lines[:hole] - $lines[:display] - $charts[:chart_notes].length
    raise ArgumentError.new("Terminal has not enough lines for chart from #{$chart_file} (by #{-yroom} lines)") if yroom < 0

    # compute and store offset-values en passant
    yoff = ( yroom - 1 ) / 2
    yoff = 0 if yoff < 0
    yoff += 1 if yroom > 1
    $conf[:chart_offset_xyl][0..1] = [ (xroom * 0.5).to_i, yoff ]

    # check for clashes
    clashes_ok = (2..4).map do |n|
      [[:help, :comment, :comment_tall, :comment_low],
       [:hint_or_message, :message2, :message_bottom]].map do |set|
        set.combination(n).map {|tuple| Set.new(tuple)}
      end
    end.flatten
    
    lines_inv = $lines.inject(Hash.new([])) {|m,(k,v)| m[v] += [k]; m}
    clashes = lines_inv.select {|l,ks| ks.length > 1 && !clashes_ok.include?(Set.new(ks))}
    if clashes.length > 0
      puts "Collisions:"
      clashes.each {|l,ks| puts "Keys #{ks} all map to line #{l}"}
      raise ArgumentError.new('See above')
    end

    # check bottom line 
    bt_key, bt_line, = $lines.max_by {|k,l| l}
    # lines for ansi term start at 1
    if bt_line > $term_height
      raise ArgumentError.new("Line #{bt_key} = #{bt_line} is larger than terminal height = #{$term_height}")
    end
    
  rescue ArgumentError => e
    puts "\n[width, height] = [#{$term_width}, #{$term_height}]"
    puts
    pp $lines if $debug
    err e.to_s unless graceful
    puts "\e[0m#{e}"
    return false
  end

  if $opts[:debug] && $debug_what.include?(:check_screen) && $debug_state[:kb_handler_started]
    puts "[width, height] = [#{$term_width}, #{$term_height}]"
    pp $lines
    puts "press any key to continue"
    $ctl_kb_queue.deq
    $ctl_kb_queue.clear
  end

  if hint_on_large_term && ( $term_width > 1.5 * $conf[:term_min_width] || $term_height > 1.5 * $conf[:term_min_height] )
    $msgbuf.print "... consider adjusting it for better readability", 5, 5, later: true
    $msgbuf.print "This terminal [#{$term_width}, #{$term_height}] is much larger than needed [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}] ...", 5, 5
  end
  
  return true
end


def sys cmd, failinfo = nil
  out, stat = Open3.capture2e(cmd)
  if !stat.success?
    cited = out.lines.map {|l| " >> #{l}"}.join
    err("Command '#{cmd}' failed with:\n#{cited}" + ( failinfo  ?  "\n#{failinfo}"  :  '' ))
  end
  out
end


$figlet_cache = Hash.new

def do_figlet_unwrapped text, font, width_template = nil, truncate = :left
  fail "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)
  cmd = "figlet -w 400 -f #{font} -d #{$font2dir[font]} -l  -- \"#{text}\""
  cmdt = cmd + truncate.to_s
  unless $figlet_cache[cmdt]
    out = sys(cmd).force_encoding('UTF-8')
    $perfctr[:figlet_1] += 1
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


$figlet_wrap_cache = Hash.new

def get_figlet_wrapped text, font
  fail "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)
  cmd = "figlet -w #{$term_width - 4} -f #{font} -d #{$font2dir[font]} -l -- \"#{text}\""
  unless $figlet_wrap_cache[cmd]
    out = sys(cmd).force_encoding('UTF-8')
    $perfctr[:figlet_2] += 1
    lines = out.lines.map {|l| l.rstrip}

    # strip common spaces at front in groups of four, known to be figlet line height
    lines = lines.each_slice(4).map do |lpl| # lines (terminal) per line (figlet)
      common = lpl.select {|l| l.lstrip.length > 0}.
                 map {|l| l.length - l.lstrip.length}.min || 0
      lpl.map {|l| l[common .. -1] || ''}
    end.flatten

    $figlet_wrap_cache[cmd] = lines.map {|l| '  ' + l}
  end
  $figlet_wrap_cache[cmd]
end


def figlet_char_height font
  fail "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)
  # high and low chars
  out = sys("figlet -f #{font} -d #{$font2dir[font]} -l Igq")
  $perfctr[:figlet_3] += 1
  out.lines.length
end


$figlet_text_width_cache = Hash.new
def figlet_text_width text, font
  unless $figlet_text_width_cache[text + font]
    fail "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)
    out = sys("figlet -f #{font} -d #{$font2dir[font]} -l -- \"#{text}\"").force_encoding('UTF-8')
    $perfctr[:figlet_4] += 1
    $figlet_text_width_cache[text + font] = out.lines.map {|l| l.strip.length}.max
  end
  $figlet_text_width_cache[text + font]
end


def prepare_term
  system("stty -echo -icanon min 1 time 0")  # no timeout on read, one char is enough
  # hide cursor
  Kernel::print "\e[?25l"  
end


def sane_term
  system("stty sane")
  Kernel::print "\e[?25h"  # show cursor
end


def clear_screen_and_scrollback
  # clear screen
  print "\e[2J" 
  # clear scrollback and screen and switch to different buffer for some terms at least
  print "\e[3J"
end


def start_kb_handler
  $term_kb_handler = Thread.new do
    loop do
      key = STDIN.getc
      if key == "\e"
        # try to read cursor keys and some
        begin
          ch = Timeout::timeout(0.05) { STDIN.getc }
          if ch == '['
            ch = Timeout::timeout(0.05) { STDIN.getc }
            key = case ch
                  when 'A'
                    'up'
                  when 'B'
                    'down'
                  when 'C'
                    'right'
                  when 'D'
                    'left'
                  when 'Z'
                    'shift-tab'
                  else
                    "\e"
                  end
          elsif ch == "\t"
            key = 'shift-tab'
          end
        rescue Timeout::Error => e
        end
      end
      $ctl_kb_queue.enq key
    end
  end
  $debug_state[:kb_handler_started] = true
end


def stop_kb_handler
  $term_kb_handler.kill if $term_kb_handler
end


def make_term_immediate
  prepare_term
  start_kb_handler
end


def make_term_cooked
  sane_term
  stop_kb_handler
end


def handle_kb_play_holes
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear

  if char == ' '
    print "\e[0m\e[32m SPACE to continue ... "
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    print "go \e[0m"
    sleep 0.5
  elsif char == "\t" || char == '+'
    $ctl_hole[:skip] = true
  elsif char == 'v'
    $ctl_hole[:vol_down] = true
  elsif char == 'V'
    $ctl_hole[:vol_up] = true
  elsif char == 'h'
    $ctl_hole[:show_help] = true
  end
end


def handle_kb_play_holes_or_notes_simple
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear

  if char == ' '
    print "\e[0m\e[32m SPACE to continue ... "
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    print "go \e[0m"
    sleep 0.5
  elsif char == "\t" || char == '+'
    $ctl_hole[:skip] = true
  elsif char == 'v'
    $ctl_hole[:vol_down] = true
  elsif char == 'V'
    $ctl_hole[:vol_up] = true
  elsif char == 'h'
    $ctl_hole[:show_help] = true
  end
end


def handle_kb_play_recording
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear

  if char == '.' || char == ',' || char == '-'
    $ctl_rec[:replay] = true
  elsif char == ' '
    $ctl_rec[:pause_continue] = true
  elsif char == '<'
    $ctl_rec[:slower] = true
  elsif char == '>'
    $ctl_rec[:faster] = true
  elsif char == 'v'
    $ctl_rec[:vol_down] = true
  elsif char == 'V'
    $ctl_rec[:vol_up] = true
  elsif char == 'l'
    $ctl_rec[:loop] = true
  elsif char == 'L' && $ctl_can[:loop_loop]
    $ctl_rec[:loop] = $ctl_rec[:loop_loop] = !$ctl_rec[:loop_loop] 
  elsif char == 'c' && $ctl_can[:lick_lick]
    $ctl_rec[:lick_lick] = !$ctl_rec[:lick_lick] 
  elsif char == 'h'
    $ctl_rec[:show_help] = true
  elsif char == "\t" || char == '+'
    $ctl_rec[:skip] = true
  end
end


def handle_kb_play_recording_simple
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear
  if char == ' '
    $ctl_rec[:pause_continue] = true
  elsif char == 'v'
    $ctl_rec[:vol_down] = true
    $ctl_rec[:replay] = true
  elsif char == 'V'
    $ctl_rec[:vol_up] = true
    $ctl_rec[:replay] = true
  elsif char == 'l'
    $ctl_rec[:loop] = true
  elsif char == 'h'
    $ctl_rec[:show_help] = true
    $ctl_rec[:replay] = true
  elsif char == '-'
    $ctl_rec[:replay] = true
  elsif char == "\t" || char == '+'
    $ctl_rec[:skip] = true
  end
end


def handle_kb_play_semis
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear

  if char == ' '
    $ctl_prog[:pause_continue] = true
  elsif %w(0 1 2 3 4 5 6 7 8 9).include?(char)
    $ctl_prog[:prefix] = '' unless $ctl_prog[:prefix]
    $ctl_prog[:prefix] += char
    print "\n\e[0m\e[2mprefix is #{$ctl_prog[:prefix]}\e[0m\n"
  elsif char == "\e"
    $ctl_prog[:prefix] = nil
    print "\n\e[0m\e[2mprefix cleared\e[0m\n"
  elsif char == 's' || char == '+'
    $ctl_prog[:semi_up] = true
  elsif char == 'S' || char == '-'
    $ctl_prog[:semi_down] = true
  elsif char == 'v'
    $ctl_prog[:vol_down] = true
  elsif char == 'V'
    $ctl_prog[:vol_up] = true
  elsif char == 'l'
    $ctl_prog[:toggle_loop] = true
  elsif char == 'h'
    $ctl_prog[:show_help] = true
  elsif char == 'q'
    $ctl_prog[:quit] = true
  end
end


def handle_kb_play_pitch
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear
  $ctl_pitch[:any] = true

  if char == ' '
    $ctl_pitch[:pause_continue] = true
  elsif char == 'v'
    $ctl_pitch[:vol_down] = true
  elsif char == 'V'
    $ctl_pitch[:vol_up] = true
  elsif char == 'h'
    $ctl_pitch[:show_help] = true
  elsif char == 's' || char == '+'
    $ctl_pitch[:semi_up] = true
  elsif char == 'S' || char == '-'
    $ctl_pitch[:semi_down] = true
  elsif char == 'o'
    $ctl_pitch[:octave_up] = true
  elsif char == 'O'
    $ctl_pitch[:octave_down] = true
  elsif char == 'f'
    $ctl_pitch[:fifth_up] = true
  elsif char == 'F'
    $ctl_pitch[:fifth_down] = true
  elsif char == 'W'
    $ctl_pitch[:wave_up] = true
  elsif char == 'w'
    $ctl_pitch[:wave_down] = true
  elsif char == 'q' || char == 'x' || char == "\e"
    $ctl_pitch[:quit] = true
  elsif char == "\n"
    $ctl_pitch[:accept_or_repeat] = true
  else
    $ctl_pitch[:any] = false
  end
end


def handle_kb_play_inter
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear
  $ctl_inter[:any] = true

  if char == ' '
    $ctl_inter[:pause_continue] = true
  elsif char == '+'
    $ctl_inter[:widen] = true
  elsif char == '-'
    $ctl_inter[:narrow] = true
  elsif char == '<'
    $ctl_inter[:down] = true
  elsif char == '>'
    $ctl_inter[:up] = true
  elsif char == 'g'
    $ctl_inter[:gap_dec] = true
  elsif char == 'G'
    $ctl_inter[:gap_inc] = true
  elsif char == 'l'
    $ctl_inter[:len_dec] = true
  elsif char == 'L'
    $ctl_inter[:len_inc] = true
  elsif char == 'h'
    $ctl_inter[:show_help] = true
  elsif char == 'q' || char == 'x' || char == "\e"
    $ctl_inter[:quit] = char
  elsif char == 's'
    $ctl_inter[:swap] = true
  elsif char == 'v'
    $ctl_inter[:vol_down] = true
  elsif char == 'V'
    $ctl_inter[:vol_up] = true
  elsif char == "\n"
    $ctl_inter[:replay] = true
  else
    $ctl_inter[:any] = false
  end
end


def handle_kb_play_chord
  return if $ctl_kb_queue.length == 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear
  $ctl_chord[:any] = true

  if char == ' '
    $ctl_chord[:pause_continue] = true
  elsif char == 'g'
    $ctl_chord[:gap_dec] = true
  elsif char == 'G'
    $ctl_chord[:gap_inc] = true
  elsif char == 'l'
    $ctl_chord[:len_dec] = true
  elsif char == 'L'
    $ctl_chord[:len_inc] = true
  elsif char == 'v'
    $ctl_chord[:vol_down] = true
  elsif char == 'V'
    $ctl_chord[:vol_up] = true
  elsif char == 'W'
    $ctl_chord[:wave_up] = true
  elsif char == 'w'
    $ctl_chord[:wave_down] = true
  elsif char == 'h'
    $ctl_chord[:show_help] = true
  elsif char == "\n"
    $ctl_chord[:replay] = true
  elsif char == 'q' || char == 'x' || char == "\e"
    $ctl_chord[:quit] = char
  else
    $ctl_chord[:any] = false
  end
end


def handle_kb_mic
  return unless $ctl_kb_queue.length > 0
  char = $ctl_kb_queue.deq
  $ctl_kb_queue.clear
  waited = false

  if char == ' '
    ctl_response 'SPACE to continue', hl: true
    begin
      char = $ctl_kb_queue.deq
    end until char == ' '
    ctl_response 'continue', hl: true
    waited = true
  elsif char == "\n"
    if $ctl_can[:next]
      $ctl_mic[:next] = true
      text = 'Skip'
    elsif $opts[:comment] == :journal
      $ctl_mic[:journal_current] = true
      text = 'Add to journal'
    else
      text = get_text_invalid(char)
    end
  elsif char == 'l' && $ctl_can[:lick]
    $ctl_mic[:change_lick] = true
    text = 'Named'
  elsif char == 'e' && $ctl_can[:lick]
    $ctl_mic[:edit_lick_file] = true
    text = 'Edit'
  elsif char == 't' && $ctl_can[:lick]
    $ctl_mic[:change_tags] = true
    text = 'Tags'
  elsif char == 'R' && $ctl_can[:lick]
    $ctl_mic[:reverse_holes] = :all
    text = 'Reverse'
  elsif char.ord == 18 && $ctl_can[:lick]
    $ctl_mic[:toggle_record_user] = true
    text = 'Record user'
  elsif char == '>' && $ctl_can[:octave]
    $ctl_mic[:octave] = :up
    text = 'Octave up'
  elsif char == '<' && $ctl_can[:octave]
    $ctl_mic[:octave] = :down
    text = 'Octave down'
  elsif char == '@' && $ctl_can[:lick]
    $ctl_mic[:change_partial] = true
    text = 'Partial'
  elsif char == '*' && $ctl_can[:lick]
    $ctl_mic[:star_lick] = :up
    text = 'Star this lick up'
  elsif char == '/' && $ctl_can[:lick]
    $ctl_mic[:star_lick] = :down
    text = 'Star this lick down'
  elsif char == 'm' && $ctl_can[:switch_modes]
    $ctl_mic[:switch_modes] = true
    text = 'Switch modes'
  elsif char == 'j' && !$ctl_can[:next]
    $ctl_mic[:journal_menu] = true
    text = 'Journal menu'
  elsif char == 'w' && !$ctl_can[:next]
    $ctl_mic[:warbles_prepare] = true
    text = 'Prepare warbles'
  elsif char == 'k'
    $ctl_mic[:change_key] = true
    text = nil
  elsif char == 's'
    $ctl_mic[:rotate_scale] = true
    text = nil
  elsif char == 'S'
    $ctl_mic[:change_scale] = true
    text = nil
  elsif char == 'K'
    $ctl_mic[:pitch] = true
    text = nil
  elsif char == 'q'
    $ctl_mic[:quit] = true
    text = nil
  elsif char == '1'
    $ctl_mic[:done] = true
    text = 'Hole done'
  elsif char == '!' && $opts[:debug]
    $ctl_mic[:debug] = !$ctl_mic[:debug]
    text = "Debug: #{$ctl_mic[:debug]}"
  elsif char == '?' or char == 'h'
    $ctl_mic[:show_help] = true
    text = 'See below for short help'
  elsif char == 'd'
    $ctl_mic[:change_display] = true
    text = 'Change display'
  elsif char == 'D'
    $ctl_mic[:change_display] = :choose
    text = 'Choose display'
  elsif char == 'r'
    $ctl_mic[:set_ref] = true
    text = 'Set reference'
  elsif char == 'c'
    $ctl_mic[:change_comment] = true
    text = 'Change comment'
  elsif char == 'C'
    $ctl_mic[:change_comment] = :choose
    text = 'Choose comment'
  elsif %w(. : , ; p).include?(char) && $ctl_can[:next]
    $ctl_mic[:replay] = true
    $ctl_mic[:ignore_recording] = (char == ',' || char == ';')
    $ctl_mic[:ignore_holes] = (char == '.' || char == ':')
    $ctl_mic[:ignore_partial] = (char == ';' || char == ':' || char == 'p')
    text = 'Replay'
  elsif char == 'P' && $ctl_can[:next]
    $ctl_mic[:auto_replay] = :true
    text = $opts[:auto_replay]  ?  'auto replay OFF'  :  'auto replay ON'
  elsif (char == '0' || char == '-') && $ctl_can[:next]
    $ctl_mic[:forget] = true
    text = 'Forget'
  elsif char == '#' && $ctl_can[:no_progress]
    $ctl_mic[:toggle_progress] = true
    # $opts[:no_progress] will be toggled later
    text = $opts[:no_progress]  ?  'Track progress'  :  'Do not track progress'
  elsif char.ord == 127
    if $ctl_can[:next]
      $ctl_mic[:back] = true
      text = 'Skip back'
    elsif $opts[:comment] == :journal
      $ctl_mic[:journal_delete] = true
      text = 'Delete from journal'
    elsif $opts[:comment] == :warbles
      $ctl_mic[:warbles_clear] = true
      text = 'Clear warbles'
    else
      text = get_text_invalid(char)
    end
  elsif char.ord == 12
    $ctl_mic[:redraw] = Set[:silent, :clear]
    text = 'redraw'
  elsif char == 'i'
    $opts[:immediate] = !$opts[:immediate]
    text = 'immediate is ' + ( $opts[:immediate] ? 'ON' : 'OFF' )
    $ctl_mic[:redraw] = Set[:silent] if $opts[:comment] == :holes_some
  elsif char == 'L' && $ctl_can[:loop] && $ctl_can[:next]
    $ctl_mic[:start_loop] = true
    text = 'Loop started'
  elsif char == '&'
    $opts[:debug] = true
    text = 'Debug is ON'
  elsif char.length > 0
    text = get_text_invalid(char)
  end
  ctl_response text if text && !waited
  waited
end


def ctl_response text = nil, **opts
  if text
    $ctl_response_non_def_ts = Time.now.to_f 
  else
    return if $ctl_response_non_def_ts && Time.now.to_f - $ctl_response_non_def_ts < 3
    text = $ctl_response_default
  end
  fail "Internal error text '#{text}' is longer (#{text.length} chars) than #{$ctl_response_width}" if text.length > $ctl_response_width
  print "\e[1;#{$term_width - $ctl_response_width}H\e[0m\e[#{opts[:hl] ? 32 : 2}m#{text.rjust($ctl_response_width)}\e[0m"
end
  

def read_answer ans2chs_dsc
  klists = Hash.new
  ans2chs_dsc.each do |ans, chs_dsc|
    klists[ans] = chs_dsc[0].join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  i = 0
  ans2chs_dsc.each do |ans, chs_dsc|
    print "  %*s :  %-22s" % [maxlen, klists[ans], chs_dsc[1]]
    puts if (i += 1) % 2 == 0
  end

  begin
    print "\nYour choice (h for help): "
    char = one_char
    char = {' ' => 'SPACE', "\n" => 'RETURN'}[char] || char
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


def draw_data marker1, marker2

  # area accessible for plot. right and left border might be plotted
  # over, but top and bottom line not
  plot_width = ( $term_width * 0.9 ).to_i
  plot_height = ( $term_height * 0.4 ).to_i
  if !$recorded_data_ts ||
     $recorded_data_ts < File.mtime($recorded_data) ||
     $term_width != $recorded_processed[:term_width] ||
     $term_height != $recorded_processed[:term_height]
    $recorded_processed, $recorded_data_ts = process_recorded_data(plot_width)
  end
  rec_proc = $recorded_processed

  # frame
  buf = Array.new
  buf << '+' + '-' * ( plot_width - 2 ) + '+'
  plot_height.times { buf << '|' + ' ' * ( plot_width - 2 ) + '|' }

  # x-axis
  buf << '+' + '-' * ( plot_width - 2 ) + '+'
  minx = rec_proc[:vals_norm][0][0]
  maxx = rec_proc[:vals_norm][-1][0]
  # leftmost and rightmost tick
  txt = '%.1f' % minx
  buf << txt + ' ' * ( plot_width - txt.length )
  txt = '%.1f' % maxx
  buf[-1][-txt.length .. -1] = txt

  # middle ticks
  parts = [-0.1, 0.2, -0.3, 0.4, -0.5, 0.6, -0.7, 0.8, -0.9]
  parts = parts.map {|p| p.abs} if $term_width > 90
  parts.each do |prt|
    tick_only = ( prt < 0)
    prt = prt.abs
    txt = '%.1f' % ( minx + prt * ( maxx - minx ))
    mid = (plot_width * prt).to_i
    buf[-2][mid] = '+'
    buf[-1][mid - txt.length / 2 .. mid + txt.length / 2] = txt unless tick_only
  end

  # data
  px = 0
  # we do not plat all data
  rec_proc[:vals_norm][1 .. -2].each do |x, y|
    py = plot_height * y
    ((-2 - py).to_i .. -3).each {|y| buf[y][px + 1] = '*'}
    px += 1
  end

  # markers
  unless marker1 == 0 && marker2 == 0
    # marker2 is guaranteed to be higher than marker1
    [[marker2, "\e[34m", 'to:'], [marker1,"\e[32m", 'from:']].each do |x, col, desc|
      px = plot_width * (x - minx) / ( maxx - minx)
      if px <= plot_width
        (1 .. 1 + plot_height).each {|y| buf[y][px] = col + ':' + "\e[0m"} 
        txt = desc + '%.1f' % x 
        txt_col = col + txt + "\e[0m"
        # put exact position in first line
        if px < 3
          buf[0][0 ... txt.length] = txt_col
        elsif px > plot_width - 2
          buf[0][-txt.length .. -1] = txt_col
        else
          xs = ( px - txt.length / 2 ).to_i
          buf[0][xs ... xs + txt.length] = txt_col
        end
      end
    end
  end

  # output
  print "\e[0m"
  buf[0 .. -1].each {|line| puts '  ' + line}
end


def process_recorded_data plot_width
  rec_proc = {term_width: $term_width,
              term_height: $term_height,
              vals_norm: Array.new}
  # first two lines are comments
  num_lines = sys("wc -l #{$recorded_data}").to_i - 2
  lines_per_bin = num_lines / plot_width
  fail "Internal error: no lines per bin" if lines_per_bin < 1

  # read file and put data into bins
  lines_this_bin = 0
  sum_secs_this_bin = 0
  sum_vals_this_bin = 0
  line_count = 0
  binned = Array.new
  File.open($recorded_data) do |data|
    2.times { data.gets }
    while line = data.gets
      fields = line.chomp.split.map {|x| Float(x)}
      fail "Internal error: #{line.chomp.split}" unless fields.length == 2
      sum_secs_this_bin += fields[0]
      sum_vals_this_bin += fields[1].abs
      lines_this_bin += 1
      if lines_this_bin == lines_per_bin
        binned << [ sum_secs_this_bin / lines_per_bin,
                    sum_vals_this_bin / lines_per_bin ]
        lines_this_bin = 0
        sum_secs_this_bin = 0
        sum_vals_this_bin = 0
      end
    end
  end
  
  # get max
  max = binned.map {|b| b[1]}.max
  rec_proc[:vals_norm] = if max == 0
                           binned.map {|b| [b[0], 0]}
                         else
                           binned.map {|b| [b[0], b[1]/max]}
                         end
  [ rec_proc, File.mtime($recorded_data) ]
end


def one_char
  prepare_term
  char = STDIN.getc
  sane_term
  char
end  


def print_chart skip_hole = nil
  xoff, yoff, len = $conf[:chart_offset_xyl]
  if ( $opts[:display] == :chart_intervals || $opts[:display] == :chart_inter_semis ) && !$hole_ref
    print "\e[0m\e[#{$lines[:display] + yoff + 4}H  You need to set a reference hole, before this chart can be displayed."
  else    
    print "\e[#{$lines[:display] + yoff}H"
    $charts[$opts[:display]].each_with_index do |row, ridx|
      print ' ' * ( xoff - 1)
      row[0 .. -2].each_with_index do |cell, cidx|
        hole = $note2hole[$charts[:chart_notes][ridx][cidx].strip]
        if skip_hole && skip_hole == hole
          print "\e[#{cell.length}C"
        else
          printf "\e[0m\e[%dm" % (comment_in_chart?(cell)  ?  2  :  get_hole_color_inactive(hole))
          print cell
        end
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
  end
end


def clear_area_display
  ($lines[:display] .. $lines[:hole] - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$lines[:display]}H"
end


def clear_area_comment offset = 0
  ($lines[:comment_tall] + offset .. $lines[:hint_or_message] - 1).each {|l| print "\e[#{l}H\e[K"}
  print "\e[#{$lines[:comment_tall]}H"
end


def clear_area_message
  print "\e[#{$lines[:hint_or_message]}H\e[K"
  print "\e[#{$lines[:message2]}H\e[K" if $lines[:message2] > 0
end


def update_chart hole, state, good = nil, was_good = nil, was_good_since = nil
  return if ( $opts[:display] == :chart_intervals || $opts[:display] == :chart_inter_semis ) && !$hole_ref
  # a hole can appear at multiple positions in the chart
  $hole2chart[hole].each do |xy|
    x = $conf[:chart_offset_xyl][0] + xy[0] * $conf[:chart_offset_xyl][2]
    y = $lines[:display] + $conf[:chart_offset_xyl][1] + xy[1]
    cell = $charts[$opts[:display]][xy[1]][xy[0]]
    hole_color = if state == :inactive
                   "\e[%dm" % get_hole_color_inactive(hole)
                 elsif $opts[:no_progress]
                   "\e[%dm\e[7m" % get_hole_color_inactive(hole)
                 else
                   "\e[%dm\e[7m" % get_hole_color_active(hole, good, was_good, was_good_since)
                 end
    print "\e[#{y};#{x}H\e[0m#{hole_color}#{cell}\e[0m"
  end
end


# a hole, that is beeing currently played
def get_hole_color_active hole, good, was_good, was_good_since
  if !hole
    2
  elsif good || (was_good && (Time.now.to_f - was_good_since) < 0.5)
    if $hole2flags[hole].include?(:main)
      92
    else
      94
    end
  elsif was_good && (Time.now.to_f - was_good_since) < 1
    if $hole2flags[hole].include?(:main)
      32
    else
      34
    end
  elsif was_good
    33
  else
    31
  end
end
    

# a hole, that is not played
def get_hole_color_inactive hole, bright = false
  if $scale_holes.include?(hole)
    if $hole2flags[hole].include?(:main)
      32
    else
      bright ? 94 : 34
    end
  else
    2
  end
end


def handle_win_change
  $term_height, $term_width = %x(stty size).split.map(&:to_i)
  $lines = calculate_screen_layout
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
      sleep 0.2
    end
    $term_height, $term_width = %x(stty size).split.map(&:to_i)
    $lines = calculate_screen_layout
    system('clear')
    puts
  end 
  ctl_response 'redraw'
  $figlet_cache = Hash.new
  $ctl_mic[:redraw] = Set.new()
  $ctl_sig_winch = false
  $freqs_queue.clear
end


def choose_interactive prompt, names
  prompt_orig = prompt
  names.uniq!
  clear_area_comment
  clear_area_message
  # keep screen-line as a variable to alow redraw
  prompt_template = "\e[%dH\e[0m%s \e[J"
  help_template = "\e[%dH\e[2m(any char or cursor keys to select, ? for short help)"
  print prompt_template % [$lines[:comment_tall] + 1, prompt]
  $chia_loc_cache = nil
  $chia_no_matches = nil
  total_chars = chia_padded(names).join.length
  print help_template % ( $lines[:comment_tall] + 2 )
  idx_hl = 0
  idx_hl += 1 while names[idx_hl][0] == ';'
  frame_start = 0
  frame_start_was = Array.new

  input = ''
  matching = names
  idx_last_shown = chia_print_in_columns(chia_framify(names, frame_start), idx_hl, total_chars)
  print chia_desc_helper(yield(matching[idx_hl]), names[idx_hl][0] == ';') if block_given? && matching[idx_hl]
  loop do
    key = $ctl_kb_queue.deq.downcase
    if key == '?'
      clear_area_comment
      clear_area_message
      print "\e[#{$lines[:comment_tall] + 1}H\e[0m"
      puts "Help on selecting: Just type.\e[32m"
      puts
      puts " - any char adds to search, which narrows choices"
      puts " - cursor keys move selection, ctrl-l redraws"
      puts " - RETURN accepts, ESC aborts"
      puts " - TAB and S-TAB go to next/prev page if '...more'"
      puts
      puts "\e[0m\e[2m(any key to continue)\e[0m"
      $ctl_kb_queue.deq
      clear_area_comment(2)        

    elsif key.match?(/^[[:print:]]$/)
      if (prompt + input).length > $term_width - 4
        prompt = '(...): '
        input += key if (prompt + input).length <= $term_width - 4
      else
        prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
        input += key
      end
      matching = names.select {|n| n.downcase[input]}
      idx_hl = ( frame_start > 0  ?  1  :  0 )
    elsif key.ord == 127 # backspace
      input[-1] = '' if input.length > 0
      matching = names.select {|n| n[input]} 
      idx_hl = ( frame_start > 0  ?  1  :  0 )
      prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
      $chia_no_matches = nil
    elsif key.ord == 8 # ctrl-backspace
      input= '' if input.length
      matching = names
      idx_hl = ( frame_start > 0  ?  1  :  0 )
      prompt = prompt_orig
      $chia_no_matches = nil
    elsif %w(left right up down).include?(key)
      idx_hl = chia_move_loc(idx_hl, key,
                             idx_last_shown, frame_start > 0 ? 1 : 0) if idx_last_shown >= 0
    elsif key == "\n"
      if matching.length == 0
        $chia_no_matches ="\e[0;101mNO MATCHES !\e[0m Please shorten input or type ESC to abort !"
      elsif matching[idx_hl][0] == ';'
        clear_area_comment(2)
        clear_area_message
        print "\e[#{$lines[:comment_tall] + 4}H\e[0m\e[2m  '#{matching[idx_hl]}'\e[0m is a comment, please choose another item."
        print "\e[#{$lines[:comment_tall] + 5}H\e[0m\e[2m    Press any key to continue ...\e[0m"
        $ctl_kb_queue.deq
      else
        clear_area_comment
        clear_area_message
        return matching[idx_hl]
      end
    elsif key.ord == 12 # ctrl-l
      print "\e[2J"
      handle_win_change
      print prompt_template % [$lines[:comment_tall] + 1, prompt]
      print "\e[0m\e[32m#{input}\e[0m\e[K"
      print help_template % ( $lines[:comment_tall] + 2 )
    elsif key == "\e"
      clear_area_comment
      clear_area_message
      return nil
    elsif key == "\t"
      if idx_last_shown + frame_start < matching.length - 1
        frame_start_was = Array.new if frame_start == 0
        frame_start_was << frame_start
        frame_start += idx_last_shown
        idx_hl = ( frame_start > 0  ?  1  :  0 )
      end
    elsif key == 'shift-tab'
      if frame_start > 0
        frame_start = frame_start_was.pop || 0
        idx_hl = ( frame_start > 0  ?  1  :  0 )
      end
    end
    print prompt_template % [$lines[:comment_tall] + 1, prompt]
    print "\e[0m\e[32m#{input}\e[0m\e[K"
    print help_template % ( $lines[:comment_tall] + 2 )
    idx_last_shown = chia_print_in_columns(chia_framify(matching, frame_start), idx_hl, total_chars)
    print chia_desc_helper(yield(matching[idx_hl]), names[idx_hl][0] == ';') if block_given? && matching[idx_hl]
  end
end


def chia_print_in_columns names, idx_hl, total_chars
  offset = ( total_chars > $term_width * 3  ?  3  :  4)
  print "\e[#{$lines[:comment_tall] + offset}H\e[0m\e[2m"
  $chia_loc_cache = Array.new
  max_lines = $lines[:hint_or_message] - $lines[:comment_tall] - 4
  # prepare array and print it over existing lines to reduce flicker
  lines = (0 .. max_lines).map {|x| ''}
  idx_last_shown = names.length - 1
  if names.length == 0
    clear_area_comment(2)
    lines[0] = "  " + ( $chia_no_matches || 'No matches, please shorten input ...' )
  else
    lines_count = 0
    line = '  '
    wrote_more = false
    chia_padded(names).each_with_index do |name,idx|
      break if lines_count > max_lines
      if (line + name).length > $term_width - 4
        if lines_count == max_lines && idx < names.length - 1
          # we cannot output the current element, so we overwrite even the
          # previous one to tell about this
          text_more = ' ... more'
          line[-text_more.length ..] = text_more
          $chia_loc_cache.pop
          idx_last_shown = idx - 2
          wrote_more = true
        end
        # we know that we have reached the end, so we output our line
        lines[lines_count] = chia_line_helper(line)
        lines_count += 1
        line = '  '
      end
      $chia_loc_cache << [line.length, lines_count] unless wrote_more
      line[-1] = (name[0] == ';' ? '{' : '[') if idx == idx_hl
      line += name
      line[line.rstrip.length] = (name[0] == ';' ? '}' : ']')  if idx == idx_hl
    end
    # only output, if not already done above
    lines[lines_count] = chia_line_helper(line) unless wrote_more || line.strip.empty?
  end
  lines.each_with_index do |line, idx|
    print "\e[#{$lines[:comment_tall] + offset + idx}H#{line}\e[K"
  end
  return idx_last_shown
end


def chia_line_helper line
  line.gsub('['," \e[0m\e[32m\e[7m").gsub(']', "\e[0m\e[2m ").
    gsub('{'," \e[0m\e[2m\e[7m").gsub('}',"\e[0m\e[2m ")
end


def chia_desc_helper text, is_comment
  "\e[#{$lines[:message_bottom]}H\e[0m\e[#{is_comment ? 2 : 32}m" +
    ( is_comment ? 'This is a comment and cannot be chosen ...' : truncate_text(text) ) +
    "\e[0m\e[K"
end


def chia_framify names, frame_start
  if frame_start == 0
    return names
  else
    if names
      return ['... more'] + names[frame_start .. -1]
    else
      return nil
    end
  end
end


def chia_move_loc idx_old, dir, idx_last_shown, idx_min
  column_old, line_old = $chia_loc_cache[idx_old]
  line_max = $chia_loc_cache[-1][1]
  if dir == 'left'
    idx_new = idx_old - 1
  elsif dir == 'right'
    idx_new = idx_old + 1
  elsif dir == 'up'
    idx_new = idx_old
    if line_old > 0 
      line_new = line_old - 1
      $chia_loc_cache[0 .. idx_old].each_with_index do |pos, idx_of_this|
        column_of_this, line_of_this = pos
        if line_of_this == line_new
          column_of_next, line_of_next = $chia_loc_cache[idx_of_this + 1]
          # keep updating until break below
          idx_new = idx_of_this
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end
    end
  elsif dir == 'down'
    idx_new = idx_old
    if line_old < line_max
      # there is one line below, so try it
      line_new = line_old + 1
      # idx in loop below stats at 0
      $chia_loc_cache[idx_old .. idx_last_shown ].each_with_index do |pos, idx|
        column_of_this, line_of_this = pos
        idx_of_this = idx_old + idx
        if line_of_this == line_new
          # keep updating until break below
          idx_new = idx_of_this
          # no further entries
          break if idx_of_this == idx_last_shown
          column_of_next, line_of_next = $chia_loc_cache[idx_of_this + 1]
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end
    end
  end
  # make sure to be in range
  idx_new = [idx_new, idx_min].max
  idx_new = [idx_new, idx_last_shown ].min

  return idx_new
end


def chia_padded names
  names.
    map {|name| name + ' '}.
    map {|name| name + ' ' * (-name.length % 8)}
end


def report_condition_wait_key text, condition = :error
  clear_area_comment
  print "\e[#{$lines[:comment_tall]}H\e[J\n"
  case condition
  when :error
    print "\e[0;101mAn error has happened:"
  when :info
    print "\e[0m\e[2mPlease note:"
  else
    fail "Internal error invalid condition"
  end
  print "\e[0m\n\n"
  print text
  print "\n\n\e[2mPress any key to continue ... \e[K"
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
end


def journal_menu
  clear_area_comment
  if $opts[:comment] != :journal
    print "\e[#{$lines[:comment_tall] + 3}H\e[0m\e[2m    Switching to comment \e[0mjournal\e[2m ...\e[0m"
    tag = 'switch to comment journal'
    stime = $messages_seen[tag]  ?  0.1  :  0.2
    $messages_seen[tag] = true
    5.times do
      break if $ctl_kb_queue.length > 0
      sleep stime
    end
    $opts[:comment] = :journal
    clear_area_comment
  end
  print "\e[#{$lines[:comment_tall]}H\e[J"
  print "\e[2m"
  puts " There are two ways to add holes to the journal in the comment area:"
  print "\e[0m\e[32m"
  puts "   j,a: toggle on/off all notes played"
  print "\e[0m\e[32m"
  puts "    Or\e[0m\e[2m, after leaving this menu (and when comment is journal) just press"
  puts "       RETURN to add the note currently played or BACKSPACE to delete it."
  puts " Within this menu again, operate on the current content of the journal:"
  print "\e[0m\e[32m"
  puts "     p: play the journal shown, using durations (e.g. '(0.3)') if any"
  puts "     e: invoke editor on it  c: clear it (offer saving before)"
  puts "     w: write it to file     r: recall 100 lines from file into edit"
  print "\e[0m\e[2m Type any of j,a,p,e,c,w,r or any other key to cancel ... \e[K"
  char = $ctl_kb_queue.deq
  case char
  when 'a', 'j'
    $ctl_mic[:journal_all_toggle] = true
  when 'w'
    $ctl_mic[:journal_write] = true
  when 'w'
    $ctl_mic[:journal_write] = true
  when 'p'
    $ctl_mic[:journal_play] = true
  when 'c'
    $ctl_mic[:journal_clear] = true
  when 'e'
    $ctl_mic[:journal_edit] = true
  when 'r'
    $ctl_mic[:journal_recall] = true    
  when 'q','x'
    $msgbuf.print "Quit journal menu", 0, 5
  else
    cdesc = if char.match?(/^[[:print:]]+$/)
              "'#{char}'"
            else
              "? (#{char.ord})"
            end
    $msgbuf.print "Invalid char #{cdesc} for journal menu", 0, 2
  end
  clear_area_comment
end


def prepare_warbles
  clear_area_comment
  if $opts[:comment] != :warbles
    print "\e[#{$lines[:comment_tall] + 3}H\e[0m\e[2m    Switching to comment \e[0mwarble\e[2m ...\e[0m"
    tag = 'switch to comment warble'
    stime = $messages_seen[tag]  ?  0.1  :  0.2
    $opts[:comment] = :warbles
  else
    $warbles_holes = Array.new(2)
    [0, 1].each do |idx|
      $warbles_holes[idx] = choose_interactive("Please set   \e[32m#{%w(FIRST SECOND)[idx]}\e[0m   warble hole: ", $harp_holes)
      clear_area_comment
      print "\e[0m\e[32m"
      puts
      do_figlet_unwrapped $warbles_holes[idx] || '-', 'mono9'
      print "\e[0m"
      sleep 0.7
      break unless $warbles_holes[idx]
    end
    if $warbles_holes.any?(:nil?) || $warbles_holes[0] == $warbles_holes[1]
      $warbles_holes = Array.new(2)
      $msgbuf.print "Warbling canceled", 2, 4
    end
    $warbles[:standby] = true
    $freqs_queue.clear
  end
end


def get_text_invalid char
  cdesc = if char.match?(/^[[:print:]]+$/)
            char
          elsif char.ord == 10
            'RETURN'
          elsif char.ord == 9
            'TAB'
          elsif char.ord == 127
            'BACKSPACE'
          elsif char.ord == 18
            'CTRL-R'
          else
            "? (#{char.ord})"
          end
  "Invalid char #{cdesc}, h for help"
end

