#
#  Non-interactive tools
#

def do_tools to_handle

  $lick_file ||= get_lick_file
  tools_allowed = {'transpose' => 'transpose a sequence of notes between keys',
                   'keys' => 'print a chart with keys and positions',
                   'chords' => 'print chords i, iv and v',
                   'search-in-licks' => 'search given sequence of holes (or equiv) among licks',
                   'search' => nil,
                   'chart' => 'harmonica chart',
                   'edit-licks' => "invoke editor on your lickfile #{$lick_file}"}

  tool = match_or(to_handle.shift, tools_allowed.keys) do |none, choices|
    mklen = tools_allowed.keys.map(&:length).max
    puts "\nArgument for mode 'tools' must be one of:\n\n"
    tools_allowed.each do |k,v|
      puts "    #{k.rjust(mklen)} : #{v || 'the same'}"
    end
    puts "\n,not #{none}; #{$for_usage}\n"
    err 'See above'
  end

  case tool
  when 'keys'
    tool_key_positions to_handle
  when 'transpose'
    tool_transpose to_handle
  when 'chords'
    tool_chords to_handle
  when 'search-in-licks', 'search'
    tool_search to_handle
  when 'chart'
    tool_chart to_handle
  when 'edit-licks'
    tool_edit_licks to_handle
  else
    err "Internal error: Unknown tool '#{tool}'"
  end

end


def tool_key_positions to_handle

  harp_key = 'c'
  harp_color = "\e[0m\e[32m"
  song_key = nil
  song_color = ''

  err "Can handle only one or two (optional) argument, not these: #{to_handle}" if to_handle.length > 2

  if to_handle.length >= 1
    harp_key = to_handle[0].downcase
    err "Key #{to_handle[0]} is unknown among #{$conf[:all_keys]}" unless $conf[:all_keys].include?(harp_key)
    harp_color += "\e[7m"
  end

  if to_handle.length == 2
    song_key = to_handle[1].downcase
    err "Key #{to_handle[1]} is unknown among #{$conf[:all_keys]}" unless $conf[:all_keys].include?(song_key)
    song_color = "\e[0m\e[34m\e[7m"
  end

  lines = File.read("#{$dirs[:install]}/resources/keys-positions.org").lines
  harp_idx = 0
  lines.each do |line|
    next unless line['%s']
    break if line.split('|')[1].downcase.match?(/\b#{harp_key}\b/)
    harp_idx += 1
  end

  idx = 0
  puts
  lines.each do |line|
    print '  '
    if line['%s']
      line = colorize_word_cell(line, song_key, song_color,
                                idx == harp_idx  ?  harp_color  :  "\e[0m")
      print line % (idx - harp_idx).to_s.rjust(3)
      print "\e[0m"
      idx += 1
    else
      print line
    end
  end
  puts
end


def colorize_word_cell plain, word, color_word, color_normal
  colored = "\e[0m"
  plain.strip.split('|').each_with_index do |field, idx|
    colored += if word && idx >= 2 && field.downcase.match?(/\b#{word}\b/)
                 color_word
               else
                 color_normal
               end
    colored += field + "\e[0m|"
  end
  return colored + "\n"
end


def tool_transpose to_handle

  err "Need at least two additional arguments: a second key and at least one hole (e.g. 'g -1'); #{to_handle.inspect} is not enough" unless to_handle.length > 1

  key_other = to_handle.shift
  err "Second key given '#{key_other}' is invalid" unless $conf[:all_keys].include?(key_other)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
  end

  dsemi = diff_semitones($key, key_other, :g_is_lowest)
  puts
  puts "The distance between keys #{$key} and #{key_other} is #{-dsemi} semitones."
  puts
  print <<EOHEAD
  | Hole for the Key of \e[32m#{$key}\e[0m
  |        | Note for this key
  |        |        | Hole for the Key of \e[32m#{key_other}\e[0m
  |        |        |        | One octave UP
  |        |        |        |        | One octave DOWN
EOHEAD
  template = "  | \e[32m%6s\e[0m | \e[32m%6s\e[0m | \e[32m%6s\e[0m | \e[32m%6s\e[0m | \e[32m%6s\e[0m |"
  hline = '  |' + '-' * ( (template % Array.new(5)).length - 49 ) + '|'
  to_handle.each do |hole|
    puts hline
    puts template % [hole,
                     $harp[hole][:note],
                     [0, +12, -12].map do |shift|
                       $semi2hole[$harp[hole][:semi] + dsemi + shift] || '*'
                     end].flatten
  end
  puts
  puts
end


def tool_search to_handle

  err "Need at least one hole to search (e.g. '-1'); #{to_handle.inspect} is not enough" unless to_handle.length >= 1

  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
  end
  # make each hole an array and add equivs (e.g. -2 becomes [-2, +3])
  holes_with_equivs = to_handle.map {|h| [h,$harp[h][:equiv]].flatten}

  # list_of_searches becomes a list of equivalent lists of holes to search
  searches = holes_with_equivs.inject([[]]) do |list_of_searches, equivs|
    list_of_searches.map do |search|
      equivs.map do |hole|
        search.clone.append(hole)
      end
    end.flatten(1)
  end.map do |search|
    search.join(' ')
  end

  $all_licks, $licks = read_licks

  puts "\nList of licks containing   #{to_handle.join(', ')}   or equivalent:\n\n"
  count = 0
  maxname = 0
  [:max, :print].each do |what|
    $licks.each do |lick|
      searches.each do |search|
        only_holes = lick[:holes].reject {|l| musical_event?(l)}.join(' ')
        idx = only_holes.index(search)
        if idx
          case what
          when :max
            maxname = [maxname, lick[:name].length].max
          when :print
            puts '  ' + lick[:name].rjust(maxname) + ":  \e[2m" +
                 only_holes[0, idx] + "\e[0m\e[32m" + 
                 only_holes[idx, search.length] + "\e[0m\e[2m" +
                 only_holes[idx + search.length + 1 ...] + "\e[0m" 
            count += 1
            break
          end
        end
      end
    end
  end
  puts "\n#{count} matches\n\n"
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


def tool_edit_licks to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0

  system($editor + ' ' + $lick_file)
  puts "\nEdited \e[0m\e[32m#{$lick_file}\e[0m\n\n"
end
