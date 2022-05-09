#
# Play from the commandline
#

def do_play
  $licks = read_licks
  lick = nil
  holes = ARGV.map do |hnle|  # hole, note, lick, event
    if musical_event?(hnle)
      hnle
    elsif $harp_holes.include?(hnle)
      hnle
    elsif $harp_notes.include?(hnle)
      $note2hole[hnle]
    elsif hnle == 'random'
      lick = $licks.sample(1)[0]
      lick[:holes]
    else
      lick = $licks.find {|l| l[:name] == hnle}
      err "Argument '#{hnle}' is not part of harp holes #{$harp_holes} or notes #{$harp_notes} or licks #{$licks.map {|l| l[:name]}.uniq}" unless lick
      lick[:holes]
    end
  end.flatten

  if !lick || !lick[:rec] || $opts[:holes]
    puts
    holes.each_with_index do |hole, i|
      print ' ' if i > 0
      print hole
      if musical_event?(hole)
        sleep $opts[:fast]  ?  0.25  :  0.5
      else
        play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
      end
    end
    print "\n\n"
  else
    prepare_term
    start_kb_handler
    puts
    puts "Lick " + lick[:desc] + " (h for help)\n" + lick[:holes].join(' ')
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true, true
    puts
  end
end


