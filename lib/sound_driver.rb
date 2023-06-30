#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $testing
    FileUtils.cp $test_wav, file
    sleep secs
  else
    cmd = "rec -q #{$conf[:sox_rec_extra]} -r #{$conf[:sample_rate]} -b 16 -e signed #{file} trim 0 #{secs}"
    system("#{cmd} #{output_clause}") or err "rec failed: could not run: #{cmd}\n#{$sox_rec_fail_however}"
  end
end


def play_wave file, secs = ( $opts[:fast] ? 0.5 : 1 )
  cmd = if $testing
          "sleep #{secs}"
        else    
          "play --norm=#{$vol_synth.to_db} #{$conf[:sox_play_extra]} #{file} trim 0 #{secs}"
        end
  sys(cmd, $sox_play_fail_however) unless $testing
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch #{$conf[:pitch_detection]} #{file} 2>&1)
end


def trim_recorded hole, recorded
  wave2data(recorded)
  duration = sox_query(recorded, 'Length')
  duration_trimmed = 2.0
  do_draw = true
  trimmed_wave = "#{$dirs[:tmp]}/trimmed.wav"
  play_from = find_onset
  trim_wave recorded, play_from, duration_trimmed, trimmed_wave
  loop do
    if do_draw
      draw_data(play_from, play_from + duration_trimmed)
      inspect_recorded(hole, recorded)
      do_draw = false
    else
      puts
    end
    puts "\e[93mTrimming\e[0m #{File.basename(recorded)} for hole   \e[33m#{hole}\e[0m   play from %.2f" % play_from
    puts 'Choices: <secs-start> | d:raw | p:play (SPC) | y:es (RET)'
    puts '                        f:req | r:ecord      | c:ancel'
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

   <secs-start>: set position to start from (marked by vertical bar
                 line in plot); just start to type, e.g.:  0.4
              d: draw current wave form
       p, SPACE: play from current position
      y, RETURN: accept current play position, trim file
                 and skip to next hole
              f: play a sample frequency for comparison 
            q,c: cancel and go to main menu, where you may generate
              r: record and trim again
EOHELP
      
    elsif ['', ' ', 'p'].include?(choice)
      puts "\e[33mPlay\e[0m from %.2f ..." % play_from
      play_wave trimmed_wave, 5
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y' || choice == "\n"
      FileUtils.cp trimmed_wave, recorded
      wave2data(recorded)
      puts "\nEdit\e[0m accepted, trimmed #{File.basename(recorded)}, starting with next hole.\n\n"
      return :next
    elsif choice == 'c' || choice == 'q'
      wave2data(recorded)
      puts "\nEdit\e[0m canceled, continue with current hole.\n\n"
      return :cancel
    elsif choice == 'f'
      print "\e[33mSample\e[0m sound ..."
      synth_sound hole, $helper_wave
      play_wave $helper_wave
    elsif choice == 'r'
      puts "Redo recording and trim ..."
      return :redo
    elsif number
      begin
        val = choice.to_f
        raise ArgumentError.new('must be > 0') if val < 0
        raise ArgumentError.new("must be < duration #{duration}") if val >= duration
        play_from = val
        trim_wave recorded, play_from, duration_trimmed, trimmed_wave
        do_draw = true
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    else
      puts "Invalid Input '#{choice}'"
    end
  end 
end


def trim_wave file, play_from, duration, trimmed
  puts "Taking #{duration} seconds of original sound plus 0.2 fade out, starting at %.2f" % play_from
  cmd = "sox #{file} #{trimmed} trim #{play_from.round(2)} #{play_from.round(2) + duration + 0.2} gain -n -3 fade 0 -0 0.2"
  sys cmd
end


def sox_query file, property
  sys("sox #{file} -n stat 2>&1").lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole, file, extra = ''
  puts "Hole \e[32m#{hole}\e[0m#{extra},   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m"
  cmd = "sox -n #{file} synth 4 sawtooth %#{$harp[hole][:semi]} vol #{$conf[:auto_synth_db]}db"
  sys cmd
end


def wave2data file
  sys "sox #{file} #{$recorded_data}"
end


def find_onset
  max = 0
  File.foreach($recorded_data) do |line|
    next if line[0] == ';'
    max = [max, line.split[1].to_f].max
  end
  
  max13 = max * 1.0/3
  max23 = max13 * 2
  t13 = t23 = nil
  File.foreach($recorded_data) do |line|
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
  return nil
end


