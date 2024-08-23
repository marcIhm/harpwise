#
#  Non-interactive tools
#

def do_tools to_handle

  $lick_file ||= get_lick_file

  # common error checking
  err_args_not_allowed(to_handle) if %w(chart edit-licks edit-config chords).include?($extra) && to_handle.length > 0

  case $extra
  when 'transpose'
    tool_transpose to_handle
  when 'shift'
    tool_shift to_handle
  when 'keys'
    tool_key_positions to_handle
  when 'search-in-licks'
    tool_search_in_licks to_handle
  when 'search-in-scales'
    tool_search_in_scales to_handle
  when 'search-scale-in-licks'
    tool_search_scale_in_licks to_handle
  when 'chart'
    tool_chart
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
  else
    fail "Internal error: unknown extra '#{extra}'"
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
  dsemi = diff_semitones($key, key_other, strategy: :g_is_lowest)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
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

  err "Need at least two additional arguments: a number of semitones and at least one hole (e.g. '7st -1'); '#{to_handle.join(' ')}' is not enough" unless to_handle.length > 1

  inter = to_handle.shift
  dsemi = $intervals_inv[inter] ||
          ((md = inter.match(/^[+-]?\d+st?$/)) && md[0].to_i) ||
          err("Given argument #{inter} is neither a named interval (one of: #{$intervals_inv.keys.reject {_1[' ']}.join(',')}) nor a number of semitones (e.g. 12st)")

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


def tool_search_in_licks to_handle

  err "Need at least one hole to search (e.g. '-1'); #{to_handle.inspect} is not enough" unless to_handle.length >= 1

  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
  end

  search_canon = to_handle.map {|h| $harp[h][:canonical]}

  puts "\nList of licks containing   \e[0m\e[32m#{to_handle.join(' ')}\e[0m   or equivalent:\n\n"
  count = 0
  maxlen = 0
  $all_licks, $licks, $lick_progs = read_licks

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


def tool_search_in_scales to_handle

  err "Need at least one lick-name or hole to search (e.g. '-1'); #{to_handle.inspect} is not enough" unless to_handle.length >= 1

  holes = if to_handle.length == 1
            $all_licks, $licks, $lick_progs = read_licks
            lick = $all_licks.find {|l| l[:name] == to_handle[0]}
            err "Given single argument '#{to_handle[0]}' is not the name of a lick" unless lick
            lick[:holes_wo_events]
          else
            to_handle.each do |hole|
              err "Argument '#{hole}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
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
    hls, _, _, _ = read_and_parse_scale(scale, $harp)
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

def tool_search_scale_in_licks to_handle

  err "Need the name of a scale (e.g. '#{$all_scales[-1]}') as a single argument" unless to_handle.length == 1
  scale = to_handle[0]
  err "Given argument #{scale} is not the name of a scale (any of: #{$all_scales.join(', ')})" unless $all_scales.include?(scale)
  
  holes, _, _, _ = read_and_parse_scale(scale, $harp)
  scale_holes = holes.map {|h| $harp[h][:canonical]}.uniq.
                  sort {|h1,h2| $harp[h1][:semi] <=> $harp[h2][:semi]}
  
  prev_not = false
  licks_all = Array.new
  licks_but_one = Array.new
  puts
  
  $all_licks, $licks, $lick_progs = read_licks
  $licks.each do |lick|

    lick_holes = lick[:holes_wo_events]

    lick_holes = lick_holes.map {|h| $harp[h][:canonical]}.uniq.
                   sort {|h1,h2| $harp[h1][:semi] <=> $harp[h2][:semi]}
  
    contains_all = (lick_holes - scale_holes).empty?

    contains_but_one = Array.new
    unless contains_all
      lick_holes.each do |hole|
        contains_but_one << hole if (lick_holes - [hole] - scale_holes).empty?
      end
    end

    if !contains_all && contains_but_one.length == 0
      if prev_not
        print "\e[2m#{lick[:name]}\e[0m "
      else
        print "\e[2mScale does not contain at least two holes of lick(s):\n  #{lick[:name]}\e[0m "
      end
      prev_not = true
    else
      if prev_not
        puts 
        puts
      end
      puts "Scale contains lick #{lick[:name]} with holes: #{lick_holes.join(' ')}"
      if contains_all
        puts " ,with all its holes."
        licks_all << lick[:name]
      else
        puts " ,when removing any of these holes: #{contains_but_one.join(' ')}"
        licks_but_one << lick[:name]
      end
      puts
      prev_not = false
    end
  end
  if prev_not
    puts 
    puts
  end
  puts
  puts_underlined "Summary for Scale #{scale}", '-', dim: false
  puts
  puts "Total number of licks checked: #{$licks.length}"
  puts
  puts 'Licks that are fully contained:'
  if licks_all.length == 0
    puts '  none'
  else
    print_in_columns licks_all, pad: :tabs
    puts " count: #{licks_all.length}"
  end
  puts
  puts 'Licks that are contained but one hole:'
  if licks_but_one.length == 0
    puts '  none'
  else
    print_in_columns licks_but_one, pad: :tabs
    puts " count: #{licks_but_one.length}"
  end
  puts 
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


