#
# Do the listening
#

def do_listen

  prepare_term
  start_kb_handler
  start_collect_freqs 
  $ctl_can_next = false
  $ctl_can_journal = true
  $ctl_can_loop = false
  $ctl_can_change_comment = true
  
  puts "\n\nJust go ahead and play notes from the scale ..."
  puts "Tip: \e[2mPlaying a slow backing track in parallel may be a good idea ...\e[0m"
  [2,1].each do |c|
    puts c
    sleep 1
  end
  system('clear')
  pipeline_catch_up

  get_hole(-> () {"Play notes from the scale to get \e[32mgreen\e[0m"},   # lambda_issue

           -> (played, _) {[$scale_holes.include?(played),  # lambda_good_done
                            false]},
           nil,  # lambda_skip

           -> (hole_color, isemi, itext, note, hole_disp, f1, f2) do  # lambda_comment
             color = hole_color
             text = ( case $conf[:comment_listen]
                      when :note
                        note
                      when :interval
                        itext || isemi
                      when :hole
                        hole_disp
                      when :cents
                        if $hole_ref
                          if f1 > 0 && f2 > 0 && (cnts = cents_diff(f1, f2).to_i).abs <= 200
                            color = "\e[0m\e[#{cnts.abs <= 25 ? 92 : 31}m"
                            'c %+d' % ((cnts/5.0).round(0)*5)
                          else
                            color = "\e[0m\e[31m"
                            'c  . . .'
                          end
                        else
                          color = "\e[2m"
                          'set ref'
                        end
                      else
                        fail "Internal error: #{$conf[:comment_listen]}"
                      end ) || '.  .  .'
             [color, text, 'big']
           end,

           -> (hole) do  # lambda_hint
             "Hint: Scale has #{$scale_holes.length} holes: #{$scale_holes.join(', ')}"
           end,

           -> (hole_held_before, hole_ref) do  # lambda_hole_for_inter
             hole_ref || hole_held_before
           end
          )
end