def start_collect_freqs
  num_samples = ($conf[:sample_rate] * $opts[:time_slice]).to_i
  fifo = "#{$dirs[:tmp]}/fifo_sox_rec_aubiopitch"
  File.mkfifo(fifo) unless File.exist?(fifo)
  err "File #{fifo} already exists but is not a fifo, will not overwrite" if File.ftype(fifo) != 'fifo'

  Thread.new {sox_rec_to_fifo(fifo)}
  Thread.new {aubiopitch_to_queue(fifo, num_samples)}
end


def sox_rec_to_fifo fifo
  sox_rec_cmd = if $testing
                  # 7680 is the rate of our sox-generated file; we use 10 times as much ?
                  "pv -qL 76800 #{$test_wav}"
                else
                  "rec -q #{$conf[:sox_rec_extra]} -r #{$conf[:sample_rate]} -b 16 -e signed -t wav -" +
                    ( $opts[:debug]  ?  ""  :  " 2>/dev/null" )
                end
  _, _, wait_thread  = Open3.popen2("#{sox_rec_cmd} >#{fifo}")
  wait_thread.join
  err "Command '#{sox_rec_cmd}' terminated unexpectedly\n#{$sox_rec_fail_however}"
  exit 1
end


def aubiopitch_to_queue fifo, num_samples
  aubio_cmd = "stdbuf -o0 aubiopitch --bufsize #{num_samples} --hopsize #{num_samples} --pitch #{$conf[:pitch_detection]} -i #{fifo}"
  _, aubio_out = Open3.popen2(aubio_cmd)
  ptouch = false
  loop do
    fields = aubio_out.gets.split.map {|f| f.to_f}
    $freqs_queue.enq fields[1]
    if $testing && !ptouch
      FileUtils.touch("/tmp/#{File.basename($0)}_pipeline_started") unless ptouch
      ptouch = true
    end
  end
end


def pipeline_catch_up
  $freqs_queue.clear
end


def play_hole_and_handle_kb hole, duration
  wait_thr = Thread.new do
    play_wave(this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]),
              duration)
  end  
  begin
    sleep 0.1
    # this sets $ctl_hole, which will be used by caller one level up
    handle_kb_play_holes
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_hole_or_note_simple_and_handle_kb note, duration
  
  wfile = this_or_equiv("#{$sample_dir}/%s.wav", note)
  wait_thr = Thread.new do
    if $testing
      sys "sleep #{duration}"
    else
      if wfile
        sys "play --norm=#{$vol_synth.to_db} #{$conf[:sox_play_extra]} #{wfile} trim 0 #{duration}"
      else
        sys "play -n --norm=#{$vol_synth.to_db} #{$conf[:sox_play_extra]} synth #{duration} sawtooth %#{note2semi(note)}"
      end
    end
  end  
  begin
    sleep 0.1
    # this sets $ctl_hole, which will be used by caller one level up
    handle_kb_play_holes_or_notes_simple
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_semi_and_handle_kb semi
  cmd = if $testing
          "sleep 1"
        else
          "play --norm=#{$vol_synth.to_db} -q -n #{$conf[:sox_play_extra]} synth #{( $opts[:fast] ? 1 : 0.5 )} sawtooth %#{semi}"
        end
  
  _, stdout_err, wait_thr  = Open3.popen2e(cmd)

  # loop to check repeatedly while the semitone is beeing played
  begin
    sleep 0.1
    # this sets $ctl_semi, which will be used by caller one level up
    handle_kb_play_semis
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def synth_for_inter semis, files, wfiles, gap, len
  times = [0.3, 0.3 + gap]
  files.zip(semis, times).each do |f, s, t|
    sys("sox -q -n #{$conf[:sox_play_extra]} #{wfiles[0]} trim 0.0 #{t}")
    sys("sox -q -n #{$conf[:sox_play_extra]} #{wfiles[1]} synth #{len} pluck %#{s}") 
    sys("sox -q #{$conf[:sox_play_extra]} #{wfiles[0]} #{wfiles[1]} #{f}") 
  end
end


def print_pitch_information semi, name = nil
  puts "\e[0m\e[2m#{name}\e[0m" if name
  puts "\e[0m\e[2mSemi = #{semi}, Note = #{semi2note(semi+7)}, Freq = #{'%.2f' % semi2freq_et(semi)}\e[0m"
  print "\e[0mkey of song: \e[0m\e[32m%-3s,  " % semi2note(semi+7)[0..-2]
  print "\e[0m\e[2mmatches \e[0mkey of harp: \e[0m\e[32m%-3s\e[0m" % semi2note(semi)[0..-2]
  puts
end
