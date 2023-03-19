#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $conf[:sample_rate]).to_i}" : "-d #{secs}"
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $testing
    FileUtils.cp $test_wav, file
    sleep secs
  else
    system "arecord -r #{$conf[:sample_rate]} #{duration_clause} #{file} #{output_clause}" or err "arecord failed"
  end
end


def play_sound file
  samples = $opts[:fast] ? 24000 : 0
  sys "aplay #{file} -s #{samples}" unless $testing
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch #{$conf[:pitch_detection]} #{file} 2>&1)
end


def trim_recording hole, recorded
  duration = wave2data(recorded)
  duration_trimmed = 1.0
  do_draw = true
  play_from = find_onset($recorded_data)
  trim_sound recorded, play_from, duration_trimmed, $trimmed_wave
  loop do
    if do_draw
      draw_data($recorded_data, play_from, play_from + duration_trimmed)
      inspect_recording(hole, recorded)
      do_draw = false
    else
      puts
    end
    puts "\e[93mTrimming\e[0m #{File.basename(recorded)} for hole \e[33m#{hole}\e[0m, play from %.2f" % play_from
    puts 'Choices: <num-of-secs-start> | d:raw | p:play | y:es | f:requency | r:ecord'
    print "Your choice (h for help): "
    choice = one_char

    if ('0' .. '9').to_a.include?(choice) || choice == '.'
      choice = '0.' if choice == '.'
      print "Finish with RETURN: #{choice}"
      choice += STDIN.gets.chomp.downcase.strip
      number = true
    else
      puts choice
      number = false
    end
    if choice == '?' || choice == 'h'
      puts <<EOHELP

Full Help:

   <num-of-secs-start> :  set position to start from (marked by vertical
                   line in plot); just start to type, e.g.:  0.4
       p, SPACE :  play from current position
              d :  draw current wave form
      y, RETURN :  accept current play position, trim file
                   and skip to next hole
              r :  record and trim again
EOHELP
      
    elsif ['', ' ', 'p'].include?(choice)
      puts "\e[33mPlay\e[0m from %.2f ..." % play_from
      play_sound $trimmed_wave
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y' || choice == "\r"
      FileUtils.cp $trimmed_wave, recorded
      wave2data(recorded)
      puts "\nEdit\e[0m accepted, trimmed #{File.basename(recorded)}, starting with next hole.\n\n"
      return :next_hole
    elsif choice == 'f'
      print "\e[33mSample\e[0m sound ..."
      synth_sound hole, $helper_wave
      play_sound $helper_wave
    elsif choice == 'r'
      puts "Redo recording and trim ..."
      return :redo
    elsif number
      begin
        val = choice.to_f
        raise ArgumentError.new('must be > 0') if val < 0
        raise ArgumentError.new("must be < duration #{duration}") if val >= duration
        play_from = val
        trim_sound recorded, play_from, duration_trimmed, $trimmed_wave
        do_draw = true
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    else
      puts "Invalid Input '#{choice}'"
    end
  end 
end


def trim_sound file, play_from, duration, trimmed
  puts "Taking #{duration} seconds of original sound plus 0.2 fade out, starting at %.2f" % play_from
  sys "sox #{file} #{trimmed} trim #{play_from.round(2)} #{play_from.round(2) + duration + 0.2} gain -n -3 fade 0 -0 0.2"
end


def sox_query file, property
  sys("sox #{file} -n stat 2>&1").lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole, file, extra = ''
  puts "\nGenerating   hole \e[32m#{hole}\e[0m#{extra},   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m:"
    
  puts cmd = "sox -n #{file} synth 1 sawtooth %#{$harp[hole][:semi]} gain -n -3"
  sys cmd
end


def wave2data file
  sys "sox #{file} #{$recorded_data}"
  sox_query(file, 'Length')
end


