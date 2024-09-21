#
# Analyze frequencies, notes and intervals
#


$desc_freq_cache_lb = 1
$desc_freq_cache_ub = -1
$desc_freq_cache = nil

def describe_freq freq

  # Be able to return the same result as before rather quick
  return $desc_freq_cache if freq >= $desc_freq_cache_lb && freq < $desc_freq_cache_ub

  minfr = $harp[$harp_holes[0]][:freq]
  maxfr = $harp[$harp_holes[-1]][:freq]
  # pseudo frequencies to aid analysis
  freqs = ([minfr * 3 / 4 ,
            maxfr * 4 / 3] + $freq2hole.keys).sort
  
  freqs.each_cons(3) do |pfr, fr, nfr|
    lb = (pfr + fr) / 2
    ub = (fr + nfr) / 2
    return nil, nil, nil, nil if (freq < lb)
    if (freq >= lb) and (freq < ub)
      $desc_freq_cache = [$freq2hole[fr], lb, fr, ub]
      $desc_freq_cache_lb = lb
      $desc_freq_cache_ub = ub
      return $desc_freq_cache
    end
  end
  return nil, nil, nil, nil
end


def note2semi note, range = (0..9), graceful = false
  note = note.downcase
  begin
    raise ArgumentError.new("note '#{note}' should end with a single digit in range #{range}") unless range.include?(note[-1].to_i)
    idx = $notes_with_sharps.index(note[0 .. -2]) ||
          $notes_with_flats.index(note[0 .. -2]) or
      raise ArgumentError.new("non-digit part of note '#{note}' is none of #{$notes_with_sharps.inspect} or #{$notes_with_flats.inspect}")
    return 12 * note[-1].to_i + idx - 57
  rescue ArgumentError
    return nil if graceful
    raise
  end
end


def semi2note semi, sharps_or_flats = $opts[:sharps_or_flats]
  semi += 57  # value for a4
  case sharps_or_flats
  when :flats
    $notes_with_flats[semi % 12] + (semi / 12).to_s
  when :sharps
    $notes_with_sharps[semi % 12] + (semi / 12).to_s
  else
    fail "Internal error: #{sharps_or_flats}"
  end
end


# normalize to sharp or flat depending on $opts[:sharps_or_flats]
def sf_norm note
  return semi2note(note2semi(note))
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
  ns = semi2note(semi, :sharps)
  nf = semi2note(semi, :flats)
  if no_digit
    ns = ns[0 .. -2]
    nf = nf[0 .. -2]
  end
  notes = [note]
  notes << ns if ns != note
  notes << nf if nf != note
  notes
end


def describe_inter hon1, hon2, prefer_plus: false
  return [nil, nil, nil, nil] if !hon1 || !hon2 || musical_event?(hon1) || musical_event?(hon2) 
  semi1, semi2 = [hon1, hon2].map do |hon|
    if $harp_holes.include?(hon)
      $harp[hon][:semi]
    else
      note2semi(hon)
    end
  end
  dsemi = semi1 - semi2
  if prefer_plus && dsemi < 0
    dsemi_shifted = (dsemi % 12)
    oct_shift_clause = " - #{( dsemi_shifted - dsemi ) / 12} oct"
    inter = $intervals[dsemi_shifted] || [nil, nil]
    return ["#{dsemi_shifted} st" + oct_shift_clause,
            inter[0] && ( inter[0] + oct_shift_clause ),
            inter[1] && ( inter[1] + oct_shift_clause ),
            dsemi]
  else
    inter = $intervals[dsemi] || [nil, nil]
    return ["#{dsemi} st",
            inter[0],
            inter[1],
            dsemi]
  end
end


def describe_inter_keys key1, key2
  dsemi = note2semi(key1 + '0') - note2semi(key2 + '0')
  return describe_inter_semis(dsemi)
end


def describe_inter_semis dsemi
  inter = $intervals[dsemi] || [nil, nil]
  return "#{dsemi} semitones" +
         if inter[0]
           " (#{inter[0]})"
         elsif inter[1]
           " (#{inter[1]})"
         else
           ''
         end
