#
# Do the listening
#

def do_listen
  $ctl_can_next = false
  puts "\n\nJust go ahead and play notes from the scale ..."
  puts "Tip: \e[2mPlaying a slow backing track in parallel may be a good idea ...\e[0m"
  [2,1].each do |c|
    puts c
    sleep 1
  end
  get_hole("Play any note from the scale to get \e[32mgreen\e[0m ...",
           -> (played, _) {[$scale_holes.include?(played),
                            false]},
           nil,
           nil,
           -> (_) do
             print "Hint: \e[2mChosen scale '#{$scale}' has these holes: #{$scale_holes.join(' ')}\e[0m"
          end
)
end


