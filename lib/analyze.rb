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
    return :low, nil, nil, nil if (freq < lb)
    return $freq2hole[fr], lb, fr, ub if (freq >= lb) and (freq < ub)
  end
  return :high, nil, nil, nil
end


def note2semi note
  note = note.downcase
  raise ArgumentError.new("note '#{note}' should end with a single digit") unless ('0'..'9').include?(note[-1])
  idx = $notes_with_sharps.index(note[0 .. -2]) ||
        $notes_with_flats.index(note[0 .. -2]) or
    raise ArgumentError.new("non-digit part is none of #{$notes_with_sharps.inspect} or #{$notes_with_flats.inspect}")
    return 12 * note[-1].to_i + idx - 57
end


def semi2note semi, sharp_or_flat = $conf[:pref_sig]
  semi += 57  # value for a4
  case sharp_or_flat
  when :flat
    $notes_with_flats[semi % 12] + (semi / 12).to_s
  when :sharp
    $notes_with_sharps[semi % 12] + (semi / 12).to_s
  else
    fail "Internal error: #{sharp_or_flat}"
  end
end


def semi2freq_et semi
  440 * 2**( semi / 12.0 )
end


def cents_diff f1, f2
  # see https://ohw.se/hca/tuning-theory/#3.2
  1200 * Math.log(f1.to_f/f2)/Math.log(2)
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


def analyze_with_aubio file
  freqs = run_aubiopitch(file).lines.
            map {|line| line.split[1].to_i}.
            select {|freq| freq > $conf[:min_freq] && freq < $conf[:max_freq]}
  # take only second half to avoid transients
  freqs = freqs[freqs.length/2 .. -1]
  minf, maxf = freqs.minmax
  aver = freqs.length > 0  ?  freqs.sum / freqs.length  :  0
  if ( maxf - minf ) > 0.1 * aver
    puts "(using 2nd half of #{freqs.length * 2} freqs: %5.2f .. %5.2f Hz, average %5.2f)" % [minf, maxf, aver]
    puts "\e[31mWARNING\e[0m: min and max of recorded samples are two far apart !\nMaybe repeat recording more steadily ?"
  end
  aver
end


def inspect_recording hole, file
  note = $harp[hole][:note]
  semi = note2semi(note)
  freq_et = semi2freq_et(semi)
  freq_et_p1 = semi2freq_et(semi + 1)
  freq_et_m1 = semi2freq_et(semi - 1)
  puts "\e[33mAnalysis\e[0m of current recorded/generated sound (hole: #{hole}, note: #{note}):"
  freq = analyze_with_aubio(file)
  note2semi($harp[hole][:note])
  dots, _ = get_dots('........:........', 2, freq, freq_et_m1, freq_et, freq_et_p1) {|hit, idx| idx}
  puts "Frequency: #{freq}, ET: #{freq_et.round(0)}, diff: #{(freq - freq_et).round(0)}   -1st:#{freq_et_m1.round(0)} [#{dots}] +1st:#{freq_et_p1.round(0)}"
  too_low = (freq - freq_et_m1).abs < (freq - freq_et).abs
  too_high = (freq - freq_et_p1).abs < (freq - freq_et).abs
  if too_low || too_high
    puts "\n\e[91mWARNING:\e[0m\nThe frequency recorded for \e[33m#{hole}\e[0m (note #{$harp[hole][:note]}, semi #{semi}) is too different from ET tuning:"
    puts "  You played:             #{freq}"
    puts "  ET expects:             #{freq_et.round(1)}"
    puts "  Difference:             #{(freq - freq_et).round(1)}"
    puts "  ET one semitone lower:  #{freq_et_m1.round(1)}"
    puts "  ET one semitone higher: #{freq_et_p1.round(1)}"
    puts "You played much \e[91m#{too_low ? 'LOWER' : 'HIGHER'}\e[0m than expected for hole #{hole}."
    puts "(i.e. much closer to neighboring semitones than to target note)"
    puts "\nMaybe repeat recording with the right hole and pitch ?\n\n"
  end
  return freq
end
