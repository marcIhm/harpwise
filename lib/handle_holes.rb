#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_mission, lambda_good_done_was_good, lambda_skip, lambda_comment, lambda_hint, lambda_star_lick
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_since = nil
  hole_held_min = 0.1

  # Remark: $hole_was_for_disp needs to be persistant over invocations
  # and cannot be set here

  # hole_held (the hole beeing held) is the current hole if played
  # sufficiently long; empty otherwise. hole_held_was and
  # hole_held_was_regular are previous values of hold_held, the latter
  # is guaranteed to be a regular hole
  hole_held = hole_held_was = hole_held_was_regular = hole_held_since = nil
  was_good = was_was_good = was_good_since = nil
  hints_refreshed_at = Time.now.to_f - 1000.0
  hints = hints_old = nil
  warbles_on_second_hole_was = false
  warbles_announced = false
  first_round = true
  $perfctr[:handle_holes_calls] += 1
  $perfctr[:handle_holes_this_loops] = 0
  $perfctr[:handle_holes_this_first_freq] = nil
  $perfctr[:handle_holes_this_started] = hole_start
  $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
  $ctl_response_default = 'SPACE to pause; h for help'
  loop do   # over each new frequency from pipeline, until var done or skip

    $perfctr[:handle_holes_loops] += 1
    $perfctr[:handle_holes_this_loops] += 1
    tntf = Time.now.to_f
    
    system('clear') if $ctl_mic[:redraw] && $ctl_mic[:redraw].include?(:clear)
    if first_round || $ctl_mic[:redraw]
      print_mission(get_mission_override || lambda_mission.call)
      ctl_response
      print "\e[#{$lines[:key]}H" + text_for_key
      print_chart($hole_was_for_disp) if [:chart_notes, :chart_scales, :chart_intervals].include?($opts[:display]) && ( first_round || $ctl_mic[:redraw] )
      print "\e[#{$lines[:interval]}H\e[2mInterval:   --  to   --  is   --  \e[K"
      if $ctl_mic[:redraw] && !$ctl_mic[:redraw].include?(:silent)
        print_hom("Terminal [width, height] = [#{$term_width}, #{$term_height}] is #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;101mON THE EDGE\e[0;2m of"  :  'above'} minimum [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]")
      end
      print "\e[#{$lines[:hint_or_message]}H\e[2m#{$pending_message_after_redraw}\e[0m\e[K" if $pending_message_after_redraw
      $pending_message_after_redraw = nil
      $ctl_mic[:redraw] = false
      $ctl_mic[:update_comment] = true
    end
    if $first_round_ever_get_hole
      print "\e[#{$lines[:hint_or_message]}H"
      animate_splash_line(single_line = true) if $mode == :listen
      print "\e[2mWaiting for frequency pipeline ..."
    end

    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq
    $total_freqs += 1
    $perfctr[:handle_holes_this_first_freq] ||= Time.now.to_f

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_mic
    
    behind = $freqs_queue.length * $opts[:time_slice]
    if behind > 0.5
      now = tntf
      if now - $mode_start > 10
        $lagging_freqs_lost += $freqs_queue.length 
        $freqs_queue.clear
        if now - $lagging_freqs_message_ts > 120 
          print_hom "Lagging #{'%.1f' % behind}s; more info on termination (e.g. ctrl-c)."
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
    hole, lbor, cntr, ubor = describe_freq(freq)
    sleep 2 if $testing_what == :lag

    # detect and update warbling before we overwrite hole_was_for_since
    if $opts[:comment] == :warbles
      if regular_hole?(hole_held) && ( !$warbles_holes[0] || !$warbles_holes[1] )
        $warbles_holes[0] = hole_held if !$warbles_holes[0] && hole_held != $warbles_holes[1]
        $warbles_holes[1] = hole_held if !$warbles_holes[1] && hole_held != $warbles_holes[0]
        if !warbles_announced && $warbles_holes[0] && $warbles_holes[1]
          print_hom "Warbling between holes #{$warbles_holes[0]} and #{$warbles_holes[1]}"
          warbles_announced = true
        end
      end
      if hole == $warbles_holes[1]
        warbles_on_second_hole_was = true
      else
        add_warble = ( hole == $warbles_holes[0] && warbles_on_second_hole_was)
        add_and_del_warbles(tntf, add_warble)
        warbles_on_second_hole_was = false if add_warble
      end
    end

    # give hole in chart the right color: compute hole_since
    if !hole_since || hole != hole_was_for_since
      hole_since = tntf
      hole_was_for_since = hole
    end

    # distinguish deliberate playing from noise: compute hole_held
    if regular_hole?(hole)
      hole_held_was = hole_held
      hole_held_was_regular = hole_held_was if regular_hole?(hole_held_was)
      if tntf - hole_since < hole_held_min
        # we will erase hole_held below, so now its the time to record duation
        $journal << ('(%.1f)' % (tntf - hole_held_since)) if $journal_all && hole_held && journal_length > 0 && !musical_event?($journal[-1])
        # too short, the current hole can not count as beeing held
        hole_held = nil
      else
        hole_held = hole
        # adding  hole_held_min / 2 heuristacally to get audibly more plausible durations 
        hole_held_since = hole_since + hole_held_min / 2
        if $journal_all && hole_held != hole_held_was && regular_hole?(hole_held)
          $journal << hole_held
          print_hom "#{journal_length} holes" if $opts[:comment] == :journal
        end
      end
    else
      $journal << ('(%.1fs)' % (tntf - hole_held_since)) if $journal_all && hole_held && journal_length > 0 && !musical_event?($journal[-1]) && $journal_all
      hole_held = nil
    end

    was_was_good = was_good
    good,
    done,
    was_good = if $opts[:screenshot]
                 [true, $ctl_can[:next] && tntf - hole_start > 2, false]
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
    if regular_hole?(hole)
      dots, in_range = get_dots(just_dots_short.dup, 2, freq, lbor, cntr, ubor) {|in_range, marker| in_range ? "\e[0m#{marker}\e[2m" : marker}
      cents = cents_diff(freq, cntr).to_i
      print format % [freq.round(1), cents, dots]
    else
      print format % ['--', '--', just_dots_short]
    end

    #
    # Handle intervals
    #
    hfi = $hole_ref || hole_held_was_regular
    hole_for_inter = regular_hole?(hfi)  ?  hfi  :  nil
    inter_semi, inter_text, _, _ = describe_inter(hole_held, hole_for_inter)
    if inter_semi
      print "\e[#{$lines[:interval]}HInterval: #{hole_for_inter.rjust(4)}  to #{hole_held.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    elsif hole_for_inter
      print "\e[#{$lines[:interval]}HInterval: #{hole_for_inter.rjust(4)}  to   --  is   --  \e[K"
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
    when :chart_notes, :chart_scales, :chart_intervals
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
           (regular_hole?(hole)  ?  [hole, $harp[hole][:note]]  :  ['-- ', '-- '])
    text += ", Ref: %#{longest_hole_name.length}s" % [$hole_ref || '-- ']
    text += ",  Rem: #{$hole2rem[hole] || '--'}" if $hole2rem
    print "\e[#{$lines[:hole]}H\e[2m" + truncate_text(text) + "\e[K"

    
    if lambda_comment
      $perfctr[:lambda_comment_call] += 1
      case $opts[:comment]
      when :holes_scales, :holes_intervals, :holes_all, :holes_notes
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

    
    if lambda_hint && tntf - hints_refreshed_at > 0.5
      if $message_shown_at
        # A specific message has been shown, that overrides usual hint

        # Make sure to refresh hint, once the current message has elapsed
        hints_old = nil
      else
        $perfctr[:lambda_hint_call] += 1
        hints = lambda_hint.call(hole)
        hints_refreshed_at = tntf
        if hints && hints != hints_old
          $perfctr[:lambda_hint_reprint] += 1
          print "\e[#{$lines[:message2]}H\e[K" if $lines[:message2] > 0
          print "\e[#{$lines[:hint_or_message]}H\e[0m\e[2m"
          # Using truncate_colored_text might be too slow here
          if hints.length == 1
            # for mode quiz
            print truncate_text(hints[0]) + "\e[K"
          elsif hints.length == 4 && $lines[:message2] > 0
            # for mode licks
            
            # hints:
            #  0 = name of lick,
            #  1 = tags,
            #  2 = hint (if any)
            #  3 = description of lick
            if hints[3] == ''
              # no description, put name of lick and tags on own line
              print truncate_text(hints[2]) + "\e[K"
              message2 = [hints[0], hints[1]].select {|x| x && x.length > 0}.join(' | ')
              print "\e[#{$lines[:message2]}H\e[0m\e[2m#{message2}"
            else
              # hints[0 .. 2] are on first line, hints[3] on the second
              # if necessary, we truncate or omit hints[1] (tags)
              maxl_h1 = $term_width - 10 - hints[0].length - hints[2].length
              hint_or_message = 
                if maxl_h1 >= 12
                  # enough space to show at least something
                  [hints[0],
                   if maxl_h1 > hints[1].length
                     hints[1]
                   else
                     hints[1][0,maxl_h1 - 3] + '...'
                   end,
                   hints[2]]
                else
                  # we omit hints[1] altogether
                  [hints[0], '...', hints[2]]
                end.select {|x| x && x.length > 0}.join(' | ') + "\e[K"
              print hint_or_message
              print "\e[#{$lines[:message2]}H\e[0m\e[2m"
              print truncate_text(hints[3]) + "\e[K"
            end
          else
            fail "Internal error"
          end
          print "\e[0m\e[2m"
        end
        hints_old = hints
      end
    end      
    
    if $ctl_mic[:set_ref]
      $hole_ref = regular_hole?(hole_held) ? hole_held : nil
      print_hom "#{$hole_ref ? 'Stored' : 'Cleared'} reference hole"
      if $hole_ref 
        $charts[:chart_intervals] = get_chart_with_intervals
        if $opts[:display] == :chart_intervals
          clear_area_display
          print_chart
        end
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
        choices = [ $display_choices, $display_choices ].flatten
        $opts[:display] = choices[choices.index($opts[:display]) + 1]
      end
      $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($opts[:display])
      print_hom "Display is #{$opts[:display].upcase}: #{$display_choices_desc[$opts[:display]]}"
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
        choices = [ $comment_choices[$mode], $comment_choices[$mode] ].flatten
        $opts[:comment] = choices[choices.index($opts[:comment]) + 1]
      end
      clear_area_comment
      print_hom "Comment is #{$opts[:comment].upcase}: #{$comment_choices_desc[$opts[:comment]]}"
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

    if $ctl_can[:loop] && $ctl_mic[:start_loop]
      $ctl_mic[:loop] = true
      $ctl_mic[:start_loop] = false
      print_mission(get_mission_override || lambda_mission.call)
    end
    
    if $ctl_mic[:toggle_progress]
      $opts[:no_progress] = !$opts[:no_progress]
      $ctl_mic[:toggle_progress] = false
      print_mission(get_mission_override || lambda_mission.call)
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

    if [:change_lick, :edit_lick_file, :change_tags, :reverse_holes, :switch_modes, :switch_modes, :journal_current, :journal_delete, :journal_menu, :journal_write, :journal_play, :journal_clear, :journal_edit, :journal_all_toggle, :warbles_clear].any? {|k| $ctl_mic[k]}
      # we need to return, regardless of lambda_good_done_was_good;
      # special case for mode listen, which handles the returned value
      return {hole_disp: hole_disp}
    end

    if $ctl_mic[:quit]
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[0mTerminating on user request (quit) ...\n\n"
      exit 0
    end

    if done || ( $message_shown_at && tntf - $message_shown_at > 8 )
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      $message_shown_at = false
    end
    first_round = $first_round_ever_get_hole = false
  end  # loop until var done or skip
end


def text_for_key
  text = "\e[0m#{$mode}\e[2m"
  if $mode == :licks
    text += "(#{$licks.length},#{$opts[:iterate][0..2]})"
  end
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


def regular_hole? hole
  hole && hole != :low && hole != :high
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
  begin
    keys = if $key[-1] == 's'
             $notes_with_sharps
           elsif $key[-1] == 'f'
             $notes_with_sharps
           elsif $conf[:pref_sig_def] == :flats
             $notes_with_flats
           else
             $notes_with_sharps
           end
    input = choose_interactive("Available keys (current is #{$key}): ", keys) do |key|
      if key == $key
        "The current key"
      else
        "#{describe_inter_keys(key, $key)} the current key #{$key}"
      end
    end || $key
    error = nil
    begin
      $on_error_raise = true
      check_key_and_set_pref_sig(input)
    rescue ArgumentError => error
      report_condition_wait_key error
    else
      $key = input
    ensure
      $on_error_raise = false
    end
  end while error
  $message_shown_at = Time.now.to_f
  pending_message "Changed key of harp to \e[0m#{$key}"
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
  pending_message(if key_was == $key
                  "Key of harp is still at"
                 else
                   "Changed key of harp to"
                  end + " \e[0m#{$key}")
end


def do_change_scale_add_scales
  input = choose_interactive("Choose main scale (current is #{$scale}): ", $all_scales.sort) do |scale|
    $scale_desc_maybe[scale] || '?'
  end
  $scale = input if input
  unless input
    pending_message "Did not change scale of harp."
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

  pending_message "Changed scale of harp to \e[0m\e[32m#{$scale}"
end


def do_rotate_scale_add_scales
  $used_scales.rotate!
  $scale = $used_scales[0]
  $opts[:add_scales] = $used_scales.length > 1  ?  $used_scales[1..-1].join(',')  :  nil
  pending_message "Changed scale of harp to \e[0m\e[32m#{$scale}"
end


def get_mission_override
  $opts[:no_progress]  ?  "\e[0m\e[2mNot tracking progress."  :  nil
end


def show_help
  lines_offset = ( $term_height - $conf[:term_min_height] ) / 2 + 4
  max_lines_per_frame = $conf[:term_min_height] - lines_offset - 2

  frames = Array.new
  frames << [" Help on keys (invoke 'harpwise' without args for more info):",
             " \e[0m\e[2mVersion #{$version}\e[0m\e[32m",
             "",
             "  SPACE: pause and continue      ctrl-l: redraw screen",
             "    d,D: change display (upper part of screen)",
             "    c,C: change comment (in lower part of screen)",
             "      r: set reference to hole played (not freq played)",
             "      k: change key of harp",
             "      K: play adjustable pitch and take it as new key",
             "      s: set scales                   S: rotate scales"]
  if $ctl_can[:next]
    frames[-1] <<  "      j: journal-menu; only available in mode listen"
  else
    frames[-1] <<  "      j: journal-menu to handle holes collected"
  end
    
  if $ctl_can[:switch_modes]
    frames[-1] << "      m: switch between modes #{$modes_for_switch.map(&:to_s).join(',')}"
  end
  frames[-1].append(*["      q: quit harpwise                h: this help",
                      ""])
  
  if $ctl_can[:next]
    frames << [" More help on keys (special for modes licks and quiz):",
               "",
               " RETURN: next sequence or lick     BACKSPACE: previous sequence",
               "      .: replay current                    ,: replay, holes only",
               "    :;p: replay but ignore '--partial', i.e. play all",
               "      i: toggle '--immediate'              L: loop current sequence",
               "    0,-: forget holes played               +: skip rest of sequence",
               "      #: toggle tracking progress in seq   R: play holes reversed"]
    if $ctl_can[:lick]
      frames[-1].append(*["      l: change current lick               e: edit lickfile",
                          "      t: change option --tags_any (aka -t)",
                          "      <: shift lick down by one octave     >: shift lick up",
                          "    @,P: change option --partial",
                          "     */: Add or remove Star from current lick persistently;",
                          "         select them later by tag 'starred'",
                          ""])
    else
      frames[-1] << ""
    end
    frames[-1].append(*["",
                        " Note, that other keys (and help) apply when harpwise plays itself."])
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
      frames[curr_frame][1 .. -2].each {|line| puts line}
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
                     window: 4},
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
