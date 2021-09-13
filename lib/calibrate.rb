# -*- fill-column: 78 -*-

#
# Assistant and automate for calibration
#

def do_calibrate_auto

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  err_h "Option '--only' not allowed with version '--auto'" if $opts[:only]
  puts <<EOINTRO


This will generate all needed samples for holes:

  \e[32m#{$holes.join(' ')}\e[0m

Compared with playing them yourself this sure saves time; however, those
frequencies may not match your own special harp very well.

Moreover, any samples, that you have already recorded before, will be
overwritten in this process !

  So, in this case, consider, saving such samples before !

(to do so, you may bail out now, by pressing ctrl-c)

EOINTRO

  print "\nPress RETURN to generate and play all samples in a single run: "
  STDIN.gets

  hole2freq = Hash.new
  freqs = Array.new
  $holes.each do |hole|
    puts "\nGenerating   hole \e[32m#{hole}\e[0m,   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m:"
    
    diff_semis = $harp[hole][:semi] - note2semi('a4')
    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
    puts cmd = "sox -n #{file} synth 1 sawtooth %#{diff_semis}"
    system cmd
    play_sound file
    hole2freq[hole] = analyze_with_aubio(file)
  end
  ffile = "#{$sample_dir}/frequencies.json"
  File.write(ffile, JSON.pretty_generate(hole2freq))
  puts "\nFrequencies in: #{ffile}"
  puts "\nAll recordings done.\n\n"
end


def do_calibrate_assistant
  
  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  hole = $opts[:only]
  if hole && !$holes.include?(hole)
    err_h "Only hole given to calibrates (#{hole}) is none of these: #{$holes}"   
  end
  puts <<EOINTRO


This is an interactive assistant, that will ask you to play these
holes of your harmonica one after the other, each for one second:"

  \e[32m#{$opts[:only] || $holes.join(' ')}\e[0m

Each recording is preceded by a short countdown (3,2,1).

For each hole 3 seconds will be recorded and silence will be cut off;
then the recording will be truncated to 1 second. So you may wait for
the actual red \e[31mrecording\e[0m mark before starting to play.

The harp you use now for calbration should be the one, that you will
use for your practice later.

Background: Those samples will be used to determine the frequencies of
your particular harp and will be played directly in mode 'quiz'.

Hint: If you plan to calibrate for more than one key of harp, you
  should consider copying the whole directory below 'samples' and
  record only those notes that are missing. Note, that the recorded
  samples are named after the note, not the hole, so that they can be
  copied and used universally.

Tip: You may invoke this assistant again at any later time, just to
  review your recorded notes and maybe correct some of them.


EOINTRO

  if hole
    ffile = "#{$sample_dir}/frequencies.json"
    err_b "Frequence file #{ffile} does not exist yet; do a full calibration first" unless File.exist?(ffile)
    hole2freq = JSON.parse(File.read(ffile))
    freqs = hole2freq.values
    i = $holes.find_index(hole)
    hole2freq[hole] = freqs[i] = record_hole(hole, freqs[i-1] || 0)
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
      freqs[i] = record_hole(hole, freqs[i-1] || 0)
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
  puts "\nAll recordings done."
end


def record_hole hole, prev_freq

  redo_recording = false
  begin

    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"

    if File.exists?(file) && !redo_recording
      puts "\nHole  \e[32m#{hole}\e[0m  need not be recorded, because file #{file} already exists."
      print "\nPress RETURN to see choices: "
      STDIN.gets
      print "Analysis of old: "
    else
      begin 
        puts "\nRecording hole  \e[32m#{hole}\e[0m  after countdown reaches 1,"
        print "\nPress RETURN to start: "
        STDIN.gets
        [3, 2, 1].each do |c|
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
        duration = autoedit file
        if duration < 0.9
          puts "\n\nThe trimmed sample is \e[31mtoo short\e[0m (#{duration} s) ! Please try again !\n(maybe start playing directly after red \e[31mrecording\e[0m mark or play louder)\n\n"
          print "\nPress RETURN to start over: "
          STDIN.gets
        end
      end while duration < 0.9
      puts "\e[32mdone\e[0m"
      print "Analysis: "
    end

    freq = analyze_with_aubio(file)
    
    if freq < prev_freq
      puts "\n\nWAIT !"
      puts "The frequency just recorded (= #{freq}) is \e[31mLOWER\e[0m than the frequency recorded before (= #{prev_freq}) !"
      puts "Therefore this recording cannot be accepted and you need to redo !"
      puts "\nIf however you feel, that the error is in the PREVIOUS recording already,"
      puts "you may want to skip back to the previous hole ...\n\n"
    end

    begin
      puts "\nWhats next for hole \e[33m#{hole}\e[0m ?"
      choices = {:play => [['p', 'SPACE'], 'play recorded sound'],
                 :redo => [['r'], 'redo recording']}
      if $opts[:only]
        choices[:cancel] = [['c'], 'Cancel this calibration']
      else
        choices[:back] = [['b'], 'skip back to previous hole']
      end

      if freq >= prev_freq
        if $opts[:only]        
          choices[:okay] = [['k', 'RETURN'], 'keep recording and finish']
        else
          choices[:okay] = [['k', 'RETURN'], 'keep recording and continue']
        end
      end

      answer = read_answer(choices)

      case answer
      when :play
        print "\nplay ... "
        play_sound file
        puts "done\n"
      when :redo
        redo_recording = true
      when :back, :cancel
        return -1
      end

    end while answer == :play

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
