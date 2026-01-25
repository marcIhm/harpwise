#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_mission, lambda_good_done_was_good, lambda_skip,
                 lambda_comment, lambda_hint, lambda_star_lick

  #
  # Please bear in mind, that we may enter this function multiple times during one run of
  # harpwise. E.g. for mode listen we leave this function on certain keys pressed
  # (i.e. those, that can only be handled by the caller, e.g. 'L') and enter it again
  # soon after.
  #

  # Not taking account the above has caused debugging-trouble in at least two cases:
  # - $hole_was_for_disp needs to be persistant over invocations and cannot be set here
  # - first_round as a local variable was replaced for the better fit
  #   $first_round_ever_get_hole

  
  # One-time initialize
  if $first_round_ever_get_hole
    $move_down_on_exit = true
    $msgbuf.ready
    if $hole_ref
      $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
      $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
    end
    $ctl_mic[:redraw] = Set[:silent]    
  end

  longest_hole_name = $harp_holes.max_by(&:length)
  # We cache time for (assumed) performance
  tntf = Time.now.to_f

  hole = nil
  hole_since = tntf
  hole_since_ticks = $total_freq_ticks
  for_testing_touched = false
  warbles_announced = false

  #
  # Use ticks (e.g. cycles in handle_holes), because this is
  # potentially more precise than time-spans.  If this is set shorter,
  # the journal will pick up spurious notes
  #
  hole_held_min_ticks = 2
  hole_held_min_ticks_nil = 2
  hole_held = hole_journal = hole_journal_since = nil

  was_good = was_was_good = was_good_since = nil
  hints_refreshed_at = tntf - 1000.0
  hints = hints_old = nil

  # remember for each cycle of warbling, if we have seen first fole
  last_warbles_hole = nil

  $perfctr[:handle_holes_calls] += 1
  $perfctr[:handle_holes_this_loops] = 0
  $perfctr[:handle_holes_this_first_mic] = nil

  $msgbuf.update(tntf, refresh: true)
  $ulrec.print_rec_sign_mb if $ulrec.active?
    
  loop do   # over each new frequency from pipeline, until done or skip

    $perfctr[:handle_holes_this_loops] += 1
    tntf = Time.now.to_f

    if $ctl_mic[:redraw] && $ctl_mic[:redraw].include?(:clear)
      system('clear')
    end
    
    if $ctl_mic[:redraw] || $ctl_mic[:redraw_mission] ||
       # next update of jamming timer due ?
       ( $jamming_timer_update_next && tntf > $jamming_timer_update_next )
      if movr = get_mission_override
        print_mission(*movr)
      else
        print_mission(lambda_mission.call)
      end
      $ctl_mic[:redraw_mission] = false
    end

    if $ctl_mic[:redraw]
      $perfctr[:handle_holes_redraw] += 1
      if $first_round_ever_get_hole
        ctl_response(redraw: true)
      else
        ctl_response('Redraw', hl: :low, redraw: true) unless $ctl_mic[:redraw].include?(:silent)
      end
      print "\e[#{$lines[:key]}H" + text_for_key
      print_chart($hole_was_for_disp) if [:chart_notes, :chart_scales, :chart_scales_simple, :chart_intervals, :chart_inter_semis].include?($opts[:display])
      print "\e[#{$lines[:interval]}H\e[2mInterval:   --  to   --  is   --  \e[K"
      if $ctl_mic[:redraw] && !$ctl_mic[:redraw].include?(:silent)
        proximity = if $term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]
                      "\e[0;101mON THE EDGE\e[0;2m of"
                    elsif  $term_width == $conf[:term_min_width] + 1 || $term_height == $conf[:term_min_height] + 1
                      "\e[0;101mnear the edge\e[0;2m of"
                    else
                      'above'
                    end
        $msgbuf.print "Terminal [width,height] = [#{$term_width},#{$term_height}] is #{proximity} minimum [#{$conf[:term_min_width]},#{$conf[:term_min_height]}]", 2, 5, :term
      end
      # updates messages and returns true, if hint is allowed
      hints_old = nil if $msgbuf.update(tntf, refresh: true)
      $freqs_queue.clear
      $ctl_mic[:redraw] = false
      $ctl_mic[:update_comment] = true
    end

    if $first_round_ever_get_hole
      print "\e[#{$lines[:hint_or_message]}H"
      if $mode == :listen
        animate_splash_line(single_line = true)
        # does not print anythin, but lets splash be seen
        $msgbuf.print nil, 0, 4
      end
    end

    #
    # Here we get our most important input; which is acoustic
    #
    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq
    if $testing && !for_testing_touched
      FileUtils.touch("#{$dirs[:exch_tester_tested]}/harpwise_pipeline_started")
      for_testing_touched = true
    end

    $total_freq_ticks += 1
    $perfctr[:handle_holes_this_first_mic] ||= Time.now.to_f

    return if lambda_skip && lambda_skip.call()

    #
    # Here we get our keyboard input
    #
    pipeline_catch_up if handle_kb_mic
    
    behind = $freqs_queue.length * $time_slice_secs
    if behind > 0.5
      now = tntf
      if now - $mode_start > 4
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
    ctl_response tntf: tntf

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
        # defining warble holes
        $warbles_holes[0] ||= hole_held if hole_held != $warbles_holes[1]
        $warbles_holes[1] ||= hole_held if hole_held != $warbles_holes[0]
        if !warbles_announced && $warbles_holes[0] && $warbles_holes[1]
          $msgbuf.print "Warbling between holes #{$warbles_holes[0]} and #{$warbles_holes[1]}", 5, 5, :warble
          warbles_announced = true
        end
      end
      add_warble = false
      # add new entry to $warble every time we reach hole two; see clear_warbles for its
      # structure
      if hole == $warbles_holes[0]
        last_warbles_hole = 0
      elsif hole == $warbles_holes[1]
        add_warble = ( last_warbles_hole == 0 )
        last_warbles_hole = 1
      end
      warbles_add_del(tntf, add_warble)
    end

    # distinguish deliberate playing from noise: compute hole_held
    # remember old value to allow detecting change below
    held_min_ticks = ( hole ? hole_held_min_ticks : hole_held_min_ticks_nil )
    hole_held_was = hole_held
    if $total_freq_ticks - hole_since_ticks >= held_min_ticks
      hole_held = hole 
      $first_hole_held ||= tntf if hole_held
    end

    #
    # This generates journal entries for holes that have been held
    # long enough; see mode_listen.rb for handling the explicit
    # request of a journal-entry by pressing RETURN.
    #
    if $journal_all && hole_held_was != hole_held
      # we get here, if: hole has just startet or hole has just
      # stopped or hole has just changed
      if hole_journal &&
         journal_length > 0 &&
         hole_journal != hole_held
        # hole_held has just changed, but this is not yet reflected in
        # journal; so maybe add the duration to journal, just before
        # the next hole is added
        if tntf - hole_journal_since > $journal_minimum_duration
          # put in duration for last note, if held long enough
          if !musical_event?($journal[-1])
            $journal << ('(%.1fs)' % (tntf - hole_journal_since))
            $msgbuf.print("#{journal_length} holes", 2, 5, :journal) if $opts[:comment] == :journal
          end
        else
          # too short, so do not add duration and rather remove hole
          $journal.pop if $journal[-1] && !musical_event?($journal[-1])
        end
      end
      if hole_held
        # add new hole
        hole_journal = hole_held
        $journal << hole_held
        hole_journal_since = tntf if hole_journal
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

    # Get opinion of caller on current hole
    good,
    done,
    was_good = if $opts[:screenshot]
                 [true, [:quiz, :licks].include?($mode) && tntf - hole_since > 2, false]
               else
                 $perfctr[:lambda_good_done_was_good_call] += 1
                 lambda_good_done_was_good.call(hole, hole_since)
               end

    if $ctl_mic[:hole_given]
      good = done = true
      $ctl_mic[:hole_given] = false
      $msgbuf.print "One hole for free, just as if you would have played it", 1, 4, :hole_given
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
    inter_semi, inter_text, _, _ = describe_inter($hole_held_inter, hole_for_inter, sane: true)
    if inter_semi
      print "\e[#{$lines[:interval]}HInterval: #{$hole_held_inter.rjust(4)}  to #{hole_for_inter.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[0m\e[%dm" %
                 get_hole_color_active(hole, good, was_good, was_good_since)
    hole_ref_color = "\e[#{hole == $hole_ref ?  92  :  91}m"
    case $opts[:display]
    when :chart_notes, :chart_scales, :chart_scales_simple, :chart_intervals, :chart_inter_semis
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
      when :journal, :warbles
        fit_into_comment lambda_comment.call('', nil, nil, nil, nil, nil)
      when :lick_holes, :lick_holes_large
        fit_into_comment lambda_comment.call('', nil, nil, nil, nil, nil)[1]
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
      clear_warbles(true)
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
      else
        $opts[:display] = rotate_among($opts[:display], :up, $display_choices)
      end
      if $hole_ref
        $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
        $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
      end
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_scales_simple, :chart_intervals, :chart_inter_semis].include?($opts[:display])
      print "\e[#{$lines[:key]}H" + text_for_key
      $msgbuf.print "Display is #{$opts[:display].upcase}: #{$display_choices_desc[$opts[:display]]}", 2, 5, :display
      $freqs_queue.clear
      $ctl_mic[:change_display] = false
    end

    if $ctl_mic[:change_comment]
      clear_warbles(true)
      if $ctl_mic[:change_comment] == :choose
        choices = $comment_choices[$mode].map(&:to_s)
        choices.rotate! while choices[0].to_sym != $opts[:comment]
        $opts[:comment] = (choose_interactive("Available comment choices (current is #{$opts[:comment].upcase}): ", choices) do |choice|
                             $comment_choices_desc[choice.to_sym]
                           end || $opts[:comment]).to_sym
      else
        $opts[:comment] = rotate_among($opts[:comment], :up, $comment_choices[$mode])
      end
      clear_area_comment
      $msgbuf.print "Comment is #{$opts[:comment].upcase}: #{$comment_choices_desc[$opts[:comment]]}", 2, 5, :comment
      $freqs_queue.clear
      $ctl_mic[:change_comment] = false
      $ctl_mic[:update_comment] = true
    end

    if $ctl_mic[:remote_message]
      show_remote_message
      $ctl_mic[:remote_message] = false
    end
    
    if $ctl_mic[:jamming_ps_rs]
      if $opts[:jamming]
        # mabye user has restarted 'harpwise jamming'; so check state again
        mostly_avoid_double_invocations
        if $runningp_jamming
          File.write($remote_jamming_ps_rs, Time.now)
          $remote_jamming_ps_rs_cnt += 1
          $msgbuf.print("Sent request ##{$remote_jamming_ps_rs_cnt} for pause/resume to remote jamming instance", 2, 5, :jamming)
        else
          $msgbuf.print("There seems to be no jamming instance; cannot pause/resume it", 2, 5, :jamming)
        end
      else
        $msgbuf.print("This instance does not take part in jamming, cannot pause/resume it", 2, 5, :jamming)
      end
      $ctl_mic[:jamming_ps_rs] = false
    end
        
    if $ctl_mic[:show_help]
      if $perfctr[:handle_holes_this_first_mic]
        $perfctr[:handle_holes_this_loops_per_second] = $perfctr[:handle_holes_this_loops] / ( Time.now.to_f - $perfctr[:handle_holes_this_first_mic] )
      end
      show_help
      $perfctr[:handle_holes_this_first_mic] = nil
      $perfctr[:handle_holes_this_loops] = 0
      ctl_response 'continue', hl: true
      $ctl_mic[:show_help] = false
      $ctl_mic[:redraw] = Set[:clear, :silent]
      $freqs_queue.clear
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
        stop_kb_handler
        print_player($players.structured[$players.stream_current])
        start_kb_handler
        prepare_term
        if $opts[:viewer] != 'window' || !$players.structured[$players.stream_current]['image'][0]
          puts "\n\e[0m\e[2m  Press any key to go back to mode '#{$mode}' ...\e[0m"
          $ctl_kb_queue.clear
          $ctl_kb_queue.deq
        end
        $ctl_mic[:redraw] = Set[:clear, :silent]
        $freqs_queue.clear
      else
        $msgbuf.print("Featuring players has not yet started, please stand by ...", 2, 5, :replay)
      end
    end

    if $ctl_mic[:star_lick] && lambda_star_lick
      lambda_star_lick.call($ctl_mic[:star_lick])
      $ctl_mic[:star_lick] = false
    end
    
    if $ctl_mic[:change_key]
      do_change_key
      $ctl_mic[:change_key] = false
      $ctl_mic[:redraw] = Set[:silent]
      set_global_vars_late
      set_global_musical_vars
      $freqs_queue.clear
      # need a new question
      $ctl_mic[:next] = true if $mode == :quiz
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
      do_rotate_scale_add_scales($ctl_mic[:rotate_scale])
      $ctl_mic[:rotate_scale] = false
      $ctl_mic[:redraw] = Set[:silent]
      ts_started_rotate_scale = Time.now
      set_global_vars_late
      set_global_musical_vars rotated: true, shortcut_licks: true
      $freqs_queue.clear
    end

    if $ctl_mic[:rotate_scale_reset]
      do_rotate_scale_add_scales_reset
      $ctl_mic[:rotate_scale_reset] = false
      $ctl_mic[:redraw] = Set[:silent]
      set_global_vars_late
      set_global_musical_vars rotated: true
      $freqs_queue.clear
    end

    if $ctl_mic[:options_info]
      do_show_options_info
      $ctl_mic[:options_info] = false
      $ctl_mic[:redraw] = Set[:silent]
      $freqs_queue.clear
    end

    if [:change_lick, :edit_lick_file, :change_tags, :reverse_holes, :replay_menu, :shuffle_holes, :lick_info, :switch_modes, :switch_modes, :journal_current, :journal_delete, :journal_menu, :journal_write, :journal_play, :journal_clear, :journal_edit, :journal_all_toggle, :jamming_ps_rs, :warbles_prepare, :warbles_clear, :toggle_record_user, :change_num_quiz_replay, :quiz_hint, :comment_lick_play, :comment_lick_next, :comment_lick_prev, :comment_lick_first].any? {|k| $ctl_mic[k]}
      # we need to return, regardless of lambda_good_done_was_good;
      # special case for mode listen, which handles the returned value
      return {hole_disp: hole_disp}
    end

    if $ctl_mic[:quit]
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[0m#{$resources[:term_on_quit]}\n\n"
      exit 0
    end

    $msgbuf.clear if done
    $first_round_ever_get_hole = false
  end  # loop until var done or skip
end


def text_for_key
  text = "\e[0m#{$mode}\e[2m"
  if $mode == :licks
    text += "(#{$licks.length},#{$opts[:iterate][0..2]})"
  end
  text += " \e[0m#{$quiz_flavour}\e[2m" if $quiz_flavour
  text += " #{$type} \e[0m#{$key}"
  if $used_scales.length > 1
    text += "\e[0m"
    text += " \e[32m#{$scale}"
    text += "\e[0m\e[2m," + $used_scales[1..-1].map {|s| "\e[0m\e[34m#{$scale2short[s] || s}\e[0m\e[2m"}.join(',')
    text += " (#{$scale_prog_count+1}/#{$scale_prog.length})" if $opts[:jamming]
    if $opts[:display] == :chart_scales_simple
      text += "; @ is " + $scale2short[$conf[:scale] || $scale]
    end
  else
    text += "\e[32m #{$scale}\e[0m\e[2m"
  end
  if $comment_licks && $comment_licks.length > 0
    text += "; \e[0m\e[32m#{$comment_licks[0][:name]}\e[0m\e[32m"
    text += " \e[0m\e[2m(#{$comment_licks_count+1}/#{$comment_licks.length})\e[0m\e[32m" if $opts[:jamming]
  end
  text += '; journal-all ' if $journal_all
  truncate_colored_text(text, $term_width - 16 ) + '           '
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
            print "\e[#{$lines[:comment_tall]}H\e[K" if $lines[:comment_tall] != $lines[:comment]
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
  $key = choose_interactive("Available keys (current is #{$key}): ", keys + ['random-common', 'random-all']) do |key|
    if key == $key
      "The current key"
    elsif key == 'random-common'
      "At random: One of #{$common_harp_keys.length} common harp keys"
    elsif key == 'random-all'
      "At random: One of all #{$all_harp_keys.length} harp keys"
    else
      "#{describe_inter_keys(key, $key)} to the current key #{$key}"
    end
  end || $key
  if $key == 'random-common'
    $key = ( $common_harp_keys - [$key] ).sample
  elsif $key == 'random-all'
    $key = ( $all_harp_keys - [$key] ).sample
  end
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
  puts "\e[0m\e[2mPress any key to start (and RETURN when done), or 'q' to cancel ...\e[K\e[0m\n\n"
  $ctl_kb_queue.clear
  char = $ctl_kb_queue.deq
  return if char == 'q' || char == 'x'
  $key = play_interactive_pitch(embedded: true) || $key
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

  # will otherwise collide with chosen scales
  if Set[*$scale_prog] != Set[*(add_scales + [$scale])]
    $opts[:scale_prog] = nil 
    $scale_prog = $used_scales
  end

  $msgbuf.print "Changed scale of harp to \e[0m\e[32m#{$scale}", 2, 3, :scale
end


def do_show_options_info
  clear_area_comment
  clear_area_message
  puts "\e[#{$lines[:comment] + 1}H\e[0m Command line for this instance of harpwise:"
  puts "\e[32m"
  short_command_line = 'harpwise' + $full_command_line[$0.length .. -1]
  puts wrap_words('   ', short_command_line.split(/(?= --)/).map(&:strip), ' ')
  puts
  print "\e[0m\e[2m Any key for details ...\e[0m"
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq

  clear_area_comment
  clear_area_message
  puts "\e[#{$lines[:comment] + 1}H\e[0m       Used scales:  \e[32m#{$used_scales.join(', ')}\e[0m"
  if $opts[:scale_prog]
    puts "\e[0m Scale progression:  \e[32m#{$opts[:scale_prog]}\e[0m"
    puts "\e[0m       its content:  \e[32m#{$scale_prog.join(', ')}\e[0m"
  else
    puts "\e[2m Scale progression:  none"
  end
  if $comment_licks && $comment_licks.length > 0
    puts "\e[0m     Comment licks:  \e[32m#{$comment_licks.map {|l| l[:name]}.join(', ')}\e[0m"
  else
    puts "\e[2m     Comment licks:  none"
  end
  puts
  
  print "\e[0m\e[2m #{$resources[:any_key]}\e[0m"
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
end


$sc_prog_init = nil
def do_rotate_scale_add_scales for_bak
  step = ( for_bak == :forward  ?  1  :  -1 )
  scale_was = $scale
  $sc_prog_init ||= $scale_prog.clone
  $scale_prog.rotate!(step)
  $scale_prog_count += step
  $scale_prog_count %= $scale_prog.length
  $used_scales.rotate!(step) while $used_scales[0] != $scale_prog[0]
  $scale = $used_scales[0]
  $opts[:add_scales] = $used_scales.length > 1  ?  $used_scales[1..-1].join(',')  :  nil
  clause = ( $sc_prog_init == $scale_prog  ?  ', new cycle'  :  '' )
  clause += ( $scale == scale_was ? ', repeat in prog' : '' )
  $msgbuf.print "Changed scale of harp to \e[0m\e[32m#{$scale}\e[0m\e[2m#{clause}", 0, 3, :scale
end


def do_rotate_scale_add_scales_reset
  unless $sc_prog_init
    $msgbuf.print("Scales have not been rotated yet", 0, 2) unless $opts[:jamming]
    return
  end
  $scale_prog = $sc_prog_init.clone
  $scale_prog_count = 0
  $used_scales.rotate! while $used_scales[0] != $scale_prog[0]  
  $scale = $used_scales[0]
  $opts[:add_scales] = $used_scales.length > 1  ?  $used_scales[1..-1].join(',')  :  nil
  $msgbuf.print "Reset scale of harp to initial \e[0m\e[32m#{$scale}\e[0m\e[2m", 0, 5, :scale
end


def get_mission_override
  if $jamming_mission_override
    if $jamming_timer_update_next
      jtt = get_jamming_timer_text
      [$jamming_mission_override + jtt[0], jtt[1]]
    else
      [$jamming_mission_override, 0]
    end
  else
    nil
  end 
end


def get_jamming_timer_text

  # This gets called when next timer update is due, but also on redraw-events
  
  tntf = Time.now.to_f
  $debug_log&.puts("\nJM: tntf now #{tntf} = #{Time.at(tntf).strftime('%H:%M:%S')}")
  $perfctr[:get_jamming_timer_text] += 1
  $jamming_timer_debug_info ||= Array.new

  first_delta = nil
  epsilon = 1.0 / 16.0

  # reduce typing
  jts = $jamming_timer_state
  
  if !jts
    # Prepare state of timer

    jts = Hash.new
    # put these in for debugging
    jts[:start] = tntf
    jts[:end] = $jamming_timer_end
    jts[:total_secs] = $jamming_timer_end - tntf

    # Depending on total duration we have one update every eight, quarter, half, full, two,
    # four, ... seconds
    jts[:eights_per_tick] = 2
    
    tick_syms = ['#', '#', '=', '='] + Array.new(20, '-')
    tick_cols = [94, 92, 94, 92] + Array.new(20, 32)
    # See print_mission on how to calculate the number below
    # $conf[:term_min_width] - $ctl_response_width - "Jm: ti 10/12, tm 10/15".length - "  []".length =
    # 75 - 32 - 22 - 4 = 17 = 16 (with margin)
    max_ticks = [16, $term_width - 75 + 16, 24].sort[1]
    while true
      jts[:total_ticks] = (jts[:total_secs] * 8.0 / jts[:eights_per_tick]).to_i
      jts[:tick_sym] = tick_syms.shift
      jts[:tick_col] = tick_cols.shift

      break if jts[:total_ticks] <= max_ticks
      jts[:eights_per_tick] *= 2
    end

    jts[:delta_secs] = jts[:eights_per_tick] / 8.0
    first_delta = jts[:total_secs] - jts[:delta_secs] * jts[:total_ticks]
    if first_delta < jts[:delta_secs] / 3
      # avoid first_delta beeing too short
      first_delta += jts[:delta_secs]
      jts[:total_ticks] -= 1
    end
    jts[:first_delta] = first_delta

    jts[:update_next] = [tntf + first_delta]
    jts[:total_ticks].times { jts[:update_next] << jts[:update_next][-1] + jts[:delta_secs] }
    # schedule final update slightly early to avoid overlap with next timer, that may follow
    # without a gap
    jts[:update_next][-1] -= 0.1
    
    jts[:head] = '['
    jts[:left] = ''
    jts[:right] = ('%.1fs' % jts[:total_secs]).rjust(jts[:total_ticks], '.')
    jts[:tail] = ']'
    $debug_log&.puts("New timer\n#{jts.pretty_inspect}")

  elsif tntf > $jamming_timer_update_next

    # Advance the number of tick-signs.  Do this in elsif-branch, so that text is shown once
    # in its original form, before beeing updated the next time.
    if jts[:right].length > 0
      jts[:left] += jts[:tick_sym]
      jts[:right][0] = ''
    end
    
  end  ## if !jts

  
  if tntf > $jamming_timer_update_next

    if jts[:update_next].length == 0
      $debug_log&.puts( "Last update; clearing space")
      $jamming_timer_update_next = jts = nil
      return ['', 0]
    end

    $jamming_timer_update_next = jts[:update_next].shift

    $debug_log&.puts("Update timer\n  [:left] : #{jts[:left]}\n  [:right] : #{jts[:right]}")
    $debug_log&.puts("Scheduling next timer update for #{$jamming_timer_update_next}")
    
  else
    # Probably a redraw-event
  end

  # write back (e.g. if jts == nil)
  $jamming_timer_state = jts
  
  [" \e[32m" + jts[:head] + "\e[#{jts[:tick_col]}m" + jts[:left] +
   "\e[0m\e[2m" + jts[:right] +
   "\e[0m\e[32m" + jts[:tail],
   # Total number of coloring chars in string above (e.g. \e[32m = 5)
   27]

end


def show_help mode = $mode, testing_only = false
  #
  # Remark: We see the plain-text-version of our help text as its
  # primary form, because it is easier to read and write (in code). A
  # form with more structure is derived in a second step only; to
  # allow this, we have some rules:
  #
  # - key-groups and their description are separated by ':_' which is
  #   replaced by ': ' as late as possible before printing to screen
  #   (likewise '=_' to '=')
  #
  # - Within key-groups, some heuristics are applied for characters
  #   ',' and ':'
  #
  max_lines_per_frame = 20
  fail "Internal error: max_lines_per_frame chosen too large" if max_lines_per_frame + 2 > $conf[:term_min_height]
  lines_offset = (( $term_height - max_lines_per_frame ) * 0.5).to_i

  j_spc = if $opts[:jamming]
            'resume jamming'
          else
            'continue      '
          end
  frames = Array.new
  frames << [" Help - Overview",
             "",
             "",
             "  A harmonica tool for the command line, using microphone and speaker.",
             "",
             "  Full documentation at   https://marcihm.github.io/harpwise",
             "",
             "",
             "  Read on here for help on available keys"]

  frames << [" Help on keys in main view",
             "",
             "",
             "  SPACE:_pause and #{j_spc}      CTRL-L:_redraw screen",
             "    d,D:_change display (upper part of screen)",
             "    c,C:_change comment (lower part of screen)",
             "      k:_change key of harp",
             "      K:_play adjustable pitch and take it as new key",
             "      s:_rotate scales (used scales or --scale-progression)",
             "  ALT-s:_rotate scales backward",
             "      S:_reset rotation of scales to initial state",
             "      $:_set scale, choose from all known"]
  frames << [" More help on keys:",
             "",
             ""]
  if [:quiz, :licks].include?(mode)
    frames[-1].append(*["      j:_journal-menu; write holes (mode listen only)",
                        " CTRL-R:_record and play user (mode licks only)"])
  else
    frames[-1].append(*["      j:_invoke journal-menu to handle your musical ideas;",
                        "      w:_switch comment to warble and prepare",
                        "      p:_print details about player currently drifting by",
                        "      .:_play lick from --lick-prog (shown in comment-area)",
                        "      l:_rotate among those licks     ALT-l:_backward",
                        "      L:_to first lick"])
  end
  frames[-1] << "  ALT-m:_show remote message; used with --jamming"
  
  frames[-1].append(*["    r,R:_set reference to hole played or chosen",
                      "      m:_switch between modes: #{$modes_for_switch.map(&:to_s).join(',')}",
                      "      o:_print command line with options and details",
                      "      q:_quit harpwise                    h:_this help",
                      ""])

  if [:quiz, :licks].include?(mode)
    frames << [" More help on keys; special for modes licks and quiz:",
               "",
               "",
               "  Note: 'licks' and 'sequence of holes to play' (mode quiz)",
               "  are mostly handled alike.",
               "",
               "  RETURN:_next sequence or lick     BACKSPACE:_previous"]
    if mode == :quiz
      frames[-1].append(*["      .p:_replay sequence"])
    else
      frames[-1].append(*["      .p:_replay recording",
                          "       ,:_replay menu to choose flags for next replay"])
    end

    frames[-1].append(*["       P:_toggle auto replay for repeats of the same seq",
                        "       I:_toggle immediate reveal of sequence",
                        "     0,-:_forget holes played; start over   +:_skip rest of sequence"])
    if mode == :quiz
      frames[-1].append(*["     4,H:_hints for quiz-flavour #{$quiz_flavour}",
                          "  CTRL-Z:_restart with another flavour (signals quit, tstp)"])
          if $quiz_flavour == 'replay'
            frames[-1].append(*["       n:_change number of holes to be replayed",
                                ""])
          end
    else
      frames << [" More help on keys; special for mode licks:",
                 "",
                 "",
                 "      l:_change current lick by name       L:_to first lick",
                 "      t:_change lick-selection (-t)        i:_show info on lick",
                 "      #:_shift lick by chosen interval; useful for playing a lick",
                 "         over a scale progression        9,@:_change option --partial",
                 "     */:_Add or remove Star from current lick persistently;",
                 "         select them later by tags starred/unstarred",
                 "      !:_play holes reversed               &:_shuffle holes",
                 "      1:_give one hole, as if played       e:_edit lickfile",
                 ""]
    end
  end

  frames << ["",
             " Translated keys:",
             ""]
  if $keyboard_translations.length > 0
    maxlen = $keyboard_translations.keys.map(&:length).max
    $keyboard_translations.each_slice(2) do |slice|
      frames[-1] << '      '
      slice.each do |from,to|
        frames[-1][-1] += ( "    %#{maxlen}s=_%s" % [from, [to].flatten.join('+')] ).ljust(24)
      end
    end
  else
    frames[-1] << '     none'
  end
  frames[-1].append(*["",
                      " Performance info:",
                      "",
                      "     Update loops per second:   " + ('%8.2f' % $perfctr[:handle_holes_this_loops_per_second]),
                      "        \e[0m\e[2mbased on #{$perfctr[:handle_holes_this_loops]} loops, reset after this help\e[0m\e[32m",
                      "",
                      "     Time slice (per config):      #{$opts[:time_slice]}",
                      "     Maximum jitter:               " + ($max_jitter > 0  ?  ('%8.2f sec' % $max_jitter)  :  'none'),

                      "     Samples lost due to lagging:  #{$lagging_freqs_lost}"])
  
  frames << ["",
             " Further reading:",
             "",
             "   Invoke 'harpwise' without arguments for introduction, examples",
             "   and options.",
             "",
             "   Full documentation at   https://marcihm.github.io/harpwise",
             "",
             "   Note, that other keys and help apply e.g. while harpwise plays",
             "   itself; type 'h' then for details.",
             "",
             " Questions and suggestions welcome to:     \e[92mmarc@ihm.name\e[32m",
             "",
             "                  Harpwise version is:     \e[92m#{$version}\e[32m"]

  # add prompt and frame count
  frames.each_with_index do |frame, fidx|
    # insert page-cookie
    frame[0] = frame[0].ljust($conf[:term_min_width] - 10) + "   \e[0m[#{fidx + 1}/#{frames.length}]"
    frame << "" unless frame[-1] == ""
    frame << ""  while frame.length < max_lines_per_frame - 2
    frame << ' ' +
             if fidx < frames.length - 1
               'SPACE for more; ESC to leave'
             else
               'Help done; SPACE or ESC to leave'
             end +
             if fidx > 0 
               ', BACKSPACE for prev,'
             else
               ','
             end
    frame << "   any other key to highlight its specific line of help ..."
  end
  
  # get some structured information out of frames
  all_fkgs_k2flidx = Hash.new
  frames.each_with_index do |frame, fidx|
    frame.each_with_index do |line, lidx|
      scanner = StringScanner.new(line)
      while scanner.scan_until(/\S+(:|=)_/)
        full_kg = scanner.matched
        kg = scanner.matched[0..-3].strip
        special = %w(SPACE CTRL-L CTRL-R CTRL-Z RETURN BACKSPACE LEFT RIGHT UP DOWN SPACE TAB ALT-s ALT-l ALT-m)
        ks = if special.include?(kg)
               [kg]
             else
               fail "Internal error: cannot handle #{special} with other keys in same keygroup yet; in line '#{line}'" if special.any? {|sp| kg[sp]} && !special.any {|sp| kg == sp}
               # handle comma as first or last in key group special
               if kg[0] == ',' || kg[-1] == ',' || kg.length == 1
                 kg.chars
               else
                 if kg[',']
                   kg.split(',')
                 else
                   kg.chars
                 end
               end
             end
        ks.each do |k|
          fail "Key '#{k}' already has this [frame, line]: '#{all_fkgs_k2flidx[k]}'; cannot assign it new '#{[fidx, lidx]}'; line is '#{line}'" if all_fkgs_k2flidx[k]
          all_fkgs_k2flidx[k] ||= [fidx, lidx]
        end
      end
    end
  end

  # check current set of frames more thoroughly while testing
  if $testing || testing_only
    # fkgs = frame_keys_groups
    all_fkgs_kg2line = Hash.new
    frames.each do |frame|

      err "Internal error: frame #{frame.pretty_inspect} with #{frame.length} lines is longer than maximum of #{max_lines_per_frame}" if frame.length > max_lines_per_frame

      this_fkgs_pos2group_last = Hash.new
      frame.each do |line|

        err "Internal error: line '#{line}' with #{line.length} chars is longer than maximum of #{$term_width - 2}" if line.gsub(/\e\[\d+m/,'').length > $term_width - 2

        scanner = StringScanner.new(line)
        # one keys-group after the other
        while scanner.scan_until(/\S+:_/)
          kg = scanner.matched
          this_fkgs_pos2group_last[scanner.pos] = kg
          err "Internal error: frame key group '#{kg}' in line '#{line}' has already appeared before in prior line '#{all_fkgs_kg2line[kg]}' (maybe in a prior frame)" if all_fkgs_kg2line[kg]
          all_fkgs_kg2line[kg] = line
        end
      end

      # checking of key groups, so that we can be sure to highlight
      # correctly, even with our simple approach (see below)
      err "Internal error: frame \n\n#{frame.pretty_inspect}\nhas too many positions of keys-groups (alignment is probably wrong); this_fkgs_pos2group_last = #{this_fkgs_pos2group_last}\n" if this_fkgs_pos2group_last.keys.length > 2
    end
  end

  return nil if testing_only

  #
  # present result: show and navigate frames according to user input
  #
  curr_frame_was = -1
  curr_frame = 0
  lidx_high = nil

  # loop over user-input
  loop do

    if curr_frame != curr_frame_was || lidx_high
      # actually print frame
      system('clear') if curr_frame != curr_frame_was
      print "\e[#{lines_offset}H"
      print "\e[0m"
      print "\e[0m\e[32m" if curr_frame == frames.length - 1
      print frames[curr_frame][0].rstrip
      print "\e[0m\e[32m\n"
      frames[curr_frame][1 .. -3].each_with_index do |line, lidx|
        # frames are checked for correct usage of keys-groups during
        # testing (see above), so that any errors are found and we can
        # use our simple approach, which has the advantage of beeing
        # easy to format: replacement ':_' to ': ' and '=_' to '='
        puts line.gsub(/(\S+):_/, "\e[92m\\1\e[32m: ").gsub(/(\S+)=_/, "\e[92m\\1\e[32m=").rstrip
      end
      print "\e[\e[0m\e[2m"
      puts frames[curr_frame][-2]
      print frames[curr_frame][-1]
      print "\e[0m\e[32m"
      if lidx_high
        print "\e[#{lines_offset + lidx_high}H"
        line = frames[curr_frame][lidx_high].gsub(':_', ': ').gsub('=_', '=')
        $resources[:hl_long_wheel].each do |col|
          print "\r\e[#{col}m" + line
          sleep 0.15
        end
        blinked = true
        puts "\e[32m"
      end
    end

    curr_frame_was = curr_frame
    lidx_high = nil
    key = $ctl_kb_queue.deq
    key = $opts[:tab_is] if key == 'TAB' && $opts[:tab_is]
    
    if key == 'BACKSPACE' 
      curr_frame -= 1 if curr_frame > 0
    elsif key == 'ESC'
      return
    elsif key == ' '
      if curr_frame < frames.length - 1
        curr_frame += 1
      else
        return
      end
    else
      if all_fkgs_k2flidx[key]
        lidx_high = all_fkgs_k2flidx[key][1]
        if curr_frame != all_fkgs_k2flidx[key][0]
          print "\e[#{$lines[:hint_or_message]}H\e[0m\e[2m Changing screen ...\e[K"
          sleep 0.4
          curr_frame_was = -1
          curr_frame = all_fkgs_k2flidx[key][0]
        end
      else
        system('clear')
        print "\e[#{lines_offset + 4}H"
        puts "\e[0m\e[2m Key '\e[0m#{key}\e[2m' has no function and no help within this part of harpwise."
        puts
        sleep 0.5
        puts "\e[2m #{$resources[:any_key]}\e[0m"
        $ctl_kb_queue.clear
        $ctl_kb_queue.deq
        curr_frame_was = -1
      end
    end
  end  ## loop over user input
end


def clear_warbles silent = false
  $warbles = {short: {times: Array.new,
                      val: 0.0,
                      max: 0.0,
                      window: 2},
              long: {times: Array.new,
                     val: 0.0,
                     max: 0.0,
                     window: 4},
              scale: 10}
  $warbles_holes = Array.new(2)
  $msgbuf.print("Reset holes for warbling", 5, 5, :warble) unless silent
end


def warbles_add_del tntf, add_warble

  # See clear_warbles for structure of $warbles
  
  # add_warble becomes true every time we reach hole two after having reached hole one
  # before
  
  [:short, :long].each do |type|

    $warbles[type][:times] << tntf if add_warble

    # remove warbles, that are older than window
    del_warble = ( $warbles[type][:times].length > 0 &&
                   tntf - $warbles[type][:times][0] > $warbles[type][:window] )
    $warbles[type][:times].shift if del_warble
    
    if add_warble || del_warble
      $warbles[type][:val] = if $warbles[type][:times].length > 1
                               # enough values to compute warbling
                               tspan = $warbles[type][:times][-1] - $warbles[type][:times][0]
                               if tspan > $warbles[type][:window] * 0.7
                                 # tspan of timestamps is comparable to window
                                 if add_warble
                                   ($warbles[type][:times].length - 1) / tspan
                                 else
                                   $warbles[type][:val]
                                 end
                               else
                                 # time span too short; but this is an approximation and
                                 # decays gracefully to zero
                                 $warbles[type][:times].length / $warbles[type][:window].to_f
                               end
                             else
                               0.0
                             end
      if add_warble
        $warbles[type][:max] = [ $warbles[type][:val],
                                 $warbles[type][:max] ].max
      end
      # maybe adjust scale
      rescaled = false
      while $warbles[:scale] < $warbles[type][:max] do
        $warbles[:scale] += 5
        rescaled = true
      end
      $msgbuf.print("Adjusted scale of warble-meter to #{$warbles[:scale]}",5,5) if rescaled
    end
  end
end


def show_remote_message
  specials = %w({{mission}} {{key}} {{timer}})
  if $opts[:jamming]
    $msgbuf.reset
    messages = Dir[$remote_message_dir + '/[0-9]*.txt'].sort
    if messages.length > 0
      lines = File.read(messages[0]).lines
      FileUtils.rm(messages[0])
      text = lines[0].chomp
      if text.index('{{') && specials.none? {|s| text.start_with?(s)}
        err "Internal error: remote message from #{messages[0]}: if its first line contains special sequence '{{' anywhere, it must actually start with any of '#{specials.join(", ")}' plus additional text, but not: #{lines.pretty_inspect}"
      end
      if lines.length != 2
        err "Internal error: remote message from #{messages[0]} needs exactly two lines but its content has not: #{lines.pretty_inspect}"
      end
      duration = begin
                   Float(lines[1].chomp)
                 rescue ArgumentError
                   err "Second line of remote message from #{messages[0]} is not a number: '#{lines[1].chomp}'"
                 end

      if text.start_with?('{{mission}}')
        $jamming_mission_override = text[text.index('}}') + 2 .. -1]
        err("Internal error: no text after {{mission}}") if !$jamming_mission_override || $jamming_mission_override == ''
        print_mission(*get_mission_override)
      elsif text.start_with?('{{key}}')
        key_was = $key
        key = text[text.index('}}') + 2 .. -1]
        err("Internal error: key '#{key} received from jamming is none of the available keys: #{$conf[:all_keys]}") unless $conf[:all_keys].include?(key)
        $key = key
        set_global_vars_late
        set_global_musical_vars
        print "\e[#{$lines[:key]}H" + text_for_key        
        if $key == key_was
          $msgbuf.print "Key of harp unchanged:   #{$key}", duration, duration, :key
        else
          $msgbuf.print "Changed key of harp to   #{$key}", duration, duration, :key
        end
      elsif text.start_with?('{{timer}}')
        dtext = text[text.index('}}') + 2 .. -1]
        ts_end = begin
                   Float(dtext)
                 rescue ArgumentError
                   err "Internal error: after {{timer}} there needs to be a number, not: '#{dtext}'"
                 end
        $jamming_timer_start = Time.now.to_f
        $jamming_timer_end = ts_end
        $jamming_timer_update_next = $jamming_timer_start - 1
        $jamming_timer_state = nil
        print_mission(*get_mission_override)
      else
        if text[0] == '*'
          $msgbuf.print "\e[2m>> \e[0m\e[34m#{text[1..]}", duration, duration, :remote
        else
          $msgbuf.print "\e[2m>> \e[0m\e[32m#{text}", duration, duration, :remote
        end
      end
    else
      $msgbuf.print "No remote message in #{$remote_message_dir}", 5, 5, :remote
    end
  else
    $msgbuf.print "Need to give --jamming before files from #{$remote_message_dir} can be shown", 5, 5, truncate: false, wrap: true
  end
end
