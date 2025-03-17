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
  when 'transcribe', 'trans'
    tool_transcribe to_handle
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
  when 'diag'
    tool_diag
  when 'utils', 'utilities'
    tool_utils
  else
    fail "Internal error: unknown extra '#{$extra}'"
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
    err "Key   #{to_handle[0]}   is unknown among key  #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(harp_key)
    harp_color += "\e[7m"
  end

  if to_handle.length == 2
    song_key = to_handle[1].downcase
    err "Key   #{to_handle[1]}   is unknown among keys  #{$conf[:all_keys].join('  ')}" unless $conf[:all_keys].include?(song_key)
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
    puts "Look: The new user-defined scale   '#{sname}'   already exists as a file:\n\e[2m#{sfile}\e[0m"
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
  puts "has been written to:\n\e[2m#{sfile}\e[0m"
  puts
  puts "New scale   \e[32m'#{sname}'\e[0m   has been created and may be used from now on."
  puts
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
  # offset for playing in second position i.e. for staring with the fifth note
  st_abs = $maj_sc_st_abs.clone
  # chord-v wraps to next octave, so we need to extend scale
  st_abs << $maj_sc_st_abs[-1] + $maj_sc_st_diff[0]
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


def tool_diag
  puts "\n\n"
  puts_underlined 'Some help with diagnosing sound-problems'

  puts <<~end_of_intro
  Harpwise uses the excellent program sox (aka rec, aka play).
  Normally, sox works just great, but it relies on correct
  configuration of your sound system on correct settings and
  operation of your sound hardware.

  Therefore, this assistant will invoke sox (or rec or play, both are
  links to sox) in a typical way, giving you a chance to:

    - Verify that sox (and therefore harpwise) can record and play sounds
    - Easily spot any warnings or error messages, that might appear;
      these will be in \e[0;101m red \e[0m

  end_of_intro

  FileUtils.rm $diag_wav if File.exist?($diag_wav)
  print "\e[?25l"  ## hide cursor

  puts
  puts_underlined 'Recording sound'
  cmd_rec = if $testing
              "sleep 100"
            else
              "sox -d -q -r #{$conf[:sample_rate]} #{$diag_wav}"
            end

  puts <<~end_of_intro_rec
  This will invoke:

    #{cmd_rec}

  to record any sound from your microphone.
  The recording will be stopped after 3 seconds.

  Your part is:

    - Make some sound that can be recorded, e.g. play your harp
    - Look out for any extra output e.g. WARNINGS or ERRORS that may appear

  end_of_intro_rec

  puts "Press any key to start: "
  drain_chars
  one_char
  print "\n\e[32mRecording started for 3 secs.\e[0m\n\e[0;101m"
  rec_pid = Process.spawn cmd_rec
  sleep 3
  puts "\e[0m\e[K\nDone.\n\n"
  Process.kill('HUP', rec_pid)
  Process.wait(rec_pid)

  puts
  puts_underlined 'Replaying sound'
  cmd_play = if $testing
              "sleep 3"
            else
              "play -q #{$diag_wav}"
            end

  puts <<~end_of_intro_play
  This will invoke:

    #{cmd_play}

  to replay the sound, that has just been recorded.

  You part is:

    - Listen and check, if you hear, what has been recorded previously
    - Look out for any extra output e.g. WARNINGS or ERRORS that may appear

  end_of_intro_play

  puts "Press any key to start: "
  drain_chars
  one_char
  print "\n\e[32mReplay started, 3 secs expected.\e[0m\n\e[0;101m"
  rec_pid = Process.spawn cmd_play
  Process.wait(rec_pid)
  puts "\e[0m\e[K\nDone.\n\n"

  puts
  puts_underlined 'Get hints on troubleshooting sound, especially sox ?'
  puts <<~end_of_however
  In many cases problems can be traced to incorrect settings,
  e.g. of your sound hardware (volume turned up ?).

  However, if you saw error messages in \e[0;101m red \e[0m,
  the problem might be with the configuration of sox.
  In that case, there is a collection of mixed technical
  hints that might be useful.
  end_of_however
  
  puts "\nType 'y' to read those hints or anything else to end: "
  drain_chars
  if one_char == 'y'
    puts "\n\e[32mSome hints:\e[0m\n\n"
    audio_guide = ERB.new(IO.read("#{$dirs[:install]}/resources/audio_guide.txt")).result(binding).lines
    audio_guide.pop while audio_guide[-1].strip.empty?
    audio_guide.each {|l| print l}    
  else
    puts "\n\e[32mNo hints requested.\e[0m"
  end
  
  puts "\nDiagnosis done.\n\n"  
  
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
