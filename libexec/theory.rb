
module Theory
  extend self

  def musical_event? hole_or_note, type = :general
    has_paren = hole_or_note[0] == '(' && hole_or_note[-1] == ')'
    has_brack = hole_or_note[0] == '[' && hole_or_note[-1] == ']'
    has_head = ['.', '~'].include?(hole_or_note[0])
    is_comma = [',', ';'].include?(hole_or_note)
    case type
    when :general
      has_paren || has_brack || has_head || is_comma
    when :secs
      return false unless has_paren
      return false unless hole_or_note[-2] == 's'

      begin
        !!Float(hole_or_note[1..-3])
      rescue StandardError
        false
      end
    else
      err "Internal error: #{type}"
    end
  end

  def get_musical_duration hole_or_note
    duration = ( $opts[:fast] ? 0.5 : 1.0)
    return duration unless musical_event?(hole_or_note)
    return duration unless hole_or_note[-2..-1] == 's)'

    begin
      Float(hole_or_note[1..-3])
    rescue StandardError
      duration
    end
  end
  
  def file2scale file, type = $type
    $scale_files_templates.each do |template|
      %w[holes notes].each do |what|
        parts = (template % [type, '|', what]).split('|')
        return file[parts[0].length..- parts[1].length - 1] if file[parts[0]]
      end
    end
  end

  def scales_for_type type, check, builtin_only: false
    templates = if builtin_only
                  [$scale_files_templates[0]]
                else
                  $scale_files_templates
                end
    files = templates.map do |template|
      Dir[template % [type, '*', '{holes,notes}']]
    end.flatten
    return files.map {|file| file2scale(file, type)}.sort unless check

    scale2file = Hash.new
    files.each do |file|
      scale = file2scale(file, type)
      err "Duplicate scale   #{scale}   has already been defined in:\n#{scale2file[scale]}\ncannot redefine it in:\n#{file}"  if scale2file[scale]
      scale2file[scale] = file
    end
    [scale2file.keys.sort, scale2file]
  end

  def describe_scales_maybe scales, _type
    desc = Hash.new
    count = Hash.new
    scales.each do |scale|
      _, holes_rem = YAML.load_file($scale2file[scale]).partition {|x| x.is_a?(Hash)}
      holes = holes_rem.map {|hr| hr.split[0]}
      desc[scale] = "holes #{holes.join(',')}"
      count[scale] = holes.length
    rescue Errno::ENOENT, Psych::SyntaxError
    end
    [desc, count]
  end  

  def holes_equiv? h1, h2
    if h1.is_a?(String) && h2.is_a?(String)
      h1 == h2 || $harp[h1][:equiv].include?(h2)
    else
      false
    end
  end

  def describe_freq freq
    # Be able to return the same result as before rather quick
    return $desc_freq_cache if $desc_freq_cache && freq >= $desc_freq_cache_lb && freq < $desc_freq_cache_ub

    minfr = $harp[$harp_holes[0]][:freq]
    maxfr = $harp[$harp_holes[-1]][:freq]
    # pseudo frequencies to aid analysis
    freqs = ([minfr * 3 / 4,
              maxfr * 4 / 3] + $freq2hole.keys).sort

    freqs.each_cons(3) do |pfr, fr, nfr|
      lb = (pfr + fr) / 2
      ub = (fr + nfr) / 2
      return [nil, nil, nil, nil] if freq < lb

      next unless freq >= lb && freq < ub

      $desc_freq_cache = [$freq2hole[fr], lb, fr, ub]
      $desc_freq_cache_lb = lb
      $desc_freq_cache_ub = ub
      return $desc_freq_cache
    end
    [nil, nil, nil, nil]
  end

  def note2semi note, range = (0..9), graceful = false, shadowed: false
    note = note.downcase
    begin
      raise ArgumentError.new("note '#{note}' should end with a single digit in range #{range}") unless range.include?(note[-1].to_i)

      idx = $notes_with_sharps.index(note[0..-2]) ||
            $notes_with_flats.index(note[0..-2]) ||
            (shadowed && $sharps_flats_shadowed.index(note[0..-2])) or
        raise ArgumentError.new("non-digit part of note '#{note}' is none of #{$notes_with_sharps} or #{$notes_with_flats}")
      12 * note[-1].to_i + idx - 57
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
      raise "Internal error: #{sharps_or_flats}"
    end
  end

  # normalize to sharp or flat (hence "sf_") depending on $opts[:sharps_or_flats]
  def sf_norm note, shadowed: false
    semi2note(note2semi(note, shadowed: shadowed))
  end

  def semi2freq_et semi
    440 * 2**( semi / 12.0 )
  end

  def cents_diff f1, f2
    # see https://ohw.se/hca/tuning-theory/#3.2
    1200 * Math.log(f1.to_f / f2) / Math.log(2)
  end

  def notes_equiv note
    no_digit = !note[-1].match?(/[0-9]/)
    note += '0' if no_digit
    semi = note2semi(note)
    ns = semi2note(semi, :sharps)
    nf = semi2note(semi, :flats)
    if no_digit
      ns = ns[0..-2]
      nf = nf[0..-2]
    end
    notes = [note]
    notes << ns if ns != note
    notes << nf if nf != note
    notes
  end

  def describe_inter hon1, hon2, prefer_plus: false, sane: false
    if sane
      return [nil, nil, nil, nil] if !hon1 || !hon2
    elsif !hon1 || !hon2 || Theory::musical_event?(hon1) || Theory::musical_event?(hon2)
      return [nil, nil, nil, nil]
    end
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
      ["#{dsemi_shifted} st" + oct_shift_clause,
       inter[0] && ( inter[0] + oct_shift_clause ),
       inter[1] && ( inter[1] + oct_shift_clause ),
       dsemi]
    else
      inter = $intervals[dsemi] || [nil, nil]
      ["#{dsemi} st",
       inter[0],
       inter[1],
       dsemi]
    end
  end

  def describe_inter_keys key1, key2
    dsemi = note2semi(key1 + '0') - note2semi(key2 + '0')
    describe_inter_semis(dsemi)
  end

  def describe_inter_semis dsemi
    inter = $intervals[dsemi] || [nil, nil]
    "#{dsemi} semitones" +
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
      raise "Internal error: unknown strategy #{strategy}"
    end
    dsemi
  end  
end
