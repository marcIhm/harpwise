#
# Manipulation of sound-files
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = (opts[:silent] && $opts[:debug] <= 2) ? '>/dev/null 2>&1' : ''
  system "arecord -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}" or err_b "arecord failed"
end


def play_sound file
  sys "aplay #{file}"
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch mcomb #{file} 2>&1)
end


def edit_sound hole, file

  play_from = zoom_from = 0
  zoom_to = duration = wave2data(file)
  do_draw = false
  craft_sound file, play_from, $edit_wave
  loop do
    if do_draw
      draw_data($edit_data, zoom_from, zoom_to, play_from)
      do_draw = false
    else
      puts
    end
    puts "\e[33mEditing\e[0m #{File.basename(file)} for hole \e[33m#{hole}\e[0m, zoom from #{zoom_from} to #{zoom_to}, play from #{play_from}."
    puts "Choices: <zfrom> <zto> | <pfrom> | <empty> | d | y | q | r"
    print "Your input ('h' for help): "
    choice = one_char

    if ('0' .. '9').to_a.include?(choice) || choice == '.'
      print "Finish with RETURN: #{choice}"
      choice += STDIN.gets.chomp.downcase.strip
    else
      puts
    end
    if choice == '?' || choice == 'h'
      puts <<EOHELP

Enter any of these, finish with RETURN:

  <zoom-from> <zoom-to> :  Zoom plot to given range;  Example:  0.2 0.35
           <start-from> :  Set position to play from (vertical line in plot);  Example:  0.4
                 RETURN :  Play from current position;  Example:  RETURN
                      d :  Draw wave curve again
                      y :  Accept current play position and skip to next hole
                      q :  Discard edit
                      r :  Redo this edit and recording before

EOHELP
      print "Press RETURN to continue: "
      
    elsif ['', "\r", "\n" , 'p'].include?(choice)
      puts "Playing ..."
      play_sound $edit_wave
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y'
      FileUtils.cp $edit_wave, file
      wave2data(file)
      puts "Edit accepted, updated #{File.basename(file)}, skipping to next hole."
      return :next_hole
    elsif choice == 'q'
      puts "Edit aborted, #{File.basename(file)} remains unchanged"
      return nil
    elsif choice == 'r' || choice == 'e'
      return :redo
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
          craft_sound file, play_from, $edit_wave
          do_draw = true
        else
        end
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    end
  end 
end


def craft_sound file, play_from, crafted
  puts "Taking 1 second of original sound, starting at #{play_from}"
  sys "sox #{file} #{crafted} trim #{play_from} #{play_from + 1.2} gain -n -3 fade 0 -0 0.2"
end


def sox_query file, property
  %x(sox #{file} -n stat 2>&1).lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole, file
  puts "\nGenerating   hole \e[32m#{hole}\e[0m,   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m:"
    
  diff_semis = $harp[hole][:semi] - note2semi('a4')
  puts cmd = "sox -n #{file} synth 1 sawtooth %#{diff_semis} gain -n -3"
  sys cmd
end


def wave2data file
  sys "sox #{file} #{$edit_data}"
  sox_query(file, 'Length')
end


def this_or_equiv template, note
  notes_equiv(note).each do |eq|
    name = template % eq
    return name if File.exist?(name)
  end
  return template % note
end


def name_write_note_wav note
end
