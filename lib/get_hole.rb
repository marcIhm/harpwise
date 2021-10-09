#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

$count = 0
def get_hole issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter
  $count += 1
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
  first_lap = true

  loop do   # until var done or skip

    samples, new_samples = if $opts[:screenshot]
                             samples_for_screenshot(samples, hole_start)
                           else
                             add_to_samples samples, drain_more: first_lap
                           end

    return if lambda_skip && lambda_skip.call()

    handle_kb_play
    ctl_issue
    
    print "\e[#{$line_samples}H"
    print "\e[2mSamples total: #{samples.length.to_s.rjust(2)}, new: #{new_samples.length.to_s.rjust(2)}\e[K"

    if samples.length > 6
      # do and print analysis
      pks = get_two_peaks samples.map {|x| x[1]}.sort, 10
      pk = pks[0]
      
      print "\e[#{$line_peaks}H"
      print "Peaks: [[%4d,%3d], [%4d,%3d]]\e[K" % pks.flatten
      
      good = done = false
      
      print "\e[#{$line_frequency}H"
      freq_text = "Frequency: #{pk[0].to_s.rjust(4)}"

      if pk[1] > 6
        hole_was_ts = hole
        hole = nil
        hole, lbor, ubor = describe_freq(pk[0])
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
        if hole == :low || hole == :high
          print freq_text
        else
          print (freq_text + "  in range [#{lbor.to_s.rjust(4)},#{ubor.to_s.rjust(4)}]").ljust(40) + 
                (hole  ?  "Note #{$harp[hole][:note]}"  :  '') + "\e[K"
          hole_for_inter = lambda_hole_for_inter.call(hole_held_before) if lambda_hole_for_inter
        end
      else
        hole = nil
        print freq_text + "  but count of peak below 7\e[K"
      end
    else
      # Not enough samples, analysis not possible
      hole, good, done = [nil, false, false]
      print "\e[#{$line_peaks}H"
      print "Not enough samples\e[K"
      print "\e[#{$line_frequency}H\e[K"
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

    first_lap = false
  end  # loop until var done or skip
end


def add_to_samples samples, drain_more: false
  tnow = Time.now.to_f
  # Get and filter new samples
  # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
  # Unfortunately the values below are sensitive to timing issues; which caused the program to listen
  # to itself in mode quiz.
  begin
    start_record = Time.now.to_f
    record_sound ( drain_more ? 0.16 : 0.1 ), $collect_wave, silent: true
  end while Time.now.to_f - start_record < ( drain_more ? 0.15 : 0.05 )
  new_samples = run_aubiopitch($collect_wave, "--hopsize 1024").lines.
                  map {|l| f = l.split; [f[0].to_f + tnow, f[1].to_i]}.
                  select {|f| f[1]>0}
  # curate our pool of samples
  samples += new_samples
  samples = samples[-32 .. -1] if samples.length > 32
  samples.shift while samples.length > 0 && tnow - samples[0][0] > 1
  [samples, new_samples]
end


def samples_for_screenshot samples, tstart
  tnow = Time.now.to_f
  if Time.now.to_f - tstart > 0.5
    samples = (1..78).to_a.map {|x| [tnow + x/100.0, 797]}
  end
  [samples, samples[0, 20]]
end


