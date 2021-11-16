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

  get_hole(-> () {"Play any note from the scale to get \e[32mgreen\e[0m ..."},   # lambda_issue

           -> (played, _) {[$scale_holes.include?(played),  # lambda_good_done
                            false]},
           nil,  # lambda_skip

           -> (hole_color, isemi, itext, note, hole) do  # lambda_comment_big
             [ hole_color,
               '    ' + ( ( case $conf[:comment_listen]
                            when :note
                              note
                            when :interval
                              itext || isemi
                            when :hole
                              hole.to_s
                            else
                              fail "Internal error: #{$conf[:comment_listen]}"
                            end ) || '.  .  .' ) ,
               'big' ]
           end,

           -> (hole) do  # lambda_hint
             holes = $scale_holes.dup
             if hole && (hidx = $scale_holes.index(hole.to_s))
               holes[hidx] = "\e[0m\e[32m" + holes[hidx] + "\e[0m\e[2m"
             end
             print "Hint: \e[2mScale has #{$scale_holes.length} holes: #{holes.join(', ')}\e[0m"
           end,

           -> (hole_held_before, hole_ref) do  # lambda_hole_for_inter
             hole_ref || hole_held_before
           end
          )
end


