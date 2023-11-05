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
  $ctl_can[:switch_modes] = true
  $modes_for_switch ||= [:listen, :licks]

  system('clear')
  pipeline_catch_up
  $hole_was_for_disp = nil
  jlen_refresh_comment_cache = comment_cache = nil

  while !$ctl_mic[:switch_modes] do
    
    result = handle_holes(
      
      # lambda_mission
      -> () {"\e[0mPlay from the scale to get \e[32mgreen\e[0m"},   


      # lambda_good_done_was_good
      -> (played, _) {[$scale_holes.include?(played), false, false]},
      

      # lambda_skip
      nil,  

      
      # lambda_comment
      -> (hole_color, isemi, itext, note, hole_disp, freq) do
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
                 if $warbles[:short][:max] == 0 && $warbles[:long][:max] == 0 &&
                    !$warbles[:standby]
                   return ["\e[K",
                           "   Warbling between two holes; start slowly to define them;\e[K",
                           "   clear with BACKSPACE\e[K",
                           "\e[K",
                           case $opts[:time_slice]
                           when :short
                             ["   \e[2mMax warble speed is above 10; this is already the highest\e[K",
                              "   value, that can be realized with option --time-slice\e[K"]
                           when :medium
                             # The stated limit 10 is what we get from test id-68
                             ["   \e[2mMax warble speed is around 10, but you may try to\e[K",
                              "   raise this by giving option '--time-slice short'\e[K"]
                           when :long
                             ["   \e[2mMax warble speed is below 10, but you may try to\e[K",
                              "   raise this by giving option '--time-slice medium'\e[K"]
                           end].flatten
                 else
                   return ["\e[K",
                           warble_comment(:short),
                           "\e[K",
                           warble_comment(:long)].flatten
                 end
               when :journal
                 return ["\e[K",
                         "\e[K",
                         "   No journal yet to show.",
                         "\e[K",
                         "   \e[2mPlay and use RETURN to add hole beeing played, BACKSPACE to remove",
                         "   \e[2mType 'j' for menu e.g. to switch on journal for all notes beeing played\e[0m"] if $journal.length == 0
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
        if Time.now.to_f - $program_start < 3
          []
        else
          if $opts[:comment] == :journal
            # the same hint as below is also produced right after each
            # hole within handle_holes
            ["#{journal_length} holes"]
          else
            ["\e[0m\e[2mRemark: " +
             if $all_scales.length == 1 || $opts[:add_no_holes]
               "Scale has"
             else
               "Combined Scales have"
             end +
             " #{$scale_holes.length} of #{$harp_holes.length} holes"]
          end
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
          make_term_cooked
          clear_area_comment
          puts "\e[#{$lines[:comment_tall] + 2}H\e[0m\e[32mYou may enter an inline comment at the current position."
          puts
          print "\e[0mYour comment (20 chars cutoff): "
          comment = STDIN.gets.chomp.strip
          comment.gsub!('(','')
          comment.gsub!(')','')
          make_term_immediate
          clear_area_comment
          if comment.length > 0
            $journal[-1] = comment[0 .. 19]
          else
            $journal[-1] = '(-)'
          end
        else
          $journal << '(-)'
        end
      else
        $journal << hole_disp
      end
      $msgbuf.print "#{journal_length} holes", 0, 5
    end
    
    if $ctl_mic[:journal_delete]
      $ctl_mic[:journal_delete] = false
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
      if journal_length > 0
        make_term_cooked
        clear_area_comment
        puts "\e[#{$lines[:comment_tall] + 2}H\e[0m\e[32mYou may enter a comment to be saved along with the holes; empty fo none."
        puts
        print "\e[0mYour comment for these #{journal_length} holes: "
        comment = STDIN.gets.chomp.strip
        make_term_immediate
        clear_area_comment
        journal_write(comment)
        $msgbuf.print "Wrote \e[0m#{journal_length} holes\e[2m to #{$journal_file}", 2, 5, :journal
      else
        $msgbuf.print "No holes in journal, that could be written to file", 2, 5, :journal
      end
      $freqs_queue.clear
    end

    if $ctl_mic[:journal_play]
      $ctl_mic[:journal_play] = false
      if journal_length > 0
        $msgbuf.print 'Journal played', 0, 5, later: true
        $msgbuf.print 'Playing journal, press any key to skip ...', 0, 0
        [$journal, '(0.5)'].flatten.each_cons(2).each_with_index do |(hole, hole_next), idx|
          lines, _ = tabify_hl($lines[:hint_or_message] - $lines[:comment_tall], $journal, idx)
          fit_into_comment lines
          unless musical_event?(hole)
            play_wave(this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]),
                      get_musical_duration(hole_next))
          end
          if $ctl_kb_queue.length > 0
            $msgbuf.print "Skipped to end of journal", 2, 5, :journal
            break
          end
        end
        sleep 0.5
        $ctl_kb_queue.clear
        $freqs_queue.clear
      else
        $msgbuf.print "No holes in journal, that could be played", 2, 5, :journal
      end
    end

    if $ctl_mic[:journal_clear]
      clear_area_comment
      print "\e[#{$lines[:comment_tall] + 1}H\e[J\n  \e[0;101mSure to clear journal ?\e[0m\n\n"
      print "\e[0m  'c' to save and clear, 'C' (upcase) to clear without save,\n\n   \e[2many other key to cancel ...\e[0m"
      $ctl_kb_queue.clear
      char = $ctl_kb_queue.deq
      clear_area_comment
      $freqs_queue.clear
      if char == 'c'
        $journal = Array.new
        journal_write("Automatic save before clearing journal")
        $msgbuf.print "Saved and cleared journal", 2, 5, :journal
      elsif char == 'C'
        $journal = Array.new
        $msgbuf.print "Cleared journal without save", 2, 5, :journal
      else
        $msgbuf.print "Journal NOT cleared", 2, 5, :journal
      end
      $ctl_mic[:journal_clear] = false
    end

    if $ctl_mic[:journal_edit]
      $ctl_mic[:journal_edit] = false
      edit_journal
      $freqs_queue.clear
      $ctl_mic[:redraw] = Set[:silent]
    end

    if $ctl_mic[:journal_recall]
      $ctl_mic[:journal_recall] = false
      content = if File.exist?($journal_file) && File.size($journal_file) > 0
                  head = <<~END
                  ### 
                  ###   Up to 100 lines from journal file
                  ###
                  ###      #{$journal_file}
                  ###
                  ###   all lines commented out.
                  ###   Uncomment  (remove '#') any lines with holes,
                  ###   that you want to add to the current journal.
                  ###
                  ###   The current journal (#{journal_length} holes, uncommented)
                  ###   follows at the end of the file; so that just 
                  ###   closing this editor does not change it.
                  ###

