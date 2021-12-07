#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def get_hole lambda_issue, lambda_good_done, lambda_skip, lambda_comment, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_disp = nil
  hole_held = hole_held_before = hole_held_since = nil
  journal_holes = Array.new
  first = true

  loop do   # until var done or skip
    if first || $ctl_redraw
      print "\e[#{$line_issue}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
      $ctl_default_issue = "SPACE to pause; h for help"
      ctl_issue
      print "\e[#{$line_key}H\e[2m" + text_for_key
      
      print_chart if $conf[:display] == :chart
      if $ctl_redraw
        print "\e[#{$line_hint_or_message}H\e[2mTerminal [width, height] = [#{$term_width}, #{$term_height}] #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;91mON THE EDGE of\e[0;2m"  :  'is above'} minimum size [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]\e[K\e[0m"
        $message_shown = Time.now.to_f
      end
      $ctl_redraw = false
    end
    print "\e[#{$line_hint_or_message}HWaiting for frequency pipeline to start ..." if first

    handle_win_change if $ctl_sig_winch

    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq
    
    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_play
    ctl_issue
    
    good = done = false
      
    hole_was_for_since = hole
    hole = nil
    hole, lbor, cntr, ubor = describe_freq(freq)
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_for_since
    if hole != hole_held  &&  Time.now.to_f - hole_since > 0.2
      hole_held_before = hole_held
      write_to_journal(hole_held, hole_held_since, journal_holes) if $write_journal && regular_hole?(hole_held)
      if hole
        hole_held = hole
        hole_held_since = hole_since
      end
    end
    hole_for_inter = nil
    
    good, done = lambda_good_done.call(hole, hole_since)
    if $opts[:screenshot]
      good = true
      done = true if $ctl_can_next && Time.now.to_f - hole_start > 2
    end

    print "\e[2m\e[#{$line_frequency}HFrequency:  "
    just_dots_short = '........:........'
    if hole != :low && hole != :high
      dots, _ = get_dots(just_dots_short.dup, 2, freq, lbor, cntr, ubor) {|hit, idx| hit ? "\e[0m#{idx}\e[2m" : idx}
      print "#{'%6.1f Hz' % freq}  [#{dots}]\e[2m\e[K"
      hole_for_inter = lambda_hole_for_inter.call(hole_held_before, $hole_ref) if lambda_hole_for_inter
    else
      print "   --  Hz  [#{just_dots_short}]\e[K"
    end

    print "\e[#{$line_interval}H"
    inter_semi, inter_text = describe_inter(hole_held, hole_for_inter)
    if inter_semi
      print "Interval: #{hole_for_inter.rjust(4)}  to #{hole_held.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[#{regular_hole?(hole)  ?  ( good ? 92 : 31 )  :  2}m"
    case $conf[:display]
    when :chart
      update_chart(hole_was_for_disp, :normal) if hole_was_for_disp && hole_was_for_disp != hole
      hole_was_for_disp = hole if hole
      update_chart(hole, good  ?  :good  :  :bad) 
    when :hole
      print "\e[#{$line_display}H\e[0m"
      print hole_color
      do_figlet hole_disp, 'mono12', longest_hole_name
    when :bend
      print "\e[#{$line_display + 2}H"
      if $hole_ref
        semi_ref = $harp[$hole_ref][:semi]
        just_dots_long = '......:......:......:......'
        dots, hit = get_dots(just_dots_long.dup, 3, freq,
                             semi2freq_et(semi_ref - 2),
                             semi2freq_et(semi_ref),
                             semi2freq_et(semi_ref + 2)) {|ok,idx| idx}
        print ( hit  ?  "\e[92m\e[48;5;236m"  :  "\e[31m" )
        do_figlet dots, 'smblock', 'fixed:' + just_dots_long
      else
        print "\e[2m"
        do_figlet 'set ref first', 'smblock'
      end
    else
      fail "Internal error: #{$conf[:display]}"
    end

    print "\e[#{$line_hole}H\e[2m"
    if regular_hole?(hole)
      print "Hole: \e[0m%#{longest_hole_name.length}s\e[2m, Note: \e[0m%4s\e[2m" % [hole, $harp[hole][:note]]
    else
      print "Hole: %#{longest_hole_name.length}s, Note: %4s" % ['-- ', '-- ']
    end
    print ", Ref: %#{longest_hole_name.length}s" % [$hole_ref || '- ']
    print "\e[K"

    if lambda_comment
      comment_color,
      comment_text,
      font,
      sample_text =
      lambda_comment.call(hole_color,
                          inter_semi,
                          inter_text,
                          hole && $harp[hole] && $harp[hole][:note],
                          hole_disp,
                          freq,
                          $hole_ref ? semi2freq_et($harp[$hole_ref][:semi]) : nil)
      print "\e[#{$line_comment}H#{comment_color}"
      do_figlet comment_text, font, sample_text
    end

    if done
      print "\e[#{$line_call}H"
      $move_down_on_exit = false
      return
    end

    if lambda_hint && !$message_shown
      hint = lambda_hint.call(hole) || ''
      print "\e[#{$line_hint_or_message}H"
      hint = hint[0 .. $term_width - 8] + '(...)' if hint.length >= $term_width - 4 
      print "\e[2m#{hint}\e[0m\e[K"
    end      

    if $ctl_set_ref
      $hole_ref = regular_hole?(hole_held) ? hole_held : nil
      print "\e[#{$line_hint_or_message}H\e[2m#{$hole_ref ? 'Stored' : 'Cleared'} reference for intervals and display of bends\e[0m\e[K"
      $message_shown = Time.now.to_f
      $ctl_set_ref = false
    end

    if $ctl_change_display
      choices = [ $display_choices, $display_choices ].flatten
      $conf[:display] = choices[choices.index($conf[:display]) + 1]
      clear_area_display
      print_chart if $conf[:display] == :chart
      print "\e[#{$line_hint_or_message}H\e[2mDisplay is now #{$conf[:display].upcase}\e[0m\e[K"
      $message_shown = Time.now.to_f
      $ctl_change_display = false
    end

    if $ctl_can_change_comment && $ctl_change_comment
      choices = [ $comment_choices, $comment_choices ].flatten
      $conf[:comment_listen] = choices[choices.index($conf[:comment_listen]) + 1]
      clear_area_comment
      print "\e[#{$line_hint_or_message}H\e[2mComment is now #{$conf[:comment_listen].upcase}\e[0m\e[K"
      $message_shown = Time.now.to_f
      $ctl_change_comment = false
    end

    if $ctl_show_help
      clear_area_comment
      fail 'internal error 1 for help' if $can_journal != $can_change_comment
      fail 'internal error 2 for help' if $can_next != $can_loop
      # we have room from $line_comment to $line_hint_or_message (included)
      print "\e[#{$line_comment + 1}H\e[2mShort help:\e[0m\e[32m\n"
      print "  SPACE: pause                TAB or d: change display\n"
      print "      j: toggle journal     S-TAB or c: change comment\n" if $ctl_can_change_comment
      print "      r: set reference          ctrl-l: redraw\n"
      print "      h: this help\n"
      print "    RET: next sequence       BACKSPACE: previous sequence\n" if $ctl_can_next
      print "      l: loop over sequence\n" if $ctl_can_next
      print "\e[0m\e[2mType any key to continue ...\e[0m"
      $ctl_kb_queue.clear
      $ctl_kb_queue.deq
      ctl_issue 'continue', hl: true
      clear_area_comment
      $ctl_show_help = false
    end

    if $ctl_can_loop && $ctl_start_loop
      $ctl_loop = true
      $ctl_start_loop = false
      print "\e[#{$line_issue}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
    end
    
    if $ctl_can_journal && $ctl_toggle_journal
      if $write_journal
        write_to_journal(hole_held, hole_held_since, journal_holes) if regular_hole?(hole_held)
        if journal_holes.length > 0
          IO.write($journal_file, "All holes: #{journal_holes.join(' ')}\n", mode: 'a')
          journal_holes = Array.new
        end
        IO.write($journal_file, "Stop writing journal at #{Time.now}\n", mode: 'a')
      else
        IO.write($journal_file, "\nStart writing journal at #{Time.now}\nColumns: Secs since prog start, duration, hole, note\n", mode: 'a')
      end
      $write_journal = !$write_journal
      ctl_issue "Journal #{$write_journal ? ' ON' : 'OFF'}"
      $ctl_toggle_journal = false
      print "\e[#{$line_hint_or_message}H\e[2m"      
      print ( $write_journal  ?  "Appending to "  :  "Done with " ) + $journal_file
      print "\e[K"
      print "\e[#{$line_key}H\e[2m" + text_for_key      
      $message_shown = Time.now.to_f
    end

    if done || ( $message_shown && Time.now.to_f - $message_shown > 8 )
      print "\e[#{$line_hint_or_message}H\e[K"
      $message_shown = false
    end
    first = false
  end  # loop until var done or skip
end


def write_to_journal hole, since, journal_holes
  IO.write($journal_file,
           "%8.2f %8.2f %12s %6s\n" % [ Time.now.to_f - $program_start,
                                        Time.now.to_f - since,
                                        hole,
                                        $harp[hole][:note]],
           mode: 'a')
  journal_holes << hole
end


def text_for_key
  text_for_key = "Mode: #{$mode} #{$type} #{$key} #{$scale}"
  text_for_key += ', journal: ' + ( $write_journal  ?  ' on' : 'off' ) if $ctl_can_journal
  text_for_key += "\e[K"
end


def regular_hole? hole
  hole && hole != :low && hole != :high
end


def get_dots dots, delta, freq, low, middle, high
  ndots = (dots.length - 1)/2
  if freq > middle
    pos = ndots + ( ndots + 1 ) * (freq - middle) / (high - middle)
  else
    pos = ndots - ( ndots + 1 ) * (middle - freq) / (middle - low)
  end

  hit = ((ndots - delta  .. ndots + delta) === pos )
  dots[pos] = yield( hit, 'I') if pos > 0 && pos < dots.length
  return dots, hit
end
