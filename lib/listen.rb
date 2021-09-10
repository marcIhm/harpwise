#
# Do the listening
#

def do_listen
  system("stty -echo")
  $ctl_can_next = false
  puts "\n\nJust go ahead and play notes from the scale ..."
  puts "Tip: \e[2mPlaying a slow backing track in parallel may be a good idea ...\e[0m"
  [2,1].each do |c|
    puts c
    sleep 1
  end
  system('clear')
  get_hole("Play any note from the scale to get \e[32mgreen\e[0m ...",

           -> (played, _) {[$scale_holes.include?(played),  # lambda_good_done
                            false]},
           nil,  # lambda_skip

           -> (inter_text) do  # lambda_comment_big
             inter_text || '.  .  .'
           end,

           -> () do  # lambda_hint
             print "Hint: \e[2mScale '#{$scale}' has these holes: #{$scale_holes.join(' ')}\e[0m"
           end,

           -> (hole_held_before) do  # lambda_hole_for_inter
             hole_held_before
           end
          )
end


