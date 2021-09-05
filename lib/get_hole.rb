#
# Get hole
#


def get_hole issue, lambda_good_done, lambda_skip, lambda_comment, lambda_hint

  samples = Array.new
  # See  https://en.wikipedia.org/wiki/ANSI_escape_code
  print "\e[?25l"  # hide cursor
  $move_down_on_exit = true
  
  print "\e[#{$line_issue}H\e[0m"
  puts_pad issue, true
  $ctl_default_issue = "SPACE to pause#{$ctl_can_next ? '; n,RET next' + ($opts[:loop] ? '' : '; l loop') : ''}"
  ctl_issue

  tstart = Time.now.to_f
  hole_since = nil
  hole = '-'
  comment_text_was = nil

  loop do   

    if lambda_comment
      comment_text = lambda_comment.call()
      if comment_text_was != comment_text
        print "\e[#{$line_comment}H\e[2m"
        do_figlet comment_text, 'smblock'
        comment_text_was = comment_text
      end
    end

    samples, new_samples = if $opts[:screenshot]
                             samples_for_screenshot 
                           else
                             add_to_samples samples
                           end

    return if lambda_skip && lambda_skip.call()

    poll_and_handle_kb
    
    print "\e[#{$line_samples}H"
    puts_pad "\e[2mSamples total: #{samples.length}, new: #{new_samples.length}"

    if samples.length > 6
      hole, hole_since, good, done = do_analysis(samples, hole, hole_since, lambda_good_done)
    else
      hole, hole_since, good, done = ['-', hole_since, false, false]
      print "\e[#{$line_analysis}H"
      puts_pad 'Not enough samples'
      print "\e[#{$line_analysis2}H"
      puts_pad
    end
    
    print "\e[#{$line_hole}H\e[0m"
    print "\e[#{hole == '-' ? 2 : ( good ? 32 : 31 )}m"
    do_figlet hole, 'mono12'

    if done
      print "\e[?25h"  # show cursor
      print "\e[#{$line_listen}H"
      $move_down_on_exit = false
      return hole
    end

    print "\e[#{$line_hint}H"
    lambda_hint.call(tstart) if lambda_hint
  end
end


def add_to_samples samples
  tnow = Time.now.to_f
  # Get and filter new samples
  # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
  begin
    tstart_record = Time.now.to_f
    record_sound 0.1, $sample_file, silent: true
  end while Time.now.to_f - tstart_record < 0.05
  new_samples = run_aubiopitch($sample_file, "--hopsize 1024").lines.
                  map {|l| f = l.split; [f[0].to_f + tnow, f[1].to_i]}.
                  select {|f| f[1]>0}
  # curate our pool of samples
  samples += new_samples
  samples = samples[-32 .. -1] if samples.length > 32
  samples.shift while samples.length > 0 && tnow - samples[0][0] > 1
  [samples, new_samples]
end


def samples_for_screenshot
  tnow = Time.now.to_f
  if Time.now.to_f - tstart > 0.5
    samples = (1..78).to_a.map {|x| [tnow + x/100.0, 797]}
  end
  [samples, samples[0, 20]]
end


def do_analysis samples, hole, hole_since, lambda_good_done
  # each peak has structure [frequency in hertz, count]
  pks = get_two_peaks samples.map {|x| x[1]}.sort, 10
  pk = pks[0]
  
  print "\e[#{$line_analysis}H"
  puts_pad "Peaks: #{pks.inspect}"
  
  good = done = false
  
  print "\e[#{$line_analysis2}H"
  text = "Frequency: #{pk[0]}"

  if pk[1] > 4
    hole_was = hole
    hole, lbor, ubor = describe_freq pk[0]
    hole_since = Time.now.to_f if !hole_since || hole != hole_was

    good, done = lambda_good_done.call(hole, hole_since)

    if $opts[:screenshot]
      good = true
      done = true if Time.now.to_f - tstart > 2
    end
    puts_pad text + " in range [#{lbor},#{ubor}]" + ", Note \e[0m#{$harp[hole][:note]}\e[2m" if ubor
  else
    hole = '-'
    puts_pad text + ' but count below threshold'
  end

  [hole, hole_since, good, done]
end