def find_onset data_file
  max = 0
  File.foreach(data_file) do |line|
    next if line[0] == ';'
    max = [max, line.split[1].to_f].max
  end
  
  max13 = max * 1.0/3
  max23 = max13 * 2
  t13 = t23 = nil
  File.foreach(data_file) do |line|
    next if line[0] == ';'
    t, v = line.split.map(&:to_f)
    t13 = t if !t13 && v >= max13
    t23 = t if !t23 && v >= max23
  end
  ts = t13 - 2 * ( t23 - t13 ) - 0.1
  ts = 0 if ts < 0
  ts
end


def this_or_equiv template, note
  notes_equiv(note).each do |eq|
    name = template % eq
    return name if File.exist?(name)
  end
  return template % note
end


def start_collect_freqs
  num_samples = ($conf[:sample_rate] * $opts[:time_slice]).to_i
  fifo = "#{$dirs[:tmp]}/fifo_arecord_aubiopitch"
  File.mkfifo(fifo) unless File.exist?(fifo)
  err "File #{fifo} already exists but is not a fifo, will not overwrite" if File.ftype(fifo) != 'fifo'

  Thread.new {arecord_to_fifo(fifo)}
  Thread.new {aubiopitch_to_queue(fifo, num_samples)}
end


def arecord_to_fifo fifo
  arec_cmd = if $testing
               "cat #{$test_wav} /dev/zero >#{fifo}"
             else
               "arecord -r #{$conf[:sample_rate]} >#{fifo}" +
                 ( $opts[:debug]  ?  ""  :  " 2>/dev/null" )
             end
  _, _, wait_thread  = Open3.popen2(arec_cmd)
  wait_thread.join
  err "command '#{arec_cmd}' terminated unexpectedly"
  exit 1
end


def aubiopitch_to_queue fifo, num_samples
  aubio_cmd = "stdbuf -o0 aubiopitch --bufsize #{num_samples} --hopsize #{num_samples} --pitch #{$conf[:pitch_detection]} -i #{fifo}"
  _, aubio_out = Open3.popen2(aubio_cmd) unless $testing

  ptouch = false
  loop do
    if $testing
      sleep 0.1
      FileUtils.touch("/tmp/#{File.basename($0)}_pipeline_started") unless ptouch
      ptouch = true
      fields = [0.0, 16059.87793]
    else
      fields = aubio_out.gets.split.map {|f| f.to_f}
    end
    $freqs_queue.enq fields[1]
  end
end


def pipeline_catch_up
  $freqs_queue.clear
end


