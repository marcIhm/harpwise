#
#  Non-interactive tools
#

def do_tools to_handle

  $lick_file ||= get_lick_file

  # common error checking
  err_args_not_allowed(to_handle) if %w(edit-licks edit-config chords).include?($extra) && to_handle.length > 0

  case $extra
  when 'transpose'
    tool_transpose to_handle
  when 'shift'
    tool_shift to_handle
  when 'shift-to-groups'
    tool_shift_to_groups to_handle
  when 'keys'
    tool_key_positions to_handle
  when 'spread-notes'
    tool_spread_notes to_handle
  when 'make-scale'
    tool_make_scale to_handle
  when 'search-holes-in-licks'
    tool_search_holes_in_licks to_handle
  when 'search-lick-in-scales'
    tool_search_lick_in_scales to_handle
  when 'licks-from-scale'
    tool_licks_from_scale to_handle
  when 'chart'
    tool_chart to_handle
  when 'edit-licks'
    tool_edit_file $lick_file, to_handle
  when 'edit-config'
    tool_edit_file $early_conf[:config_file_user], to_handle
  when 'transcribe'
    tool_transcribe to_handle
  when 'translate'
    tool_translate to_handle
  when 'notes-major', 'notes'
    tool_notes to_handle
  when 'interval', 'inter'
    puts
    s1, s2 = normalize_interval(to_handle)
    print_interval s1, s2
    puts
  when 'progression', 'prog'
    tool_progression to_handle
  when 'chords'
    tool_chords
  when 'diag', 'diag1'
    tool_diag1
  when 'diag2'
    tool_diag2
  when 'diag3'
    tool_diag3
  when 'diag-hints'
    tool_diag_hints
  when 'utils', 'utilities'
    tool_utils
  else
    fail "Internal error: unknown extra '#{$extra}'"
  end
end


def tool_key_positions to_handle

  if $opts[:terse]
    err "This tool does not accept arguments, if option --terse is present" if to_handle.length > 0
    puts
    puts "\e[2mMatching keys of most common richter harmonicas,\nplayed in second position, with keys of songs:"
    puts
    puts "\e[2m  Harp\e[0m      G   A   C   D"
    puts "\e[2m  Song\e[0m      D   E   G   A"
    puts
    puts
    return
  end
  
  harp_key = $key
  harp_color = if $source_of[:key] == 'command-line'
                 "\e[0m\e[32m"
               else
                 "\e[0m"
               end
  song_key = nil
  song_color = ''

  err "Can handle only one or two (optional) argument, not these: #{to_handle}" if to_handle.length > 2

  if to_handle.length >= 1 && to_handle[0] != '.'
    song_key = to_handle[0].downcase
    err "Key   #{to_handle[0]}   is neither '.' nor any known key  #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(song_key)
    song_color = "\e[0m\e[34m\e[7m"
  end

  if to_handle.length >= 2 && to_handle[1] != '.'
    harp_key = to_handle[1].downcase
    err "Key   #{to_handle[1]}   is neither '.' not any known key  #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(harp_key)
    harp_color = "\e[0m\e[32m\e[7m"
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
      print "\e[0m\e[2m" + line + "\e[0m"
    end
  end
  puts
end


def tool_spread_notes notes
  if !$opts[:terse]
    puts
    puts "\e[2mAll holes, that produce the given notes in any octave:"
    puts "As a chart:\e[0m"
    puts
  end
  notes.map! {|n| n.gsub(/\d+$/,'')}
  notes.each do |note|
    err "Note   #{note}   is unknown among   #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(note)
  end
  notes.map! {|n| sf_norm(n + '4')[0..-2]}
  holes = Array.new
  notes.each do |note|
    holes.append(*$bare_note2holes[note])
  end
  holes.sort_by! {|h| $harp[h][:semi]}.map! {|h| $harp[h][:canonical]}.uniq!
  
  if $opts[:terse]
    puts holes.join('  ')
    exit
  end

  print_chart_with_notes notes, strip_octave: true
  puts
  puts "\e[2mAs a list (usable as an adhoc scale):\e[0m"
  puts
  puts '  ' + holes.join('  ')
  puts
end


