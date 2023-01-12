#
#  Non-interactive tools
#

def do_tools to_handle

  tools_allowed = %w(positions transpose chart chords print)
  tool = match_or(to_handle.shift, tools_allowed) do |none, choices|
    err "Argument for mode 'tools' must be one of #{choices}, not #{none}; #{$for_usage}"
  end

  case tool
  when 'positions'
    tool_positions to_handle
  when 'transpose'
    tool_transpose to_handle
  when 'chords'
    tool_chords to_handle
  when 'chart'
    tool_chart to_handle
  when 'print'
    tool_print to_handle
  else
    err "Internal error: Unknown tool '#{tool}'"
  end

end


def tool_positions to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0
  
puts <<EOCHART

  | Key of Song  |              |              |              |
  | or Key       | Key of Harp  | Key of Harp  | Key of Harp  |
  | of Harp in   | 2nd Position | 3rd Position | 4th Position |
  | 1st Position |              |              |              |
  |--------------+--------------+--------------+--------------|
  | G            | C            | F            | Bf           |
  |--------------+--------------+--------------+--------------|
  | Af           | Df           | Fs           | B            |
  |--------------+--------------+--------------+--------------|
  | A            | D            | G            | C            |
  |--------------+--------------+--------------+--------------|
  | Bf           | Ef           | Af           | Cs           |
  |--------------+--------------+--------------+--------------|
  | B            | E            | A            | D            |
  |--------------+--------------+--------------+--------------|
  | C            | F            | Bf           | Ef           |
  |--------------+--------------+--------------+--------------|
  | Cs           | Fs           | B            | E            |
  |--------------+--------------+--------------+--------------|
  | D            | G            | C            | F            |
  |--------------+--------------+--------------+--------------|
  | Ef           | Af           | Cs           | Fs           |
  |--------------+--------------+--------------+--------------|
  | E            | A            | D            | G            |
  |--------------+--------------+--------------+--------------|
  | F            | Bf           | Ef           | Af           |
  |--------------+--------------+--------------+--------------|
  | Fs           | B            | E            | A            |

EOCHART
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
  $charts[:chart_notes].each_with_index do |row, ridx|
    print '  '
    row[0 .. -2].each_with_index do |cell, cidx|
      hole = $note2hole[$charts[:chart_notes][ridx][cidx].strip]
      print cell
    end
    puts "\e[0m\e[2m#{row[-1]}\e[0m"
  end
  puts
end


def tool_print to_handle
  $all_licks, $licks = read_licks
  holes, lnames, snames, special = partition_to_play_or_print(to_handle)
  err "Cannot print these special arguments: #{special}" if special.length > 0
  
  puts "\nType is #{$type}, key of #{$key}."
  puts
  
  if holes.length > 0

    puts 'Holes given as arguments:'
    puts
    print_holes_and_notes holes

  elsif snames.length > 0

    puts 'Scales given as arguments:'
    puts
    snames.each do |sname|
      puts " #{sname}:"
      puts
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      print_holes_and_notes scale_holes
    end
      
  elsif lnames.length > 0

    puts 'Licks given as arguments:'
    puts
    lnames.each do |lname|
      puts " #{lname}:"
      puts
      lick = $licks.find {|l| l[:name] == lname}
      print_holes_and_notes lick[:holes]
    end

  end

  puts
end


def print_holes_and_notes holes
  print_in_columns holes
  puts
  print_in_columns holes.map {|h| $hole2note[h]}
  puts
end
