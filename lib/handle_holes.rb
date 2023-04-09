#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_mission, lambda_good_done_was_good, lambda_skip, lambda_comment, lambda_hint, lambda_hole_for_inter, lambda_star_lick
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  
  hole_start = Time.now.to_f
  hole = hole_since = nil
  # $hole_was_for_disp needs to be persistant over invocations and
  # cannot be set here
  hole_held = hole_held_before = hole_held_since = nil
  was_good = was_was_good = was_good_since = nil
  hints_refreshed_at = Time.now.to_f - 1000.0
  hints = hints_old = nil
  first_round = true
  warbles = Array.new
  $perfctr[:handle_holes_calls] += 1
  $perfctr[:handle_holes_this_loops] = 0
  $perfctr[:handle_holes_this_started] = hole_start
  $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
  $column_short_hint_or_message = 1
  $ctl_response_default = 'SPACE to pause; h for help'

  loop do   # until var done or skip

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
        print "\e[#{$lines[:hint_or_message]}H\e[2mTerminal [width, height] = [#{$term_width}, #{$term_height}] is #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;101mON THE EDGE\e[0;2m of"  :  'above'} minimum [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]\e[K\e[0m"
        $column_short_hint_or_message = 1
        $message_shown_at = Time.now.to_f
      end
      print $pending_message_after_redraw
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

    if $opts[:comment] == :warbles && !$max_warble_shown
      print "\e[#{$lines[:hint_or_message]}H\e[2mMax warble speed is #{max_warble_clause}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
    end

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_mic
    
    behind = $freqs_queue.length * $opts[:time_slice]
    if behind > 0.5
      now = Time.now.to_f
      if now - $program_start > 10
        $lagging_freqs_lost += $freqs_queue.length 
        $freqs_queue.clear
        if now - $lagging_freqs_message_ts > 120 
          print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[0m"
          print "Lagging #{'%.1f' % behind}s; more info on termination (e.g. ctrl-c)."
          print "\e[K"
          $lagging_freqs_message_ts = $message_shown_at = now
        end
      else
        $freqs_queue.clear
      end
    end

    # also restores default text after a while
    ctl_response

    handle_win_change if $ctl_sig_winch
    
    good = done = false
    
    hole_was_for_since = hole
    hole = nil
    
    hole, lbor, cntr, ubor = describe_freq(freq)
    
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_for_since
    if hole != hole_held && Time.now.to_f - hole_since > 0.1
      hole_held_before = hole_held
      write_hole_to_journal(hole_held, hole_held_since) if $journal_active && $mode == :listen && regular_hole?(hole_held)
      if hole
        hole_held = hole
        hole_held_since = hole_since
      end
    end
    hole_for_inter = nil

    if $hole_ref && hole == $hole_ref && hole != hole_was_for_since
      now = Time.now.to_f
      warbles << now
      warbles.shift while now - warbles[0] > 2
    end

    was_was_good = was_good
    good,
    done,
    was_good = if $opts[:screenshot]
                 [true, $ctl_can[:next] && Time.now.to_f - hole_start > 2, false]
               else
                 $perfctr[:lambda_good_done_was_good_call] += 1
                 lambda_good_done_was_good.call(hole, hole_since)
               end
    # even if we do not track progress we need to return to forget
    done = $ctl_mic[:forget] if $opts[:no_progress]
    if $ctl_mic[:done]
      good = done = true
      $ctl_mic[:done] = false
    end

    was_good_since = Time.now.to_f if was_good && was_good != was_was_good

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

    if lambda_hole_for_inter
      $perfctr[:lambda_hole_for_inter_call] += 1
      hole_for_inter = lambda_hole_for_inter.call(hole_held_before, $hole_ref)
    end
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
      when :holes_scales
        fit_into_comment lambda_comment.call
      when :holes_intervals
        fit_into_comment lambda_comment.call
      when :holes_all
        fit_into_comment lambda_comment.call
      when :holes_notes
        fit_into_comment lambda_comment.call
      else
        # lambda may choose a different position
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
                            freq,
                            warbles)
        print "\e[#{line}H#{color}"
        do_figlet_unwrapped text, font, width_template
      end
    end

    if done
      print "\e[#{$lines[:message2]}H" if $lines[:message2] > 0
      return
    end

    if lambda_hint && Time.now.to_f - hints_refreshed_at > 0.5
      if $message_shown_at
        # triggers refresh of hint, once the current message has been elapsed
        hints_old = nil
      else
        $perfctr[:lambda_hint_call] += 1
        hints = lambda_hint.call(hole)
        hints_refreshed_at = Time.now.to_f
        if hints != hints_old
          $perfctr[:lambda_hint_reprint] += 1
          print "\e[#{$lines[:message2]}H\e[K" if $lines[:message2] > 0
          print "\e[#{$lines[:hint_or_message]}H\e[0m\e[2m"
          # Using truncate_colored_text might be too slow here
          if hints.length == 1
            # for mode quiz
            print truncate_text(hints[0]) + "\e[K"
            $column_short_hint_or_message = 1
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
              $column_short_hint_or_message = 1
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
              $column_short_hint_or_message = ( hint_or_message.rindex('|') || -2 ) + 3
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
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2m#{$hole_ref ? 'Stored' : 'Cleared'} reference hole\e[0m\e[K"
      if $hole_ref 
        $charts[:chart_intervals] = get_chart_with_intervals
        if $opts[:display] == :chart_intervals
          clear_area_display
          print_chart
        end
      end
      $message_shown_at = Time.now.to_f
      warbles = Array.new
      $ctl_mic[:set_ref] = false
      $ctl_mic[:update_comment] = true
    end
    
    if $ctl_mic[:change_display]
      choices = [ $display_choices, $display_choices ].flatten
      choices = choices.reverse if $ctl_mic[:change_display] == :back
      $opts[:display] = choices[choices.index($opts[:display]) + 1]
      $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($opts[:display])
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mDisplay is now #{$opts[:display].upcase}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
      $ctl_mic[:change_display] = false
    end
    
    if $ctl_mic[:change_comment]
      choices = [ $comment_choices[$mode], $comment_choices[$mode] ].flatten
      choices = choices.reverse if $ctl_mic[:change_comment] == :back
      $opts[:comment] = choices[choices.index($opts[:comment]) + 1]
      clear_area_comment
      warble_clause = if $opts[:comment] == :warbles
                        ", max speed is " + max_warble_clause
                      else
                        ''
                      end
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mComment is now #{$opts[:comment].upcase}#{warble_clause}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
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
    
    if $ctl_mic[:toggle_journal]
      $journal_active = !$journal_active
      if $journal_active
        journal_start
        $journal_listen = Array.new
      else
        write_hole_to_journal(hole_held, hole_held_since) if $mode == :listen && regular_hole?(hole_held)
        IO.write($journal_file, "All holes: #{$journal_listen.join(' ')}\n", mode: 'a') if $mode == :listen && $journal_listen.length > 0
        # do not issue message in journal
      end
      ctl_response "Journal #{$journal_active ? ' ON' : 'OFF'}"
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2m"      
      print ( $journal_active  ?  "Appending to "  :  "Done with " ) + $journal_file
      print "\e[K"
      $message_shown_at = Time.now.to_f

      $ctl_mic[:toggle_journal] = false

      print "\e[#{$lines[:key]}H" + text_for_key      
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

    return if [:change_lick, :edit_lick_file, :change_tags, :reverse_holes, :switch_modes].any? {|k| $ctl_mic[k]}

    if $ctl_mic[:quit]
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[0mTerminating on user request (quit) ...\n\n"
      exit 0
    end

    if done || ( $message_shown_at && Time.now.to_f - $message_shown_at > 8 )
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[K"
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
  text += '; journal: ' + ( $journal_active  ?  ' on' : 'off' )
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
      report_error_wait_key error
    else
      $key = input
    ensure
      $on_error_raise = false
    end
  end while error
  $message_shown_at = Time.now.to_f
  $pending_message_after_redraw = "\e[#{$lines[:hint_or_message]}H\e[2mChanged key of harp to \e[0m#{$key}\e[K"
  $message_shown_at = Time.now.to_f
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
  $key = play_adjustable_pitch(embedded = true) || $key
  text = if key_was == $key
           "Key of harp is still at"
         else
           "Changed key of harp to"
         end
  $pending_message_after_redraw = "\e[#{$lines[:hint_or_message]}H\e[2m#{text} \e[0m#{$key}\e[K" 
  $message_shown_at = Time.now.to_f
end


def do_change_scale_add_scales
  input = choose_interactive("Choose main scale (current is #{$scale}): ", $all_scales.sort) do |scale|
    $scale_desc_maybe[scale] || '?'
  end
  $scale = input if input
  unless input
    $message_shown_at = Time.now.to_f
    $pending_message_after_redraw = "\e[#{$lines[:hint_or_message]}H\e[2mDid not change scale of harp.\e[0m\e[K"
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

  $message_shown_at = Time.now.to_f
  $pending_message_after_redraw = "\e[#{$lines[:hint_or_message]}H\e[2mChanged scale of harp to \e[0m\e[32m#{$scale}\e[0m\e[K"
end


def do_rotate_scale_add_scales
  $used_scales.rotate!
  $scale = $used_scales[0]
  $opts[:add_scales] = $used_scales.length > 1  ?  $used_scales[1..-1].join(',')  :  nil
  $message_shown_at = Time.now.to_f
  $pending_message_after_redraw = "\e[#{$lines[:hint_or_message]}H\e[2mChanged scale of harp to \e[0m\e[32m#{$scale}\e[0m\e[K"
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
             "      j: toggle journal file",
             "      s: set scales                   S: rotate scales"]
  if $ctl_can[:switch_modes]
    frames[-1] << "      m: switch between modes #{$modes_for_switch.map(&:to_s).join(',')}"
  elsif $mode == :listen
    frames[-1].append(*["      m: switch between modes; not available now; rather start",
                        "         with modes quiz or licks to be able to switch to",
                        "         listen and then back"])
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


def max_warble_clause
  "#{(1/(2*$opts[:time_slice])).to_i}; tune --time-slice to increase"
end