def tool_make_scale holes
  err "Need at least one hole as an argument" if holes.length == 0
  holes.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp:   #{$harp_holes.join('  ')}" unless $harp_holes.include?(hole)
  end
  holes = holes.uniq.sort_by {|h| $harp[h][:semis]}
  room = "\n\n\e[2A"
  line = "\n" + ' ' * ( $term_width / 8 ) + "\e[2m" + '-' * ( $term_width / 2 ) + "\e[0m\n\n"
  cont = {'holes' => holes}
  puts
  puts "Creating new user-defined scale from given holes and from answers to a few questions ..."

  print line
  print room
  print "Please enter name of the new scale (required): "
  sname = gets.chomp.strip.gsub(/[^[:print:]]/,'').downcase
  err "Given new name   '#{sname}'   contains spaces" if sname[' ']
  err "Given new name   '#{sname}'   is too short (must be three chars or more)" if sname.length < 3
  err "Given new name   '#{sname}'   is already the name of an existing builtin scale; these builtin scales cannot be overwritten. Try   'harpwise print scales'   for a list of all known scales." if $all_scales.include?(sname) && !$scale2file[sname][$dirs[:data]]
  sfile = $scale_files_templates[1] % [$type, sname, 'holes']
  if File.exist?(sfile)
    puts
    puts "Look, the new user-defined scale   '#{sname}'   already exists as a file:\n\n  \e[2m#{sfile}\e[0m"
    puts
    puts "Do you want to overwite it ?"
    print room
    print "Enter 'y' to overwrite, anything else to cancel: "
    answer = gets.chomp.strip
    if answer != 'y'
      puts
      puts "Creation of new scale has been canceled."
      puts
      puts
      exit
    end
  end

  print line
  print room
  print "Please enter 1-2 char short name for the new scale (empty to omit): "
  short = gets.chomp.strip.gsub(/[^[:print:]]/,'')
  err "Given short name   '#{short}'   contains spaces" if short[' ']
  err "Given short name   '#{short}'   is too long (must be 1-2 chars)" if short.length > 2
  cont['short'] = short if short.length > 0
  
  print line
  print room
  print "Please enter description for the new scale\n(multiple words, less than 80 chars, empty to omit): "
  desc = gets.chomp.strip.gsub(/[^[:print:]]/,'')
  err "Given description   '#{desc}'   is too long (#{desc.length} chars > 80)" if desc.length > 80
  cont['desc'] = desc if desc.length > 0

  print line
  print room
  ycont = YAML.dump(cont)
  File.write(sfile, "#\n# User-defined scale\n#\n" + ycont )
  puts "This content:"
  puts
  puts "\e[2m#{ycont}\e[0m"
  puts
  puts "has been written to:\n\n  \e[2m#{sfile}\e[0m"
  puts
  puts "\e[2m(if later you want to remove the scale, just remove this file)\e[0m"
  puts
  puts "New scale   \e[32m'#{sname}'\e[0m   with #{holes.length} holes has been created."
  puts
  puts
end


