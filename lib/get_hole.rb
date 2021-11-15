#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def get_hole lambda_issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  
  print "\e[#{$line_issue}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
  $ctl_default_issue = "SPACE to pause; h for help"
  ctl_issue
  print "\e[#{$line_key}H\e[2m" + text_for_key

  print_chart if $conf[:display] == :chart
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_disp = nil
  hole_held = hole_held_before = hole_held_since = nil
  message_shown = nil
  journal_holes = Array.new

  loop do   # until var done or skip

    freq = $opts[:screenshot]  ?  797  :  $freqs_queue.deq

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_play
    ctl_issue
    
    print "\e[#{$line_driver}H"
    print "\e[2mPipeline: slice: %.2f, jitter: %5.02f, queued: %d#{$debug_info}\e[K" %
          [$conf[:time_slice], $analysis_delay, $freqs_queue.length]
    
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
      done = true if Time.now.to_f - hole_start > 2
    end

    print "\e[#{$line_frequency}HFrequency:  "
    dots = '..........:..........'
    if hole != :low && hole != :high
      if freq > cntr
        pos = 10 + 11 * (freq - cntr) / (ubor - cntr)
      else
        pos = 10 - 11 * (cntr - freq) / (cntr - lbor)
      end
      dots[pos] = (( 7 .. 13) === pos  ?  "\e[0mI\e[2m"  :  'I' )
      print "#{'%6.1f Hz' % freq}  [#{dots}]"
      print "  Note \e[0m#{$harp[hole][:note]}\e[K\e[2m"
      hole_for_inter = lambda_hole_for_inter.call(hole_held_before) if lambda_hole_for_inter
    else
      print "   --  Hz  [#{dots}]  Note --\e[K"
    end

    print "\e[#{$line_interval}H"
    inter_semi, inter_text = describe_inter(hole_held, hole_for_inter)
    if inter_semi
      print "Interval: #{hole_for_inter.rjust(4)}  to #{hole_held.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[#{regular_hole?(hole)  ?  ( good ? 32 : 31 )  :  2}m"
    if $conf[:display] == :chart
      update_chart(hole_was_for_disp, :normal) if hole_was_for_disp && hole_was_for_disp != hole
      hole_was_for_disp = hole if hole
      update_chart(hole, good  ?  :good  :  :bad) 
    else
      print "\e[#{$line_display}H\e[0m"
      print hole_color
      do_figlet hole_disp, 'mono12'
    end
      
    if lambda_comment_big
      comment_color, comment_text, font = lambda_comment_big.call(hole_color,
                                                                  inter_semi,
                                                                  inter_text,
                                                                  hole && $harp[hole] && $harp[hole][:note],
                                                                  hole_disp)
      print "\e[#{$line_comment_big}H#{comment_color}"
      do_figlet '   ' + comment_text, font
    end

    if done
      print "\e[#{$line_listen}H"
      $move_down_on_exit = false
      return
    end

    print "\e[#{$line_hint}H"
    lambda_hint.call(hole) if lambda_hint

    if $ctl_change_display
      $conf[:display] = ( $conf[:display] == :chart  ?  :hole  :  :chart )
      clear_area_display
      print_chart if $conf[:display] == :chart
      print "\e[#{$line_message}H\e[2mDisplay is now #{$conf[:display]}\e[0m\e[K"
      message_shown = Time.now.to_f
      $ctl_change_display = false
    end

    if $ctl_can_change_comment && $ctl_change_comment
      choices = [ $comment_choices, $comment_choices ].flatten
      $conf[:comment_listen] = choices[choices.index($conf[:comment_listen]) + 1]
      clear_area_comment
      print "\e[#{$line_message}H\e[2mComment is now #{$conf[:comment_listen]}\e[0m\e[K"
      message_shown = Time.now.to_f
      $ctl_change_comment = false
    end

    if $ctl_show_help
      $ctl_show_help = false
      print "\e[#{$line_message}HShort help: SPACE to pause"
      print "; TAB to change display"
      print "; c to change comment" if $ctl_can_change_comment
      print "; j for journal" if $ctl_can_journal
      print '; RET next sequence; BACKSPACE previous; l loop over sequence' if $ctl_can_next
      print "\e[K"
      message_shown = Time.now.to_f
    end

    if $ctl_can_loop && $ctl_start_loop
      $ctl_loop = true
      $ctl_start_loop = false
      print "\e[#{$line_issue}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
    end
    
    if $ctl_can_journal && $ctl_toggle_journal
      if $write_journal
        write_to_journal(hole_held, hole_held_since, journal_holes)  if regular_hole?(hole_held)
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
      print "\e[#{$line_message}H\e[0m"      
      print ( $write_journal  ?  "Appending to "  :  "Done with " ) + $journal_file
      print "\e[K"
      print "\e[#{$line_key}H\e[2m" + text_for_key      
      message_shown = Time.now.to_f
    end

    if message_shown &&  Time.now.to_f - message_shown > 8
      print "\e[#{$line_message}H\e[K"
      message_shown = false
    end
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
