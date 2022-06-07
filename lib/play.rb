#
# Play from the commandline
#

def do_play
  $all_licks, $licks = read_licks
  lick = nil
  jtext = nil
  do_write_journal = true
  lick_idx_iter = nil
  cycle_after_iter = false
  prepare_term
  start_kb_handler
  any_key = "\e[2mPress any key for next lick\e[0m"
  
  begin
    holes = $to_play.map do |hnle|  # hole, note, lick, event
      if lick_idx_iter
        lick_idx_iter += 1
        if lick_idx_iter >= $licks.length
          puts "Iterated through all #{$licks.length} licks."
          if cycle_after_iter
            puts "Next cycle ..."
            puts any_key
          $ctl_kb_queue.deq
            lick_idx_iter = 0
          else
            puts "Done."
            exit
          end
        else
          puts any_key
          $ctl_kb_queue.deq
        end
        lick = $licks[lick_idx_iter]
        lick[:holes]
      elsif musical_event?(hnle)
        hnle
      elsif $harp_holes.include?(hnle)
        hnle
      elsif $harp_notes.include?(hnle)
        $note2hole[hnle]
      elsif %w(i iter iterate cycle).include?(hnle)
        cycle_after_iter = true if hnle == 'cycle'
        lick_idx_iter = 0
        lick = $licks[lick_idx_iter]
        lick[:holes]
      elsif hnle == 'random'
        err "Argument 'random' must be single on command line" if $to_play.length > 1
        lick = $licks.sample(1)[0]
        jtext = sprintf('Lick %s: ', lick[:desc]) + lick[:holes].join(' ')
        lick[:holes]
      elsif hnle == 'print'
        print_lick_and_tag_info $all_licks
        exit
      elsif hnle == 'dump'
        pp $all_licks
        exit
      elsif hnle == 'hist' || hnle == 'history'
        print_last_licks_from_journal $all_licks
        exit
      elsif (md = hnle.match(/^(\dlast|\dl)$/)) || hnle == 'last' || hnle == 'l'
        err "Argument 'last' must be single on command line" if $to_play.length > 1
        do_write_journal = false
        lick = $licks[get_last_lick_idxs_from_journal[md ? md[1].to_i-1 : 0]]
        puts "Playing last lick #{lick[:desc]} from #{$journal_file}"
        lick[:holes]
      else
        lick = $licks.find {|l| l[:name] == hnle}
        err "Argument '#{hnle}' is not part of harp holes #{$harp_holes} or notes #{$harp_notes} or licks #{$licks.map {|l| l[:name]}.uniq}" unless lick
        jtext = sprintf('Lick %s: ', lick[:desc]) + lick[:holes].join(' ')
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
      puts
      puts "Lick " + lick[:desc] + " (h for help)\n" + lick[:holes].join(' ')
      play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
      puts
    end
  end while lick_idx_iter
end


