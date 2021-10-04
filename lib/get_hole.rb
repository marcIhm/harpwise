#
# Get hole
#


def get_hole issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter

  samples = Array.new
  # See  https://en.wikipedia.org/wiki/ANSI_escape_code
  $move_down_on_exit = true
  
  print "\e[#{$line_issue}H#{issue.ljust($term_width - $ctl_issue_width)}\e[0m"
  $ctl_default_issue = "SPACE to pause#{$ctl_can_next ? '; RET next; BS back' + ($opts[:loop] ? '' : '; l loop') : ''}"
  ctl_issue
  print "\e[#{$line_key}H\e[2mType #{$type}, key of #{$key}, scale #{$scale}\e[0m"

  hole_start = Time.now.to_f
  hole = hole_since = nil
  hole_held = hole_held_before = nil

  loop do   

    samples, new_samples = if $opts[:screenshot]
                             samples_for_screenshot(samples, hole_start)
                           else
                             add_to_samples samples
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
        hole_was = hole
        hole, lbor, ubor = describe_freq pk[0]
        hole_since = Time.now.to_f if !hole_since || hole != hole_was
        if hole && hole != hole_held && Time.now.to_f - hole_since > 0.2
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
                (hole ? "Note #{$harp[hole][:note]}" : '') + "\e[K"
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
      
    print "\e[#{$line_hole}H\e[0m"
    print "\e[#{(hole && hole != :low && hole != :high) ? ( good ? 32 : 31 ) : 2}m"
    do_figlet ({ low: '-', high: '-'}[hole] || hole || '-'), 'mono12'

    if lambda_comment_big
      comment_text, font = lambda_comment_big.call(inter_semi, inter_text, hole && $harp[hole]&.[](:note))
      print "\e[#{$line_comment_big}H\e[2m"
      do_figlet comment_text, font
    end

    if done
      print "\e[#{$line_listen}H"
      $move_down_on_exit = false
      return hole
    end

    print "\e[#{$line_hint}H"
    lambda_hint.call() if lambda_hint
  end
end


def add_to_samples samples
  tnow = Time.now.to_f
  # Get and filter new samples
  # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
  begin
    start_record = Time.now.to_f
    record_sound 0.1, $collect_wave, silent: true
  end while Time.now.to_f - start_record < 0.05
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


