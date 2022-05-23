#
# Do the listening
#

def do_listen

  prepare_term
  start_kb_handler
  start_collect_freqs 
  $ctl_can_next = false
  $ctl_can_loop = false
  $ctl_can_change_comment = true
  
  system('clear')
  pipeline_catch_up

  get_hole(
    
    # lambda_issue
    -> () {"\e[0mPlay notes from the scale to get \e[32mgreen\e[0m"},   


    # lambda_good_done_was_good
    -> (played, _) {[$scale_holes.include?(played), false, false]},
    

    # lambda_skip
    nil,  

    
    # lambda_comment
    -> (hole_color, isemi, itext, note, hole_disp, f1, f2) do
      color = "\e[0m" + hole_color
      stext = nil
      text = case $conf[:comment_listen]
             when :note
               note
             when :interval
               stext = '------'
               itext || isemi
             when :hole
               hole_disp
             when :cents
               if $hole_ref
                 if f1 > 0 && f2 > 0 && (cnts = cents_diff(f1, f2).to_i).abs <= 200
                   color = "\e[0m\e[#{cnts.abs <= 25 ? 32 : 31}m"
                   stext = 'c +100'
                   'c %+d' % ((cnts/5.0).round(0)*5)
                 else
                   color = "\e[0m\e[31m"
                   stext = 'c +100'
                   'c  . . .'
                 end
               else
                 color = "\e[2m"
                 'set ref'
               end
             else
               fail "Internal error: #{$conf[:comment_listen]}"
             end || '.  .  .'
      [color, text, 'big', stext]
    end,

    
    # lambda_hint
    -> (hole) do  
      "Hint: Scale has #{$scale_holes.length} holes: #{$scale_holes.join(' ')}"
    end,

    
    # lambda_hole_for_inter
    -> (hole_held_before, hole_ref) do  
      hole_ref || hole_held_before
    end)
end


