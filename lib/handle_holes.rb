#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_issue, lambda_good_done_was_good, lambda_skip, lambda_comment, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_disp = nil
  hole_held = hole_held_before = hole_held_since = nil
  was_good = was_was_good = was_good_since = nil
  hints_refreshed_at = Time.now.to_f - 1000.0
  hints = hints_old = nil
  first_round = true
  $perfctr[:handle_holes_calls] += 1
  $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
  $column_short_hint_or_message = 1

  loop do   # until var done or skip

    $perfctr[:handle_holes_loops] += 1
    system('clear') if $ctl_listen[:redraw]
    if first_round || $ctl_listen[:redraw]
      $perfctr[:lambda_issue_call] += 1
      print_issue lambda_issue.call
      $ctl_issue_default = "SPACE to pause; h for help"
      ctl_issue
      print "\e[#{$lines[:key]}H" + text_for_key
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($conf[:display])
      print "\e[#{$lines[:interval]}H\e[2mInterval:   --  to   --  is   --  \e[K"
      if $ctl_listen[:redraw] && $ctl_listen[:redraw] != :silent
        print "\e[#{$lines[:hint_or_message]}H\e[2mTerminal [width, height] = [#{$term_width}, #{$term_height}] is #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;101mON THE EDGE\e[0;2m of"  :  'above'} minimum [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]\e[K\e[0m"
        $column_short_hint_or_message = 1
        $message_shown_at = Time.now.to_f
      end
      $ctl_listen[:redraw] = false
      $ctl_listen[:update_comment] = true
    end
    print "\e[#{$lines[:hint_or_message]}HWaiting for frequency pipeline to start ..." if $first_round_ever_get_hole

    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_listen
    # restores also default text after a while
    ctl_issue

    handle_win_change if $ctl_sig_winch
    
    good = done = false
      
    hole_was_for_since = hole
    hole = nil
    hole, lbor, cntr, ubor = describe_freq(freq)
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_for_since
    if hole != hole_held  &&  Time.now.to_f - hole_since > 0.1
      hole_held_before = hole_held
      write_to_journal(hole_held, hole_held_since) if $write_journal && $mode == :listen && regular_hole?(hole_held)
      if hole
        hole_held = hole
        hole_held_since = hole_since
      end
    end
    hole_for_inter = nil

    was_was_good = was_good
    good, done, was_good = if $opts[:screenshot]
                             [true, $ctl_can[:next] && Time.now.to_f - hole_start > 2, false]
                           else
                             $perfctr[:lambda_good_done_was_good_call] += 1
                             lambda_good_done_was_good.call(hole, hole_since)
                           end
    done = false if $opts[:no_progress]
    if $ctl_listen[:done]
      good = done = true
      $ctl_listen[:done] = false
    end

    was_good_since = Time.now.to_f if was_good && was_good != was_was_good

    print "\e[2m\e[#{$lines[:frequency]}HFrequency:  "
    just_dots_short = '.........:.........'
    format = "%6s Hz, %4s Cnt  [%s]\e[2m\e[K"
    if regular_hole?(hole)
      dots, _ = get_dots(just_dots_short.dup, 2, freq, lbor, cntr, ubor) {|hit, idx| hit ? "\e[0m#{idx}\e[2m" : idx}
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
    case $conf[:display]
    when :chart_notes, :chart_scales, :chart_intervals
      update_chart(hole_was_for_disp, :inactive) if hole_was_for_disp && hole_was_for_disp != hole
      hole_was_for_disp = hole if hole
      update_chart(hole, :active, good, was_good, was_good_since)
    when :hole
      print "\e[#{$lines[:display]}H\e[0m"
      print hole_color
      do_figlet_unwrapped hole_disp, 'mono12', longest_hole_name
    when :bend
      print "\e[#{$lines[:display] + 2}H"
      if $hole_ref
        semi_ref = $harp[$hole_ref][:semi]
        just_dots_long = '......:......:......:......'
        dots, hit = get_dots(just_dots_long.dup, 4, freq,
                             semi2freq_et(semi_ref - 2),
                             semi2freq_et(semi_ref),
                             semi2freq_et(semi_ref + 2)) {|ok,idx| idx}
        print ( hit  ?  "\e[0m\e[32m"  :  "\e[0m\e[31m" )
        do_figlet_unwrapped dots, 'smblock', 'fixed:' + just_dots_long
      else
        print "\e[2m"
        do_figlet_unwrapped 'set ref first', 'smblock'
      end
    else
      fail "Internal error: #{$conf[:display]}"
    end

    text = "Hole: %#{longest_hole_name.length}s, Note: %4s" %
           (regular_hole?(hole)  ?  [hole, $harp[hole][:note]]  :  ['-- ', '-- '])
    text += ", Ref: %#{longest_hole_name.length}s" % [$hole_ref || '-- ']
    text += ",  Rem: #{$hole2rem[hole] || '--'}" if $hole2rem
    print "\e[#{$lines[:hole]}H\e[2m" + truncate_text(text, $term_width - 4) + "\e[K"

    if lambda_comment
      $perfctr[:lambda_comment_call] += 1
      case $conf[:comment]
      when :holes_scales
        fit_into_comment lambda_comment.call
      when :holes_intervals
        fit_into_comment lambda_comment.call
      when :holes_all
        fit_into_comment lambda_comment.call
      when :holes_notes
        fit_into_comment lambda_comment.call
      else
        comment_color,
        comment_text,
        font,
        width_template,
        truncate =
        lambda_comment.call($hole_ref  ?  hole_ref_color  :  hole_color,
                            inter_semi,
                            inter_text,
                            hole && $harp[hole] && $harp[hole][:note],
                            hole_disp,
                            freq,
                            $hole_ref ? semi2freq_et($harp[$hole_ref][:semi]) : nil)
        print "\e[#{$lines[:comment_low]}H#{comment_color}"
        do_figlet_unwrapped comment_text, font, width_template, truncate
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
            print truncate_text(hints[0], $term_width - 4) + "\e[K"
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
              print truncate_text(hints[2], $term_width - 4) + "\e[K"
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
              print truncate_text(hints[3], $term_width - 4) + "\e[K"
            end
          else
            err "Internal error"
          end
          print "\e[0m\e[2m"
        end
        hints_old = hints
      end
    end      

    if $ctl_listen[:set_ref]
      $hole_ref = regular_hole?(hole_held) ? hole_held : nil
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2m#{$hole_ref ? 'Stored' : 'Cleared'} reference hole\e[0m\e[K"
      if $hole_ref 
        $charts[:chart_intervals] = get_chart_with_intervals
        if $conf[:display] == :chart_intervals
          clear_area_display
          print_chart
        end
      end
      $message_shown_at = Time.now.to_f
      $ctl_listen[:set_ref] = false
      $ctl_listen[:update_comment] = true
    end
    
    if $ctl_listen[:change_display]
      choices = [ $display_choices, $display_choices ].flatten
      choices = choices.reverse if $ctl_listen[:change_display] == :back
      $conf[:display] = choices[choices.index($conf[:display]) + 1]
      $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($conf[:display])
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mDisplay is now #{$conf[:display].upcase}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
      $ctl_listen[:change_display] = false
    end
    
    if $ctl_listen[:change_comment]
      choices = [ $comment_choices[$mode], $comment_choices[$mode] ].flatten
      choices = choices.reverse if $ctl_listen[:change_comment] == :back
      $conf[:comment] = choices[choices.index($conf[:comment]) + 1]
      clear_area_comment
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mComment is now #{$conf[:comment].upcase}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
      $ctl_listen[:change_comment] = false
      $ctl_listen[:update_comment] = true
    end

    if $ctl_listen[:show_help]
      clear_area_comment
      puts "\e[#{$lines[:help]}H\e[0mHelp on keys (see usage info of harpwise too):\e[0m\e[32m\n"
      puts "   SPACE: pause               ctrl-l: redraw screen"
      puts " TAB,S-TAB,d,D: change display (upper part of screen)"
      puts "     c,C: change comment (lower, i.e. this, part of screen)"
      puts "       r: set reference hole       j: toggle writing of journal file"
      puts "       k: change key of harp       s: change scale and --add-scale"
      puts "       q: quit                     h: this help"
      if $ctl_can[:switch_modes]
        puts "       m: switch between modes #{$modes_for_switch}"
      elsif $mode == :listen
        puts "       m: start with quiz or licks to switch to and from"
      end
      if $ctl_can[:next]
        puts "\e[0mType any key to show more help ...\e[K"
        $ctl_kb_queue.clear
        $ctl_kb_queue.deq
        clear_area_comment
        puts "\e[#{$lines[:help]}H\e[0mMore help on keys:\e[0m\e[32m\n"
        puts "     .: replay current recording          ,: replay, holes only"
        puts "   :;p: replay but ignore '--partial'"
        puts "   RET: next sequence             BACKSPACE: previous sequence"
        puts "     i: toggle '--immediate'              l: loop current sequence"
        puts "   0,-: forget holes played           TAB,+: skip rest of sequence"
        puts "     #: toggle track progress in seq"
        if $ctl_can[:named]
          puts "\e[0mType any key to show more help ...\e[K"
          $ctl_kb_queue.clear
          $ctl_kb_queue.deq
          clear_area_comment
          puts "\e[#{$lines[:help]}H\e[0mMore help on keys:\e[0m\e[32m\n"
          puts "     n: switch to lick by name            t: change options --tags"
          puts "     <: shift lick down by one octave     >: shift lick up"
          puts "     @: change option --partial"
        end
      end
      puts "\e[0mPress any key to continue ...\e[K"
      $ctl_kb_queue.clear
      $ctl_kb_queue.deq
      ctl_issue 'continue', hl: true
      clear_area_comment
      $ctl_listen[:show_help] = false
    end

    if $ctl_can[:loop] && $ctl_listen[:start_loop]
      $ctl_listen[:loop] = true
      $ctl_listen[:start_loop] = false
      $perfctr[:lambda_issue_call] += 1
      print_issue lambda_issue.call
    end
    
    if $ctl_listen[:toggle_journal]
      $write_journal = !$write_journal
      if $write_journal
        journal_start
        $journal_listen = Array.new
      else
        write_to_journal(hole_held, hole_held_since) if $mode == :listen && regular_hole?(hole_held)
        IO.write($journal_file, "All holes: #{$journal_listen.join(' ')}\n", mode: 'a') if $mode == :listen && $journal_listen.length > 0
        IO.write($journal_file, "Stop writing journal at #{Time.now}\n", mode: 'a')
      end
      ctl_issue "Journal #{$write_journal ? ' ON' : 'OFF'}"
      print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2m"      
      print ( $write_journal  ?  "Appending to "  :  "Done with " ) + $journal_file
      print "\e[K"
      $message_shown_at = Time.now.to_f

      $ctl_listen[:toggle_journal] = false

      print "\e[#{$lines[:key]}H" + text_for_key      
    end

    if $ctl_listen[:change_key]
      do_change_key
      $ctl_listen[:change_key] = false
      $ctl_listen[:redraw] = :silent
      set_global_vars_late
      set_global_musical_vars
    end

    if $ctl_listen[:change_scale]
      do_change_scale_add_scales
      $ctl_listen[:change_scale] = false
      $ctl_listen[:redraw] = :silent
      set_global_vars_late
      set_global_musical_vars
    end

    return if $ctl_listen[:named_lick] || $ctl_listen[:change_tags] || $ctl_listen[:switch_modes]

    if $ctl_listen[:quit]
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
  text += "(#{$licks.length})" if $mode == :licks
  text += " #{$type} \e[0m#{$key}"
  if $opts[:add_scales]
    text += "\e[0m"
    text += " \e[32m#{$scale}"
    text += "\e[0m\e[2m," + $all_scales[1..-1].map {|s| "\e[0m\e[34m#{$scale2short[s] || s}\e[0m\e[2m"}.join(',')
    text += ",\e[0mall\e[2m"
  else
    text += "\e[2m #{$scale}"
  end
  text += '; journal: ' + ( $write_journal  ?  ' on' : 'off' )
  truncate_colored_text(text, $term_width - 2 ) + "\e[K"
end


def regular_hole? hole
  hole && hole != :low && hole != :high
end


def get_dots dots, delta, freq, low, middle, high
  hdots = (dots.length - 1)/2
  if freq > middle
    pos = hdots + ( hdots + 1 ) * (freq - middle) / (high - middle)
  else
    pos = hdots - ( hdots + 1 ) * (middle - freq) / (middle - low)
  end

  hit = ((hdots - delta  .. hdots + delta) === pos )
  dots[pos] = yield( hit, 'I') if pos > 0 && pos < dots.length
  return dots, hit
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
  stop_kb_handler
  sane_term
  begin
    cmnt_print_in_columns 'Available keys', $conf[:all_keys], ["current is #{$key}"]
    cmnt_print_prompt  'Please enter','new key'
    
    input = STDIN.gets.chomp
    input = $key.to_s if input == ''
    error = nil
    begin
      $on_error_raise = true
      check_key_and_set_pref_sig(input)
    rescue ArgumentError => error
      cmnt_report_error_wait_key error
    else
      $key = input.to_sym
    ensure
      $on_error_raise = false
    end
  end while error
  start_kb_handler
  prepare_term
  print "\e[#{$lines[:key]}H" + text_for_key
  print "\e[#{$lines[:hint_or_message]}H\e[2mChanged key of harp to \e[0m#{$key}\e[K"
  $message_shown_at = Time.now.to_f
end


def do_change_scale_add_scales
  stop_kb_handler
  sane_term

  # Change scale
  begin
    cmnt_print_in_columns 'First setting main scale; available scales',
                          $all_scales,
                          ["current scale is #{$scale}",
                           'RETURN to keep']
    cmnt_print_prompt 'Please enter', 'new scale', '(abbrev)'
    input = STDIN.gets.chomp.strip
    error = nil
    break if input == ''
    scale = match_or(input, $all_scales) do |none, choices|
      error = "Given scale #{none} is none of #{choices}"
    end
    if error
      cmnt_report_error_wait_key error
    else
      $scale = scale
    end
  end while error

  # Change --add-scales
  begin
    cmnt_print_in_columns 'Now setting --add-scales; available scales',
                          $all_scales,
                          ["current value is #{$opts[:add_scales]}",
                           'RETURN to keep, SPACE to clear']
    cmnt_print_prompt 'Please enter', "new value for --add-scales", '(maybe abbreviated)'
    input = STDIN.gets.chomp
    error = nil
    if input == ''
      break
    elsif input.strip.empty?
      $opts[:add_scales] = nil
      break
    end
    input.gsub!(',',' ')
    add_scales = input.split.map do |scale|
      match_or(input, $all_scales) do |none, choices|
        error ||= "Given scale #{none} is none of #{choices}"
      end
    end
    if error
      cmnt_report_error_wait_key error
    else
      $opts[:add_scales] = add_scales.join(',')
    end
  end while error

  start_kb_handler
  prepare_term
  print "\e[#{$lines[:key]}H" + text_for_key
  print "\e[#{$lines[:hint_or_message]}H\e[2mChanged scale of harp to \e[0m#{$scale}\e[K"
  $message_shown_at = Time.now.to_f  
end
