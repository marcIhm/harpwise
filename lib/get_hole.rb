#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def get_hole issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  
  print "\e[#{$line_issue}H#{issue.ljust($term_width - $ctl_issue_width)}\e[0m"
  $ctl_default_issue = "SPACE to pause; h for help"
  ctl_issue
  print "\e[#{$line_key}H\e[2mType #{$type}, key of #{$key}, scale #{$scale}\e[0m"

  print_chart if $conf[:display] == :chart
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_disp = nil
  hole_held = hole_held_before = hole_held_since = nil
  remark_shown = nil

  loop do   # until var done or skip

    freq = $opts[:screenshot]  ?  797  :  $freqs_queue.deq

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_play
    ctl_issue
    
    print "\e[#{$line_driver}H"
    print "\e[2mPipeline: analysis delay: %5.02f (slice %.2f), queued: %d#{$debug_info}\e[K" %
          [$analysis_delay, $conf[:time_slice], $freqs_queue.length]
    
    good = done = false
      
    hole_was_for_since = hole
    hole = nil
    hole, lbor, ubor = describe_freq(freq)
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_for_since
    if hole != hole_held  &&  Time.now.to_f - hole_since > 0.2
      hole_held_before = hole_held
      write_journal(hole_held, hole_held_since) if $write_journal
      if hole
        hole_held = hole
        hole_held_since = Time.now.to_f
      end
    end
    hole_for_inter = nil
    
    good, done = lambda_good_done.call(hole, hole_since)
    if $opts[:screenshot]
      good = true
      done = true if Time.now.to_f - hole_start > 2
    end

    print "\e[#{$line_frequency}HFrequency:  "
    if hole != :low && hole != :high
      print "#{'%6.1f Hz' % freq}  in range [#{lbor.to_s.rjust(4)},#{ubor.to_s.rjust(4)}]" + 
            (hole  ?  "  Note #{$harp[hole][:note]}"  :  '') + "\e[K"
      hole_for_inter = lambda_hole_for_inter.call(hole_held_before) if lambda_hole_for_inter
    else
      print "    -  Hz  in range [  - ,  - ]\e[K"
    end

    print "\e[#{$line_interval}H"
    inter_semi, inter_text = describe_inter(hole_held, hole_for_inter)
    if inter_semi
      print "Interval: #{hole_for_inter.rjust(4)}  to #{hole_held.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[#{(hole  &&  hole != :low  &&  hole != :high)  ?  ( good ? 32 : 31 )  :  2}m"
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
      do_figlet comment_text, font
    end

    if done
      print "\e[#{$line_listen}H"
      $move_down_on_exit = false
      return
    end

    print "\e[#{$line_hint}H"
    lambda_hint.call(hole) if lambda_hint

    if $ctl_show_help
      $ctl_show_help = false
      print "\e[#{$line_remark}HShort help: SPACE to pause; TAB for journal"
      print '; RET next sequence; BACKSPACE previous; l loop' if $ctl_can_next
      print "\e[K"
      remark_shown = Time.now.to_f
    end
    
    if $ctl_toggle_journal
      if $write_journal
        write_journal hole_held, hole_held_since
        IO.write($conf[:journal_file], "Stop writing journal at #{Time.now}\n", mode: 'a')
      else
        IO.write($conf[:journal_file], "\nStart writing journal at #{Time.now}\nColumns: Secs since prog start, duration, hole, note\n", mode: 'a')
      end
      $write_journal = !$write_journal
      ctl_issue "Journal #{$write_journal ? ' ON' : 'OFF'}"
      $ctl_toggle_journal = false
      print "\e[#{$line_remark}H\e[0m"      
      print ( $write_journal  ?  "Appending to"  :  "Done with" ) + " journal.txt"
      print "\e[K"
      remark_shown = Time.now.to_f
    end

    if remark_shown &&  Time.now.to_f - remark_shown > 8
      print "\e[#{$line_remark}H\e[K"
      remark_shown = false
    end
  end  # loop until var done or skip
end


def write_journal hole_held, hole_held_since
  return if !hole_held || hole_held == :low || hole_held == :high
  IO.write($conf[:journal_file],
           "%8.2f %8.2f %12s %6s\n" % [ Time.now.to_f - $program_start,
                                        Time.now.to_f - hole_held_since,
                                        hole_held,
                                        $harp[hole_held][:note]],
           mode: 'a')
end
