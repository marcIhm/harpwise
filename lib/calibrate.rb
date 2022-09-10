# -*- fill-column: 74 -*-

#
# Assistant and automate for calibration
#

def do_calibrate_auto

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  puts <<EOINTRO

(type #{$type}, key of #{$key})


This will generate all needed samples for holes:

  \e[32m#{$harp_holes.each_slice(12).to_a.map{|s| s.join('  ')}.join("\n  ")}\e[0m

Letting this harpwise generate your samples is a good way to get started
quickly. The notes will be in "equal temperament" tuning.

However, any generated notes and their frequencies cannot match those of
your own special harp or style of playing very well. Therefore, later, you
may want to repeat the calibration by playing yourself (i.e. without
option '--auto').


If, on the other hand, you already have samples, recorded by yourself, in

  #{$sample_dir}

they will be overwritten in this process !

So, in that case, consider to \e[32mBACK UP\e[0m such samples before !

EOINTRO

  print "\nType 'y' to generate and play all samples for \e[32mkey of #{$key}\e[0m in a single run: "
  char = one_char
  print "\n\n"

  if char != 'y'
    puts 'Calibration aborted on user request.'
    exit 0
  end
  hole2freq = Hash.new
  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    synth_sound hole, file
    play_sound file
    hole2freq[hole] = analyze_with_aubio(file)
  end
  write_freq_file hole2freq
  puts "\nFrequencies in: #{$freq_file}"
  print_summary hole2freq, 'generated'
  puts "\nREMARK: You may wonder, why the generated frequencies do not follow equal"
  puts "temperament \e[32mexactly\e[0m and why there can be a deviation in frequency \e[32mat all\e[0m;"
  puts "this is simply because two programs are used for generation and analysis:"
  puts "sox and aubiopitch; both do a great job on their field, however sometimes"
  puts "they differ by a few Hertz."
  puts "\n\nRecordings \e[32mdone.\e[0m\n\n\n"
end


def do_calibrate_assistant

  if $opts[:hole] && !$harp_holes.include?($opts[:hole])
    err "Argument to Option '--hole', '#{$opts[:hole]}' is none of #{$harp_holes.inspect}"
  end

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)

  holes = if $opts[:hole]
            $harp_holes[$harp_holes.find_index($opts[:hole]) .. -1]
          else
            $harp_holes
          end

  puts ERB.new(IO.read("#{$dirs[:install]}/resources/calibration_intro.txt")).result(binding)

  print "Press any key to start with the first hole\n"
  print "  or type 's' to skip directly to summary: "
  char = one_char
  print "\n\n"

  if File.exist?($freq_file)
    hole2freq = yaml_parse($freq_file)
  else
    hole2freq = Hash.new
  end

  unless char == 's'
    i = 0
    begin
      hole = holes[i]
      what, freq = record_and_review_hole(hole)
      if freq
        hole2freq[hole] = freq
        write_freq_file hole2freq
      end
      
      if what == :back
        if i == 0
          puts "\n\n\e[31mCANNOT GO BACK !\e[0m  Already at first hole.\n\n\n"
          sleep 0.5
        else
          i -= 1
        end
      else
        i += 1
      end
      break if what == :quit
    end while what != :quit && i < holes.length
  end
  print_summary hole2freq, 'recorded'
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def record_and_review_hole hole

  recorded = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
  if File.exists?(recorded)
    puts "\nThere is already a generated or recorded sound present for hole  \e[32m#{hole}\e[0m"
    wave2data(recorded)
  else
    puts "\nFile  #{recorded}  for hole  \e[32m#{hole}\e[0m  is not present so it needs to be recorded or generated."
  end
  issue_before_trim = false

  # This loop contains all the operations record, trim and draw as well as some checks and user input
  # the sequence of these actions is fixed; if they are executed at all is determined by do_xxx
  # For the first loop iteration this is set below, for later iterations according to user input
  do_record, do_draw, do_trim = [false, true, false]
  freq = nil
  
  begin  # while answer != :okay

    if do_record  # false on first iteration
      puts "\nRecording hole  \e[32m#{hole}\e[0m  when '\e[31mRECORDING\e[0m' appears."
      [2, 1].each do |c|
        puts c
        sleep 1
      end

      # Discard stale samples (which we recognize, because they are delivered too fast)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $helper_wave, silent: true
      end while Time.now.to_f - tstart_record < 0.1
      
      puts "\e[31mRECORDING\e[0m to #{recorded} ..."
      record_sound 3, recorded
      wave2data(recorded)
      
      puts "\e[32mdone\e[0m"
    end

    
    if File.exists?(recorded)  # normally true, can only be false on first iteration
      
      if do_draw && !do_trim  # true on first iteration
        draw_data($recorded_data, 0, 0)
      end
            
      if do_trim  # false on first iteration
        puts issue_before_trim if issue_before_trim
        issue_before_trim = false
        result = trim_recording(hole, recorded)
        if result == :redo
          do_record, do_draw, do_trim = [true, false, true]
          redo                         
        elsif result == :next_hole
          return :next, analyze_with_aubio(recorded)
        end
      end
      
      freq = inspect_recording(hole, recorded)
      
    end

    # get user input
    puts "\e[93mReview and/or record\e[0m hole   \e[33m#{hole}\e[0m   (key of #{$key})"
    choices = {:play => [['p', 'SPACE'], 'play recording', 'play recorded sound'],
               :draw => [['d'], 'draw sound', 'draw sound data (again)'],
               :frequency => [['f'], 'frequency sample', 'show and play the ET frequency of the hole by generating and analysing a sample sound; does not overwrite current recording'],
               :record => [['r'], 'record and trim', 'record RIGHT AWAY (after countdown); then trim recording and remove initial silence and surplus length'],
               :generate => [['g'], 'generate sound', 'generate a sound for the ET frequency of the hole'],
               :back => [['b'], 'back to prev hole', 'jump back to previous hole']}
    
    choices[:okay] = [['y', 'RETURN'], 'accept and continue', 'continue to next hole'] if File.exists?(recorded)
    choices[:quit] = [['q'], 'quit calibration', 'exit from calibration']
    
    answer = read_answer(choices)

    # operations will be in this sequence if set below according to user input
    do_record, do_draw, do_trim = [false, false, false]
    case answer
    when :play
      print "\e[33mPlay\e[0m ... "
      play_sound recorded
      puts 'done'
    when :draw
      do_draw = true
    when :back
      return :back, freq
    when :quit
      return :quit, freq
    when :frequency
      print "\e[33mGenerate\e[0m and analyse a sample sound:"
      synth_sound hole, $helper_wave
      play_sound $helper_wave
      puts "Frequency: #{analyze_with_aubio($helper_wave)}"
    when :generate
      synth_sound hole, recorded
      wave2data(recorded)
      do_draw = true
    when :record
      do_record, do_draw, do_trim = [true, false, true]
      issue_before_trim = "\e[33mTrimming\e[0m recorded sound right away ...\n"
    end
    
  end while answer != :okay

  return :next, freq
end


def write_freq_file hole2freq
  # Recreate the hash in order of $harp_holes
  hole2freq_sorted = Hash.new
  [$harp_holes + hole2freq.keys].flatten.each do |hole|
    hole2freq_sorted[hole] = hole2freq[hole]
  end
  File.write($freq_file, YAML.dump(hole2freq_sorted))
end


def print_summary hole2freq, rec_or_gen
  template = '    %8s | %8s | %8s | %6s | %6s | %s '
  puts "Recordings in #{$sample_dir}"
  puts "\nSummary of #{rec_or_gen} frequencies:\n\n"
  puts template % %w(Hole Freq ET Diff Cents Gauge)
  puts '  ------------' + '-' * (template % ['','','','','','']).length
  maxhl = $harp_holes.map(&:length).max
  $harp_holes.each do |hole|
    semi = note2semi($harp[hole][:note])
    freq = hole2freq[hole]
    unless freq
      puts template % [hole.ljust(maxhl), '', '', '', 'not yet #{rec_or_gen}']
      next
    end
    freq_et = semi2freq_et(semi)
    freq_et_p1 = semi2freq_et(semi + 1)
    freq_et_m1 = semi2freq_et(semi - 1)
    gauge = if (freq_et_m1 - freq).abs < (freq_et - freq).abs
              ' too low' 
            elsif (freq_et_p1 - freq).abs < (freq_et - freq).abs
              'too high' 
            else
              get_dots('........:........', 2, freq, freq_et_m1, freq_et, freq_et_p1) {|hit, idx| idx}[0]
            end
    puts template % [hole.ljust(maxhl), freq.round(0), freq_et.round(0), (freq - freq_et).round(0), cents_diff(freq, freq_et).round(0), gauge]
  end
  puts "\nYou may compare #{rec_or_gen} frequencies with those calculated from equal"
  puts "temperament tuning. The gauge shows the difference in frequency between"
  puts "#{rec_or_gen} and target frequency (:); left and right border are the"
  puts "neighbouring semitones."
end
