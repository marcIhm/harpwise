#
# User-interaction (reading of kb-input and reaction)
#


module Interact
  extend self

  def prepare_screen
    return [24, 80] unless STDOUT.isatty

    STDOUT.sync = true
    `stty size`.split.map(&:to_i)
  end

  def check_screen graceful: false
    begin
      # check screen-size
      raise ArgumentError.new("Screen is too small:\n[#{$term_width},#{$term_height}] (actual)  <  [#{$conf[:term_min_width]},#{$conf[:term_min_height]}] (needed)") if $term_width < $conf[:term_min_width] || $term_height < $conf[:term_min_height]

      # check if enough room between lines for various fonts
      [[:display, :hole,
        Text::figlet_char_height('mono12')],
       [:comment, :hint_or_message,
        Text::figlet_char_height($mode == :listen ? 'mono9' : 'smblock')]].each do |l1, l2, height|
        space = $lines[l2] - $lines[l1]
        raise ArgumentError.new("Space of #{space} lines between $lines[#{l1}] and $lines[#{l2}] is less than needed #{height}") if height > space
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
      $conf[:chart_offset_xyl][0..1] = [(xroom * 0.5).to_i, yoff]

      # check for clashes
      clashes_ok = (2..4).map do |n|
        [%i[help comment comment_tall comment_flat],
         %i[hint_or_message message2 message_bottom]].map do |set|
          set.combination(n).map {|tuple| Set.new(tuple)}
        end
      end.flatten

      lines_inv = $lines.each_with_object(Hash.new([])) do |(k, v), m|
        m[v] += [k]
      end
      clashes = lines_inv.select {|_l, ks| ks.length > 1 && !clashes_ok.include?(Set.new(ks))}
      if clashes.length > 0
        puts 'Collisions:'
        clashes.each {|l, ks| puts "Keys #{ks} all map to line #{l}"}
        raise ArgumentError.new('See above')
      end

      # check bottom line
      bt_key, bt_line, = $lines.max_by {|_k, l| l}
      # lines for ansi term start at 1
      raise ArgumentError.new("Line #{bt_key} = #{bt_line} is larger than terminal height = #{$term_height}") if bt_line > $term_height
    rescue ArgumentError => e
      puts "\n[width, height] = [#{$term_width}, #{$term_height}]"
      puts
      # not sure if resizing helps, but thats the only thing the user can do
      err e.to_s + "\n\nPlease enlarge screen and try again." unless graceful
      puts "\e[0m#{e}"
      return false
    end

    if $opts[:debug] && $debug_what.include?(:check_screen) && $debug_state[:kb_handler_started]
      puts "[width, height] = [#{$term_width}, #{$term_height}]"
      pp $lines
      puts $resources[:any_key]
      $ctl_kb_queue.deq
      $ctl_kb_queue.clear
    end

    true
  end

  def prepare_term
    # no timeout on read, one char is enough
    system('stty -echo -icanon min 1 time 0')
    Kernel.print "\e[?25l"  ## hide cursor
  end

  def sane_term
    system('stty sane') if STDOUT.isatty
    # This is not the exact opposite of prepare_term, because it does not show cursor; the
    # only place where this is needed (at_exit) does this explicitly
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
        $ctl_kb_queue.enq get_complex_key
      end
    end
    $debug_state[:kb_handler_started] = true
  end

  def stop_kb_handler
    $term_kb_handler.kill if $term_kb_handler
  end

  def start_fifo_handler
    File.mkfifo($remote_fifo) unless File.exist?($remote_fifo)
    ftype = File.ftype($remote_fifo)
    err "Fifo '#{$remote_fifo}' required for option --jamming does exist, but it is of type '#{ftype}' instead of 'fifo'" unless ftype == 'fifo'

    fifo = File.open($remote_fifo, 'r+')
    $ctl_fifo_queue.clear
    $remote_fifo_handler = Thread.new do
      loop do
        $ctl_fifo_queue.enq fifo.gets.chomp
      end
    end
  end

  def stop_fifo_handler
    $remote_fifo_handler.kill if $remote_fifo_handler
    $remote_fifo_handler = nil
  end

  def make_term_immediate
    prepare_term
    start_kb_handler
    start_fifo_handler if $opts[:jamming]
  end

  def make_term_cooked
    sane_term
    stop_kb_handler
    stop_fifo_handler if $opts[:jamming]
  end

  def handle_kb_play_holes_or_notes
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq

    if char == ' '
      space_to_cont
      print "go \e[0m"
      sleep 0.5
    elsif ['TAB', '+', 'RETURN'].include?(char)
      $ctl_hole[:skip] = true
    elsif char == 'v'
      $ctl_hole[:vol_down] = true
    elsif char == 'V'
      $ctl_hole[:vol_up] = true
    elsif char == 'l'
      $ctl_lk_hl[:toggle_loop] = true
    elsif char == 'h'
      $ctl_hole[:show_help] = true
    elsif char == '*' && $ctl_lk_hl[:can_star_unstar]
      $ctl_lk_hl[:star_lick] = :up
    elsif char == '/' && $ctl_lk_hl[:can_star_unstar]
      $ctl_lk_hl[:star_lick] = :down
    else
      $ctl_hole[:invalid] = get_text_invalid(char)
    end
  end

  def handle_kb_play_lick_recording
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq

    if ['.', '-'].include?(char)
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
      $ctl_lk_hl[:toggle_loop] = true
    elsif char == 'h'
      $ctl_rec[:show_help] = true
    elsif ['TAB', '+', 'RETURN'].include?(char)
      $ctl_rec[:skip] = true
    elsif char == '*' && $ctl_lk_hl[:can_star_unstar]
      $ctl_lk_hl[:star_lick] = :up
    elsif char == '/' && $ctl_lk_hl[:can_star_unstar]
      $ctl_lk_hl[:star_lick] = :down
    else
      $ctl_rec[:invalid] = get_text_invalid(char)
    end
  end

  def handle_kb_play_recording
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq

    if char == ' '
      $ctl_rec[:pause_continue] = true
    elsif char == 'v'
      $ctl_rec[:vol_down] = true
      $ctl_rec[:replay] = true
    elsif char == 'V'
      $ctl_rec[:vol_up] = true
      $ctl_rec[:replay] = true
    elsif char == 'l'
      $ctl_lk_hl[:toggle_loop] = true
    elsif char == 'h'
      $ctl_rec[:show_help] = true
      $ctl_rec[:replay] = true
    elsif char == '-'
      $ctl_rec[:replay] = true
    elsif ['TAB', '+', 'RETURN'].include?(char)
      $ctl_rec[:skip] = true
    else
      $ctl_rec[:invalid] = get_text_invalid(char)
    end
  end

  def handle_kb_play_semis
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq

    if char == ' '
      $ctl_prog[:pause_continue] = true
    elsif %w[0 1 2 3 4 5 6 7 8 9].include?(char)
      $ctl_prog[:prefix] = '' unless $ctl_prog[:prefix]
      $ctl_prog[:prefix] += char
      print "\e[0m\e[2mprefix is #{$ctl_prog[:prefix]}\e[0m\n"
    elsif char == 'ESC'
      $ctl_prog[:prefix] = nil
      print "\e[0m\e[2mprefix cleared\e[0m\n"
    elsif ['s', '+', 'u'].include?(char)
      $ctl_prog[:semi_up] = true
    elsif ['S', '-', 'd'].include?(char)
      $ctl_prog[:semi_down] = true
    elsif char == 'v'
      $ctl_prog[:vol_down] = true
    elsif char == 'V'
      $ctl_prog[:vol_up] = true
    elsif char == 'l'
      $ctl_prog[:toggle_loop] = true
    elsif ['<', 'p'].include?(char)
      $ctl_prog[:prev_prog] = true
    elsif ['>', 'n'].include?(char)
      $ctl_prog[:next_prog] = true
    elsif char == 'h'
      $ctl_prog[:show_help] = true
    elsif char == 'q'
      $ctl_prog[:quit] = true
    else
      $ctl_prog[:invalid] = get_text_invalid(char)
    end
  end

  def handle_kb_play_pitch
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq
    $ctl_pitch[:any] = true

    if char == ' '
      $ctl_pitch[:pause_continue] = true
    elsif char == 'v'
      $ctl_pitch[:vol_down] = true
    elsif char == 'V'
      $ctl_pitch[:vol_up] = true
    elsif char == 'h'
      $ctl_pitch[:show_help] = true
    elsif ['s', '+', 'UP'].include?(char)
      $ctl_pitch[:semi_up] = true
    elsif ['S', '-', 'DOWN'].include?(char)
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
    elsif %w[q x ESC].include?(char)
      $ctl_pitch[:quit] = true
    elsif char == 'RETURN'
      $ctl_pitch[:accept_or_repeat] = true
    elsif char == '.'
      $ctl_pitch[:repeat] = true
    else
      $ctl_pitch[:invalid] = get_text_invalid(char)
      $ctl_pitch[:any] = false
    end
  end

  def handle_kb_play_inter
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq
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
    elsif %w[q x ESC].include?(char)
      $ctl_inter[:quit] = char
    elsif char == 's'
      $ctl_inter[:swap] = true
    elsif char == 'v'
      $ctl_inter[:vol_down] = true
    elsif char == 'V'
      $ctl_inter[:vol_up] = true
    elsif char == 'RETURN'
      $ctl_inter[:replay] = true
    else
      $ctl_inter[:invalid] = get_text_invalid(char)
      $ctl_inter[:any] = false
    end
  end

  def handle_kb_play_chord
    return if $ctl_kb_queue.length == 0

    char = $ctl_kb_queue.deq
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
    elsif char == 's'
      $ctl_chord[:single] = true
    elsif char == 'S'
      $ctl_chord[:unsingle] = true
    elsif char == 'h'
      $ctl_chord[:show_help] = true
    elsif char == 'RETURN'
      $ctl_chord[:replay] = true
    elsif %w[q x ESC].include?(char)
      $ctl_chord[:quit] = char
    else
      $ctl_chord[:invalid] = get_text_invalid(char)
    end
  end

  #
  # Handle keyboard when listening to microphone, i.e. during main interactive loop in
  # show_mic.rb
  #
  def handle_kb_mic
    return unless $ctl_kb_queue.length > 0 || $ctl_fifo_queue.length > 0

    char = if $ctl_kb_queue.length > 0
             $ctl_kb_queue.deq
           else
             $ctl_fifo_queue.deq
           end
    if $keyboard_translations[char]
      if $keyboard_translations[char].is_a?(String)
        char = $keyboard_translations[char]
      else
        # sneak in other chars, to be processed next
        $keyboard_translations[char][1..-1].reverse.each do |ch|
          $ctl_kb_queue.enq(ch)
        end
        char = $keyboard_translations[char][0]
      end
    end
    waited = false

    if char == ' '
      if $opts[:jamming]
        $ctl_mic[:jamming_ps_rs] = true
      else
        txt = 'SPACE to continue'
        cnt = 0
        begin
          while $ctl_kb_queue.empty?
            ctl_response txt, hl: cnt / 10
            cnt += 1
            sleep 0.1
          end
          char = $ctl_kb_queue.deq
        end until char == ' '
        txt = 'and on !'
        [[false, 0.2], [0, 0.2], [2, 0.8], [false, 0]].each do |hl, slp|
          ctl_response txt, hl: hl
          sleep slp
        end
        waited = true
      end
    elsif char == 'RETURN'
      if %i[quiz licks].include?($mode)
        $ctl_mic[:next] = true
        text = 'Skip'
      elsif $opts[:comment] == :journal
        $ctl_mic[:journal_current] = true
        text = 'Add to journal'
      else
        text = get_text_invalid(char, true)
      end
    elsif %w[H 4].include?(char) && $mode == :quiz
      $ctl_mic[:quiz_hint] = true
      text = 'Quiz Hints'
    elsif char == 'l' && $mode == :licks
      $ctl_mic[:change_lick] = true
      text = 'Named'
    elsif char == 'e' && $mode == :licks
      $ctl_mic[:edit_lick_file] = true
      text = 'Edit'
    elsif char == 't' && $mode == :licks
      $ctl_mic[:change_tags] = true
      text = 'Tags'
    elsif char == '!' && $mode == :licks
      $ctl_mic[:reverse_holes] = :all
      text = 'Reverse'
    elsif char == '&' && $mode == :licks
      $ctl_mic[:shuffle_holes] = true
      text = 'Shuffle'
    elsif char == 'i' && $mode == :licks
      $ctl_mic[:lick_info] = true
      text = 'Lick info'
    elsif char == 'o' && %i[listen licks].include?($mode)
      $ctl_mic[:options_info] = true
      text = 'Option info'
    elsif char == 'CTRL-R' && $mode == :licks
      $ctl_mic[:toggle_record_user] = true
      text = 'Toggle record'
    elsif char == '#' && $mode == :licks
      $ctl_mic[:shift_inter] = true
      text = 'Choose shift interval'
    elsif ['@', '9'].include?(char) && $mode == :licks
      $ctl_mic[:change_partial] = true
      text = 'Partial'
    elsif char == '*' && $mode == :licks
      $ctl_mic[:star_lick] = :up
      text = 'Star this lick up'
    elsif char == '/' && $mode == :licks
      $ctl_mic[:star_lick] = :down
      text = 'Star this lick down'
    elsif char == 'm' && %i[listen quiz licks].include?($mode)
      $ctl_mic[:switch_modes] = true
      text = 'Switch modes'
    elsif char == 'j' && $mode == :listen
      $ctl_mic[:journal_menu] = true
      text = 'Journal menu'
    elsif char == 'w' && $mode == :listen
      $ctl_mic[:warbles_prepare] = true
      text = 'Prepare warbles'
    elsif char == 'k'
      $ctl_mic[:change_key] = true
      text = nil
    elsif char == 's'
      $ctl_mic[:rotate_scale] = :forward
      text = nil
    elsif char == 'ALT-s'
      $ctl_mic[:rotate_scale] = :backward
      text = nil
    elsif char == 'S'
      $ctl_mic[:rotate_scale_reset] = true
      text = nil
    elsif char == '$'
      $ctl_mic[:change_scale] = true
      text = nil
    elsif char == 'L' && $mode == :licks
      $ctl_mic[:first_lick] = true
      text = 'First lick'
    elsif char == 'K'
      $ctl_mic[:pitch] = true
      text = nil
    elsif char == 'q'
      $ctl_mic[:quit] = true
      text = nil
    elsif char == '1' && %i[quiz licks].include?($mode)
      $ctl_mic[:hole_given] = true
      text = 'One hole given'
    elsif char == '!' && $opts[:debug]
      $ctl_mic[:debug] = !$ctl_mic[:debug]
      text = "Debug: #{$ctl_mic[:debug]}"
    elsif ['?', 'h'].include?(char)
      $ctl_mic[:show_help] = true
      text = 'See below for short help'
    elsif char == 'd'
      $ctl_mic[:change_display] = true
      text = 'Change display'
    elsif char == 'D'
      $ctl_mic[:change_display] = :choose
      text = 'Choose display'
    elsif char == 'ALT-m'
      $ctl_mic[:remote_message] = true
    elsif %w[r R].include?(char)
      $ctl_mic[:set_ref] = ( char == 'r' ? :played : :choose )
      text = 'Set reference'
    elsif char == 'CTRL-BACKSPACE'
      if $opts[:comment] == :journal
        $ctl_mic[:journal_clear] = true
        text = 'Clear journal'
      else
        text = get_text_invalid(char, true)
        $msgbuf.print 'CTRL-BACKSPACE only works for comment journal', 0, 2
      end
    elsif char == 'c'
      $ctl_mic[:change_comment] = true
      text = 'Change comment'
    elsif char == 'C'
      $ctl_mic[:change_comment] = :choose
      text = 'Choose comment'
    elsif %w[. p].include?(char) && %i[quiz licks].include?($mode)
      $ctl_mic[:replay] = true
      $ctl_mic[:replay_flags] = Set.new
      text = 'Replay'
    elsif char == ',' && $mode == :licks
      $ctl_mic[:replay_menu] = true
      text = 'Replay menu'
    elsif char == '.' && $mode == :listen
      $ctl_mic[:comment_lick_play] = true
      text = 'Play lick'
    elsif char == 'l' && $mode == :listen
      $ctl_mic[:comment_lick_next] = true
      text = 'Next lick'
    elsif char == 'ALT-l' && $mode == :listen
      $ctl_mic[:comment_lick_prev] = true
      text = 'Prev lick'
    elsif char == 'L' && $mode == :listen
      $ctl_mic[:comment_lick_first] = true
      text = 'First lick'
    elsif char == 'P' && %i[quiz licks].include?($mode)
      $ctl_mic[:auto_replay] = true
      text = $opts[:auto_replay] ? 'auto replay OFF' : 'auto replay ON'
    elsif char == 'p'
      $ctl_mic[:player_details] = true
    elsif ['0', '-'].include?(char) && %i[quiz licks].include?($mode)
      $ctl_mic[:forget] = true
      text = 'Forget'
    elsif char == 'n' && $mode == :quiz && $extra == 'replay'
      $ctl_mic[:change_num_quiz_replay] = true
      text = 'Change num of holes'
    elsif char == 'BACKSPACE'
      if %i[quiz licks].include?($mode)
        $ctl_mic[:back] = true
        text = 'Skip back'
      elsif $opts[:comment] == :journal
        $ctl_mic[:journal_delete] = true
        text = 'Delete from journal'
      elsif $opts[:comment] == :warbles
        $ctl_mic[:warbles_clear] = true
        text = 'Clear warbles'
      else
        text = get_text_invalid(char, true)
      end
    elsif char == 'CTRL-L'
      $ctl_mic[:redraw] = Set[:silent, :clear]
      text = 'redraw'
    elsif char == 'I'
      $opts[:immediate] = !$opts[:immediate]
      text = 'immediate is ' + ( $opts[:immediate] ? 'ON' : 'OFF' )
      $ctl_mic[:redraw] = Set[:silent] if $opts[:comment] == :holes_some
    elsif char == '§'
      $opts[:debug] = true
      text = 'Debug is ON'
    elsif char.length > 0
      text = get_text_invalid(char, true)
    end
    ctl_response(text) if text && !waited
    waited
  end

  def ctl_response text = nil, hl: false, tntf: Time.now.to_f, redraw: false
    # Immediate acknowledge to user input. Also, after a while, display default text if no
    # input has been given
    if redraw
      text = $ctl_response_last_text || $ctl_response_default
    else
      if text
        # remember timestamp of non-default text
        $ctl_response_non_def_ts = tntf
      else
        # let any non-default text stand for 3 secs
        return if $ctl_response_non_def_ts && tntf < $ctl_response_non_def_ts + 3

        text = $ctl_response_default
      end
      return if $ctl_response_last_text == text
    end
    $ctl_response_last_text = text
    text = text[0..$ctl_response_width - 1] if text.length > $ctl_response_width
    print "\e[#{$lines[:mission]};#{$term_width - $ctl_response_width}H\e[0m"
    if hl.is_a?(Numeric)
      wheel = $resources[:hl_wheel]
      print "\e[0m\e[#{wheel[hl % wheel.length]}m"
    elsif text == $ctl_response_default || hl == :low
      print "\e[2m"
    elsif hl
      print "\e[32m"
    else
      print "\e[0m"
    end
    print "#{text.rjust($ctl_response_width)}\e[0m"
  end

  def read_answer ans2chs_dscs
    ans2klist = ans2chs_dscs.map {|ans, chs_dscs| [ans, chs_dscs[0].join(',')]}.to_h
    maxlenl = ans2klist.values.map(&:length).max
    # let two entries spill over
    maxlenr = ans2chs_dscs.values.map {|chs_dscs| chs_dscs[1].length}.max
    items = []
    ans2chs_dscs.each do |ans, chs_dsc|
      item = ["  #{ans2klist[ans].rjust(maxlenl)}",
              ': ',
              "#{chs_dsc[1].ljust(maxlenr)}"]
      if (items + item).flatten.join.length <= $conf[:term_min_width]
        items << item
      else
        items.each {|itm| print itm[0] + itm[1] + "\e[2m" + itm[2] + "\e[0m"}
        puts
        items = [item]
      end
    end
    if items.length > 0
      items.each {|itm| print itm[0] + itm[1] + "\e[2m" + itm[2] + "\e[0m"}
      puts
    end
    begin
      print 'Your choice (h for help): '
      char = one_char
      char = 'SPACE' if char == ' '
      puts char
      answer = nil
      ans2chs_dscs.each do |ans, chs_dsc|
        answer = ans if chs_dsc[0].include?(char)
      end
      answer = :help if char == 'h'
      puts "Invalid key: '#{char.match?(/[[:print:]]/) ? char : '?'}' (#{char.ord})" unless answer
      if answer == :help
        puts "Full Help:\n\n"
        ans2chs_dscs.each do |ans, chs_dsc|
          desc_lines = chs_dsc[2..-1]
          desc = ([desc_lines[0]] + desc_lines[1..-1].map {|l| ' ' * (maxlenl + 5) + l}).join("\n")
          puts "  %#{maxlenl}s:  %s" % [ans2klist[ans], desc]
        end
        puts
      end
    end while !answer || answer == :help
    answer
  end

  def drain_chars
    prepare_term
    # drain any already pending chars
    system('stty -echo -icanon min 0 time 0')
    Kernel.print "\e[?25l"  ## hide cursor
    begin
    end while STDIN.getc
    system('stty min 1')
    sane_term
  end

  def one_char
    prepare_term
    # wait for char
    key = get_complex_key
    # drain any remaining chars (e.g. after pressing function-keys)
    system('stty -echo -icanon min 0 time 0')
    Kernel.print "\e[?25l"  ## hide cursor
    begin
    end while STDIN.getc
    system('stty min 1')
    sane_term
    key
  end

  def clear_area_display
    ($lines[:display]..$lines[:hole] - 1).each {|l| print "\e[#{l}H\e[K"}
    print "\e[#{$lines[:display]}H"
  end

  def clear_area_comment offset = 0
    ($lines[:comment_tall] + offset..$lines[:hint_or_message] - 1).each {|l| print "\e[#{l}H\e[K"}
    print "\e[#{$lines[:comment_tall]}H"
  end

  def clear_area_message
    ($lines[:hint_or_message]..$term_height).each do |lnum|
      print "\e[#{lnum}H\e[K"
    end
  end

  def handle_win_change
    $term_height, $term_width = `stty size`.split.map(&:to_i)
    $lines = Cfg::calculate_screen_layout
    print "\e[s\e[2J\e[u"
    until check_screen(graceful: true)
      puts "\e[2m"
      puts "\n\n\e[0mScreensize is not acceptable, see above!"
      puts "\nYou may enlarge screen right now to continue,"
      puts
      puts 'or press CTRL-C to break.'
      $ctl_sig_winch = false
      sleep 0.2 until $ctl_sig_winch
      $term_height, $term_width = `stty size`.split.map(&:to_i)
      $lines = Cfg::calculate_screen_layout
      system('clear')
      puts
    end
    $figlet_cache = Hash.new
    $warble_cache = Hash.new
    $freqs_queue.clear
    $ctl_mic[:redraw] = Set.new
    $ctl_sig_winch = false
  end

  def journal_menu
    $opts[:comment] = :journal
    clear_area_comment
    clear_area_message
    print "\e[#{$lines[:comment_tall]}H\e[J"
    print "\e[2m"
    puts " \e[0m\e[34mJournal-menu             \e[0m\e[32ma\e[0m\e[2m: toggle journal of all notes (now #{$journal_all ? ' ON' : 'OFF'})"
    print "\e[0m\e[32m"
    puts "     \e[0m\e[32mp\e[0m\e[2m: play journal, using durations (e.g. '(0.3s)')"
    puts "     \e[0m\e[32me\e[0m\e[2m: invoke editor     \e[0m\e[32ms\e[0m\e[2m: show short for copy"
    puts "     \e[0m\e[32mw\e[0m\e[2m: write to file     \e[0m\e[32mr\e[0m\e[2m: recall 100 old lines from file into edit"
    puts " \e[0m\e[34mOutside\e[0m\e[2m this menu, when comment is 'journal'"
    puts "     \e[0m\e[32mRETURN\e[0m\e[2m: add the current hole   \e[0m\e[32mBACKSPACE\e[0m\e[2m: delete most recent"
    puts "     \e[0m\e[32mCTRL-H, CTRL-BACKSPACE\e[0m\e[2m: save, then delete whole journal; use here too"
    puts " \e[0m\e[34mAnywhere, anytime\e[0m\e[2m        \e[0m\e[32mj\e[0m\e[2m: invoke journal-menu and switch comment"

    print "\e[0m\e[2m Type one of the keys above for action, any other to leave; \e[0m\e[32mthen play\e[0m\e[2m ...\e[K"
    char = $ctl_kb_queue.deq
    case char
    when 'j'
    when 'a'
      $ctl_mic[:journal_all_toggle] = true
    when 'w'
      $ctl_mic[:journal_write] = true
    when 'p'
      $ctl_mic[:journal_play] = true
    when 'CTRL-BACKSPACE'
      $ctl_mic[:journal_clear] = true
    when 's'
      $ctl_mic[:journal_short] = true
    when 'e'
      $ctl_mic[:journal_edit] = true
    when 'r'
      $ctl_mic[:journal_recall] = true
    when 'q', 'x'
      $msgbuf.print 'Quit journal menu', 0, 5
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
      stime = $messages_seen[tag] ? 0.1 : 0.2
      $messages_seen[tag] = true
      5.times do
        break if $ctl_kb_queue.length > 0

        sleep stime
      end
      $opts[:comment] = :warbles
    else
      $warbles_holes = Array.new(2)
      clear_area_comment
      print "\e[#{$lines[:comment_tall] + 2}H\e[0m"
      puts '   Setting holes for warbling:'
      puts
      puts "     Press \e[32mm\e[0m to choose from menu"
      puts "     or \e[32mw\e[0m or \e[32many other key\e[0m to choose by playing."
      $ctl_kb_queue.clear
      char = $ctl_kb_queue.deq
      if char == 'm'
        [0, 1].each do |idx|
          $warbles_holes[idx] = Choose::choose_interactive("Please set   \e[32m#{%w[FIRST SECOND][idx]}\e[0m   hole for warbling: ", $harp_holes)
          clear_area_comment
          print "\e[0m\e[32m"
          puts
          Text::do_figlet_unwrapped $warbles_holes[idx] || '-', 'mono9'
          print "\e[0m"
          sleep 0.7
          break unless $warbles_holes[idx]
        end
      end
      if $warbles_holes.any?(:nil?) || $warbles_holes[0] == $warbles_holes[1]
        $warbles_holes = Array.new(2)
        if $warbles_holes[0] && $warbles_holes[0] == $warbles_holes[1]
          $msgbuf.print 'Cannot choose the same hole twice; warbling canceled', 2, 4
        else
          $msgbuf.print 'Warbling holes have not been set', 2, 4
        end
        ShowMic::clear_warbles
      else
        $msgbuf.print 'Warbling holes set', 2, 4
      end
      $freqs_queue.clear
    end
  end

  def get_text_invalid char, simple = false
    cdesc = if char.match?(/^[[:print:]]+$/)
              char
            else
              "? (#{char.ord})"
            end
    return 'invalid key ' + cdesc if simple


    "invalid key '#{cdesc}', h for help"
  end

  def space_to_cont
    wheel = $resources[:hl_wheel]
    # text may wrap around to next line and cause screen to scroll
    # up. So we first go with spaces and erase them: if wrap occurs, we
    # end up at start of next line (which is okay); if no wrap occurs we
    # end at the original pos.
    # Note, that \e[s is not usable here, because it does not help in
    # case of scroll up
    print ' ' * $resources[:space_to_cont].length
    print "\e[#{$resources[:space_to_cont].length}D"
    cnt = 0
    begin
      while $ctl_kb_queue.empty?
        print "\e[0m\e[#{wheel[( cnt / 10 ) % wheel.length]}m#{$resources[:space_to_cont]}"
        print "\e[#{$resources[:space_to_cont].length}D"
        cnt += 1
        sleep 0.1
      end
      char = $ctl_kb_queue.deq
    end until char == ' '
    print "\e[0m\e[2m#{$resources[:space_to_cont]}"
  end

  def gets_with_cursor
    Kernel.print "\e[?25h"  ## show cursor
    input = STDIN.gets.chomp.strip
    Kernel.print "\e[?25l"  ## hide cursor
    input
  end

  def get_complex_key
    #
    # Hint: Also use "showkey -a" to find out the exact
    # character-sequence, that are beeing sent by special keys
    #
    key = STDIN.getc
    complete = true
    # chars after initial escape
    chs = Array.new
    #
    # Handle key sequences starting with escape
    #
    if key == "\e"
      #
      # Try to recognize cursor keys and some others
      #
      begin
        chs << Timeout.timeout(0.05) { STDIN.getc }
        if chs[0] == '['
          chs << Timeout.timeout(0.05) { STDIN.getc }
          key = case chs[1]
                when 'A'
                  'UP'
                when 'B'
                  'DOWN'
                when 'C'
                  'RIGHT'
                when 'D'
                  'LEFT'
                when 'Z'
                  'SHIFT-TAB'
                when '5', '6'
                  chs << Timeout.timeout(0.05) { STDIN.getc }
                  if chs[2] == '~'
                    if chs[1] == '5'
                      'PAGE-UP'
                    else
                      'PAGE-DOWN'
                    end
                  else
                    complete = false
                  end
                else
                  complete = false
                end
        elsif chs[1] == "\t"
          key = 'SHIFT-TAB'
        elsif ('a'..'z').include?(chs[1])
          key = 'ALT-' + chs[1]
        elsif chs[1]
          complete = false
        else
          complete = false
        end
        unless complete
          # Got no complete escape sequence; probably some special key,
          # we dont recognize yet. So read until timeout to report it
          # properly as one single key and to not leave chars unconsumed
          chs << Timeout.timeout(0.05) { STDIN.getc } while true
        end
      rescue Timeout::Error
        key = 'ESC-' + escape_chars(chs) unless complete
      end
    end

    #
    # Translate selected control-characters and escape-sequences into
    # descriptive and printable text. Tested under Windows Terminal and
    # KDE Konsole.
    #
    if key.length == 1

      # Simple chars
      case key
      when "\n"
        'RETURN'
      when "\t"
        'TAB'
      when "\e"
        'ESC'
      else

        case key.ord
        when 18
          'CTRL-R'
        when 12
          'CTRL-L'
        when 127
          'BACKSPACE'
        when 8
          'CTRL-BACKSPACE'
        else
          key
        end
      end

    else  ##  for key.length != 1

      # Escape-sequences
      case key
      when 'ESC-[1;5D'
        'CTRL-LEFT'
      when 'ESC-[1;5C'
        'CTRL-RIGHT'
      when 'ESC-[1;5A'
        'CTRL-UP'
      when 'ESC-[1;5B'
        'CTRL-DOWN'
      when 'ESC-[1;2D'
        'SHIFT-LEFT'
      when 'ESC-[1;2C'
        'SHIFT-RIGHT'
      when 'ESC-[1;2A'
        'SHIFT-UP'
      when 'ESC-[1;2B'
        'SHIFT-DOWN'
      when 'ESC-[1;3D'
        'ALT-LEFT'
      when 'ESC-[1;3C'
        'ALT-RIGHT'
      when 'ESC-[1;3A'
        'ALT-UP'
      when 'ESC-[1;3B'
        'ALT-DOWN'
      when 'ESC-\x0a'
        'ALT-RETURN'
      when 'ESC-\x7f'
        'ALT-BACKSPACE'
      when 'ESC-[5;3~'
        'ALT-PAGE-UP'
      when 'ESC-[5;5~'
        'CTRL-PAGE-UP'
      when 'ESC-[6;3~'
        'ALT-PAGE-DOWN'
      when 'ESC-[6;5~'
        'CTRL-PAGE-DOWN'
      when 'ESC-[3~'
        'DEL'
      when 'ESC-[3;3~'
        'ALT-DEL'
      when 'ESC-[3;5~'
        'CTRL-DEL'
      when 'ESC-[H'
        'POS1'
      when 'ESC-[1;3H'
        'ALT-POS1'
      when 'ESC-[1;5H'
        'CTRL-POS1'
      when 'ESC-[F'
        'END'
      when 'ESC-[1;3F'
        'ALT-END'
      when 'ESC-[1;5F'
        'CTRL-END'
      when 'ESC-[2~'
        'INSERT'
      when 'ESC-[2;3~'
        'ALT-INSERT'
      when 'ESC-[2;5~'
        'CTRL-INSERT'
      when 'ESC-OP'
        'F1'
      when 'ESC-OQ'
        'F2'
      when 'ESC-OR'
        'F3'
      when 'ESC-OS'
        'F4'
      when 'ESC-[15~'
        'F5'
      when 'ESC-[17~'
        'F6'
      when 'ESC-[18~'
        'F7'
      when 'ESC-[19~'
        'F8'
      when 'ESC-[20~'
        'F9'
      when 'ESC-[21~'
        'F10'
      when 'ESC-[23~'
        'F11'
      when 'ESC-[24~'
        'F12'
      else
        key = escape_chars(key.split(//)) if key !~ /^[[:print:]]$/
        key
      end
    end
  end

  def escape_chars chs
    chs.map do |ch|
      if ch =~ /[[:graph:]]/
        ch
      elsif ch.ord <= 255
        '\\x%02x' % ch.ord
      else
        '\\u%04x' % ch.ord
      end
    end.join
  end

  def report_condition_wait_key text, condition = :error
    Interact::clear_area_comment
    print "\e[#{$lines[:comment_tall]}H\e[J\n"
    case condition
    when :error
      print "\e[0;101mAn error has happened:"
    when :info
      print "\e[0m\e[2mPlease note:"
    else
      raise 'Internal error invalid condition'
    end
    print "\e[0m\n\n"
    print text
    print "\n\n\e[2m#{$resources[:any_key]}\e[K"
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
  end
end
