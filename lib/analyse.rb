#
# Analyze frequencies, notes and intervals
#


def describe_freq freq

  minfr = $harp[$harp_holes[0]][:freq]
  maxfr = $harp[$harp_holes[-1]][:freq]
  # pseudo frequencies to aid analysis
  freqs = ([minfr * 3 / 4 ,
            maxfr * 4 / 3] + $freq2hole.keys).sort
  
  freqs.each_cons(3) do |pfr, fr, nfr|
    lb = (pfr + fr) / 2
    ub = (fr + nfr) / 2
    return :low, nil, nil if (freq < lb)
    return $freq2hole[fr], lb, ub if (freq >= lb) and (freq < ub)
  end
  return :high, nil, nil
end


def note2semi note
  note = note.downcase
  raise ArgumentError.new("note '#{note}' should end with a single digit") unless ('0'..'9').include?(note[-1])
  idx = $notes_with_sharps.index(note[0 .. -2]) ||
        $notes_with_flats.index(note[0 .. -2]) or
    raise ArgumentError.new("non-digit part is none of #{$notes_with_sharps.inspect} or #{$notes_with_flats.inspect}")
    return 12 * note[-1].to_i + idx
end


def semi2note semi, sharp_or_flat = :sharp
  case sharp_or_flat
  when :flat
    $notes_with_flats[semi % 12] + (semi / 12).to_s
  when :sharp
    $notes_with_sharps[semi % 12] + (semi / 12).to_s
  else
    fail "Internal error: #{sharp_or_flat}"
  end
end


def notes_equiv note
  no_digit = !note[-1].match?(/[0-9]/)
  note += '0' if no_digit
  semi = note2semi(note)
  ns = semi2note(semi, :sharp)
  nf = semi2note(semi, :flat)
  if no_digit
    ns = ns[0 .. -2]
    nf = nf[0 .. -2]
  end
  notes = [note]
  notes << ns if ns != note
  notes << nf if nf != note
  notes
end


def describe_inter hole1, hole2
  semi1, semi2 = [hole1, hole2].map {|h| $harp.dig(h, :semi)}
  return [nil, nil] unless semi1 && semi2  # happens for pseudo holes low and high
  diff_semi = semi1 - semi2
  return ["#{diff_semi.abs} st", $intervals[diff_semi.abs]]
end
