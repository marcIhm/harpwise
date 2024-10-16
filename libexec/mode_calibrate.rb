# -*- fill-column: 74 -*-

#
# Assistant and automate for calibration
#

def do_calibrate_auto to_handle

  err "Can handle only the single argument 'all', not:   #{to_handle.join('  ')}" if to_handle.length > 1 || ( to_handle.length == 1 && to_handle[0] != 'all' )
  do_all = ( to_handle.length > 0 )

  all_keys = if do_all
               $all_harp_keys
             else
               [$key]
             end

  your_own = <<EOYOUROWN
Letting harpwise generate your samples is the preferred way to get
started.  The frequencies will be in "equal temperament" tuning.

But please note, that the generated samples and their frequencies
cannot match those of your own harp or style very well. So, later,
you may want to repeat the calibration by playing yourself
EOYOUROWN
  
  if do_all
    puts <<EOINTRO

\e[2m(type #{$type})\e[0m


This will \e[32mautomatically\e[0m generate all needed samples
for \e[32mall holes\e[0m of \e[32mall keys\e[0m:

  \e[32m#{all_keys.each_slice(12).to_a.map{|s| s.join('  ')}.join("\n  ")}\e[0m

harmonica type is #{$type}. Other types still require their
own calibration.

Be warned, that any prior manual calibration, e.g. hole-sample you
haveplayed yourself, will be overwritten in this process.

#{your_own.chomp}
e.g. for a specific key via 'harpwise calibrate c'
EOINTRO

    puts "\nNow, type 'y' to let harpwise generate all samples for all keys."
    char = one_char
    puts
    
    if char != 'y'
      puts "Calibration aborted on user request ('#{char}')."
      puts
      exit 0
    end

  end
  
  all_keys.each_with_index do |key, idx|

    $key = key
    
    if do_all
      puts "Calibrating for key of   \e[92m#{$key}\e[0m   [#{idx+1}/#{all_keys.length}]\n"
    else
      puts <<EOINTRO

\e[2m(type #{$type}, key of #{$key})\e[0m


This will generate all needed samples for holes:

  \e[32m#{$harp_holes.each_slice(12).to_a.map{|s| s.join('  ')}.join("\n  ")}\e[0m

Harmonica type   #{$type},   key of   #{$key};   other keys or types will require
their own calibration, but only once.

#{your_own.chomp}
without option '--auto', i.e. 'harpwise calibrate #{$key}'
EOINTRO

      puts "\nNow, type 'y' to let harpwise generate all samples for the \e[32mkey of #{$key}\e[0m"
      char = one_char
      puts
      
      if char != 'y'
        puts "Calibration aborted on user request ('#{char}')."
        puts
        exit 0
      end
    end

    set_global_vars_late
    set_global_musical_vars
    FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)    
    
    hole2freq = Hash.new
    $harp_holes.each_with_index do |hole, idx|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      synth_sound hole, file, " (%2d of #{$harp_holes.length})" % (idx + 1), silent: do_all
      print "\e[2m#{hole}\e[0m  " if do_all
      play_wave file, 0.5 unless do_all
      hole2freq[hole] = analyze_with_aubio(file)
    end
    write_freq_file hole2freq
    puts "\nFrequencies in: #{$freq_file}"
    if do_all
      puts "\n"
    else
      print_summary hole2freq, 'generated'
      puts "\nREMARK: You may wonder, why the generated frequencies do not follow equal"
      puts "temperament \e[32mexactly\e[0m and why there can be a deviation in frequency \e[32mat all\e[0m;"
      puts "this is simply because two programs are used for generation and analysis:"
      puts "sox and aubiopitch; both do a great job on their field, however sometimes"
      puts "they differ by a few Hertz."
      puts
    end
  end
  puts
  puts "Calibration \e[32mdone.\e[0m\n\n\n"    
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

  print "\nPress any key to start with the first hole\n"
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
      elsif what == :cancel
        # keep current value of i
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

  sample_file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
  backup = "#{$sample_dir}/backup.wav"
  if File.exist?(sample_file)
    puts "\nThere is already a generated or recorded sound present for hole  \e[32m#{hole}\e[0m"
    puts "\e[2m#{sample_file}\e[0m"
    wave2data(sample_file)
    FileUtils.cp(sample_file, backup)
  else
    puts "\nFile  #{sample_file}  for hole  \e[32m#{hole}\e[0m  is not present so it needs to be recorded or generated."
  end
  issue_before_trim = false

  # This loop contains all the operations record, trim and draw as well as some checks and user input
  # the sequence of these actions is fixed; if they are executed at all is determined by do_xxx
  # For the first loop iteration this is set below, for later iterations according to user input
  do_record, do_draw, do_trim = [false, true, false]
  freq = nil
  
  begin  # while answer != :okay

    # false on first iteration
    if do_record 
      rec_dura = 3
      puts "\nRecording #{rec_dura} secs for hole  \e[32m#{hole}\e[0m  when '\e[0;101mRECORDING\e[0m' appears."
      [2, 1].each do |c|
        puts c
        sleep 1
      end

      # Discard stale samples (which we recognize, because they are delivered too fast)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $helper_wave, silent: true
      end while Time.now.to_f - tstart_record < 0.1

      puts "\e[0;101mRECORDING\e[0m to #{sample_file} ..."
      record_sound rec_dura, sample_file
      wave2data(sample_file)
      
      puts "\e[32mdone\e[0m"
    end

    # normally true, can only be false on first iteration
    if File.exist?(sample_file)  
   
      # true on first iteration
      wave2data(sample_file)
      draw_data(0, 0) if do_draw && !do_trim  

      # false on first iteration
      if do_trim  
        puts issue_before_trim if issue_before_trim
        issue_before_trim = false
        result = trim_recorded(hole, sample_file)
        if result == :redo
          do_record, do_draw, do_trim = [true, false, true]
          redo                         
        elsif result == :next || result == :cancel
          FileUtils.mv(backup, sample_file) if result == :cancel && File.exist?(backup)
          FileUtils.rm(backup) if File.exist?(backup)
          return result, analyze_with_aubio(sample_file)
        end
      end
      
      freq = inspect_recorded(hole, sample_file)
      
    end

    # get user input
    # ruler for 75 chars:
    #            ---------------------------------------------------------------------------
    puts "\e[34mReview and/or record\e[0m hole   \e[32m#{hole}\e[0m   (key of #{$key})"
    choices = {:play =>
               [['p', 'SPACE'],
                'play current recording',
                'play current recording'],
               :draw =>
               [['d'],
                'draw sound',
                'draw sound data (again)'],
               :frequency =>
               [['f'],
                'play frequency sample',
                'show and play the ET frequency of the hole by generating and',
                'analysing a sample sound; does not overwrite current recording'],
               :record =>
               [['r'],
                'record and trim',
                'record RIGHT AWAY (after countdown); then trim recording',
                'and remove initial silence and surplus length'],
               :generate =>
               [['g'],
                'generate sound',
                'generate a sound (instead of recording it) for the',
                'ET frequency of the hole'],
               :back =>
               [['b'],
                'back to prev hole',
                'jump back to previous hole and discard work on current']}
    choices[:okay] = [['y', 'RETURN'], 'accept and continue', 'continue to next hole'] if File.exist?(sample_file)
    choices[:quit] = [['q'], 'quit calibration', 'exit from calibration']
    
    answer = read_answer(choices)

    # operations will be in this sequence if set below according to user input
    do_record, do_draw, do_trim = [false, false, false]
    case answer
    when :play
      if File.exist?(sample_file)
        print "\e[34mPlay\e[0m ... "
        play_wave sample_file, 5
        puts 'done'
      else
        print "\e[31mFile #{sample_file} does not exist !\e[0m\n"
      end
    when :draw
      do_draw = true
    when :back
      return :back, freq
    when :quit
      return :quit, freq
    when :frequency
      print "\e[0m\e[34mGenerate\e[0m and analyse a sample sound:"
      synth_sound hole, $helper_wave
      play_wave $helper_wave, 0.25
      puts "Frequency: #{analyze_with_aubio($helper_wave)}"
    when :generate
      synth_sound hole, sample_file
      wave2data(sample_file)
      do_draw = true
    when :record
      do_record, do_draw, do_trim = [true, false, true]
      issue_before_trim = "\e[0m\e[34mTrimming\e[0m recorded sound right away ...\n"
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