def colorize_word_cell plain, word, color_word, color_normal
  colored = "\e[0m\e[2m"
  plain.strip.split('|').each_with_index do |field, idx|
    colored += if word && idx >= 2 && field.downcase.match?(/\b#{word}\b/)
                 color_word
               else
                 color_normal
               end
    colored += field + "\e[0m\e[2m|\e[0m"
  end
  return colored + "\n"
end


def tool_transpose to_handle

  err "Need at least two additional arguments: a second key and at least one hole (e.g. 'g -1'); '#{to_handle.join(' ')}' is not enough" unless to_handle.length > 1

  key_other = to_handle.shift
  err "Second key given '#{key_other}' is invalid" unless $conf[:all_keys].include?(key_other)
  dsemi = diff_semitones($key, key_other, strategy: :g_is_lowest)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp:   #{$harp_holes.join('  ')}" unless $harp_holes.include?(hole)
  end

  puts
  puts "Transposing holes and notes from key #{$key} to #{key_other};"
  puts "difference between harps is #{describe_inter_semis(dsemi)};"
  puts "holes change but notes stay the same:"
  puts
  puts
  cols = Array.new
  cols << ['Holes given', 'Notes', 'Holes transposed', 'Oct up', 'Oct down']
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

  to_handle, inter, dsemi = tools_shift_helper(to_handle)  
  
  puts
  puts "Shifting holes by #{describe_inter_semis(dsemi)}:"
  puts
  puts
  cols = Array.new

  heads = ['Holes or']
  cols << ['Notes given', 'as notes', 'Holes shifted', 'Notes shifted', 'Oct up', 'Oct down']
  to_handle.each do |hon|
    note = $harp.dig(hon,:note) || hon
    cols << [hon,
             note,
             semi2note(note2semi(note) + dsemi),
             [0, +12, -12].map do |shift|
               $semi2hole[note2semi(note) + dsemi + shift] || '*'
             end].flatten
    cols[-1][2], cols[-1][3] = cols[-1][3], cols[-1][2]
  end
  print_transposed(cols, [2,3], heads: heads)
  puts
end


def tool_shift_to_groups to_handle

  to_handle, inter, dsemi = tools_shift_helper(to_handle)
  
  puts
  puts "Shifting holes or notes by #{describe_inter_semis(dsemi)} and showing"
  puts "all holes, that map to the same bare note (i.e. ignoring octaves)"
  puts
  puts
  cols = Array.new
  heads = ['Holes or', nil, 'Bare note', 'Holes with']
  cols << ['Notes given', 'as notes', 'shifted', 'same bare']
  to_handle.each do |hon|
    note = $harp.dig(hon,:note) || hon    
    bare_note_shifted = semi2note(note2semi(note) + dsemi)[0..-2]
    cols << [hon,
             note,
             bare_note_shifted]
    $bare_note2holes[bare_note_shifted].each do |hole|
      cols[-1] << hole
    end
  end
  print_transposed(cols, heads: heads)
  puts
end


def tools_shift_helper to_handle
  err "Need at least two additional arguments: a number of semitones and at least one hole or note (e.g. '7st -1'); '#{to_handle.join(' ')}' is not enough" unless to_handle.length > 1

  inter = to_handle.shift
  dsemi = $intervals_inv[inter] ||
          ((md = inter.match(/^[+-]?\d+st?$/)) && md[0].to_i) ||
          err("Given argument #{inter} is neither a named interval (one of: #{$intervals_inv.keys.reject {_1[' ']}.join(',')}) nor a number of semitones (e.g. 12st)")

  if to_handle.length == 1
    $all_licks, $licks, $all_lick_progs = read_licks
    if lick = $all_licks.find {|l| l[:name] == to_handle[0]}
      to_handle = lick[:holes]
    end
  end

  to_handle.reject! {|h| musical_event?(h)}
  hons = []
  to_handle.each do |hon|
    if note2semi(hon, 2..8, true) || $harp_holes.include?(hon)
      hons << hon
    else
      err("Argument '#{hon}' is neither   a note   nor   " +
          "a hole of a #{$type}-harp:   #{$harp_holes.join('  ')}" +
          ( to_handle.length == 1  ?  "   and not a lick either"  :  '' ))
    end
  end
  return [hons, inter, dsemi]
end


def print_transposed cols, emphasis = nil, heads: nil

  # make sure, that all columns have the same number of elements
  maxlen = cols.map(&:length).max
  cols.each do |col|
    while col.length < maxlen
      col << ''
    end
  end
  
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
      if idx_cols == 0
        lines[idx_lines] += ( cell.length > 0  ?  ': '  :  '  ' )
      end
    end
  end

  lines.each_with_index do |line, idx|
    if emphasis
      if emphasis.include?(idx)
        print "\e[0m\e[32m"
      else
        print "\e[2m"
      end
    else
      print "\e[0m"
    end
    if heads && heads[idx]
      puts heads[idx].rjust(max_in_col[0] + 2)
      head = nil
    end
    puts line
    print "\e[0m\n"
  end
end


def tool_search_holes_in_licks to_handle

  err "Need at least one hole to search (e.g. '-1'); #{to_handle.inspect} is not enough" unless to_handle.length >= 1

  to_handle.reject! {|h| musical_event?(h)}
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp:   #{$harp_holes.join('  ')}" unless $harp_holes.include?(hole)
  end

  search_canon = to_handle.map {|h| $harp[h][:canonical]}

  puts "\nList of licks containing   \e[0m\e[32m#{to_handle.join(' ')}\e[0m   or equivalent:\n\n"
  count = 0
  maxlen = 0
  $all_licks, $licks, $all_lick_progs = read_licks

  [:max, :print].each do |what|
    $licks.each do |lick|
      lick_holes = lick[:holes].reject {|nh| musical_event?(nh)}
      lick_canon = lick_holes.map {|h| $harp[h][:canonical]}
      # check if our search appears within lick
      idx = (0 .. lick_canon.length - search_canon.length).
              find {|ix| lick_canon[ix, search_canon.length] == search_canon}
      if idx
        case what
        when :max
          maxlen = [maxlen, lick[:name].length].max
        when :print
          puts '  ' + lick[:name].rjust(maxlen) + ":\e[2m" +
               # extra padding for non-edge-case
               (idx == 0  ?  ''  :  '  ') +
               [lick_holes[0 ... idx], ["\e[0m\e[32m "],
                lick_holes[idx, search_canon.length], [" \e[0m\e[2m"],
                lick_holes[idx + search_canon.length ..]].
                 flatten.join(' ').strip + "\e[0m" 
          count += 1
        end
      end
    end
  end
  puts "\n#{count} matches.\n\n"
end


def tool_search_lick_in_scales to_handle

  err "Need at least one lick-name or hole to search (e.g. '-1'); #{to_handle.inspect} is not enough" unless to_handle.length >= 1

  holes = if to_handle.length == 1
            $all_licks, $licks, $all_lick_progs = read_licks
            lick = $all_licks.find {|l| l[:name] == to_handle[0]}
            err "Given single argument '#{to_handle[0]}' is not the name of a lick" unless lick
            lick[:holes_wo_events]
          else
            to_handle.each do |hole|
              err "Argument '#{hole}' is not a hole of a #{$type}-harp:   #{$harp_holes.join('  ')}" unless $harp_holes.include?(hole)
            end
            to_handle
          end
  puts
  puts " Given holes: #{holes.join(' ')}"

  holes = holes.map {|h| $harp[h][:canonical]}.uniq.
            sort {|h1,h2| $harp[h1][:semi] <=> $harp[h2][:semi]}
  
  # match against scales
  mt_scales_all = Array.new
  sc_hls = Hash.new
  $all_scales.each do |scale|
    hls = read_and_parse_scale(scale, $harp)
    sc_hls[scale] = hls.map {|h| $harp[h][:canonical]}.uniq.
                      sort {|h1,h2| $harp[h1][:semi] <=> $harp[h2][:semi]}
    mt_scales_all << scale if (holes - sc_hls[scale]).empty?
  end
  

  puts "these unique: #{holes.join(' ')}"
  puts
  puts "Scales containing all given holes:"
  print_in_columns(mt_scales_all, pad: :tabs)
  puts
  puts "Removing each of the given holes to get matches with more scales:"
  puts
  cnt = 0
  holes.each do |hole|
    mt_scales = sc_hls.keys.select {|s| (holes - [hole] - sc_hls[s]).empty?}
    next if mt_scales == mt_scales_all
    puts "Scales containing all given holes but #{hole}:"
    print_in_columns(mt_scales, pad: :tabs)
    cnt += 1
  end
  puts "Nothing found." if cnt == 0
  puts
end


def tool_licks_from_scale to_handle

  $all_licks, $licks, $all_lick_progs = read_licks
  
  th_grouped = to_handle.group_by {|th| recognize_among(th, [:scale, :lick])}
  needed = 'Required arguments are a single scale and optionally the name of a single lick'
  err "#{needed}, but no argument at all has been given" if to_handle.length == 0
  err "#{needed}. Cannot handle these: #{th_grouped[false].join(' ')}" if th_grouped[false]
  err "#{needed}. But no scale has been given." unless th_grouped[:scale]
  err "#{needed}. But more than one scale has been given: #{th_grouped[:scale].join(' ')}" if th_grouped[:scale].length > 1
  err "#{needed}. But more than one lick has been given: #{th_grouped[:lick].join(' ')}" if th_grouped[:lick] && th_grouped[:lick].length > 1

  lick_name = th_grouped[:lick]&.at(0)
  scale = th_grouped[:scale][0]
  scale_holes = read_and_parse_scale(scale, $harp)
  # _cus stands for canonical, uniq, sorted
  scale_holes_cus = scale_holes.map {|h| $harp[h][:canonical]}.uniq.
                      sort {|h1,h2| $harp[h1][:semi] <=> $harp[h2][:semi]}


  if lick_name

    lick = $licks.find {|l| l[:name] == lick_name}

    lick_holes_c = lick[:holes_wo_events].map {|h| $harp[h][:canonical]}
    heads = ["lick  #{lick_name}", "scale  #{scale}"]
    max_len = heads.map(&:length).max
    puts
    print heads[0].rjust(max_len) + ':   '
    cnt = 0
    lick[:holes].each do |h|
      if musical_event?(h) || scale_holes_cus.include?($harp[h][:canonical])
        print "\e[0m\e[32m#{h}\e[0m  "
        cnt += 1
      else
        print "\e[2m#{h}\e[0m  "
      end
    end
    puts
    puts
    puts heads[1].rjust(max_len) + ':   ' + scale_holes.join('  ')
    puts
    pct = (100.0 * cnt / lick_holes_c.length).round(0)
    puts "\e[32m#{cnt}\e[0m of #{lick_holes_c.length} holes (= #{pct} %) are from scale"
    puts
  else
    
    err "First argument #{scale} is not the name of a scale (any of: #{$all_scales.join(', ')})" unless $all_scales.include?(scale)

    licks_empty_cnt = 0
    licks_w_counts = Array.new
    
    licks_ranked = $licks.map do |lick|
      
      # _c stands for canonical
      lick_holes_c = lick[:holes_wo_events].map {|h| $harp[h][:canonical]}
      
      if lick_holes_c.length == 0
        licks_empty_cnt += 1
        next
      end
      
      # using '-' keeps duplicate holes, (as long as they are not from
      # scale, of course); in contrast 'lick_holes_c & scale_holes_cus'
      # does not keep duplicates
      holes_not_in = lick_holes_c - scale_holes_cus

      { name: lick[:name],
        pct_from: ( 100 * ( lick_holes_c.length - holes_not_in.length ) / lick_holes_c.length ).round(0),
        cnt_from: lick_holes_c.length }
      
    end.compact.sort_by! {|x| [x[:pct_from], x[:cnt_from]]}.reverse

    licks_grouped = licks_ranked.group_by {|l| l[:pct_from] / 20}
    max_group = 5
    min_group = 3
    (0 .. min_group - 1).each {|p| licks_grouped.delete(p)}
    
    puts
    puts "#{$licks.length} licks have been checked against scale   #{scale}."
    puts "Below you find the licks, that have   #{min_group * 20}%  or more   of their holes from scale."
    puts "Licks are grouped and sorted by this percentage, also by their length."
    puts

    max_group.downto(min_group).each do |group|
      puts
      puts_underlined "#{group * 20}%" + ( group == max_group  ?  ''  :  ' or more' ) + ':'
      if !licks_grouped[group] || licks_grouped[group].length == 0
        puts '  none'
      else
        print "\e[32m"
        print_in_columns licks_grouped[group].map {|l| l[:name]}, pad: :tabs
        puts
        puts "\e[0mcount: #{licks_grouped[group].length}"
      end
      puts
    end
    puts
    puts "Fore more details about a single lick, invoke again with its name as an additional argument."
    puts
  end
end


def tool_progression to_handle
  err "Need at a base note and some distances, e.g. 'a4 4st 10st'" unless to_handle.length >= 1

  puts
  puts_underlined 'Progression:'
  prog = base_and_delta_to_semis(to_handle)
  holes, notes, abs_semis, rel_semis = get_progression_views(prog)
  
  puts_underlined 'Holes:', '-'
  print_progression_view holes
  
  puts_underlined 'Notes:', '-'
  print_progression_view notes
  
  puts_underlined 'Absolute Semitones (a4 = 0):', '-'
  print_progression_view abs_semis
  
  puts_underlined 'Relative Semitones to first:', '-'
  print_progression_view rel_semis

end


def tool_chords

  puts "\nChords for harp in key of #{$key} played in second position:\n\n"
  st_abs = $maj_sc_st_abs.clone
  # chord-v wraps to next octave, so we need to extend scale
  st_abs << $maj_sc_st_abs[-1] + $maj_sc_st_diff[0]
  # offset for playing in second position i.e. for staring with the fifth note
  offset = st_abs[5-1]
  names = %w(i iv v)
  [[1, 3, 5], [4, 6, 8], [5, 7, 9]].each do |chord|
    chord_st = chord.map do |i|
      semi = offset + st_abs[i-1]
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
  puts
  puts
  holes_or_notes, _, _, _, _, _ = partition_for_mode_or_amongs(to_handle,
                                                               amongs: [:hole, :note],
                                                               extra_allowed: false)

  to_print = [:chart_notes]
  notes = []
  if holes_or_notes.length == 0
    to_print << :chart_scales if $used_scales[0] != 'all'
    if $opts[:ref]
      to_print << :chart_intervals
      to_print << :chart_inter_semis 
      $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
      $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
    end
  else
    notes = holes_or_notes.map {|hon| $harp[hon]&.dig(:note) || hon}
  end
  to_print.each do |tp|
    puts tp[6 .. -1].to_s.capitalize.gsub('_',' ') + ':'
    if tp == :chart_scales
      puts("\e[2m" +
           $used_scales.map do |sc|
             sc + $scale2short[sc].then do |sh|
               (sh && (':' + sh)) || ''
             end
           end.join(',') +
           "\e[0m")
    end
    $charts[tp].each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        if notes.length == 0
          print cell
        elsif notes.include?(cell.strip)
          print cell
        elsif comment_in_chart?(cell)
          print cell
        else
          hcell = ' ' * cell.length
          hcell[hcell.length / 2] = '-'
          print hcell
        end
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
    puts
  end
end


def tool_edit_file file, to_handle = []

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0
  puts "\nInvoking #{$editor} on \e[0m\e[32m#{file}\e[0m\n\n"
  sleep 1 
  exec($editor + ' ' + file)
end


def tool_transcribe to_handle

  err "need a single argument" if to_handle.length == 0
  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 1

  $all_licks, $licks, $all_lick_progs = read_licks

  puts
  to_play = if File.exist?(to_handle[0])
              puts "Assuming this file is in key of #{$key}; please specify\ncorrect key on command line if not."
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

  # for mode tools, we do not require samples generally; so do it late here
  $freq2hole = read_samples

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
  play_recording_and_handle_kb to_play, ts_with_holes_durations
  puts "\n\n\n"

end


def tool_translate to_handle

  err "Tool 'translate' does not accept arguments (because of expected problems with shell-quoting); rather enter some holes when prompted" if to_handle.length > 0

  notations = { parens: {desc: ["Blow is 1, draw is (2), bends are not known (yet)"],
                        example: "(1)  2  (2)  ?  3  ?  ?  (2)"},
                harpwise: {desc: ["The standard notation of harpwise (richter); blow is +1,",
                                  "draw is -2, bends are -1/, -2//, +10/.  All other notations",
                                  "will betranslated into this one."],
                           example: "-1  +2  -2  -3/  +3  -3/  -3//  -2"}, 
                quotes: {desc: ["Blow is 1 or +1, draw is -2, bends are -1', -2\", -3\"', -3'\"",
                                "this notation is e.g. used by harmonica.com"],
                         example: "-1  +2  -2  -3'  3  -3'  -3\"  -2"},
                ricci: {desc: ["Draw has 'd' appended, blow nothing, quotes for bends;",
                               "this notation is used by Jason Ricci"],
                        example: "2d  3'  3d  2  3'  3d  4d  4  3d  2d"},
                notes: {desc: ["Just the notes rather than any harmonica-specific notation;",
                               "you may also try 'harpwise print' for this, as it will give",
                               "much more info."],
                        example: "d4  e4  g4  as4  g4  as4  a4  g4"} }
  
  puts
  puts "These harmonica notations are known \e[2m(example is from the 'St-Luis Blues'):\e[0m"
  notations.each do |nname, nota|
    puts
    puts "  \e[32m#{nname}:\e[0m  \e[2m#{nota[:desc][0]}"
    nota[:desc][1 .. -1].each {|d| puts "      #{d}"}
    puts "    \e[2mExample:  \e[2m#{nota[:example]}\e[0m"
  end
  puts
  puts "Please enter one or many lines of harmonica notation; harpwise will pick"
  puts "the notation, that matches best and will translate the given holes"
  puts "into its own standard notation (richter)."
  puts
  puts "Please note: To allow multi-line input, this will keep reading until"
  puts "you finish your input with two empty lines, i.e. hit RETURN twice."
  puts

  eiar = 0  ## empties in a row
  first_round = true
  nl_after_holes = []
  foreigns = []

  # loop as long as there is input
  begin

    # If user pastes a multi-line input all at once, we dont want to print too many prompts.

    # Remark: we cannot coalasce the two select-statements below, because during sleep, new
    # input might arrive (which is the purpose of this sleep)
    #
    # Terminal-driver normally processes all input until RETURN is hit; so select below will
    # return false on the last line of several pasted lines, if it is not ending with
    # newline
    
    sleep 0.1 unless IO.select([STDIN], nil, nil, 0)
    
    if !IO.select([STDIN], nil, nil, 0)
      # We seem to have no input; but on pasting we might have an incomplete line without
      # newline. So we need to check more thoroughly.
      
      # return input on every char, no wait
      system("stty -echo -icanon min 1 time 0")
      # change in terminal processing affects not only gets, but select too; so the line
      # below will also sense, if there is any input at all, even input not ending with
      # newline
      if IO.select([STDIN], nil, nil, 0)
        # Cursor still at end of line after incomplete input; it should be clear for the
        # user, that he needs to press RETURN
      elsif first_round
        print 'Your input:  '
      elsif eiar == 0
        print "\e[2mYour input (cont.):  \e[0m"
      elsif eiar == 1
        print "\e[2mYour input (empty to finish):  \e[0m"
      end
      # back to normal line-discipline
      system("stty sane")
    end

    fgn = gets.chomp.strip

    # allow continuation lines ending with \; ignore it though
    fgn[-1] = '' if fgn[-1] == '\\'
    eiar = if fgn == ''
             eiar + 1
           else
             0
           end

    foreigns.append(*fgn.split)
    nl_after_holes << foreigns.length if fgn != ''

    first_round = false
    
  end while eiar < 2
  puts

  if foreigns.length == 0
    puts "No input provided."
    puts
    exit
  end
  
  translations = {}
  # Try all notations
  notations.keys.each do |nname|
    translations[nname] = []
    foreigns.each do |frgn|
      # If a translation cannot translate a hole, it needs to return false (as opposed to
      # returning e.g. the untranslateable hole). This is important for the case of passing
      # holes, that are part of notation harpwise.
      translations[nname] << send("tool_translate_notation_#{nname}", frgn)
    end
  end

  # Count number of translated holes for each notation
  counts = translations.map {|nm, hls| [nm, hls.select {|h| h}.length]}.to_h
  mx = counts.values.max
  if mx == 0
    puts "None of the available notations could match  \e[1many\e[0m  hole from your input !"
    puts
    exit
  end

  # Collect translations which translate the maximum number of holes, i.e. which are best
  best = counts.keys.group_by {|nname| counts[nname]}[mx]
  # But although the translate the same (i.e. maximum) number of holes, their translations
  # can still be different
  best_trs = best.group_by {|nname| translations[nname]}.invert

  # Report how well the notations dd
  print 'You input '
  if best.length == 1
    if mx == foreigns.length
      print "is fully covered by one notation"
    else
      print "is covered best (#{mx} of #{foreigns.length} holes) by one notation"
    end
  else
    if mx == foreigns.length
      print "is fully covered by #{best.length} notations"
    else
      print "is covered best (#{mx} of #{foreigns.length} holes) by #{best.length} notations"
    end
  end
  puts " (see below)\nand translates into harpwise-richter as:"
  puts


  # Actually output results
  idx = 0
  nl_after_holes.pop
  best_trs.each do |trs, hls|
    print "  \e[32m#{trs.join(',')}:\e[0m"
    print "\n  " if nl_after_holes.length > 0
    hls.each_with_index do |hl, idx|
      print '  '
      if hl
        print "\e[0m#{hl}"
      else
        print "\e[2m#{foreigns[idx]}"
      end
      idx += 1
      print "\n  " if nl_after_holes.include?(idx)
    end
    puts "\e[0m"
  end
  puts
  if mx != foreigns.length
    puts ", where holes that could not be translated are \e[2mdim.\e[0m"
  end
  puts
end


def tool_translate_notation_parens hole
  if md = hole.match(/^(\d+)$/)
    return "+#{md[1]}"
  elsif md = hole.match(/^\((\d+)\)$/)
    return "-#{md[1]}"
  elsif hole == '123'
    return '+123'
  elsif hole == '(123)'
    return '[-123]'
  else
    return false
  end
end


def tool_translate_notation_ricci hole
  if md = hole.match(/^(\d+)$/) || hole.match(/^(\d+)b$/)
    return "+#{md[1]}"
  elsif md = hole.match(/^(\d+)d$/)
    return "-#{md[1]}"
  elsif md = hole.match(/^(\d+)"'$/) || hole.match(/^(-|\+)?(\d+)'"$/)
    return "-#{md[1]}///"
  elsif md = hole.match(/^(\d+)"$/) || hole.match(/^(\d+)''$/)
    return "-#{md[1]}//"
  elsif md = hole.match(/^(\d+)'$/)
    return "-#{md[1]}/"
  else
    return false
  end
end


def tool_translate_notation_harpwise hole
  if $harp_holes.include?(hole)
    return hole
  elsif hole.match(/^\(.*\)$/) || hole.match(/^\[.*\]$/)
    return hole
  else
    return false
  end
end


def tool_translate_notation_quotes hole

  # try normal ascii-quotes (single and double) first
  if md = hole.match(/^(-|\+)?(\d+)"'$/) || hole.match(/^(-|\+)?(\d+)'"$/)
    return (md[1] || '+') + "#{md[2]}///"
  elsif md = hole.match(/^(-|\+)?(\d+)"$/) || hole.match(/^(-|\+)?(\d+)''$/)
    return (md[1] || '+') + "#{md[2]}//"
  elsif md = hole.match(/^(-|\+)?(\d+)'$/)
    return (md[1] || '+') + "#{md[2]}/"
  end

  # Right quotes as used by harmonica.com
  # \u2019 = Right Single Quotation Mark
  # \u201D = Right Double Quotation Mark
  if md = hole.match(/^(-|\+)?(\d+)\u201D\u2019$/) || hole.match(/^(-|\+)?(\d+)\u2019\u201D$/)
    return (md[1] || '+') + "#{md[2]}///"
  elsif md = hole.match(/^(-|\+)?(\d+)\u201D$/) || hole.match(/^(-|\+)?(\d+)\u2019\u2019$/)
    return (md[1] || '+') + "#{md[2]}//"
  elsif md = hole.match(/^(-|\+)?(\d+)\u2019$/)
    return (md[1] || '+') + "#{md[2]}/"
  end

  # no quotes at all
  if md = hole.match(/^(-|\+)?(\d+)$/)
    return (md[1] || '+') + "#{md[2]}"
  end

  # chords
  if hole == '-123'
    return '[-123]'
  elsif hole == '123'
    return '[+123]'
  else
    return false
  end
  
end


def tool_translate_notation_notes hole
  return $note2hole[hole] || false
end


def tool_notes to_handle

  err "Tool 'notes' needs a key as an additional argument" if to_handle.length != 1
  harp_key = to_handle[0].downcase
  err "Key   #{to_handle[0]}   is unknown among keys  #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(harp_key)

  puts
  puts "Notes of major scale \e[2m(with semi diffs and \e[0m\e[32mf\e[0m\e[2mifth)\e[0m"
  [-7, 0].each do |offset|
    ssemi = note2semi(harp_key + '4') + offset
    puts "Starting at \e[32m#{semi2note(ssemi)[0 ... -1]}\e[0m:"
    puts
    print '  '
    notes = $maj_sc_st_abs.map {|dsemi| semi2note(ssemi + dsemi)}.map {|n| n[0 ... -1]}
    notes.each_with_index do |n,idx|
      print "\e[32m" if idx == 0 || idx == 4
      print n + "\e[0m   "
    end
    puts
    
    diffs = $maj_sc_st_diff.clone
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
  puts
end


def tool_diag1
  puts "\n\n"
  puts_underlined 'Record and replay sound'

  txt = <<~end_of_intro
  Harpwise uses the excellent program sox (aka rec, aka play) for
  audio recording and replay.
  Normally sox works just great but it relies on correct configuration
  of your sound system and on correct settings and operation of your
  sound hardware.

  Therefore, this assistant will invoke sox (or rec or play, both are
  links to sox) in a typical way, giving you a chance to:

    - Verify that sox (and therefore harpwise) can record and play
      sounds in good quality
    - Easily spot any warnings or errors, that might appear

  end_of_intro

  txt.lines.each {|l| print l; sleep 0.01}
  
  FileUtils.rm $diag_wav if File.exist?($diag_wav)
  print "\e[?25l"  ## hide cursor

  puts
  puts_underlined 'Record'
  see_sox = "\e[34m===== %s of output of sox/%s =====\e[0m"
  rec_time = 10
  cmd_rec = "sox -d -r #{$conf[:sample_rate]} #{$diag_wav}"
  cmd_rec += ' trim 0 2' if $testing

  txt = <<~end_of_intro_rec
  This will invoke:

    #{cmd_rec}

  to record any sound from your microphone.
  The recording will be stopped after #{rec_time} seconds.

  Your part is:

    - Make some sound, that can be recorded, e.g. count up:
        one -- two -- three -- four -- five ...

    - Watch the dynamic level display of sox/rec and check, that it moves in
      sync  (i.e. without delay) with your counting

    - Look out for any extra output e.g. WARNINGS or ERRORS that may appear

  end_of_intro_rec

  txt.lines.each {|l| print l; sleep 0.01}
  
  puts "Start making sound and press \e[32many key\e[0m to start: "
  drain_chars
  one_char
  puts "\n\e[32mRecording started for #{rec_time} secs.\e[0m\n\n"
  puts see_sox % ['START', 'rec']
  rec_pid = Process.spawn cmd_rec
  sleep rec_time
  puts
  puts
  puts see_sox % ['END', 'rec']
  puts "\e[0m\e[K\nDone.\n\n"
  Process.kill('HUP', rec_pid)
  Process.wait(rec_pid)

  puts
  puts_underlined 'Replay'
  cmd_play = if $testing
               "play -v 0 #{$diag_wav}"
             else
               "play #{$diag_wav}"
             end

  txt = <<~end_of_intro_play
  This will invoke:

    #{cmd_play}

  to replay the sound, that has just been recorded.

  You part is:

    - Listen and check that you hear, what has been recorded
    - Listen for initial cracks, distortion or overall poor audio quality
    - Look out for any extra output e.g. WARNINGS or ERRORS that may appear

  end_of_intro_play

  txt.lines.each {|l| print l; sleep 0.01}
  
  puts "Press \e[32many key\e[0m to start: "
  drain_chars
  one_char
  print "\n\e[32mReplay started, #{rec_time} secs expected.\e[0m\n\n"
  puts see_sox % ['START', 'play']
  rec_pid = Process.spawn cmd_play
  Process.wait(rec_pid)
  puts
  puts see_sox % ['END', 'play']
  puts "\e[0m\e[K\nDone.\n\n"

  txt = <<~end_of_outro

  Diagnosis done.

  You may also want to try the other diag-tools:

    diag2: test mp3-playback
    diag3: check frequency recognition

  and, if there have been problems:

    \e[32mdiag-hints\e[0m: some proven suggestion on how to fix common problems

  end_of_outro
  
  txt.lines.each {|l| print l; sleep 0.01}
  
end


def tool_diag2

  cmd_play = if $testing
               "play -v 0 #{$dirs[:install]}/recordings/wade.mp3"
             else
               "play #{$dirs[:install]}/recordings/wade.mp3"
             end

  puts "\n\n"
  puts_underlined 'Playing an mp3'

  txt = <<~end_of_intro
  Hapwise uses sox to play mp3-files, e.g. the licks that come with harpwise
  or that you have collected.

  Therefore this test will try to play an mp3 like this:

    #{cmd_play}

  Your part is:

    - Listen if the mp3 is played at all and in good quality.

  end_of_intro

  txt.lines.each {|l| print l; sleep 0.01}

  print "\e[?25l"  ## hide cursor

  puts "Press \e[32many key\e[0m to start: "
  drain_chars
  one_char
  puts "\n\e[32mPlay started.\e[0m\n\n"
  see_sox = "\e[34m===== %s of output of sox/%s =====\e[0m"
  puts see_sox % ['START', 'play']
  system(cmd_play)
  puts see_sox % ['END', 'play']

  puts <<~end_of_outro

  Diagnosis done.

  If there have been any problems, try:

    \e[32mdiag-hints\e[0m for some proven suggestion on how to fix common problems.

  end_of_outro

end


def tool_diag3

  cmd_aub = get_pipeline_cmd(:sox, '-d')

  puts "\n\n"
  puts_underlined 'Testing the frequency recognition'

  txt = <<~end_of_intro
  Please note: This tests requires sound recording to work properly;
  you may want to test this first with:    harpwise tools diag1
  and then come back here.


  Harpwise uses the program aubiopitch to convert the audio (which is
  recorded by sox) into a series of frequency-values; all in real time.

  Both programs are connected in a pipeline like this:

    #{cmd_aub}

  this pipeline emits a stream of timestamps + frequencies, which in
  turn will be read and displayed by harpwise.

  The test will start the pipeline above and print its results for
  10 seconds; the first 10 lines will also be captured and printed again
  after termination so that you may inspect them for errors.
  
  Please note, that a few error-messages are okay, as long as after
  that the stream of timestamps + frequencies sets in.

  Your part is:

    - Make some sound, e.g. play your harmonica; also play lower and
      higher to see if the printed frequencies change accordingly

    - After the pipeline has been terminated, scan the re-printed output
      for unexpected errors

  end_of_intro

  txt.lines.each {|l| print l; sleep 0.01}  
  print "\e[?25l"  ## hide cursor

  puts
  puts_underlined 'Converting sound to frequencies'
  aub_time = 10

  puts "Start making sound and press \e[32many key\e[0m to start: "
  drain_chars
  one_char
  puts "\n\e[32mFrequency pipeline started for #{aub_time} secs.\e[0m\n\n"
  puts "\e[34m===== START of output of sox + aubiopitch =====\e[0m"
  puts

  #
  # Remark: The code below is deliberately similar to the one in sox_to_aubiopitch_to_queue,
  # see there too for some explanations
  # 
  _, ppl_out_err, wait_thr = Open3.popen2e(cmd_aub)
  # cmd may need some time to terminate in the case of startup problems
  sleep 0.2
  if !wait_thr.alive? && !IO.select([ppl_out_err], nil, nil, 2)
    err "Command terminated unexpectedly, please see errors above"
  end
  line = nil
  lines = []
  no_gets = 0
  started = Time.now
  loop do
    # gets (below) might block, so guard it by timeout
    begin
      Timeout.timeout(10) do
        # gets might return nil for unknown reasons (e.g. in an unpatched homebrew-setup)
        while !(line = ppl_out_err.gets)
          sleep 0.5
          no_gets += 1
          err "10 times no output from command" if no_gets > 10
        end
        line.chomp!
        puts line
      end
    rescue Timeout::Error
      err "No output from comand"
    end  # check for timeout in gets
    
    sleep 0.02 if $testing
    lines << line if lines.length < 10
    
    break if Time.now - started > 10
  end
  
  txt = <<~end_of_outro

  \e[0mPipeline done.

  Have timestamps + frequencies been printed above ?
  Did they vary according to the pitch of your sounds ?

  When when there was no sound, did the frequency actually read  0.000  ?
  Otherwise you microphone's amplification might be set too high
  or your environment might be too noisy.

  Here are the first 10 lines repeated for inspection:\e[2m

  end_of_outro

  txt.lines.each {|l| print l; sleep 0.01}

  lines.each {|l| puts l}
  puts
  puts "\e[0mSome initial warnings or errors are okay, as long as they are\nfollowed by the expected data."
  puts
  puts "\e[0mThe expected data would be a stream of lines with two numbers each,\njust like this (e.g.):  3.328000 159.699326"

  puts <<~end_of_outro

  Diagnosis done.

  If there have been any problems, try:

    \e[32mdiag-hints\e[0m for some proven suggestion on how to fix common problems.

  end_of_outro

  Process.kill('KILL', wait_thr.pid) if wait_thr.alive?
end


def tool_diag_hints
  puts "\n\n"
  puts_underlined 'Some hints on troubleshooting '
  
  txt = <<~end_of_intro

  These hints can help to solve problems, that have come up during
  the use of any of the diagnosis-tools (e.g. harpwise tools diag).

  In some cases such problems can be solved easily by adjusting the
  settings of your sound system. E.g. the recording level might be
  set too low or the wrong audio-device might be selected.

  However, if you saw error messages in the output of sox, or heard
  distortions or a noticable delay in recording, the problem might
  rather be with the configuration of your audio system and/or sox.

  For these cases, there is a collection of technical hints, that have
  been proven useful.

  end_of_intro

  txt.lines.each {|l| print l; sleep 0.01}
  
  puts "Press \e[32many key\e[0m to read them (\e[32ml\e[0m or \e[32mm\e[0m for less or more): "
  drain_chars
  char = one_char

  gfile = "#{$dirs[:install]}/resources/audio_guide.txt"
  if char == 'l' || char == 'm'
    pgr = Hash[*%w(l less m more)].to_h[char]
    puts "\npaging  #{gfile}  with #{pgr} ... "
    sleep 0.5
    system("#{pgr} #{gfile}")
    puts 'Done.'
    puts
  else
    puts "\n\e[32mSome hints\n----------\e[0m\n"
    audio_guide = ERB.new(IO.read(gfile)).result(binding).lines
    audio_guide.pop while audio_guide[-1].strip.empty?
    audio_guide.each {|l| print l; sleep 0.01}    
    puts "\n\e[2mEnd of hints.\e[0m\n\n"
  end
end


def tool_utils
  lines = ERB.new(IO.read("#{$dirs[:install]}/utils/README.org")).result(binding).lines
  summaries = Hash.new
  head = nil
  first_para = []
  puts
  state = :before_head
  lines.each_with_index do |line, idx|
    next if line.strip[0] == '#'
    if state == :in_first_para && line.strip.length == 0
      state = :after_first_para
      summaries[head] = first_para
    end
    state = :in_first_para if state == :after_head && line.strip.length > 0
    first_para << line if state == :in_first_para
    if line =~ /^\*/
      print "\e[32m"
      state = :after_head
      first_para = []
      head = line
    end
    print line
    print "\e[0m"
    sleep 0.02 if idx < 10
  end
  puts
  puts
  sleep 0.2
  puts "\e[0mSummary:\e[0m"
  puts
  summaries.each do |head, lines|
    print "\e[32m#{head}\e[0m"
    print lines.join
    puts
  end
  puts
  puts "Find these utilities in:   #{$dirs[:install]}/utils"
  puts
end
