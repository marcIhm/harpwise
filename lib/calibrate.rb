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
    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
    synth_sound hole, file
    play_sound file
    hole2freq[hole] = analyze_with_aubio(file)
  end
  File.write($freq_file, JSON.pretty_generate(hole2freq))
  puts "\nFrequencies in: #{$freq_file}"
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def do_calibrate_assistant

  if $opts[:hole] && !$holes.include?($opts[:hole])
    err_b "Argument to Option '--hole', '#{$opts[:hole]} is none of #{$holes.inspect}"
  end

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  hole_desc = $opts[:hole] ? "#{$opts[:hole]} and beyond" : $holes.join(' ')
  puts <<EOINTRO


This is an interactive assistant, that will ask you to play these
holes of your harmonica one after the other, each for one second:

  \e[32m#{hole_desc}\e[0m

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
  with ctrl-c after any hole. To start with a specific hole use option
  '--hole'.


EOINTRO

  print "Press RETURN to start with the \e[32mfirst\e[0m hole: "
  STDIN.gets

  if File.exist?($freq_file)
    hole2freq = JSON.parse(File.read($freq_file))
  else
    hole2freq = Hash.new
  end
  freqs = Array.new
  i = $opts[:hole] ? $holes.index($opts[:hole]) : 0

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
    File.write($freq_file, JSON.pretty_generate(hole2freq))
  end while i <= $holes.length - 1
  system("ls -lrt #{$sample_dir}")
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def review_hole hole, prev_freq

  file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
  do_draw = true
  do_edit = false
  do_record = false
  if File.exists?(file)
    puts "\nHole  \e[32m#{hole}\e[0m  need not be recorded or generated, because #{file} already exists."
    duration = wave2data(file)
  else
    puts "\nFile  #{file}  for hole  \e[32m#{hole}\e[0m  is not present so it needs to be recorded or generated."
  end
  issue_before_edit = false

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
        record_sound 0.2, $collect_wave, silent: true
      end while Time.now.to_f - tstart_record < 0.1
      
      puts "\e[31mrecording\e[0m to #{file} ..."
      record_sound 3, file
      duration = wave2data(file)
      
      puts "\e[32mdone\e[0m"
      do_draw = true
    end

    if File.exists?(file)
      if do_draw
        draw_data($edit_data, 0, duration, 0)
        puts "Analysis of current recorded/generated sound: "
        freq = analyze_with_aubio(file)
        puts "Frequency: #{freq}"
      end
      
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

      if !do_draw
        puts "Analysis of current recorded/generated sound: "
        freq = analyze_with_aubio(file)
        puts "Frequency: #{freq}"
      end
    
      if freq < prev_freq
        puts "\n\nWAIT !"
        puts "The frequency recorded for \e[33m#{hole}\e[0m (= #{freq}) is \e[31mLOWER\e[0m than the frequency recorded before (= #{prev_freq}) !"
        puts "Therefore this recording cannot be accepted and you need to redo !"
        puts "\nIf however you feel, that the error is in the PREVIOUS recording already,"
        puts "you may want to skip back to the previous hole ...\n\n"
      end
    end

    puts "\n\e[33mWhat's next\e[0m for hole \e[33m#{hole}\e[0m ?"
    choices = {:play => [['p', 'SPACE'], 'play recorded sound'],
               :edit => [['e'], 'edit recorded sound, i.e. set start for play'],
               :draw => [['d'], 'redraw sound data'],
               :record => [['r'], "record RIGHT AWAY (after countdown)"],
               :generate => [['g'], 'generate a sound for the holes nominal frequency'],
               :frequency => [['f'], "show the holes nominal frequency by generating and analysing a\n              sample sound; does not overwrite current recording"],
               :back => [['b'], 'skip back to previous hole']}
    
    choices[:okay] = [['RETURN'], 'keep sound and continue'] if File.exists?(file) && freq >= prev_freq
    
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
    when :frequency
      print "--- Generate and analyse a sample sound:"
      synth_sound hole, $collect_wave
      puts "Frequency: #{analyze_with_aubio($collect_wave)}"
      puts "--- done\n\n"
    when :generate
      synth_sound hole, file
      duration = wave2data(file)
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