def play_hole_and_handle_kb hole
  wait_thr = Thread.new { play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]) }
  begin
    sleep 0.1
    handle_kb_play_holes
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_recording_and_handle_kb recording, start, length, key, first_round = true, octave_shift = 0

  trim_clause = if start && length
                  "trim #{start} #{length}"
                elsif start
                  "trim #{start}"
                elsif length
                  "trim 0.0 #{start}"
                else
                  ""
                end
  dsemi = diff_semitones($key, key, :g_is_lowest) + octave_shift * 12
  pitch_clause = ( dsemi == 0  ?  ''  :  "pitch #{dsemi * 100}" )
  tempo = 1.0
  volume = 0
  $ctl_rec[:loop] = $ctl_rec[:loop_loop]
  imm_ctrls_again = [:replay, :slower, :vol_up, :vol_down]
  loop_message_printed = false
  lick_lick_was = $ctl_rec[:lick_lick]
  loop_loop_was = $ctl_rec[:loop_loop]

  # loop as long as the recording needs to be played again due to
  # immediate controls triggered while it is playing
  begin
    tempo_clause = ( tempo == 1.0  ?  ''  :  ('tempo -m %.1f' % tempo) )
    volume_clause = ( volume == 0  ?  ''  :  ('vol %ddb' % volume) )
    cmd = "play -q -V1 #{$lick_dir}/recordings/#{recording} -t alsa #{trim_clause} #{pitch_clause} #{tempo_clause} #{volume_clause}".strip
    IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
    return false if $testing
    _, _, wait_thr  = Open3.popen2(cmd)
    (imm_ctrls_again + [:skip, :pause_continue, :show_help]).each {|k| $ctl_rec[k] = false}
    started = Time.now.to_f
    duration = 0.0
    paused = false

    # loop to check repeatedly while the recording is beeing played
    begin
      sleep 0.1
      handle_kb_play_recording
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        if paused
          Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
          paused = false
          print "\e[0m\e[32mgo \e[0m"
        else
          Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
          paused = true
          duration += Time.now.to_f - started
          started = Time.now.to_f
          printf "\e[0m\e[32m %.1fs SPACE to continue ... \e[0m", duration
        end
      elsif $ctl_rec[:slower]
        tempo -= 0.1 if tempo > 0.4
        print "\e[0m\e[32mx%.1f \e[0m" % tempo
      elsif $ctl_rec[:vol_up]
        volume += 3 if volume < 30
        print "\e[0m\e[32m%+ddB \e[0m" % volume
      elsif $ctl_rec[:vol_down]
        volume -= 3 if volume > -30
        print "\e[0m\e[32m%+ddB \e[0m" % volume
      elsif $ctl_rec[:show_help]
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        display_kb_help 'recording',first_round,
                        "  SPACE: pause/continue        <: decrease speed\n" + 
                        "      +: jump to end           -: jump to start\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        "      l: loop over recording   " +
                        ( $ctl_can[:loop_loop]  ?  "L: loop over next recording too\n"  :  "\n" ) +
                        ( $ctl_can[:lick_lick]  ?  "      c: continue with next lick without waiting for key\n"  :  "\n" )
        print "\e[#{$lines[:hint_or_message]}H" unless first_round
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32mreplay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32mjump to end \e[0m"
      end

      if $ctl_rec[:lick_lick] != lick_lick_was
        print "\n\e[0m\e[32mContinue with next lick at end is: \e[0m" +
              ( $ctl_rec[:lick_lick]  ?  'ON'  :  'OFF' ) + "\n"
        lick_lick_was = $ctl_rec[:lick_lick]
      end

      if $ctl_rec[:loop_loop] != loop_loop_was
        print "\n\e[0m\e[32mLoop over next licks is: \e[0m" +
              ( $ctl_rec[:loop_loop]  ?  'ON'  :  'OFF' ) + "\n"
        loop_loop_was = $ctl_rec[:loop_loop]
      end

      if $ctl_rec[:loop] && !loop_message_printed
        print "\e[0m\e[32mloop (+ to end) " + 
              ( $ctl_rec[:loop_loop]  ?  ' and loop after loop (L to end)'  :  '' ) +
              "\e[0m"
        loop_message_printed = true
      end

      # need to go leave this loop and play again if any immediate
      # controls have been triggered
    end while wait_thr.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}
    
    $ctl_rec[:loop] = false if $ctl_rec[:skip]
    if wait_thr.alive?
      Process.kill('KILL',wait_thr.pid)
      wait_thr.join
    end
  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} || $ctl_rec[:loop]
  $ctl_rec[:skip]
end


