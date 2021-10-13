#
# Get hole
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def get_hole issue, lambda_good_done, lambda_skip, lambda_comment_big, lambda_hint, lambda_hole_for_inter
  $time_of_get_hole_start = Time.now.to_f
  $total_time_recorded = 0
  Thread.new {collect_samples_in_bg}
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

    $total_iterations_in_get_hole += 1
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

  end  # loop until var done or skip
end


def collect_samples_in_bg
  max_aup_threads = 8
  slice = 0.1
  aup_threads = Array.new
  first = true
  loop do
    if aup_threads.length > 0 && ( !aup_threads[0][1].alive? || aup_threads.length >= max_aup_threads )
      aup_threads[0].join
      aup_threads.shift
    end
    file_num = ((1 .. max_aup_threads).to_a - aup_threads.map {|nt| nt[0]}).min
    file_name = $collect_wave_template % file_num
    if first
      begin
        start_record = Time.now.to_f
        record_sound slice, file_name, silent: true
      end while Time.now.to_f - start_record < slice * 0.8
    else
      record_sound slice, file_name, silent: true
    end
    aup_threads << [file_num, Thread.new {aubiopitch_to_queue(file_name)}]
    first = false
  end
end


def aubiopitch_to_queue fname
  tnow = Time.now.to_f
  new_samples = run_aubiopitch(fname, "--hopsize 1024").lines.
                  map {|l| f = l.split; [f[0].to_f + tnow, f[1].to_i]}.
                  select {|f| f[1]>0}
  $new_samples_queue.enq new_samples
end


def add_to_samples samples
  tnow = Time.now.to_f
  max_samples = 16
  # Get and filter new samples
  new_samples = $new_samples_queue.deq
  # curate our pool of samples
  samples += new_samples
  samples = samples[- max_samples .. -1] if samples.length > max_samples
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


