#
#  Non-interactive tools
#

def do_tools to_handle

  $lick_file ||= get_lick_file
  tools_allowed = {'transpose' => 'transpose a sequence of notes between keys',
                   'shift' => 'shift a sequence of notes by the given number of semitones',
                   'keys' => 'print a chart with keys and positions',
                   'intervals' => 'print all known intervals',
                   'chords' => 'print chords i, iv and v',
                   'search-in-licks' => 'search given sequence of holes (or equiv) among licks',
                   'search' => nil,
                   'chart' => 'harmonica chart',
                   'edit-licks' => "invoke editor on your lickfile #{$lick_file}",
                   'el' => nil,
                   'edit-config' => "invoke editor on your personal config file #{$early_conf[:config_file_user]}",
                   'ec' => nil,
                   'transcribe' => 'transcribe given lick or music-file approximately',
                   'trans' => nil,
                   'notes' => 'print notes of major scale for given key'}

  tool = match_or(to_handle.shift, tools_allowed.keys) do |none, choices|
    mklen = tools_allowed.keys.map(&:length).max
    puts "\nArgument for mode 'tools' must be one of those listed below,\nnot #{none}#{not_any_source_of}\n\n"
    tools_allowed.each do |k,v|
      puts "    #{k.rjust(mklen)} : #{v || 'the same'}"
    end
    puts "\n" + $for_usage
    err 'See above'
  end

  case tool
  when 'keys'
    tool_key_positions to_handle
  when 'transpose'
    tool_transpose to_handle
  when 'shift'
    tool_shift to_handle
  when 'intervals'
    tool_intervals to_handle
  when 'chords'
    tool_chords to_handle
  when 'search-in-licks', 'search'
    tool_search to_handle
  when 'chart'
    tool_chart to_handle
  when 'edit-licks', 'el'
    tool_edit_licks to_handle
  when 'edit-config', 'ec'
    tool_edit_config to_handle
  when 'transcribe', 'trans'
    tool_transcribe to_handle
  when 'notes'
    tool_notes to_handle
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

  err "Need at least two additional arguments: a second key and at least one hole (e.g. 'g -1'); '#{to_handle.join(' ')}' is not enough" unless to_handle.length > 1

  key_other = to_handle.shift
  err "Second key given '#{key_other}' is invalid" unless $conf[:all_keys].include?(key_other)
  dsemi = diff_semitones($key, key_other, :g_is_lowest)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
  end

  puts
  puts "Transposing holes and notes from key #{$key} to #{key_other} by #{describe_inter_semis(-dsemi)};"
  puts "holes change but notes and pitch stay the same:"
  puts
  puts
  cols = Array.new
  cols << ['Holes', 'Notes', 'new Holes', 'Oct up', 'Oct down']
  to_handle.each do |hole|
    cols << [hole,
             $harp[hole][:note],
             [0, +12, -12].map do |shift|
               $semi2hole[$harp[hole][:semi] + dsemi + shift] || '*'
             end].flatten
  end
  print_transposed(cols, [2])
  puts
end


def tool_shift to_handle

  err "Need at least two additional arguments: a number of semitones and at least one hole (e.g. '7st -1'); '#{to_handle.join(' ')}' is not enough" unless to_handle.length > 1

  inter = to_handle.shift
  dsemi = $intervals_inv[inter] ||
          ((md = inter.match(/^[+-]?\d+st?$/)) && md[0].to_i) ||
          err("Given argument #{inter} is neither a named interval (one of: #{$intervals_inv.keys.join(',')}) nor a number of semitones (e.g. 12st)")

  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
  end

  puts
  puts "Shifting holes and notes by #{describe_inter_semis(dsemi)}:"
  puts
  puts
  cols = Array.new
  cols << ['Holes given', 'Notes', 'Holes shifted', 'Notes shifted', 'Oct up', 'Oct down']
  to_handle.each do |hole|
    cols << [hole,
             $harp[hole][:note],
             semi2note($harp[hole][:semi] + dsemi),
             [0, +12, -12].map do |shift|
               $semi2hole[$harp[hole][:semi] + dsemi + shift] || '*'
             end].flatten
    cols[-1][2], cols[-1][3] = cols[-1][3], cols[-1][2]
  end
  print_transposed(cols, [2,3])
  puts
end


def print_transposed cols, emphasis

  max_in_col = Array.new
  cols.each do |cells|
    max = 0
    cells.each do |cell|
      max = [max, cell.length].max
    end
    max_in_col << max
  end

  lines = Array.new(cols[0].length, '')
  cols.each_with_index do |cells, idx_cols|
    cells.each_with_index do |cell, idx_lines|
      lines[idx_lines] += cell.rjust(max_in_col[idx_cols] + 2)
      lines[idx_lines] += ': ' if idx_cols == 0
    end
  end

  lines.each_with_index do |line, idx|
    if emphasis.include?(idx)
      print "\e[0m\e[32m"
    else
      print "\e[2m"
    end
    puts line
    print "\e[0m\n"
  end
end


def tool_intervals to_handle

  err "Tool 'intervals' does not allow additional arguments" if to_handle.length > 0

  puts
  puts "Known intervals: semitones and various names"
  puts
  $intervals.each do |st, names|
    puts " %3dst: #{names.join(', ')}" % st
  end
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
                 ( only_holes[idx + search.length ...] || '') + "\e[0m" 
            count += 1
            break
          end
        end
      end
    end
  end
  puts "\n#{count} matches.\n\n"
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
    print_in_columns chord_st.map {|st| ( $semi2hole[$min_semi + st] || '--')}, pad: :fill
    print_in_columns chord_st.map {|st| semi2note($min_semi + st)}, pad: :fill
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
    to_print << :chart_inter_semis 
    $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
    $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
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


