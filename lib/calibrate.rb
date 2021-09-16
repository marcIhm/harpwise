# -*- fill-column: 78 -*-

#
# Assistant and automate for calibration
#

def do_calibrate_auto

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  puts <<EOINTRO


This will generate all needed samples for holes:

  \e[32m#{$holes.join(' ')}\e[0m

Letting this program generate your samples is a good way to get started
quickly.  However, the generated notes and their frequencies cannot match
those of your own special harp or style of playing very well. Therefore,
later, you may want to repeat the calibration by playing yourself
(i.e. without option '--auto').


If, on the other hand you already have samples, recorded by yourself, they
will be overwritten in this process !

  So, in that case, consider, \e[32mSAVING\e[0m such samples before !

(to do so, you may bail out now, by pressing ctrl-c)

EOINTRO

  print "\nPress RETURN to generate and play all samples in a single run: "
  STDIN.gets

  hole2freq = Hash.new
  freqs = Array.new
  $holes.each do |hole|
    file = synth_sound hole
    play_sound file
    hole2freq[hole] = analyze_with_aubio(file)
  end
  ffile = "#{$sample_dir}/frequencies.json"
  File.write(ffile, JSON.pretty_generate(hole2freq))
  puts "\nFrequencies in: #{ffile}"
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def do_calibrate_assistant
  
  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  if hole && !$holes.include?(hole)
    err_h "Only hole given to calibrates (#{hole}) is none of these: #{$holes}"   
  end
  puts <<EOINTRO


This is an interactive assistant, that will ask you to play these
holes of your harmonica one after the other, each for one second:

  \e[32m#{$holes.join(' ')}\e[0m

Each recording is preceded by a short countdown (2,1).
If there already is a recording, it will be plotted first.

For each hole, 3 seconds will be recorded and silence will be cut off front
and rear; then the recording will be truncated to 1 second. So you may well
wait for the actual red \e[31mrecording\e[0m mark before starting to play.

The harp, that you use now for calbration, should be the one, that you will
use for your practice later.


Background: Those samples will be used to determine the frequencies of your
  particular harp and will be played directly in mode 'quiz'.

Hint: If you want to calibrate for another key of harp, you might copy the
  whole directory below 'samples' and record only those notes that are
  missing.

Tip: You may invoke this assistant again at any later time, just to review
  your recorded notes and maybe correct some of them.


EOINTRO

  print "Press RETURN to start with the \e[32mfirst\e[0m hole: "
  STDIN.gets

  if hole
    ffile = "#{$sample_dir}/frequencies.json"
    err_b "Frequence file #{ffile} does not exist yet; do a full calibration first" unless File.exist?(ffile)
    hole2freq = JSON.parse(File.read(ffile))
    freqs = hole2freq.values
    i = $holes.find_index(hole)
    hole2freq[hole] = freqs[i] = review_hole(hole, freqs[i-1] || 0)
    if freqs[i] < 0
      puts "Hole #{hole} has not been recorded; exiting ..."
      exit 0
    end
  else
    hole2freq = Hash.new
    freqs = Array.new
    i = 0
    begin
      hole = $holes[i]
      freqs[i] = review_hole(hole, freqs[i-1] || 0)
      if freqs[i] < 0
        if i > 0 
          puts "Skipping  \e[32mback\e[0m  !"
          i -= 1
        else
          puts "Cannot skip, back already at first hole ..."
        end
      else
        hole2freq[hole] = freqs[i]
        i += 1
      end
    end while i <= $holes.length - 1
  end
  File.write("#{$sample_dir}/frequencies.json", JSON.pretty_generate(hole2freq))
  system("ls -lrt #{$sample_dir}")
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def review_hole hole, prev_freq

  file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
  do_draw = true
  do_edit = false
  if File.exists?(file)
    initial_issue = "\nHole  \e[32m#{hole}\e[0m  need not be recorded or generated, because #{file} already exists."
    duration = wave2data(file)
    do_record = false
  else
    do_record = true
  end
  issue_before_edit = initial_issue = false

  begin
      
    if do_record
      puts "\nRecording hole  \e[32m#{hole}\e[0m  when '\e[31mrecording\e[0m' appears."
      [2, 1].each do |c|
        puts "\e[31m#{c}\e[0m"
        sleep 1
      end
      
      # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $sample_file, silent: true
      end while Time.now.to_f - tstart_record < 0.1
      
      puts "\e[31mrecording\e[0m to #{file} ..."
      record_sound 3, file
      duration = wave2data(file)
      
      puts "\e[32mdone\e[0m"
      do_draw = true
    end

    if do_draw
      draw_data($edit_data, 0, duration, 0)
      print "Analysis: "
      freq = analyze_with_aubio(file)
    end
    puts initial_issue if initial_issue
    initial_issue = false

    if do_edit
      puts issue_before_edit if issue_before_edit
      issue_before_edit = false
      result = edit_sound(hole, file)
      if  result == :redo
        puts "Redo ..."
        redo                         
      elsif result == :next_hole
        return analyze_with_aubio(file)
      end
    end

    print "Analysis: "
    freq = analyze_with_aubio(file)
    
    if freq < prev_freq
      puts "\n\nWAIT !"
      puts "The frequency recorded for \e[33m#{hole}\e[0m (= #{freq}) is \e[31mLOWER\e[0m than the frequency recorded before (= #{prev_freq}) !"
      puts "Therefore this recording cannot be accepted and you need to redo !"
      puts "\nIf however you feel, that the error is in the PREVIOUS recording already,"
      puts "you may want to skip back to the previous hole ...\n\n"
    end

    puts "\n\e[33mWhat's next\e[0m for hole \e[33m#{hole}\e[0m ?"
    choices = {:play => [['p', 'SPACE'], 'play recorded sound'],
               :edit => [['e'], 'edit recorded sound, i.e. set start for play'],
               :draw => [['d'], 'redraw sound data'],
               :record => [['r'], "record RIGHT AWAY (after countdown)"],
               :generate=> [['g'], 'generate a sound for the holes nominal frequency'],
               :back => [['b'], 'skip back to previous hole']}
    
    choices[:okay] = [['k', 'RETURN'], 'keep recording and continue'] if freq >= prev_freq
    
    answer = read_answer(choices)

    do_edit = do_draw = do_record = false
    case answer
    when :play
      print "\nplay ... "
      play_sound file
      puts "done\n"
    when :edit
      do_edit = do_draw = true
    when :draw
      do_draw = true
    when :generate
      synth_sound hole
      do_draw = true
    when :record
      do_draw = do_record = do_edit = true
      issue_before_edit = 'Editing recorded sound right away ...'
    when :back, :cancel
      return -1
    end
    
  end while answer != :okay

  return freq
end


def analyze_with_aubio file
  samples = run_aubiopitch(file).lines.
              map {|l| l.split[1].to_i}.
              select {|f| f>0}.
              sort
  pks = get_two_peaks samples, 10
  puts "Peaks: #{pks.inspect}"
  pks[0][0]
end


