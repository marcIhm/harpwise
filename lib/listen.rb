#
# Do the listening
#

def do_listen
  unless $other_mode_saved[:conf]
    make_term_immediate
    start_collect_freqs
  end
  $ctl_can[:next] = false
  $ctl_can[:loop] = false

  system('clear')
  pipeline_catch_up
  $hole_was_for_disp = nil
  jlen_refresh_comment_cache = comment_cache = nil

  while !$ctl_mic[:switch_modes] do
    
    result = handle_holes(
      
      # lambda_mission
      -> () {"\e[0mPlay notes from the scale to get \e[32mgreen\e[0m"},   


      # lambda_good_done_was_good
      -> (played, _) {[$scale_holes.include?(played), false, false]},
      

      # lambda_skip
      nil,  

      
      # lambda_comment
      -> (hole_color, isemi, itext, note, hole_disp, freq, warbles) do
        color = "\e[0m" + hole_color
        witdh_template = nil
        line = $lines[:comment_low]
        font = 'mono9'
        text = case $opts[:comment]
               when :note
                 note
               when :interval
                 width_template = '------'
                 itext || isemi
               when :hole
                 hole_disp
               when :cents_to_ref
                 if $hole_ref
                   freq_ref = semi2freq_et($harp[$hole_ref][:semi])
                   if freq > 0 && freq_ref > 0 && (cnts = cents_diff(freq, freq_ref).to_i).abs <= 999
                     color = "\e[0m\e[#{cnts.abs <= 25 ? 32 : 31}m"
                     width_template = 'c +100'
                     'c %+d' % ((cnts/5.0).round(0)*5)
                   else
                     color = "\e[0m\e[31m"
                     width_template = 'c +100'
                     'c  ...'
                   end
                 else
                   color = "\e[2m"
                   "set ref"
                 end
               when :gauge_to_ref
                 font = 'smblock'
                 just_dots_long = '......:......:......:......'
                 template_text = 'fixed:' + just_dots_long
                 font = 'smblock'
                 line += 2
                 if $hole_ref
                   semi_ref = $harp[$hole_ref][:semi]
                   dots, in_range = get_dots(just_dots_long.dup, 4, freq,
                                             semi2freq_et(semi_ref - 2),
                                             semi2freq_et(semi_ref),
                                             semi2freq_et(semi_ref + 2)) {|ok,marker| marker}
                   color =  in_range  ?  "\e[0m\e[32m"  :  "\e[2m"
                   dots
                 else
                   color = "\e[2m"
                   "set ref"
                 end
               when :warbles
                 font = 'smblock'
                 line += 2
                 if $hole_ref
                   if warbles.length > 2
                     color = "\e[0m\e[32m"
                     '%.1f' % ( warbles.length / ( Time.now.to_f - warbles[0] ) )
                   else
                     color = "\e[2m"
                     '--'
                   end
                 else
                   color = "\e[2m"
                   "set ref"
                 end
               when :journal
                 return ["\e[K", "\e[K", "   No journal yet to show.", "\e[K", "   \e[2mPlay and use RETURN to add hole beeing played, BACKSPACE to remove", "   \e[2mType 'j' for menu e.g. to switch on journal for all notes beeing played\e[0m"] if $journal.length == 0
                 if jlen_refresh_comment_cache != $journal.length || $ctl_mic[:update_comment]
                   jlen_refresh_comment_cache = $journal.length
                   comment_cache, to_del = tabify_hl($lines[:hint_or_message] - $lines[:comment_tall], $journal)
                   $journal.shift(to_del)
                 end
                 # different convention on return value than other comments
                 return comment_cache
               else
                 fail "Internal error: #{$opts[:comment]}"
               end || '...'
        [color, text, line, font, width_template]
      end,

      
      # lambda_hint
      -> (hole) do
        if $opts[:comment] == :journal
          # the same hint as below is also produced right after each
          # hole within handle_holes
          ["#{$journal.length / 2} holes"]
        else
          ["\e[0m\e[2mHint: " +
           if $all_scales.length == 1 || $opts[:add_no_holes]
             "Scale has"
           else
             "Combined Scales have"
           end +
           " #{$scale_holes.length} holes: #{$scale_holes.join(' ')}"]
        end
      end,

      
      # lambda_star_lick
      nil
    )  # end of get_hole

    #
    # Handling Journal
    #
    if $ctl_mic[:journal_current]
      $ctl_mic[:journal_current] = false
      hole_disp = result&.dig(:hole_disp)
      if hole_disp == '-'
        case $journal[-1]
        when '(-)'
          $journal[-1] = '(+)'
        when '(+)'
          $journal[-1] = '(-)'
        else
          $journal << '(-)'
        end
      else
        $journal << hole_disp
      end
      print_hom "#{$journal.length} holes"
    end
    
    if $ctl_mic[:journal_delete]
      $ctl_mic[:journal_delete] = false
      $journal.pop while musical_event?($journal[-1])
      $journal.pop
    end
    
    if $ctl_mic[:journal_menu]
      journal_menu
      $ctl_mic[:redraw] = Set[:silent]
      $freqs_queue.clear
      $ctl_mic[:journal_menu] = false
    end

    if $ctl_mic[:journal_write]
      $ctl_mic[:journal_write] = false
      if $journal.length > 0
        IO.write($journal_file, "\n\n\n#{Time.now} -- #{$journal.length} holes from journal:\n\n" +
                 + tabify_plain($journal) + "\n\n", mode: 'a')
        pending_message "Wrote \e[0m#{$journal.length} holes\e[2m to #{$journal_file}"
      else
        pending_message "No holes in journal, that could be written to file"
      end
    end

    if $ctl_mic[:journal_play]
      $ctl_mic[:journal_play] = false
      if $journal.length > 0
        print_hom 'Playing journal, press any key to skip ...'
        pending_message "Journal played"
        [$journal, '(0.5)'].flatten.each_cons(2).each_with_index do |(hole, hole_next), idx|
          lines, _ = tabify_hl($lines[:hint_or_message] - $lines[:comment_tall], $journal, idx)
          fit_into_comment lines
          unless musical_event?(hole)
            play_sound(this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]),
                       ((get_musical_duration(hole_next) || 1.0) * $conf[:sample_rate]).to_i)
          end
          if $ctl_kb_queue.length > 0
            pending_message "Skipped to end of journal"
            break
          end
        end
        sleep 0.5
        $ctl_kb_queue.clear
        $freqs_queue.clear
      else
        pending_message "No holes in journal, that could be played"
      end
    end

    if $ctl_mic[:journal_clear]
      clear_area_comment
      print "\e[#{$lines[:comment_tall] + 2}H\e[J\n  \e[0;101mSure to clear journal ?\e[0m\n"
      print "\n\e[0m  'y' to clear, any other key to cancel ..."
      $ctl_kb_queue.clear
      char = $ctl_kb_queue.deq
      clear_area_comment
      $freqs_queue.clear
      if char == 'y'
        $journal = Array.new
        pending_message "Cleared journal"
      else
        pending_message "Journal NOT cleared"
      end
      $ctl_mic[:journal_clear] = false
    end

    if $ctl_mic[:journal_edit]
      $ctl_mic[:journal_edit] = false
      edit_journal
      $freqs_queue.clear
      $ctl_mic[:redraw] = Set[:silent]
    end

    if $ctl_mic[:journal_all_toggle]
      $ctl_mic[:journal_all_toggle] = false
      $journal_all = !$journal_all
      pending_message("journal-all is " +
                      ( $journal_all ? 'ON' : 'OFF' ))
      ctl_response "journal-all #{$journal_all ? ' ON' : 'OFF'}"
    end
  end
end


def edit_journal
  tfile = Tempfile.new(File.basename($0))
  tfile.write(tabify_plain($journal, true))
  tfile.close
  if edit_file(tfile.path)
    catch (:invalid_hole) do
      holes = Array.new
      File.readlines(tfile.path).join(' ').split.each do |hole|
        if musical_event?(hole) || $harp_holes.include?(hole)
          holes << hole
        else
          report_error_wait_key "Editing failed, this is not a hole nor a musical event: '#{hole}'"
          throw :invalid_hole
        end
      end
      $journal = holes
      pending_message 'Updated journal'
      return
    end
  end
  pending_message 'journal remains unchanged'
end


def tabify_plain holes, dense = false
  text = ''
  cell_len = $harp_holes.map {|h| h.length}.max + 2
  holes.each_slice(10) do |slice|
    text += slice.map do |hole|
      hole.rjust(cell_len)
    end.join + (dense  ?  "\n"  :  "\n\n")
  end
  text
end
