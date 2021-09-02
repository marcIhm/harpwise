#
# Perform quiz
#

def do_quiz
  system("stty -echo")
  install_ctl
  puts "\n\nLooping: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  puts $ctl_pause_continue
  [2,1].each do |c|
    puts c
    sleep 1
  end
  
  loop do
    all_wanted = $scale_holes.sample($num_quiz)
    sleep 0.3
    print ' '.ljust($term_width - 2)
    print "\r"
    all_wanted.each do |hole|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      print "listen ... "
      play_sound file
      $ctl_paused = false
    end

    print "\e[32mand !\e[0m"
    sleep 0.5

    $ctl_can_skip = true
    all_wanted.each_with_index do |wanted,idx|
      tstart = Time.now.to_f
      get_hole(
        if $num_quiz == 1 
          "Play the note you have heard !"
        else
          "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
        end + '    ' + $ctl_pause_continue,
        -> (played, since ) {[played == wanted,
                              played == wanted &&
                              Time.now.to_f - since > 0.5]}, # do not return okay immediately
        -> () {$ctl_skip},
        -> () do
          if idx < all_wanted.length
            if all_wanted.length == 1
              text = '.  .  .'
            else
              text = 'Yes  ' + '*' * idx + '-' * (all_wanted.length - idx)
            end
            print "\e[2m"
            system("figlet -c -k -f smblock \"#{text}\"")
            print "\e[0m"
            print "\e[#{$line_comment2}H"
            print "... and on ..."
          end
        end,
        -> (tstart) do
          passed = Time.now.to_f - tstart
          if passed > 3
            print "Hint: play \e[32m#{wanted}\e[0m (#{$harp[wanted][:note]})"
            print " \e[2m ... the hole sequence is: #{all_wanted.join(' ')}\e[0m" if passed > 8
          end
        end)
    end
    if $ctl_skip
      print "\e[#{$line_comment2}H"
      puts_pad "... skipping ..."
      $ctl_skip = false
      sleep 1
      next
    end
    print "\e[#{$line_comment}H"
    figlet_out = %x(figlet -c -f smblock Great !)
    print "\e[32m"
    puts_pad figlet_out
    print "\e[0m"
    print "\e[#{$line_comment2}H"
    puts_pad "You are right: #{all_wanted.join(' ')} ... and \e[32magain\e[0m !"
    puts
    sleep 1
  end
end

