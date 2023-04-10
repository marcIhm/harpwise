#
#  Non-interactive tools
#

def do_tools to_handle

  tools_allowed = %w(keys positions transpose chart chords print)
  tool = match_or(to_handle.shift, tools_allowed) do |none, choices|
    err "Argument for mode 'tools' must be one of #{choices}, not #{none}; #{$for_usage}"
  end

  case tool
  when 'keys', 'positions'
    tool_key_positions to_handle
  when 'transpose'
    tool_transpose to_handle
  when 'chords'
    tool_chords to_handle
  when 'chart'
    tool_chart to_handle
  else
    err "Internal error: Unknown tool '#{tool}'"
  end

end


def tool_key_positions to_handle
  
  err "Can handle only one (optional) argument, not these: #{to_handle}" if to_handle.length > 1
  if to_handle.length == 1
    center_key = to_handle[0].downcase
    err "Key #{to_handle[0]} is unknown among #{$conf[:all_keys]}" unless $conf[:all_keys].include?(center_key)
  else
    center_key = 'c'
  end
  lines = File.read("#{$dirs[:install]}/resources/keys-positions.org").lines
  center_idx = 0
  lines.each do |line|
    next unless line['%s']
    break if line.split('|')[1].downcase.match?(/\b#{center_key}\b/)
    center_idx += 1
  end

  idx = 0
  puts
  lines.each do |line|
    if line['%s']
      if idx == center_idx 
        print "\e[0m\e[32m"
      elsif line.downcase.match?(/\b#{center_key}\b/)
        line.gsub!(/\b(#{center_key})\b/i, "\e[0m\e[34m" + '\1' + "\e[0m")
      end
      print line % (idx - center_idx).to_s.rjust(3)
      print "\e[0m"
      idx += 1
    else
      print line
    end
  end
  puts
end


def tool_transpose to_handle

  err "Need at least two additional arguments: a second key and at least one hole (e.g. 'g -1'); #{to_handle.inspect} is not enough" unless to_handle.length > 1

  key_other = to_handle.shift
  err "Second key given '#{key_other}' is invalid" unless $conf[:all_keys].include?(key_other)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp" unless $harp_holes.include?(hole)
  end

  dsemi = diff_semitones($key, key_other, :g_is_lowest)
  puts
  puts "The distance between keys #{$key} and #{key_other} is #{-dsemi} semitones."
  puts
  print <<EOHEAD
  | Hole for the Key of #{$key}
  |        | Note for this key
  |        |        | Hole for the Key of #{key_other}
  |        |        |        | One Octave up
  |        |        |        |        | One Octave down
EOHEAD
  template = '  | %6s | %6s | %6s | %6s | %6s |'
  hline = '  |' + '-' * ( (template % Array.new(5)).length - 4 ) + '|'
  to_handle.each do |hole|
    puts hline
    puts template % [hole,
                     $harp[hole][:note],
                     [0, -12, +12].map do |shift|
                       $semi2hole[$harp[hole][:semi] + dsemi + shift] || '*'
                     end].flatten
  end
  puts
  puts
end


def tool_chords to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0

  puts "\nChords for harp in key of #{$key} played in second position:\n\n"
  # offset of notes of major scale against base note; computed from
  # whole- and half-note steps
  scale_semi_tones = [2, 2, 1, 2, 2, 2, 1, 2].inject([0]) {|memo, elem| memo << memo[-1] + elem; memo}
  # offset for playing in second position i.e. for staring with the fifth note
  offset = scale_semi_tones[5-1]
  names = %w(i iv v)
  [[1, 3, 5], [4, 6, 8], [5, 7, 9]].each do |chord|
    chord_st = chord.map do |i|
      semi = offset + scale_semi_tones[i-1]
      semi -= 12 if $semi2hole[$min_semi + semi - 12]
      semi
    end.sort
    puts "chord-#{names[0]}:"
    print_in_columns chord_st.map {|st| ( $semi2hole[$min_semi + st] || '--') + ' '}
    print_in_columns chord_st.map {|st| semi2note($min_semi + st) + ' '}
    puts
    names.shift
  end

end


def tool_chart to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0

  puts
  puts
  to_print = [:chart_notes]
  to_print << :chart_scales if $used_scales[0] != 'all'
  if $opts[:ref]
    to_print << :chart_intervals 
    $charts[:chart_intervals] = get_chart_with_intervals
  end
  to_print.each do |tp|
    puts tp.to_s + ':'
    $charts[tp].each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        print cell
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
    puts
  end
  puts
end
