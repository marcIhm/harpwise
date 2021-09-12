#
# Handle recording of sounds and recognition of notes
#


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

  # pseudo frequencies to aid analysis
  freqs = ([$harp[$holes[0]][:freq] / 2,
            $harp[$holes[0]][:freq] * 2] + $freq2hole.keys).sort
  
  freqs.each_cons(3) do |pfr, fr, nfr|
    lb = (pfr + fr) / 2
    ub = (fr + nfr) / 2
    return 'low' if (freq < lb)
    return $freq2hole[fr],lb,ub if (freq >= lb) and (freq < ub)
  end
  return 'high'
end
  

def note2semi note
  notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  notes_with_flats = %w( c df d ef e f gf g af a bf b )

  note = note.downcase
  raise ArgumentError.new('should end on a single digit') unless ('1'..'9').include?(note[-1])
  idx = notes_with_sharps.index(note[0 .. -2]) ||
        notes_with_flats.index(note[0 .. -2]) or
    raise ArgumentError.new("non-digit part is none of #{notes_with_sharps.inspect} or #{notes_with_flats.inspect}")
    return 12 * note[-1].to_i + idx
end


def describe_inter hole1, hole2
  semi1, semi2 = [hole1, hole2].map {|h| $harp.dig(h, :semi)}
  return [nil, nil] unless semi1 && semi2  # happens for pseudo holes low and high
  diff_semi = semi1 - semi2
  return ["#{diff_semi.abs} st", $intervals[diff_semi.abs]]
end
