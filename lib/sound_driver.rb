#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $opts[:testing]
    FileUtils.cp "/tmp/#{File.basename($0)}_testing.wav", file
    sleep secs
  else
    system "arecord -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}" or err_b "arecord failed"
  end
end


def play_sound file
  sys "aplay #{file}" unless $opts[:testing]
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch #{$conf[:pitch_detection]} #{file} 2>&1)
end


def trim_recording hole, recorded
  duration = wave2data(recorded)
  do_draw = true
  play_from = find_onset($recorded_data)
  trim_sound recorded, play_from, $trimmed_wave
  loop do
    if do_draw
      draw_data($recorded_data, play_from)
      inspect_recording(hole, recorded)
      do_draw = false
    else
      puts
    end
    puts "\e[33mTrimming\e[0m #{File.basename(recorded)} for hole \e[33m#{hole}\e[0m, play from %.2f." % play_from
    puts 'Choices: <play_from> | d:raw | y:es | q:uit | r:ecord'
    print "Your choice ('h' for help): "
    choice = one_char

    if ('0' .. '9').to_a.include?(choice) || choice == '.'
      choice = '0.' if choice == '.'
      print "Finish with RETURN: #{choice}"
      choice += STDIN.gets.chomp.downcase.strip
      numeric = true
    else
      puts choice
      numeric = false
    end
    if choice == '?' || choice == 'h'
      puts <<EOHELP

Full Help:

   <start-from> :  set position to play from (vertical line in plot);  Example:  0.4
       p, SPACE :  play from current position
              d :  draw current wave form
              y :  accept current play position and skip to next hole
              q :  discard edit
              r :  record and edit again
EOHELP
      
    elsif ['', ' ', "\r", "\n" , 'p'].include?(choice)
      puts "Play from %.2f ..." % play_from
      play_sound $trimmed_wave
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y'
      FileUtils.cp $trimmed_wave, recorded
      wave2data(recorded)
      puts "\nEdit accepted, trimmed #{File.basename(recorded)}, skipping to next hole.\n\n"
      return :next_hole
    elsif choice == 'q'
      puts "\nEdit aborted, #{File.basename(recorded)} remains untrimmed.\n\n"
      return nil
    elsif choice == 'r' || choice == 'e'
      return :redo
    elsif numeric
      begin
        val = choice.to_f
        raise ArgumentError.new('must be > 0') if val < 0
        raise ArgumentError.new("must be < duration #{duration}") if val >= duration
        play_from = val
        trim_sound recorded, play_from, $trimmed_wave
        do_draw = true
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    else
      puts "Invalid Input '#{choice}'"
    end
  end 
end


def trim_sound file, play_from, trimmed
  puts "Using 1 second of original sound, starting at %.2f" % play_from
  sys "sox #{file} #{trimmed} trim #{play_from.round(2)} #{play_from + 1.2} gain -n -3 fade 0 -0 0.2"
end


def sox_query file, property
  %x(sox #{file} -n stat 2>&1).lines.select {|line| line[property]}[0].split.last.to_f
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
  err_h "File #{fifo} already exists but is not a fifo, will not overwrite" if File.ftype(fifo) != "fifo"

  Thread.new {arecord_to_fifo(fifo)}
  Thread.new {aubiopitch_to_queue(fifo, num_samples)}
end


def arecord_to_fifo fifo
  arec_cmd = if $opts[:testing]
               "cat /tmp/#{File.basename($0)}_testing.wav /dev/zero >#{fifo}"
             else
               "arecord -r #{$sample_rate} >#{fifo} 2>/dev/null"
             end
  _, _, wait_thread  = Open3.popen2(arec_cmd)
  wait_thread.join
  err_b "command '#{arec_cmd}' terminated unexpectedly"
  exit 1
end


def aubiopitch_to_queue fifo, num_samples
  aubio_cmd = "stdbuf -o0 aubiopitch --bufsize #{num_samples * 1} --hopsize #{num_samples} --pitch #{$conf[:pitch_detection]} -i #{fifo}"
  _, aubio_out = Open3.popen2(aubio_cmd)
  
  loop do
    fields = aubio_out.gets.split.map {|f| f.to_f}
    sleep 0.1 if $opts[:testing]
    $jitter = Time.now.to_f - $program_start - fields[0]
    $freqs_queue.enq fields[1]
  end
end


def pipeline_catch_up
  $freqs_queue.clear
end
