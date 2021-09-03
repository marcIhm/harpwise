# -*- fill-column: 78 -*-

#
# Assistant for calibration
#

def do_calibrate

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
  hole = $opts[:only]
  if hole && !$holes.include?(hole)
    err_h "Only hole given to calibrates (#{hole}) is none of these: #{$holes}"   
  end
  puts <<EOINTRO

This is an interactive assistant, that will ask you to play these
holes of your harmonica one after the other, each for one second:"

  \e[32m#{$opts[:only] || $holes.join(' ')}\e[0m

Each recording is preceded by a short countdown (2,1).

To avoid silence in the recording, you should start playing within the
countdown already and play a moment over the end of the recording.
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
  print "Press RETURN to start the step-by-step process ... "
  STDIN.gets
  puts

  if hole
    ffile = "#{$sample_dir}/frequencies.json"
    err_h "Frequence file #{file} does not exist yet; do a full calibration first" unless File.exist?(ffile)
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
  puts "All recordings done:"
  system("ls -lrt #{$sample_dir}")
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
      puts "\nRecording hole  \e[32m#{hole}\e[0m  after countdown reaches 1,"
      print "\nPress RETURN to start recording: "
      STDIN.gets
      [2,1].each do |c|
        puts c
        sleep 1
      end
      
      puts "\e[31mrecording\e[0m to #{file} ..."
      # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $sample_file, silent: true
      end while Time.now.to_f - tstart_record < 0.05

      record_sound 1, file
      puts "\e[32mdone\e[0m"
      print "Analysis: "
    end

    samples = %x(aubiopitch --pitch mcomb #{file} 2>&1).lines.
                map {|l| l.split[1].to_i}.
                select {|f| f>0}.
                sort
    pks = get_two_peaks samples, 10
    puts "Peaks: #{pks.inspect}"
    freq = pks[0][0]
    
    if freq < prev_freq
      puts "\nThe frequency just recorded (= #{freq}) is \e[32mLOWER\e[0m than the frequency recorded before (= #{prev_freq}) !"
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
      if freq < prev_freq
        answer = read_answer(choices)
      else
        choices[:okay] = [['k', 'RETURN'], 'keep recording and continue']
        answer = read_answer(choices)
      end
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

