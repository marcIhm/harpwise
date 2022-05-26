#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $opts[:testing]
    FileUtils.cp $test_wav, file
    sleep secs
  else
    system "arecord -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}" or err "arecord failed"
  end
end


def play_sound file
  samples = $opts[:fast] ? 24000 : 0
  sys "aplay #{file} -s #{samples}" unless $opts[:testing]
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
    print "Your choice ('h' for help): "
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


def synth_sound hole, file
  puts "\nGenerating   hole \e[32m#{hole}\e[0m,   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m:"
    
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
  num_samples = ($sample_rate * $conf[:time_slice]).to_i
  fifo = "#{$tmp_dir}/fifo_arecord_aubiopitch"
  File.mkfifo(fifo) unless File.exist?(fifo)
  err "File #{fifo} already exists but is not a fifo, will not overwrite" if File.ftype(fifo) != "fifo"

  Thread.new {arecord_to_fifo(fifo)}
  Thread.new {aubiopitch_to_queue(fifo, num_samples)}
end


def arecord_to_fifo fifo
  arec_cmd = if $opts[:testing]
               "cat #{$test_wav} /dev/zero >#{fifo}"
             else
               # point 1 of a delicate balance for tests
               "arecord -r #{$sample_rate} >#{fifo} 2>/dev/null"
             end
  _, _, wait_thread  = Open3.popen2(arec_cmd)
  wait_thread.join
  err "command '#{arec_cmd}' terminated unexpectedly"
  exit 1
end


def aubiopitch_to_queue fifo, num_samples
  aubio_cmd = "stdbuf -o0 aubiopitch --bufsize #{num_samples * 1} --hopsize #{num_samples} --pitch #{$conf[:pitch_detection]} -i #{fifo}"
  _, aubio_out = Open3.popen2(aubio_cmd)
  
  loop do
    fields = aubio_out.gets.split.map {|f| f.to_f}
    # point 2 of a delicate balance for tests
    sleep 0.2 if $opts[:testing]
    $jitter = Time.now.to_f - $program_start - fields[0]
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
    handle_kb_play
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_recording_and_handle_kb recording, start, length, key, first_lap = true

  trim_clause = if start && length
                  "trim #{start} #{length}"
                elsif start
                  "trim #{start}"
                elsif length
                  "trim 0.0 #{start}"
                else
                  ""
                end
  dsemi = note2semi($key.to_s + '0') - note2semi(key + '0')
  dsemi -= 12 if dsemi > 6
  dsemi += 12 if dsemi < -6
  pitch_clause = if dsemi == 0
                   ""
                 else
                   "pitch #{dsemi * 100}"
                 end

  return false if $opts[:testing]
  tempo = 1.0
  $ctl_rec_loop = false
  ctl_not_loop = true
  begin
    tempo_clause = if tempo == 1.0
                     ""
                   else
                     "tempo %.1f" % tempo
                   end                  
    cmd = "play -q -V1 #{$lick_dir}/recordings/#{recording} -t alsa #{trim_clause} #{pitch_clause} #{tempo_clause}"
    _, _, wait_thr  = Open3.popen2(cmd)
    $ctl_skip = $ctl_replay = $ctl_pause_continue = $ctl_slower = $ctl_help = $ctl_show_help = false
    started = Time.now.to_f
    duration = 0.0
    paused = false
    begin
      sleep 0.1
      handle_kb_play_recording
      if $ctl_pause_continue
        $ctl_pause_continue = false
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
      elsif $ctl_slower
        tempo -= 0.1 if tempo > 0.4
        print "\e[0m\e[32mx%.1f\e[0m " % tempo
      elsif $ctl_rec_loop
        print "\e[0m\e[32m loop (+ to end)\e[0m" if ctl_not_loop
        ctl_not_loop = false
      elsif $ctl_show_help
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        display_kb_help 'recording',first_lap, <<~end_of_content
          SPACE: pause/continue
          TAB,+: skip to end         -: skip to start
              <: decrease speed      l: loop over recording
        end_of_content
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
        $ctl_show_help = false
      elsif $ctl_replay
        print "\e[0m\e[32m replay\e[0m"
      end
    end while wait_thr.alive? && !$ctl_skip && !$ctl_replay && !$ctl_slower
    $ctl_rec_loop = false if $ctl_skip
    Process.kill('KILL',wait_thr.pid) if wait_thr.alive?
    wait_thr.join unless $ctl_skip # raises any errors from thread
    err('See above') unless $ctl_skip || $ctl_replay || $ctl_slower || $ctl_rec_loop || wait_thr.value.success?
  end while $ctl_replay || $ctl_slower || $ctl_rec_loop
  $ctl_skip
end
