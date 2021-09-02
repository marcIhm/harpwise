
#
# Handle recording of sounds and recognition of notes
#


def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = (opts[:silent] && !$opts[:debug]) ? '>/dev/null 2>&1' : ''
  system(dbg "arecord -D pulse #{duration_clause} #{file} #{output_clause}") or fail 'arecord failed'
end


def play_sound file
  system(dbg "aplay -D pulse #{file} >/dev/null 2>&1") or fail 'aplay failed'
end


def find_best_bin data, width
  len = data.length - 1
  idx_for_max = 0
  count_max = 0
  for idx in 0 .. len do
    count = 1
    while idx + count <= len
      break if (data[idx + count] - data[idx]).abs > width
      count += 1
    end
    if count > count_max
      idx_for_max = idx
      count_max = count
    end
  end
  return idx_for_max, count_max
end


def find_best_bin_bidi data, width
  # try data forward and backward
  ifw, cfw = find_best_bin data, width
  ibw, cbw = find_best_bin data.reverse, width
  if cfw >= cbw
    return ifw, cfw
  else
    return data.length - ibw - cbw, cbw
  end
end


def get_two_peaks data, width

  # find maximum
  idx_m, cnt_m = find_best_bin_bidi(data, width)
  sum_m = data[idx_m, cnt_m].sum

  # investigate left and right of max
  data_l = data[0, idx_m]
  data_r = data[idx_m + cnt_m .. -1]
  
  idx_l, cnt_l = find_best_bin_bidi(data_l, width)
  sum_l = data_l[idx_l .. idx_l + cnt_l - 1].sum

  idx_r, cnt_r = find_best_bin_bidi(data_r, width)
  sum_r = data_r[idx_r .. idx_r + cnt_r - 1].sum

  # maximum peak and higher of left or right peak
  pks = [divide(sum_m, cnt_m),
         if cnt_l > cnt_r
           divide(sum_l, cnt_l)
         else
           divide(sum_r, cnt_r)
         end]

  # use second peak if frequency of first is too low
  if pks[0][0] < 200 && pks[1][0] > 200 && pks[1][1] > 4
    pks.reverse!
  end

  return pks
end


def divide sum, cnt
  if cnt == 0
    [0, 0]
  else
    [(sum.to_f/cnt).to_i, cnt]
  end
end


def describe_freq freq
  fr_prev = -1
  $freqs.each_cons(3) do |pfr, fr, nfr|
    lbor = (pfr+fr)/2
    ubor = (fr+nfr)/2
    higher_than_prev = (freq >= lbor)
    lower_than_next = (freq < ubor)
    return $freq2hole[fr],lbor,ubor if higher_than_prev and lower_than_next
    return $freq2hole[$freqs[0]] if lower_than_next
  end
  return $freq2hole[$freqs[-1]]
end
  

def get_hole issue, lambda_good_done, lambda_skip, lambda_comment, lambda_hint

  samples = Array.new
  system('clear')
  # See  https://en.wikipedia.org/wiki/ANSI_escape_code
  print "\e[?25l"  # hide cursor
  $move_down_on_exit = true

  print issue + "      \e[2m(SPACE to pause#{$ctl_can_next ? ', n next, l loop' : ''})\e[0m"

  tstart = last_poll = Time.now.to_f
  hole = '-'
  while true do   
    tnow = Time.now.to_f

    print "\e[#{$line_comment}H"
    lambda_comment.call if lambda_comment
    print "\e[H\e[1H"
    
    # Get and filter new samples
    # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
    begin
      tstart_record = Time.now.to_f
      record_sound 0.1, $sample_file, silent: true
    end while Time.now.to_f - tstart_record < 0.05
    new_samples = %x(aubiopitch --pitch mcomb #{$sample_file} 2>/dev/null).lines.
                    map {|l| f = l.split; [f[0].to_f + tnow, f[1].to_i]}.
                    select {|f| f[1]>0}
    # curate our pool of samples
    samples += new_samples
    samples = samples[-32 .. -1] if samples.length > 32
    samples.shift while samples.length > 0 && tnow - samples[0][0] > 1

    poll_and_handle
    
    hole_was = hole
    hole = '-'
    extra = ''
    if $opts[:screenshot]
      if Time.now.to_f - tstart > 0.5
        samples = (1..78).to_a.map {|x| [tnow + x/100.0, 797]}
        new_samples = samples[0, 20]
      end
    end
    return if lambda_skip && lambda_skip.call()
    if samples.length > 8
      # each peak has structure [frequency in hertz, count]
      pks = get_two_peaks samples.map {|x| x[1]}.sort, 10
      pk = pks[0]

      good = done = false
      
      extra = "Frequency: #{pk[0]}"
      if pk[1] > 8
        hole, lbor, ubor = describe_freq pk[0]
        hole_since = Time.now.to_f if hole != hole_was
        good, done = lambda_good_done.call(hole, hole_since)
        if $opts[:screenshot]
          good = true
          done = true if Time.now.to_f - tstart > 2
        end
        extra += " in range [#{lbor},#{ubor}], Note \e[0m#{$harp[hole][:note]}\e[2m" if lbor
      else
        extra += ' but count below threshold'
      end
      extra += "\nPeaks: #{pks.inspect}"
    end
    figlet_out = %x(figlet -f mono12 -c " #{hole}")
    # See  https://en.wikipedia.org/wiki/ANSI_escape_code
    print "\e[#{$line_note}H"
    if hole == '-'
      print "\e[2m"
    else
      print "\e[#{good ? 32 : 31}m"
    end
    puts_pad figlet_out
    print "\e[#{$line_samples}H"
    puts_pad "\e[0m\e[2mSamples total: #{samples.length}, new: #{new_samples.length}"
    puts_pad extra
    print "\e[0m"
    if done
      print "\e[?25h"  # show cursor
      print "\e[#{$line_comment}H"
      $move_down_on_exit = false
      return hole
    end
    print "\e[#{$line_hint}H"
    lambda_hint.call(tstart) if lambda_hint
  end
end


