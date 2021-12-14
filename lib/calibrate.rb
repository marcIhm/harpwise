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

Letting this program generate your samples is a good way to get started
quickly. The notes will be in "equal temperament" (rather than "just
tuning").

However, the generated notes and their frequencies cannot match those of
your own special harp or style of playing very well. Therefore, later, you
may want to repeat the calibration by playing yourself (i.e. without
option '--auto').


If, on the other hand you already have samples, recorded by yourself, they
will be overwritten in this process !

  So, in that case, consider, \e[32mSAVING\e[0m such samples before !

(to do so, you may bail out now, by pressing ctrl-c)

EOINTRO

  print "\nPress RETURN to generate and play all samples for \e[32mkey of #{$key}\e[0m in a single run: "
  STDIN.gets

  hole2freq = Hash.new
  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    synth_sound hole, file
    play_sound file
    hole2freq[hole] = analyze_with_aubio(file)
  end
  write_freq_file hole2freq
  puts "\nFrequencies in: #{$freq_file}"
  puts "\n\nRecordings \e[32mdone.\e[0m\n\n\n"
end


def do_calibrate_assistant

  if $opts[:hole] && !$harp_holes.include?($opts[:hole])
    err_b "Argument to Option '--hole', '#{$opts[:hole]} is none of #{$harp_holes.inspect}"
  end

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)

  holes = if $opts[:hole]
            $harp_holes[$harp_holes.find_index($opts[:hole]) .. -1]
          else
            $harp_holes
          end

  puts <<EOINTRO


This is an interactive assistant, that will ask you to play these holes of
your harmonica, key of #{$key}, one after the other, each for one second:

  \e[32m#{holes.join(' ')}\e[0m

Each recording is preceded by a short countdown (2,1).
If there already is a recording, it will be plotted first.

For each hole, 3 seconds will be recorded and you will get a chance to
manually cut off initial silence; then the recording will be truncated to 1
second. So you may well wait for the actual red \e[31mrecording\e[0m mark
before starting to play.

The harp, that you use now for calbration, should be the one, that you will
use for your practice later.


Background: Those samples will be used to determine the frequencies of your
  particular harp and will be played directly in mode 'quiz'.

Hint: If you want to calibrate for another key of harp, you might copy the
  whole directory below 'samples' and record only those notes that are
  missing.

Tips: You may invoke this assistant again at any later time, just to review
  your recorded notes and maybe correct some of them. 
  Results are written to disk immediately, so you may end the process
  after any hole. To record a specific hole only, use option
  '--hole'.

  After all holes have been recorded, a summary of all frequencies will be
  shown, so that you may do an overall check of your recordings.

EOINTRO

  print "Press any key to start with the first hole\n"
  print "   or type 's' to skip directly to summary: "
  char = one_char
  print "\n\n"

  if File.exist?($freq_file)
    hole2freq = yaml_parse($freq_file)
  else
    hole2freq = Hash.new
  end

  unless char == 's'
    (0 .. holes.length - 1).each do |i|
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
        redo
      end
      break if what == :quit
    end
  end
  puts "Recordings in #{$sample_dir}"
  puts "\nSummary of recorded frequencies:\n\n"
  puts '       Hole  |  Freq  |    ET  | Diff |   Remark'
  puts '  ------------------------------------------------'
  maxhl = $harp_holes.map(&:length).max
  $harp_holes.each do |hole|
    semi = note2semi($harp[hole][:note])
    freq = hole2freq[hole]
    freq_et = semi2freq_et(semi)
    freq_et_p1 = semi2freq_et(semi + 1)
    freq_et_m1 = semi2freq_et(semi - 1)
    remark = if (freq_et_m1 - freq).abs < (freq_et - freq).abs
               ' too low' 
             elsif (freq_et_p1 - freq).abs < (freq_et - freq).abs
               'too high' 
             else
               ''
             end
    print '    %8s | %6.2d | %6.2d | %4d | %s ' % [hole.ljust(maxhl), freq, freq_et, freq - freq_et, remark]
    puts
  end
  puts "\nYou may compare recorded frequencies with those calculated from equal temperament tuning. Remarks indicate, if the frequency of any recording is nearer to a neighboring semitone than to the target one."
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def record_and_review_hole hole

  recorded = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
  if File.exists?(recorded)
    puts "\nHole  \e[32m#{hole}\e[0m  need not be recorded or generated, because #{recorded} already exists."
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
        draw_data($recorded_data, 0)
      end
            
      if do_trim  # false on first iteration
        puts issue_before_trim if issue_before_trim
        issue_before_trim = false
        result = trim_recording(hole, recorded)
        if result == :redo
          puts "Redo recording and trim ..."
          do_record, do_draw, do_trim = [true, false, true]
          redo                         
        elsif result == :next_hole
          return :next, analyze_with_aubio(recorded)
        end
      end
      
      freq = inspect_recording(hole, recorded)
      
    end

    # get user input
    puts "\n\e[33mReview and/or record\e[0m hole   \e[33m#{hole}\e[0m   (key of #{$key})"
    choices = {:play => [['p', 'SPACE'], 'play recorded', 'play recorded sound'],
               :draw => [['d'], 'draw sound', 'draw sound data (again)'],
               :frequency => [['f'], 'frequency sample', 'show and play the ET frequency of the hole by generating and analysing a sample sound; does not overwrite current recording'],
               :record => [['r'], 'record and trim', 'record and trim RIGHT AWAY (after countdown)'],
               :trim => [['t'], 'trim', 'trim recorded sound, i.e. set start for play'],
               :generate => [['g'], 'generate', 'generate a sound for the ET frequency of the hole'],
               :back => [['b'], 'back', 'go back to previous hole'],
               :quit => [['q', 'x'], 'exit', 'exit from calibration but still save frequency of current hole']}
    
    choices[:okay] = [['y', 'RETURN'], 'keep recording and on', 'keep recording and continue'] if File.exists?(recorded)
    
    answer = read_answer(choices)

    # operations will be in this sequence if set below according to user input
    do_record, do_draw, do_trim = [false, false, false]
    case answer
    when :play
      print 'Play ... '
      play_sound recorded
      puts 'done'
    when :trim
      do_trim = true
    when :draw
      do_draw = true
    when :back
      return :back, freq
    when :quit
      return :quit, freq
    when :frequency
      print 'Generate and analyse a sample sound:'
      synth_sound hole, $helper_wave
      play_sound $helper_wave
      puts "Frequency: #{analyze_with_aubio($helper_wave)}"
      puts "done\n\n"
    when :generate
      synth_sound hole, recorded
      wave2data(recorded)
      do_draw = true
    when :record
      do_record, do_draw, do_trim = [true, false, true]
      issue_before_trim = "\nTrimming recorded sound right away ...\n\n"
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
