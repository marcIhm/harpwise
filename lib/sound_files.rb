#
# Manipulation of sound-files
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = (opts[:silent] && $opts[:debug] <= 2) ? '>/dev/null 2>&1' : ''
  sys "arecord -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}"
end


def play_sound file
  sys "aplay #{file}"
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch mcomb #{file} 2>&1)
end


def edit_sound hole, file

  sys "sox #{file} tmp/sound.dat"
  workfile = 'tmp/workfile.wav'
  play_from = zoom_from = 0
  zoom_to = duration = sox_query(file, 'Length')
  do_draw = true
  cut_sound file, workfile, play_from
  loop do
    if do_draw
      draw_wave('tmp/sound.dat', zoom_from, zoom_to, play_from) if do_draw
    else
      puts
    end
    puts "Editing #{File.basename(file)} for hole #{hole}, zoom from #{zoom_from} to #{zoom_to}, play from #{play_from}."
    do_draw = false
    puts "Choices: <zfrom> <zto> | <pfrom> | <empty> | d | y | n"
    print "Your input ('h' for help): "
    choice = STDIN.gets.chomp.downcase.strip
    if choice == '?' || choice == 'h'
      puts <<EOHELP

<zoom-from> <zoom-to> RET  :  Zoom plot to given range;  Example:  0.2 0.35 RET
<start-from>          RET  :  Set position to play from (vertical line in plot);  Example:  0.4 RET
                      RET  :  Play from current position;  Example:  RET
                    d RET  :  Draw wave curve again
                    y RET  :  Accept current play position and return
                    n RET  :  Discard edit

EOHELP
      print "Press RETURN to continue: "
      
    elsif choice == '' || choice == 'p'
      puts "Playing ..."
      play_sound workfile
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y'
      FileUtils.cp workfile, file
      puts "Edit accepted, updated #{File.basename(file)}"
      return
    elsif choice == 'n'
      puts "Edit aborted, #{File.basename(file)} remains unchanged"
      return
    else
      begin
        vals = choice.split.map {|x| Float(x)}
        vals.each do |x|
          raise ArgumentError.new('must be > 0') if x < 0
          raise ArgumentError.new("must be < duration #{duration}") if x >= duration
        end
        if vals.length == 2
          zoom_from, zoom_to = vals
          do_draw = true
        elsif vals.length == 1
          play_from = vals[0]
          cut_sound file, workfile, play_from
          do_draw = true
        else
        end
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    end
  end 
end


def cut_sound file, workfile, play_from
  puts "Cutting original sound 1 second from #{play_from}"
  sys "sox #{file} #{workfile} trim #{play_from} #{play_from + 1.2} gain -n -3 fade 0 -0 0.2"
end


def sox_query file, property
  %x(sox #{file} -n stat 2>&1).lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole
  puts "\nGenerating   hole \e[32m#{hole}\e[0m,   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m:"
    
  diff_semis = $harp[hole][:semi] - note2semi('a4')
  file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
  puts cmd = "sox -n #{file} synth 1 sawtooth %#{diff_semis} gain -n -3"
  sys cmd
  file
end
