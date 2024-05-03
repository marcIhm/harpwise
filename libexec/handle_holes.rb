#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_mission, lambda_good_done_was_good, lambda_skip, lambda_comment, lambda_hint, lambda_star_lick
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  # we cache time for (assumed) performance reasons
  tntf = Time.now.to_f
  
  # Remark: $hole_was_for_disp needs to be persistant over invocations
  # and cannot be set here

  hole = nil
  hole_since = tntf
  hole_since_ticks = $total_freq_ticks

  # Use ticks (e.g. cycles in handle_holes), because this is
  # potentially more precise than time-spans.  If this is set shorter,
  # the journal will pick up spurious notes
  #
  hole_held_min_ticks = 3
  hole_held_min_ticks_nil = 2
  hole_held = hole_journal = hole_journal_since = nil

  was_good = was_was_good = was_good_since = nil
  $msgbuf.update(tntf, refresh: true)
  hints_refreshed_at = tntf - 1000.0
  hints = hints_old = nil

  warbles_first_hole_seen = false
  warbles_announced = false

  first_round = true
  for_testing_touched = false
  $perfctr[:handle_holes_calls] += 1
  $perfctr[:handle_holes_this_loops] = 0
  $perfctr[:handle_holes_this_first_freq] = nil
  if $hole_ref
    $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
    $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
  end
  $msgbuf.ready
  
  loop do   # over each new frequency from pipeline, until var done or skip

    $perfctr[:handle_holes_this_loops] += 1
    tntf = Time.now.to_f

    if first_round || $ctl_mic[:redraw]
      system('clear') if $ctl_mic[:redraw] && $ctl_mic[:redraw].include?(:clear)
      print_mission(get_mission_override || lambda_mission.call)
      ctl_response
      print "\e[#{$lines[:key]}H" + text_for_key
      print_chart($hole_was_for_disp) if [:chart_notes, :chart_scales, :chart_intervals, :chart_inter_semis].include?($opts[:display])
      print "\e[#{$lines[:interval]}H\e[2mInterval:   --  to   --  is   --  \e[K"
      if $ctl_mic[:redraw] && !$ctl_mic[:redraw].include?(:silent)
        $msgbuf.print "Terminal [width, height] = [#{$term_width}, #{$term_height}] is #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;101mON THE EDGE\e[0;2m of"  :  'above'} minimum [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]", 2, 5, :term
      end
      # updates messages and returns true, if hint is allowed
      hints_old = nil if $msgbuf.update(tntf, refresh: true)
      $ctl_mic[:redraw] = false
      $ctl_mic[:update_comment] = true
    end
    if $first_round_ever_get_hole
      print "\e[#{$lines[:hint_or_message]}H"
      if $mode == :listen
        animate_splash_line(single_line = true)
        $msgbuf.print nil, 0, 6
      end
    end

    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq
    if $testing && !for_testing_touched
      FileUtils.touch("/tmp/#{File.basename($0)}_pipeline_started")
      for_testing_touched = true
    end

    $total_freq_ticks += 1
    $perfctr[:handle_holes_this_first_freq] ||= Time.now.to_f

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_mic
    
    behind = $freqs_queue.length * $time_slice_secs
    if behind > 0.5
      now = tntf
      if now - $mode_start > 10
        $lagging_freqs_lost += $freqs_queue.length 
        $freqs_queue.clear
        if now - $lagging_freqs_message_ts > 120 
          $msgbuf.print "Lagging #{'%.1f' % behind}s; more info on termination (e.g. ctrl-c).", 5, 5
          $lagging_freqs_message_ts = now
        end
      else
        $freqs_queue.clear
      end
    end

    # also restores default text after a while
    ctl_response

    handle_win_change if $ctl_sig_winch
    
    # transform freq into hole
    hole_was = hole
    hole, lbor, cntr, ubor = describe_freq(freq)
    if hole_was != hole
      hole_since = tntf
      hole_since_ticks = $total_freq_ticks
    end
    sleep 1 if $testing_what == :lag

    # detect and update warbling
    if $opts[:comment] == :warbles
      if hole_held && ( !$warbles_holes[0] || !$warbles_holes[1] )
        # defining warbel holes
        $warbles_holes[0] = hole_held if !$warbles_holes[0] && hole_held != $warbles_holes[1]
        $warbles_holes[1] = hole_held if !$warbles_holes[1] && hole_held != $warbles_holes[0]
        if !warbles_announced && $warbles_holes[0] && $warbles_holes[1]
          $msgbuf.print "Warbling between holes #{$warbles_holes[0]} and #{$warbles_holes[1]}", 5, 5, :warble
          warbles_announced = true
        end
      end
      add_warble = false
      if hole == $warbles_holes[0]
        warbles_first_hole_seen = true
      elsif hole == $warbles_holes[1]
        add_warble = warbles_first_hole_seen
        warbles_first_hole_seen = false
      end
      add_and_del_warbles(tntf, add_warble)
    end

    # distinguish deliberate playing from noise: compute hole_held
    # remember old value to allow detecting change below
    held_min_ticks = ( hole ? hole_held_min_ticks : hole_held_min_ticks_nil )
    hole_held_was = hole_held
    hole_held = hole if $total_freq_ticks - hole_since_ticks >= held_min_ticks

    # update journal if hole_held has changed
    if $journal_all && hole_held_was != hole_held
      if hole_held
        if hole_journal && hole_journal != hole_held
          $journal << ('(%.1fs)' % (tntf - hole_journal_since)) if journal_length > 0 && !musical_event?($journal[-1])
        end
        hole_journal = hole_held
        $journal << hole_held
        hole_journal_since = hole_since 
        $msgbuf.print("#{journal_length} holes", 2, 5, :journal) if $opts[:comment] == :journal
      else
        $journal << ('(%.1fs)' % (tntf - hole_journal_since)) if journal_length > 0 && !musical_event?($journal[-1])
      end
    end

    # $hole_held_inter should never be nil and different from current hole_held
    if !$hole_held_inter || (hole_held && $hole_held_inter != hole_held)
      # the same condition below and above, only with different vars
      # btw: this is not a stack
      if !$hole_held_inter_was || ($hole_held_inter && $hole_held_inter_was != $hole_held_inter)
        $hole_held_inter_was = $hole_held_inter
      end
      $hole_held_inter = hole_held
    end
    
    good,
    done,
    was_good = if $opts[:screenshot]
                 [true, [:quiz, :licks].include?($mode) && tntf - hole_since > 2, false]
               else
                 $perfctr[:lambda_good_done_was_good_call] += 1
                 lambda_good_done_was_good.call(hole, hole_since)
               end

    if $ctl_mic[:done]
      good = done = true
      $ctl_mic[:done] = false
    end

    was_good_since = tntf if was_good && was_good != was_was_good

    #
    # Handle Frequency and gauge
    #
    print "\e[2m\e[#{$lines[:frequency]}HFrequency:  "
    just_dots_short = '.........:.........'
    format = "%6s Hz, %4s Cnt  [%s]\e[2m\e[K"
    if hole
      dots, in_range = get_dots(just_dots_short.dup, 2, freq, lbor, cntr, ubor) {|in_range, marker| in_range ? "\e[0m#{marker}\e[2m" : marker}
      cents = cents_diff(freq, cntr).to_i
      print format % [freq.round(1), cents, dots]
    else
      print format % ['--', '--', just_dots_short]
    end

    #
    # Handle intervals
    #
    hole_for_inter = $hole_ref || $hole_held_inter_was
    inter_semi, inter_text, _, _ = describe_inter($hole_held_inter, hole_for_inter)
    if inter_semi
      print "\e[#{$lines[:interval]}HInterval: #{$hole_held_inter.rjust(4)}  to #{hole_for_inter.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[0m\e[%dm" %
                 if $opts[:no_progress]
                   get_hole_color_inactive(hole)
                 else
                   get_hole_color_active(hole, good, was_good, was_good_since)
                 end
    hole_ref_color = "\e[#{hole == $hole_ref ?  92  :  91}m"
    case $opts[:display]
    when :chart_notes, :chart_scales, :chart_intervals, :chart_inter_semis
      update_chart($hole_was_for_disp, :inactive) if $hole_was_for_disp && $hole_was_for_disp != hole
      $hole_was_for_disp = hole if hole
      update_chart(hole, :active, good, was_good, was_good_since)
    when :hole
      print "\e[#{$lines[:display]}H\e[0m"
      print hole_color
      do_figlet_unwrapped hole_disp, 'mono12', longest_hole_name
    else
      fail "Internal error: #{$opts[:display]}"
    end

    text = "Hole: %#{longest_hole_name.length}s, Note: %4s" %
           (hole  ?  [hole, $harp[hole][:note]]  :  ['-- ', '-- '])
    text += ", Ref: %#{longest_hole_name.length}s" % [$hole_ref || '-- ']
    text += ",  Rem: #{$hole2rem[hole] || '--'}" if $hole2rem
    print "\e[#{$lines[:hole]}H\e[2m" + truncate_text(text) + "\e[K"

    
    if lambda_comment
      $perfctr[:lambda_comment_call] += 1
      case $opts[:comment]
      when :holes_scales, :holes_intervals, :holes_inter_semis, :holes_all, :holes_notes
        fit_into_comment lambda_comment.call
      when :journal
        fit_into_comment lambda_comment.call('', nil, nil, nil, nil, nil)
      when :warbles
        fit_into_comment lambda_comment.call('', nil, nil, nil, nil, nil)
      else
        color,
        text,
        line,
        font,
        width_template =
        lambda_comment.call($hole_ref  ?  hole_ref_color  :  hole_color,
                            inter_semi,
                            inter_text,
                            hole && $harp[hole] && $harp[hole][:note],
                            hole_disp,
                            freq)
        print "\e[#{line}H#{color}"
        do_figlet_unwrapped text, font, width_template
      end
    end

    if done
      print "\e[#{$lines[:message2]}H" if $lines[:message2] > 0
      return
    end

    # updates and returns true, if hint is allowed
    if $msgbuf.update(tntf)
      # A specific message has been shown, that overrides usual hint,
      # so trigger redisplay of hint when message is expired
      hints_old = nil
    elsif lambda_hint && tntf - hints_refreshed_at > 1
      # Make sure to refresh hint, once the current message has elapsed
      $perfctr[:lambda_hint_call] += 1
      hints = lambda_hint.call(hole)
      hints_refreshed_at = tntf
      if hints && hints[0] && hints != hints_old
        $perfctr[:lambda_hint_reprint] += 1
        print "\e[#{$lines[:message2]}H\e[K" if $lines[:message2] > 0
        print "\e[#{$lines[:hint_or_message]}H\e[0m\e[2m"
        # Using truncate_colored_text might be too slow here
        if hints.length == 1
          # for mode quiz and listen
          print truncate_text(hints[0]) + "\e[K"
        elsif hints.length == 2 && $lines[:message2] > 0
          # for mode licks
          # hints:
          #  0 = hole_hint
          #  1 = lick_hint (rotates through name, tags and desc)
          print truncate_text(hints[0]) + "\e[K"
          print "\e[#{$lines[:message2]}H\e[0m\e[2m"
          print truncate_text(hints[1]) + "\e[K"
        else
          fail "Internal error"
        end
        print "\e[0m\e[2m"
      end
      hints_old = hints
    end
                                                                                                   
    if $ctl_mic[:set_ref]
      if $ctl_mic[:set_ref] == :played
        $hole_ref = hole_held
      else
        choices = $harp_holes
        $hole_ref = choose_interactive("Choose the new reference hole: ", choices) do |choice|
          "Hole #{choice}"
        end 
        $freqs_queue.clear        
      end
      $msgbuf.print "#{$hole_ref ? 'Stored' : 'Cleared'} reference hole", 2, 5, :ref
      if $hole_ref 
        $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
        $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
      end
      if $opts[:display] == :chart_intervals || $opts[:display] == :chart_inter_semis 
        clear_area_display
        print_chart
      end
      clear_warbles 
      $ctl_mic[:set_ref] = false
      $ctl_mic[:update_comment] = true
    end

    if $ctl_mic[:change_display]
      if $ctl_mic[:change_display] == :choose
        choices = $display_choices.map(&:to_s)
        choices.rotate! while choices[0].to_sym != $opts[:display]
        $opts[:display] = (choose_interactive("Available display choices (current is #{$opts[:display].upcase}): ", choices) do |choice|
                             $display_choices_desc[choice.to_sym]
        end || $opts[:display]).to_sym
        $freqs_queue.clear
      else
        $opts[:display] = rotate_among($opts[:display], :up, $display_choices)
      end
      if $hole_ref
        $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
        $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
      end
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_intervals, :chart_inter_semis].include?($opts[:display])
      $msgbuf.print "Display is #{$opts[:display].upcase}: #{$display_choices_desc[$opts[:display]]}", 2, 5, :display
      $ctl_mic[:change_display] = false
    end
    
    if $ctl_mic[:change_comment]
      clear_warbles
      if $ctl_mic[:change_comment] == :choose
        choices = $comment_choices[$mode].map(&:to_s)
        choices.rotate! while choices[0].to_sym != $opts[:comment]
        $opts[:comment] = (choose_interactive("Available comment choices (current is #{$opts[:comment].upcase}): ", choices) do |choice|
                             $comment_choices_desc[choice.to_sym]
                           end || $opts[:comment]).to_sym
        $freqs_queue.clear
      else
        $opts[:comment] = rotate_among($opts[:comment], :up, $comment_choices[$mode])
      end
      clear_area_comment
      $msgbuf.print "Comment is #{$opts[:comment].upcase}: #{$comment_choices_desc[$opts[:comment]]}", 2, 5, :comment
      $ctl_mic[:change_comment] = false
      $ctl_mic[:update_comment] = true
    end

    if $ctl_mic[:show_help]
      show_help
      ctl_response 'continue', hl: true
      $ctl_mic[:show_help] = false
      $ctl_mic[:redraw] = Set[:clear, :silent]
      $freqs_queue.clear
    end

    if $ctl_mic[:start_loop]
      $ctl_mic[:loop] = true
      $ctl_mic[:start_loop] = false
      print_mission(get_mission_override || lambda_mission.call)
    end
    
    if $ctl_mic[:toggle_progress]
      $opts[:no_progress] = !$opts[:no_progress]
      $ctl_mic[:toggle_progress] = false
      print_mission(get_mission_override || lambda_mission.call)
    end

    if $ctl_mic[:auto_replay]
      $opts[:auto_replay] = !$opts[:auto_replay]
      $ctl_mic[:auto_replay] = false
      $msgbuf.print("Auto replay is: " + ( $opts[:auto_replay] ? 'ON' : 'OFF' ), 2, 5, :replay)
    end

    if $ctl_mic[:player_details]
      $ctl_mic[:player_details] = false
      if $players.stream_current
        system('clear')
        puts
        print_player($players.structured[$players.stream_current])
        if $opts[:viewer] != 'feh' || !$players.structured[$players.stream_current]['image'][0]
          puts "\n\e[0m\e[2m  Press any key to go back to mode '#{$mode}' ...\e[0m"
          $ctl_kb_queue.clear
          $ctl_kb_queue.deq
        end
        $ctl_mic[:redraw] = Set[:clear, :silent]
        $freqs_queue.clear
      else
        $msgbuf.print("Featuring players not yet started, please stand by", 2, 5, :replay)
      end
    end

    if $ctl_mic[:star_lick] && lambda_star_lick
      lambda_star_lick.call($ctl_mic[:star_lick] == :up  ?  +1  :  -1)
      $ctl_mic[:star_lick] = false
    end
    
    if $ctl_mic[:change_key]
      do_change_key
      $ctl_mic[:change_key] = false
      $ctl_mic[:redraw] = Set[:silent]
      set_global_vars_late
      set_global_musical_vars
      $freqs_queue.clear
    end

    if $ctl_mic[:pitch]
      do_change_key_to_pitch
      $ctl_mic[:pitch] = false
      $ctl_mic[:redraw] = Set[:clear, :silent]
      set_global_vars_late
      set_global_musical_vars
      $freqs_queue.clear
    end

    if $ctl_mic[:change_scale]
      do_change_scale_add_scales
      $ctl_mic[:change_scale] = false
      $ctl_mic[:redraw] = Set[:silent]
      set_global_vars_late
      set_global_musical_vars
      $freqs_queue.clear
    end

    if $ctl_mic[:rotate_scale]
      do_rotate_scale_add_scales
      $ctl_mic[:rotate_scale] = false
      $ctl_mic[:redraw] = Set[:silent]
      set_global_vars_late
      set_global_musical_vars
      $freqs_queue.clear
    end

    if [:change_lick, :edit_lick_file, :change_tags, :reverse_holes, :shuffle_holes, :switch_modes, :switch_modes, :journal_current, :journal_delete, :journal_menu, :journal_write, :journal_play, :journal_clear, :journal_edit, :journal_all_toggle, :warbles_prepare, :warbles_clear, :toggle_record_user, :change_num_quiz_replay, :quiz_hint].any? {|k| $ctl_mic[k]}
      # we need to return, regardless of lambda_good_done_was_good;
      # special case for mode listen, which handles the returned value
      return {hole_disp: hole_disp}
    end

    if $ctl_mic[:quit]
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[0mTerminating on user request (quit) ...\n\n"
      exit 0
    end

    $msgbuf.clear if done
    first_round = $first_round_ever_get_hole = false
  end  # loop until var done or skip
end


def text_for_key
  text = "\e[0m#{$mode}\e[2m"
  if $mode == :licks
    text += "(#{$licks.length},#{$opts[:iterate][0..2]})"
  end
  text += " \e[0m#{$extra}\e[2m" if $extra
  text += " #{$type} \e[0m#{$key}"
  if $used_scales.length > 1
    text += "\e[0m"
    text += " \e[32m#{$scale}"
    text += "\e[0m\e[2m," + $used_scales[1..-1].map {|s| "\e[0m\e[34m#{$scale2short[s] || s}\e[0m\e[2m"}.join(',')
  else
    text += "\e[32m #{$scale}\e[0m\e[2m"
  end
  text += '; journal-all ' if $journal_all
  truncate_colored_text(text, $term_width - 2 ) + "\e[K"
end


def get_dots dots, delta_ok, freq, low, middle, high
  hdots = (dots.length - 1)/2
  if freq > middle
    pos = hdots + ( hdots + 1 ) * (freq - middle) / (high - middle)
  else
    pos = hdots - ( hdots + 1 ) * (middle - freq) / (middle - low)
  end

  in_range = ((hdots - delta_ok  .. hdots + delta_ok) === pos )
  dots[pos] = yield( in_range, 'I') if pos > 0 && pos < dots.length
  return dots, in_range
end


def fit_into_comment lines
  start = if lines.length >= $lines[:hint_or_message] - $lines[:comment_tall]
            $lines[:comment_tall]
          else
            print "\e[#{$lines[:comment_tall]}H\e[K"
            $lines[:comment]
          end
  print "\e[#{start}H\e[0m"
  (start .. $lines[:hint_or_message] - 1).to_a.each do |n|
    puts ( lines[n - start] || "\e[K" )
  end 
end


def do_change_key
  key_was = $key
  keys = if $key[-1] == 's'
           $notes_with_sharps
         elsif $key[-1] == 'f'
           $notes_with_sharps
         elsif $opts[:sharps_or_flats] == :flats
           $notes_with_flats
         else
           $notes_with_sharps
         end
  $key = choose_interactive("Available keys (current is #{$key}): ", keys) do |key|
    if key == $key
      "The current key"
    else
      "#{describe_inter_keys(key, $key)} to the current key #{$key}"
    end
  end || $key
  if $key == key_was
    $msgbuf.print "Key of harp unchanged \e[0m#{$key}", 2, 5, :key
  else
    $msgbuf.print "Changed key of harp to \e[0m#{$key}", 2, 5, :key
  end
end


def do_change_key_to_pitch
  clear_area_comment
  clear_area_message
  key_was = $key
  print "\e[#{$lines[:comment]+1}H\e[0mUse the adjustable pitch to change the key of harp.\e[K\n"
  puts "\e[0m\e[2mPress any key to start (and RETURN when done) ...\e[K\e[0m\n\n"
  $ctl_kb_queue.clear
  char = $ctl_kb_queue.deq
  return if char == 'q' || char == 'x'
  $key = play_interactive_pitch(embedded = true) || $key
  $msgbuf.print(if key_was == $key
                "Key of harp is still at"
               else
                 "Changed key of harp to"
                end + " \e[0m#{$key}", 2, 5, :key)
end


def do_change_scale_add_scales
  input = choose_interactive("Choose main scale (current is #{$scale}): ", $all_scales.sort) do |scale|
    $scale_desc_maybe[scale] || '?'
  end
  $scale = input if input
  unless input
    $msgbuf.print "Did not change scale of harp.", 0, 5, :key
    return
  end
  
  # Change --add-scales
  add_scales = []
  loop do
    input = choose_interactive("Choose additional scale #{add_scales.length + 1} (current is '#{$opts[:add_scales]}'): ",
                               ['DONE', $all_scales.sort].flatten) do |scale|
      if scale == 'DONE'
        'Choose this, when done with adding scales'
      else
        $scale_desc_maybe[scale] || '?'
      end
    end
    break if !input || input == 'DONE'
    add_scales << input
  end
  if add_scales.length == 0
    $opts[:add_scales] = nil
  else
    $opts[:add_scales] = add_scales.join(',')
  end

  $msgbuf.print "Changed scale of harp to \e[0m\e[32m#{$scale}", 2, 5, :scale
end


def do_rotate_scale_add_scales
  $used_scales.rotate!
  $scale = $used_scales[0]
  $opts[:add_scales] = $used_scales.length > 1  ?  $used_scales[1..-1].join(',')  :  nil
  $msgbuf.print "Changed scale of harp to \e[0m\e[32m#{$scale}", 0, 5, :scale
end


def get_mission_override
  $opts[:no_progress]  ?  "\e[0m\e[2mNot tracking progress."  :  nil
end


def show_help
  max_lines_per_frame = 20
  fail "Internal error: max_lines_per_frame chosen too large" if max_lines_per_frame + 2 > $conf[:term_min_height]
  lines_offset = (( $term_height - max_lines_per_frame ) * 4 / 5.0).to_i
  
  frames = Array.new
  frames << [" Help on keys (invoke 'harpwise' without args for more info):",
             " \e[0m\e[2mVersion #{$version}\e[0m\e[32m",
             "",
             "  SPACE: pause and continue      ctrl-l: redraw screen",
             "    d,D: change display (upper part of screen)",
             "    c,C: change comment (in lower part of screen)",
             "    r,R: set reference to hole played or chosen",
             "      k: change key of harp",
             "      K: play adjustable pitch and take it as new key",
             "      s: rotate current scales        S: set scales"]
  if [:quiz, :licks].include?($mode)
    frames[-1] <<  "      j: journal-menu; only available in mode listen"
    frames[-1] <<  " ctrl-r: record and play user (mode licks only)"
  else
    frames[-1] <<  "      j: journal-menu to handle holes collected"
    frames[-1] <<  "      w: switch comment to warble and prepare"
    frames[-1] <<  "      p: print details about current player"
  end
    
  if [:listen, :quiz, :licks].include?($mode)
    frames[-1] << "      m: switch between modes #{$modes_for_switch.map(&:to_s).join(',')}"
  end
  frames[-1].append(*["      q: quit harpwise                h: this help",
                      ""])
  
  if [:quiz, :licks].include?($mode)
    frames << [" More help on keys (special for modes licks and quiz):",
               "",
               " RETURN: next sequence or lick     BACKSPACE: previous sequence",
               "     .:: replay current                   ,;: replay, holes only",
               "    :;p: replay but ignore '--partial', i.e. play all",
               "      P: toggle automatic replay when looping over a sequence",
               "      i: toggle '--immediate'              L: loop current sequence",
               "    0,-: forget holes played               +: skip rest of sequence",
               "      t: toggle tracking progress in seq"]
    if $mode == :quiz
      frames[-1] << "      H: hints for quiz-flavour #{$extra}"
    end
    if $mode == :licks
      frames[-1].append(*["      l: change current lick               e: edit lickfile",
                          "      t: change option --tags-any (aka -t)",
                          "      %: shift lick by chosen interval     @: change option --partial",
                          "     */: Add or remove Star from current lick persistently;",
                          "         select them later by tag 'starred'",
                          "      !: play holes reversed               &: shuffle holes",
                          ""])
    elsif $mode == :quiz && $extra == 'replay'
      frames[-1] << "      n: change number of holes to be replayed"
      frames[-1] << ""
    else
      frames[-1] << ""
    end
    frames[-1].append(*[" Note, that other keys (and help) apply when harpwise plays itself."])
  end

  # add prompt to frames, so that it can be tested below
  frames.each_with_index do |frame, curr_frame|
    can_back = ( curr_frame > 0 )
    can_for = ( curr_frame < frames.length - 1 )
    prompt = ' ' +
             if can_for
               'Press any key to show more help'
             else
               'Press any key to leave help'
             end +
             if can_back
               ', BACKSPACE for previous screen'
             else
               ''
             end +
             ' ...'
    frame << prompt
  end
    
  
  if $testing
    frames.each do |frame|
      err "Internal error: frame #{frame} with #{frame.length} lines is longer than maximum of #{max_lines_per_frame}" if frame.length > max_lines_per_frame
      frame.each do |line|
        err "Internal error line '#{line}' with #{line.length} chars is longer than maximum of #{$term_width - 1}" if line.length > $term_width - 1
      end
    end
  end

  curr_frame_was = -1
  curr_frame = 0
  loop do
    can_back = ( curr_frame > 0 )
    can_for = ( curr_frame < frames.length - 1 )
    if curr_frame != curr_frame_was
      system('clear')
      print "\e[#{lines_offset}H"
      print "\e[0m"
      print frames[curr_frame][0]
      print "\e[0m\e[32m\n"
      frames[curr_frame][1 .. -2].each do |line|
        puts line.gsub(/(\S+): /, "\e[92m\\1\e[32m: ")
      end
      print "\e[\e[0m"
      print frames[curr_frame][-1]
      print "\e[0m\e[32m"
    end
    curr_frame_was = curr_frame
    key = $ctl_kb_queue.deq
    if key.ord == 127
      curr_frame -= 1 if can_back
    else
      if can_for
        curr_frame += 1
      else
        return
      end
    end
  end
end


def clear_warbles standby = false
  $warbles = {short: {times: Array.new,
                      val: 0.0,
                      max: 0.0,
                      window: 1},
              long: {times: Array.new,
                     val: 0.0,
                     max: 0.0,
                     window: 3},
              scale: 10,
              standby: standby}
  $warbles_holes = Array.new(2)
end


def add_and_del_warbles tntf, add_warble

  [:short, :long].each do |type|

    $warbles[type][:times] << tntf if add_warble

    # remove warbles, that are older than window
    del_warble = ( $warbles[type][:times].length > 0 &&
                   tntf - $warbles[type][:times][0] > $warbles[type][:window] )
    $warbles[type][:times].shift if del_warble
    
    if ( add_warble || del_warble )
      $warbles[type][:val] = if $warbles[type][:times].length > 0
                               $warbles[type][:times].length / $warbles[type][:window].to_f
                             else
                               0
                             end
      $warbles[type][:max] = [ $warbles[type][:val],
                               $warbles[type][:max] ].max
      # maybe adjust scale
      $warbles[:scale] += 5 while $warbles[:scale] < $warbles[type][:max]
    end
  end
end


# Hint or message buffer for main loop in handle holes. Makes sure, that all
# messages are shown long enough
class MsgBuf
  @@lines_durations = Array.new
  @@printed_at = nil
  @@ready = false
  @@printed = Array.new

  def print text, min, max, group = nil, later: false
    # remove any outdated stuff
    if group
      # of each group there should only be one elemnt in messages;
      # older ones are removed. group is only useful, if min > 0
      idx = @@lines_durations.each_with_index.find {|x| x[0][3] == group}&.at(1)
      @@lines_durations.delete_at(idx) if idx
    end

    # use min duration for check
    @@lines_durations.pop if @@lines_durations.length > 0 && @@printed_at && @@printed_at + @@lines_durations[-1][1] < Time.now.to_f
    @@lines_durations << [text, min, max, group] if @@lines_durations.length == 0 || @@lines_durations[-1][0] != text
    # later should be used for batches of messages, where print is
    # invoked multiple times in a row; the last one should be called
    # without setting later
    if @@ready && text && !later
      Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{text}\e[0m\e[K"
      @@printed.push([text, min, max, group]) if $testing
    end
    @@printed_at = Time.now.to_f
  end

  # return true, if there is message content left, i.e. if
  # message-line should not be used e.g. for hints
  def update tntf = nil, refresh: false

    tntf ||= Time.now.to_f

    # we keep elements in @@lines_durations until they are expired
    return false if @@lines_durations.length == 0

    # use max duration for check
    if @@printed_at && @@printed_at + @@lines_durations[-1][2] < Time.now.to_f
      # current message is old
      @@lines_durations.pop
      if @@lines_durations.length > 0
        # display new topmost message
        if @@ready && @@lines_durations[-1][0]
          Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{@@lines_durations[-1][0]}\e[0m\e[K"
          @@printed.push(@@lines_durations[-1]) if $testing
        end
        @@printed_at = Time.now.to_f
        return true
      else
        # no current message
        @@printed_at = nil
        # just became empty, return true one more time
        return true
      end
    else
      # current message is still valid
      if @@ready && @@lines_durations[-1][0] && refresh
        Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{@@lines_durations[-1][0]}\e[0m\e[K"
        @@printed.push(@@lines_durations[-1]) if $testing
        @@printed_at = Time.now.to_f
      end
      return true
    end
  end

  def ready
    @@ready = true
  end

  def clear
    @@lines_durations = Array.new
    @@printed_at = nil
    Kernel::print "\e[#{$lines[:hint_or_message]}H\e[K" if @@ready
  end

  def printed
    @@printed
  end

  def empty?
    return @@lines_durations.length > 0
  end

  def get_lines_durations
    @@lines_durations
  end

  def borrowed secs
    # correct for secs where lines have been borrowed something else
    # (e.g. playing the licka)
    @@printed_at += @@printed_at if @@printed_at
  end
end
