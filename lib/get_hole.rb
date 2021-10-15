#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def get_hole issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  
  print "\e[#{$line_issue}H#{issue.ljust($term_width - $ctl_issue_width)}\e[0m"
  $ctl_default_issue = "SPACE to pause#{$ctl_can_next ? '; RET next; BS back' + ($opts[:loop] ? '' : '; l loop') : ''}"
  ctl_issue
  print "\e[#{$line_key}H\e[2mType #{$type}, key of #{$key}, scale #{$scale}\e[0m"

  print_chart if $conf[:display] == :chart
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_disp = nil
  hole_held = hole_held_before = nil

  loop do   # until var done or skip

    freq = $opts[:screenshot]  ?  797  :  $freqs_queue.deq

    return if lambda_skip && lambda_skip.call()

    $freqs_queue.clear if handle_kb_play
    ctl_issue
    
    print "\e[#{$line_driver}H"
    print "\e[2mProcessing: analysed/measured: %3.02f, cycles per sec: %4.1f, queued: %d\e[K" %
          [$freqs_rate_ratio, $freqs_per_sec, $freqs_queue.length]
    
    good = done = false
      
    hole_was_ts = hole
    hole = nil
    hole, lbor, ubor = describe_freq(freq)
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_ts
    if hole  &&  hole != hole_held  &&  Time.now.to_f - hole_since > 0.2
      hole_held_before = hole_held
      hole_held = hole
    end
    hole_for_inter = nil
    
    good, done = lambda_good_done.call(hole, hole_since)
    if $opts[:screenshot]
      good = true
      done = true if Time.now.to_f - hole_start > 2
    end

    freq_text = "\e[#{$line_frequency}HFrequency:  %6.1f Hz" % freq
    if hole == :low || hole == :high
      print freq_text
    else
      print freq_text + "  in range [#{lbor.to_s.rjust(4)},#{ubor.to_s.rjust(4)}]" + 
            (hole  ?  "  Note #{$harp[hole][:note]}"  :  '') + "\e[K"
      hole_for_inter = lambda_hole_for_inter.call(hole_held_before) if lambda_hole_for_inter
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
      update_chart(hole_was_disp, :normal) if hole_was_disp && hole_was_disp != hole
      hole_was_disp = hole if hole
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

  end  # loop until var done or skip
end


def add_to_freq_samples samples
  tnow = Time.now.to_f
  max_samples = 1
  # Get and filter new samples
  new_samples = $freqs_queue.deq
  # curate our pool of samples
  samples += new_samples
  samples = samples[- max_samples .. -1] if samples.length > max_samples
#  samples.shift while samples.length > 0 && tnow - samples[0][0] > 1
  [samples, new_samples]
end
