#
# Handle recording of sounds and recognition of notes
#


def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = (opts[:silent] && !$opts[:debug]) ? '>/dev/null 2>&1' : ''
  system(dbg "arecord -D pulse -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}") or fail 'arecord failed'
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
  

