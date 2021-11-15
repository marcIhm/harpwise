# -*- fill-column: 78 -*-

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
quickly. The notes will be in "equal temperament" (rather than "just tuning").

However, the generated notes and their frequencies cannot match those of your
own special harp or style of playing very well. Therefore, later, you may want
to repeat the calibration by playing yourself (i.e. without option '--auto').


If, on the other hand you already have samples, recorded by yourself, they
will be overwritten in this process !

  So, in that case, consider, \e[32mSAVING\e[0m such samples before !

(to do so, you may bail out now, by pressing ctrl-c)

EOINTRO

  print "\nPress RETURN to generate and play all samples for \e[32mkey of #{$key}\e[0m in a single run: "
  STDIN.gets

  hole2freq = Hash.new
  freqs = Array.new
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
  Results are written to disk immediately, so you may interrupt the process
  with ctrl-c after any hole. To record a specific hole only, use option
  '--hole'.


EOINTRO

  print "Press RETURN to start with the \e[32mfirst\e[0m hole: "
  STDIN.gets

  if File.exist?($freq_file)
    hole2freq = yaml_parse($freq_file)
  else
    hole2freq = Hash.new
  end
  freqs = Array.new

  holes.each do |hole|
    what, freq = record_and_review_hole(hole)
    if freq
      hole2freq[hole] = freq
      freqs << freq
      write_freq_file hole2freq
    end

    break if what == :quit
  end
  puts "Recordings in #{$sample_dir}"
  puts "\nSummary of recorded frequencies:\n\n"
  $harp_holes.each do |hole|
    puts "  Hole %-8s, Frequency: %6.2d   (ET: %6.2d)" % [hole, hole2freq[hole], semi2freq_et(note2semi($harp[hole][:note]))]
  end
  puts "\n(you may compare recorded frequencies with those calculated from equal temperament tuning)"
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def record_and_review_hole hole

  file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
  if File.exists?(file)
    puts "\nHole  \e[32m#{hole}\e[0m  need not be recorded or generated, because #{file} already exists."
    duration = wave2data(file)
  else
    puts "\nFile  #{file}  for hole  \e[32m#{hole}\e[0m  is not present so it needs to be recorded or generated."
  end
  issue_before_edit = false

  # This loop contains all the operations record, edit and draw as well as some checks and user input
  # the sequence of these actions is fixed; if they are executed at all is determined by do_xxx
  # For the first loop iteration this is set below, for later iterations according to user input
  do_record = false
  do_draw = true
  do_edit = false
  freq = nil
  begin  # while answer != :okay

    if do_record  # false on first iteration
      puts "\nRecording hole  \e[32m#{hole}\e[0m  when '\e[31mrecording\e[0m' appears."
      [2, 1].each do |c|
        puts "\e[31m#{c}\e[0m"
        sleep 1
      end

      # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $collect_wave, silent: true
      end while Time.now.to_f - tstart_record < 0.1
      
      puts "\e[31mrecording\e[0m to #{file} ..."
      record_sound 3, file
      duration = wave2data(file)
      
      puts "\e[32mdone\e[0m"
      do_draw = true
    end

    
    if File.exists?(file)  # normally true, can only be false on first iteration
      
      if do_draw  # true on first iteration
        draw_data($edit_data, 0, duration, 0)
        rec_ok, freq = inspect_recording(hole, file)
        do_edit = false unless rec_ok
      end
      
      
      if do_edit  # false on first iteration
        puts issue_before_edit if issue_before_edit
        issue_before_edit = false
        result = edit_sound(hole, file)
        if  result == :redo
          puts "Redo ..."
          redo                         
        elsif result == :next_hole
          return :next, analyze_with_aubio(file)
        end
      end

      
      if !do_draw  # false on first iteration
        _, freq = inspect_recording(hole, file)
      end
      
    end

    # get user input
    puts "\n\e[33mWhat's next\e[0m for hole   \e[33m#{hole}\e[0m   (key of #{$key}) ?"
    choices = {:play => [['p', 'SPACE'], 'play recorded sound'],
               :edit => [['e'], 'edit recorded sound, i.e. set start for play'],
               :draw => [['d'], 'redraw sound data'],
               :record => [['r'], "record RIGHT AWAY (after countdown)"],
               :generate => [['g'], 'generate a sound for the holes ET frequency'],
               :frequency => [['f'], "show and play the ET frequency of the hole by generating and\n              analysing a sample sound; does not overwrite current recording"],
               :quit => [['q', 'x'], 'exit from calibration but still save frequency of current hole']}
    
    choices[:okay] = [['RETURN'], 'keep sound and continue'] if File.exists?(file)
    
    answer = read_answer(choices)

    # operations will be in this sequence if set below according to user input
    do_record = do_draw = do_edit = false
    case answer
    when :play
      print "play ... "
      play_sound file
      puts "done\n"
    when :edit
      do_draw = do_edit = true
    when :draw
      do_draw = true
    when :quit
      return :quit, freq
    when :frequency
      print "--- Generate and analyse a sample sound:"
      synth_sound hole, $collect_wave
      play_sound $collect_wave
      puts "Frequency: #{analyze_with_aubio($collect_wave)}"
      puts "--- done\n\n"
    when :generate
      synth_sound hole, file
      duration = wave2data(file)
      do_draw = true
    when :record
      do_record = do_draw = do_edit = true
      issue_before_edit = 'Editing recorded sound right away ...'
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
