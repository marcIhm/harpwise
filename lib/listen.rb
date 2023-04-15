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
  
  handle_holes(
    
    # lambda_mission
    -> () {"\e[0mPlay notes from the scale to get \e[32mgreen\e[0m"},   


    # lambda_good_done_was_good
    -> (played, _) {[$scale_holes.include?(played), $ctl_mic[:switch_modes], false]},
    

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
               return ["\e[K", "\e[K", '      No on-request journal yet to show.', "\e[K", "      \e[2mPlay and use 'j' or RETURN to add what is beeing played,", "      \e[2mBACKSPACE to remove, 'J' for menu.\e[0m"] if $journal_selected.length == 0
               if jlen_refresh_comment_cache != $journal_selected.length || $ctl_mic[:update_comment]
                 jlen_refresh_comment_cache = $journal_selected.length
                 comment_cache, to_del = tabify($lines[:hint_or_message] - $lines[:comment_tall], $journal_selected)
                 $journal_selected.shift(to_del)
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
      ["\e[0m\e[2mHint: " +
        if $all_scales.length == 1 || $opts[:add_no_holes]
          "Scale has"
        else
          "Combined Scales have"
        end +
        " #{$scale_holes.length} holes: #{$scale_holes.join(' ')}"]
    end,

    
    # lambda_hole_for_inter
    -> (hole_held_before, hole_ref) do  
      hfi = hole_ref || hole_held_before
      regular_hole?(hfi)  ?  hfi  :  nil
    end,

  
    # lambda_star_lick
    nil
  )  # end of get_hole
  
end