END
                  head + File.readlines($journal_file).last(100).map {|l| '# ' + l}.join + "\n"
                else
                  nil
                end
      edit_journal content
      $freqs_queue.clear
      $ctl_mic[:redraw] = Set[:silent]
    end

    if $ctl_mic[:journal_all_toggle]
      $ctl_mic[:journal_all_toggle] = false
      $journal_all = !$journal_all
      $msgbuf.print "journal-all is " +
                    ( $journal_all ? 'ON' : 'OFF' ), 2, 5, :journal
      ctl_response "journal-all #{$journal_all ? ' ON' : 'OFF'}"
    end

    #
    # Handling controls for warbling
    #
    if $ctl_mic[:warbles_clear]
      $ctl_mic[:warbles_clear] = false
      clear_warbles(true)
    end
  end
end


def edit_journal initial_content = nil
  tfile = Tempfile.new(File.basename($0))
  tfile.write(initial_content) if initial_content
  tfile.write("\n###\n### The current journal:\n###\n\n")
  tfile.write(tabify_plain($journal, true))
  tfile.close
  if edit_file(tfile.path)
    catch (:invalid_hole) do
      holes = Array.new
      File.readlines(tfile.path).each do |line|
        line.gsub!(/#.*/,"\n")
        line.strip!
        next if line.empty?
        line.split.each do |hole|
          if musical_event?(hole) || $harp_holes.include?(hole)
            holes << hole
          else
            report_condition_wait_key "Editing failed, this is not a hole nor a musical event: '#{hole}'"
            throw :invalid_hole
          end
        end
      end
      $journal = holes
      $msgbuf.print 'Updated journal', 2, 5, :journal
      return
    end
  end
  $msgbuf.print 'journal remains unchanged', 2, 5, :journal
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


def journal_write(comment)
  IO.write($journal_file, "\n\n\n#{Time.now} -- #{journal_length} holes in key of #{$key}:\n" +
                          + ( comment.empty?  ?  ''  :  "Comment: #{comment}\n" ) + "\n" + 
                          + tabify_plain($journal) + "\n\n", mode: 'a')
end


def journal_length
  $journal.select {|h| !musical_event?(h)}.length
end


def warble_comment type
  wb = $warbles[type]
  sc = $warbles[:scale]
  [val_with_meter("   #{wb[:window]}s avg", wb[:val], sc),
   val_with_meter("  max avg", wb[:max], sc)]
end


def val_with_meter head, val, scale
  meter = "\e[32m" + ( '=' * (($term_width - head.length - 4 - 2 - 2) * val / scale.to_f ).to_i)
  meter = "\e[2m." if meter[-1] == 'm'
  "\e[2m" + head + "\e[0m" + ( " %4.1f" % val ) + " " + meter + "\e[0m\e[K"
end
    
