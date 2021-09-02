#
# Do the listening
#

def do_listen
  system("stty -echo")
  install_ctl
  $ctl_can_skip = false
  puts "\n\nJust go ahead and play notes from the scale ..."
  puts "Tip: \e[2mPlaying a slow backing track in parallel may be a good idea ...\e[0m"
  puts $ctl_pause_continue
  [2,1].each do |c|
    puts c
    sleep 1
  end
  get_hole("Play any note from the scale to get \e[32mgreen\e[0m ...        #{$ctl_pause_continue}",
           -> (played, _) {[$scale_holes.include?(played),
                            false]},
           nil,
           nil,
           -> (_) do
             print "Hint: \e[2mchosen scale '#{$scale}' has these holes: #{$scale_holes.join(' ')}\e[0m"
          end
)
end


