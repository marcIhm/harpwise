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
  $modes_for_switch = [:listen, :licks]

  system('clear')
  pipeline_catch_up

  handle_holes(
    
    # lambda_issue
    -> () {"\e[0mPlay notes from the scale to get \e[32mgreen\e[0m"},   


    # lambda_good_done_was_good
    -> (played, _) {[$scale_holes.include?(played), $ctl_listen[:switch_modes], false]},
    

    # lambda_skip
    nil,  

    
    # lambda_comment
    -> (hole_color, isemi, itext, note, hole_disp, freq) do
      color = "\e[0m" + hole_color
      witdh_template = nil
      line = $lines[:comment_low]
      font = 'mono9'
      text = case $conf[:comment]
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
                 'set ref'
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
                 'set ref'
               end
             else
               fail "Internal error: #{$conf[:comment]}"
             end || '...'
      [color, text, line, font, width_template]
    end,

    
    # lambda_hint
    -> (hole) do  
      ["\e[0m\e[2mHint: Scale has #{$scale_holes.length} holes: #{$scale_holes.join(' ')}"]
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