def tool_edit_config to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0

  system($editor + ' ' + $early_conf[:config_file_user])
  puts "\nEdited \e[0m\e[32m#{$early_conf[:config_file_user]}\e[0m\n\n"
end


def tool_transcribe to_handle

  err "need a single argument" if to_handle.length == 0
  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 1

  $all_licks, $licks = read_licks

  puts
  to_play = if File.exist?(to_handle[0])
              puts "Assuming this file is in key of #{$key}; please specify\ncorrect key on commandline if not."
              to_handle[0]
            elsif lick = $all_licks.find {|l| l[:name] == to_handle[0]}
              err "Lick #{lick[:name]} has no recording" unless lick[:rec]
              puts "Lick is for harp key of #{lick[:rec_key]}."
              if lick[:rec_key] != $key
                $key = lick[:rec_key]
                # change $key, etc
                set_global_vars_late
                set_global_musical_vars
              end
              "#{$lick_dir}/recordings/#{lick[:rec]}"
            else
              err "Given agument '#{to_handle}' is neither a file to play nor the name of a lick"
            end

  puts "\n\e[2mScanning #{to_play} with aubiopitch ...\e[0m"
  cmd = get_pipeline_cmd(:sox, to_play)
  _, ppl_out_err, wait_thr = Open3.popen2e(cmd)
  good_lines = Array.new
  bad_lines = Array.new
  while wait_thr.alive?
    line = ppl_out_err.gets
    next unless line
    begin
      good_lines << line.split(' ',2).map {|f| Float(f)}
    rescue ArgumentError
      bad_lines << line
    end
  end
  exst = wait_thr.value.exitstatus
  if good_lines.length == 0 || ( exst && exst != 0 )
    err "Command returnd #{exst} and produced no usable output:\n#{cmd}\n" +
        if bad_lines.length 
          bad_lines.map {|l| " >> #{l}"}.join
        else
          ''
        end
  end
  puts "\e[2mdone.\e[0m"

  # we do not require a calibration for tools generally; so do it late here
  $freq2hole = read_calibration

  # form batches with he same note
  batched = [[[0, nil]]]
  good_lines.each do |time, freq|
    hole = describe_freq(freq)[0]
    if hole == batched[-1][-1][1]
      batched[-1] << [time, hole]
    else
      batched << [[time, hole]]
    end
  end

  # minimum number of consecutive equal samples needed
  mincons = [5, 0.2 / $time_slice_secs].max.to_i

  # keep only these batches, that are notes and played long enough
  lasting = Array.new
  batched.each do |batch|
    if batch[0][1] && batch.length > mincons
      lasting << [batch[0], batch[-1][0] - batch[0][0]].flatten
    end
  end

  puts "\n\nHoles found at secs:"
  puts
  # construct this alongside and use it later
  ts_with_holes_durations = Array.new
  line = '  '
  line_len = 2
  lasting.each_with_index do |thl, idx| # thl = timestamp, hole, length

    sketch_du = " %s#{thl[1]} %s(#{'%.1f' % thl[2]})  %s"
    field_du = sketch_du % ["\e[0m\e[32m", "\e[0m\e[2m", "\e[0m"]
    ts_with_holes_durations << [thl[0], field_du]

    sketch_ts = " %s#{'%3.1f' % thl[0]}:%s #{thl[1]}  %s"
    field_ts = sketch_ts % ["\e[0m\e[2m", "\e[0m\e[32m", "\e[0m"]
    field_ts_len = (sketch_ts % ['', '', '']).length
    if line_len + field_ts_len > $term_width - 2 
      puts line
      line = '  ' + field_ts
      line_len = 2 + field_ts_len
    else
      line += field_ts
      line_len += field_ts_len
    end
  end
  puts line

  # if necessary we have changed our key to match the lick
  print "\nPlaying \e[2m(as recorded, for a #{$key}-harp)\e[0m:"
  play_recording_and_handle_kb_simple to_play, true, ts_with_holes_durations
  puts "\n\n\n"

end


def tool_notes to_handle

  err "Tool 'notes' needs a key as an additional argument" if to_handle.length != 1
  harp_key = to_handle[0].downcase
  err "Key #{to_handle[0]} is unknown among #{$conf[:all_keys]}" unless $conf[:all_keys].include?(harp_key)

  puts
  puts "Notes of major scale starting at #{harp_key} (with semitone \e[2mdiffs\e[0m and \e[32mfifth\e[0m):"
  puts
  ssemi = note2semi(harp_key + '4')
  steps = [0,2,4,5,7,9,11,12]
  print '  '
  notes = steps.map {|dsemi| semi2note(ssemi + dsemi)}.map {|n| n[0 ... -1]}
  notes.each_with_index do |n,idx|
    print "\e[32m" if idx == 4
    print n + "\e[0m   "
  end
  puts

  diffs = []
  steps.each_cons(2) {|x,y| diffs << y - x}
  print "\e[2m  "
  notes.each do |n|
    print ' ' * n.length
    print ' '
    print diffs.shift
    print ' '
  end
  puts "\e[0m"
  puts
  
end


