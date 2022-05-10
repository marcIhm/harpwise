#
# Play from the commandline
#

def do_play
  $licks = read_licks
  lick = nil
  jtext = nil
  do_write_journal = true
  holes = ARGV.map do |hnle|  # hole, note, lick, event
    if musical_event?(hnle)
      hnle
    elsif $harp_holes.include?(hnle)
      hnle
    elsif $harp_notes.include?(hnle)
      $note2hole[hnle]
    elsif hnle == 'random'
      err "Argument 'random' must be single on command line" if ARGV.length > 1
      lick = $licks.sample(1)[0]
      jtext = sprintf('Lick %s: ', lick[:desc]) + lick[:holes].join(' ')
      lick[:holes]
    elsif hnle == 'last'
      err "Argument 'last' must be single on command line" if ARGV.length > 1
      do_write_journal = false
      lick = $licks[get_last_lick_from_journal]
      puts "Playing last lick #{lick[:desc]} from #{$journal_file}"
      lick[:holes]
    else
      lick = $licks.find {|l| l[:name] == hnle}
      err "Argument '#{hnle}' is not part of harp holes #{$harp_holes} or notes #{$harp_notes} or licks #{$licks.map {|l| l[:name]}.uniq}" unless lick
      lick[:holes]
    end
  end.flatten
  if do_write_journal
    journal_start
    jtext = holes.join(' ') unless jtext
    IO.write($journal_file, "#{jtext}\n\n", mode: 'a')
  end
  
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