def tool_chart

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


def tool_edit_file file, to_handle

  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 0
  puts "\nInvoking #{$editor} on \e[0m\e[32m#{file}\e[0m\n\n"
  sleep 1 
  exec($editor + ' ' + file)
end


def tool_transcribe to_handle

  err "need a single argument" if to_handle.length == 0
  err "cannot handle these extra arguments: #{to_handle}" if to_handle.length > 1

  $all_licks, $licks, $lick_progs = read_licks

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
  Harpwise uses the excellent program sox (aka rec aka play) under the
  hood.  Normally, sox works just great, but it relies on correct
  configuration of your sound system on correct settings and operation
  of your sound hardware.

  Therefore, this assistant will invoke sox (or rec or play, both are
  links to sox) in a typical way, giving you a chance to:

    - Verify that sox (and therefore harpwise) can record and play
      sounds
    - Easily spot any warnings or error messages, that might appear;
      these will be in \e[0;101mred\e[0m

  end_of_intro

  file = "/tmp/harpwise.wav"
  FileUtils.rm file if File.exist?(file)
  print "\e[?25l"  ## hide cursor

  puts
  puts_underlined 'Recording sound'
  cmd_rec = if $testing
              "sleep 100"
            else
              "sox -d -q -r #{$conf[:sample_rate]} #{file}"
            end

  puts <<~end_of_intro_rec
  This will invoke:

    #{cmd_rec}

  to record any sound from your microphone.
  The recording will be stopped after 3 seconds.

  You should:

    - Make some sound (e.g. play on your harmonica), that can be
      recorded
    - Look out for any extra output e.g. WARNINGS or ERRORS that may
      appear

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
              "play -q #{file}"
            end

  puts <<~end_of_intro_play
  This will invoke:

    #{cmd_play}

  to replay the sound, that has just been recorded.

  You should:

    - Listen and check, if you hear, what has been recorded previously
    - Look out for any extra output e.g. WARNINGS or ERRORS that may
      appear

  end_of_intro_play

  puts "Press any key to start: "
  drain_chars
  one_char
  print "\n\e[32mReplay started, 3 secs expected.\e[0m\n\e[0;101m"
  rec_pid = Process.spawn cmd_play
  Process.wait(rec_pid)
  puts "\e[0m\e[K\nDone.\n\n"

  puts
  puts_underlined 'Get hints on troubleshooting sox ?'
  puts <<~end_of_however
  In many cases problems can be traced to incorrect settings,
  e.g. of your sound hardware (volume turned up ?).

  However, if you saw error messages in \e[0;101mred\e[0m,
  the problem might be with the configuration of sox.
  In that case, there are some hints, that might help.
  end_of_however
  
  puts "\nType 'y' to read those hints (and anything else to end): "
  drain_chars
  if one_char == 'y'
    puts "\n\e[32mSome hints:\e[0m\n"
    puts <<end_of_guide

  Even if the program sox is present on your system, you might need to
  install support for more audio-formats; for linux this could be the
  package libsox-fmt-all.

  Sox-Errors, which mention "no default audio device" or "encode
  0-bit Unknown or not applicable" can sometimes be solved by
  setting and exporting the environment variable AUDIODRIVER to a
  suitable value.

  sox shows possible values for this when invoked without arguments;
  just search for the line 'AUDIO DEVICE DRIVERS'. Possible values
  might be 'alsa oss ossdsp pulseaudio' (linux) or 'coreaudio'
  (macOS).

  So e.g. on linux setting and exporting AUDIODRIVER=alsa might
  help.


  If this is not enough to solve the problem, you may also set
  AUDIODEV to a suitable value, which however must be understood by
  your audio driver (as specified by AUDIODRIVER).

  As a linux example lets assume, that you have set AUDIODRIVER=alsa
  above. Then, setting AUDIODEV=hw:0 in addition (which will inform
  alsa about the device to use) might work. Note, that for macOS
  most surely different values will be needed.


  Other options necessary for sox might be passed through the
  environment variable SOX_OPTS. See the man-page of sox for
  details; also see the documentation of your respective audio
  driver, e.g. alsa (for linux) or coreaudio (for macOS).
end_of_guide
  else
    puts "\n\e[32mNo hints requested.\e[0m"
  end
  
  puts "\nDiagnosis done.\n\n"  
  
end