end


def print_semis_as_abs h1, s1, h2, s2
  hmax = $harp_holes.max_by(&:length).length
  p1, p2 = [s1, s2].map {|s| ["#{s}st", $semi2hole[s], semi2note(s)]}
  cl = [p1.length, p2.length].min
  p1, p2 = [p1, p2].map {|p| p[0...cl]}
  [[h1, p1], [h2, p2]].each do |h, p|
    puts h + p.map {|x| (x || '--').rjust(hmax)}.join(' ,')
  end
end


def analyze_with_aubio file
  freqs = run_aubiopitch(file).lines.
            map {|line| line.split[1].to_i}.
            select {|freq| freq > 50 && freq < 8000}
  # take only second half to avoid transients
  freqs = freqs[freqs.length/2 .. -1]
  minf, maxf = freqs.minmax
  aver = freqs.length > 0  ?  freqs.sum / freqs.length  :  0
  if minf && maxf
    if ( maxf - minf ) > 0.1 * aver
      puts "(using 2nd half of #{freqs.length * 2} freqs: %5.2f .. %5.2f Hz, average %5.2f)" % [minf, maxf, aver]
      puts "\e[31mWARNING\e[0m: min and max of recorded samples are two far apart !\nMaybe repeat recording more steadily ?"
    end
  else
    puts "No frequencies found ! Probably you need to record again."
  end
  aver
end


def inspect_recorded hole, file
  note = $harp[hole][:note]
  semi = note2semi(note)
  freq_et = semi2freq_et(semi)
  freq_et_p1 = semi2freq_et(semi + 1)
  freq_et_m1 = semi2freq_et(semi - 1)
  puts "\e[0m\e[34mAnalysis\e[0m of current recorded/generated sound (hole: #{hole}, note: #{note}):"
  freq = analyze_with_aubio(file)
  note2semi($harp[hole][:note])
  dots, _ = get_dots('........:........', 2, freq, freq_et_m1, freq_et, freq_et_p1) {|hit, idx| idx}
  puts "Frequency: #{freq}, ET: #{freq_et.round(0)}, diff: #{(freq - freq_et).round(0)}   -1st:#{freq_et_m1.round(0)} [#{dots}] +1st:#{freq_et_p1.round(0)}"
  too_low = (freq - freq_et_m1).abs < (freq - freq_et).abs
  too_high = (freq - freq_et_p1).abs < (freq - freq_et).abs
  if too_low || too_high
    puts "\n\e[0;101mWARNING:\e[0m\nThe frequency recorded for  \e[32m#{hole}\e[0m  (note #{$harp[hole][:note]}, semi #{semi}) is too different from ET tuning:"
    puts "  You played:             #{freq}"
    puts "  ET expects:             #{freq_et.round(1)}"
    puts "  Difference:             #{(freq - freq_et).round(1)}"
    puts "  ET one semitone lower:  #{freq_et_m1.round(1)}"
    puts "  ET one semitone higher: #{freq_et_p1.round(1)}"
    puts "You played much \e[91m#{too_low ? 'LOWER' : 'HIGHER'}\e[0m than expected for hole #{hole}."
    puts "\nMaybe repeat recording with the right hole and pitch ?\n\n"
  end
  return freq
end


def diff_semitones key1, key2, strategy: nil
  # map keys to notes in octave 0
  semis = [key1, key2].map {|k| note2semi(k.to_s + '0')}
  @semi_for_g ||= note2semi('g0')
  if strategy == :minimum_distance
    # effectively move first note/semi an octave lower or higher, if
    # this gives smaller distance
    dsemi = semis[0] - semis[1]
    dsemi -= 12 if dsemi > 6
    dsemi += 12 if dsemi < -6
  elsif strategy == :g_is_lowest
    # move notes/semis up until they are above g0. This strategy is
    # useful for comparing keys of harps, where the g harp is normally
    # the lowest
    semis.map! {|s| s < @semi_for_g ? s + 12 : s}
    dsemi = semis[0] - semis[1]
  else
    fail "Internal error: unknown strategy #{strategy}"
  end
  dsemi
end