def play_adjustable_pitch do_sleep = false

  semi = note2semi($key + '4')
  all_waves = [:pluck, :sawtooth, :square, :sine]
  wave = wave_was = :pluck
  volume = 0
  min_semi = -24
  max_semi = 24
  paused = false
  wait_thr = nil
  cmd = cmd_was = nil

  sleep 0.1 if do_sleep
  puts "\e[0m\e[32mPlaying an adjustable pitch, that you may compare\nwith a song, that is played in parallel."
  puts "\n\e[0m\e[2mPrinted are the key of the song and the key of the harp\nthat matches when played in second position."

  sleep 0.1 if do_sleep
  puts
  puts "\e[0m\e[2mSuggested procedure: Play the song in the background and"
  puts "step by semitones until you hear a good match; then try a fifth"
  puts "up and down, to check if those may match even better. Step by octaves,"
  puts "if your pitch is far above or below the song."
  sleep 0.1 if do_sleep
  puts
  puts "\e[0m\e[2m(type 'h' for help)\e[0m"
  puts
  print_pitch_information(semi)
  # loop forever until ctrl-c
  loop do
    
    volume_clause = ( volume == 0  ?  ''  :  ('vol %ddb' % volume) )
    duration_clause = ( wave == :pluck  ?  3  :  86400 )
    if paused
      if wait_thr&.alive?
        Process.kill('KILL',wait_thr.pid)
        wait_thr.join
      end
    else
      # sending stdout output to /dev/null makes this immune to killing ?
      cmd = "play -q -n synth #{duration_clause} #{wave} %#{semi+7} #{volume_clause}"
      if cmd_was != cmd || !wait_thr&.alive?
        if wait_thr&.alive?
          Process.kill('KILL',wait_thr.pid)
          wait_thr.join
        end
        if $testing
          IO.write($testing_log, cmd + "\n", mode: 'a')
          cmd = 'sleep 86400 ### ' + cmd
        end
        cmd_was = cmd
        _, _, wait_thr  = Open3.popen2(cmd)
      end
    end

    begin
      break if $ctl_pitch[:any]
      handle_kb_play_pitch
      sleep 0.1
    end while wait_thr.alive?

    if $ctl_pitch[:any]
      knm = $conf_meta[:ctrls_play_pitch].select {|k| $ctl_pitch[k] && k != :any}[0].to_s.gsub('_',' ')
      if $ctl_pitch[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[2mgo\e[0m"
        else
          paused = true
          puts "\e[0m\e[2mSPACE to continue ...\e[0m"
        end
      elsif $ctl_pitch[:vol_up]
        volume += 3 if volume < 30
        puts "\e[0m\e[2m%+ddB\e[0m" % volume
      elsif $ctl_pitch[:vol_down]
        volume -= 3 if volume > -30
        puts "\e[0m\e[2m%+ddB\e[0m" % volume
      elsif $ctl_pitch[:semi_up]
        semi += 1 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:semi_down]
        semi -= 1 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:octave_up]
        semi += 12 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:octave_down]
        semi -= 12 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:fifth_up]
        semi += 7 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:fifth_down]
        semi -= 7 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:wave_up] || $ctl_pitch[:wave_down]
        wave_was = wave
        wave = if $ctl_pitch[:wave_up]
                 all_waves[(all_waves.index(wave) + 1) % all_waves.length]
               else
                 all_waves[(all_waves.index(wave) -1) % all_waves.length]
               end
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:show_help]
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        [:semi_up, :semi_down, :octave_up, :octave_down, :change_wave, :vol_up, :vol_down, :show_help]
        display_kb_help 'pitch',true,
                        "  SPACE: pause/continue      x,q: quit\n" +
                        "      w: change waveform       W: change waveform back\n" + 
                        "      s: one semitone down     S: one semitone up\n" +
                        "      o: one octave down       O: one octave up\n" +
                        "      f: one fifth down        F: one fifth up\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n"
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
        print_pitch_information(semi)
      elsif $ctl_pitch[:quit]
        $ctl_pitch[:quit] = false
        return semi2note(semi)[0..-2]
      end

      if paused && !$ctl_pitch[:pause_continue]
        paused = false
        puts "\e[0m\e[2mgo\e[0m"
      end

      $conf_meta[:ctrls_play_pitch].each {|k| $ctl_pitch[k] = false}
    end

    if wave == :pluck && wave_was != :pluck
      wave_was = wave
      5.times do
        break if $ctl_pitch[:any]
        handle_kb_play_pitch
        sleep 0.1
      end
    end
  end
end


def print_pitch_information semi, name = nil
  puts "\e[0m\e[2m#{name}\e[0m" if name
  puts "\e[0m\e[2mSemi = #{semi}, Note = #{semi2note(semi+7)}, Freq = #{'%.2f' % semi2freq_et(semi)}\e[0m"
  print "\e[0mkey of song: \e[0m\e[32m%-3s,  " % semi2note(semi + 7)[0..-2]
  print "\e[0m\e[2mmatches \e[0mkey of harp: \e[0m\e[32m%-3s\e[0m" % semi2note(semi)[0..-2]
  puts
end
