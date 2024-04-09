#
#  Non-interactive tools
#

def do_tools to_handle

  $lick_file ||= get_lick_file

  # common error checking
  err "'harpwise tools #{$extra}' does not take any arguments, these cannot be handled: #{to_handle}" if %w(chart edit-licks edit-config chords).include?($extra) && to_handle.length > 0

  case $extra
  when 'transpose'
    tool_transpose to_handle
  when 'shift'
    tool_shift to_handle
  when 'keys'
    tool_key_positions to_handle
  when 'search-in-licks', 'search'
    tool_search to_handle
  when 'chart'
    tool_chart
  when 'edit-licks'
    system($editor + ' ' + $lick_file)
    puts "\nEdited \e[0m\e[32m#{$lick_file}\e[0m\n\n"
  when 'edit-config'
    tool_edit_config
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


def tool_progression to_handle
  err "Need at a base note and some distances, e.g. 'a4 4st 10st'" unless to_handle.length >= 1
  
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
  hood.  Normally, sox works just great, but on some system the
  configuration of sox might have flaws.

  Therefore, this assistant will invoke sox (or rec or play, both are
  links to sox) in a typical way, giving you a chance to:

    - Verify that sox (and therefore harpwise) can reord and play
      sounds
    - Easily spot any warnings or error messages, that might appear;
      these will probably be \e[0;101min color\e[0m

  end_of_intro

  file = "/tmp/harpwise.wav"
  FileUtils.rm file if File.exist?(file)
  print "\e[?25l"  ## hide cursor

  puts_underlined 'Recording sound', '-'
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
  print "Recording started for 3 secs.\n\e[0;101m"
  rec_pid = Process.spawn cmd_rec
  sleep 3
  puts "\e[0m\e[K\nDone.\n\n"
  Process.kill('HUP', rec_pid)
  Process.wait(rec_pid)

  puts_underlined 'Replaying sound', '-'
  cmd_play = if $testing
              "sleep 3"
            else
              "play -q #{file}"
            end

  puts <<~end_of_intro_play
  This will invoke:

    #{cmd_play}

  replay the sound, that has just been recorded.

  You should:

    - Listen and check, if you hear, what has been recorded previously
    - Look out for any extra output e.g. WARNINGS or ERRORS that may
      appear

  end_of_intro_play

  puts "Press any key to start: "
  drain_chars
  one_char
  print "Replay started, 3 secs expected.\n\e[0;101m"
  rec_pid = Process.spawn cmd_play
  Process.wait(rec_pid)
  puts "\e[0m\e[K\nDone.\n\n"

  puts_underlined 'Some hints on troubleshooting'
  puts "If you noticed any problems or errors or warnings,\nthere are some hints, that might help."
  puts "Type 'y' to read those hints (and anything else to end): "
  drain_chars
  if one_char == 'y'
    puts <<~end_of_guide

    sox-Errors, which mention "no default audio device" or "encode
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
  end
  
  puts "\nDiagnosis done.\n\n"  
  
end
