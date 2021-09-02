#
# Perform quiz
#

def do_quiz
  system("stty -echo")
  puts "\n\nForever: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  [2,1].each do |c|
    puts c
    sleep 1
  end

  all_wanted = nil
  loop do
    ctl_loop_was = false
    unless $ctl_loop
      all_wanted = $scale_holes.sample($num_quiz)
      sleep 0.3
      all_wanted.each do |hole|
        file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
        print "listen ... "
        play_sound file
      end
    end
    print "\e[32mand !\e[0m"
    sleep 0.5

    $ctl_loop = $opts[:loop]
    $ctl_can_next = true
    all_wanted.each_with_index do |wanted,idx|
      tstart = Time.now.to_f
        get_hole(
          if $ctl_loop
            "Looping these notes silently: #{all_wanted.join(' ')}"
          else
            if $num_quiz == 1 
              "Play the note you have heard !"
            else
              "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
            end
          end,
        -> (played, since ) {[played == wanted,
                              played == wanted &&
                              Time.now.to_f - since > 0.5]}, # do not return okay immediately
        -> () {$ctl_next},
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
            if $ctl_loop
              puts_pad "Looping: the hole sequence is: #{all_wanted.join(' ')}"
            else
              if passed > 3
                print "Hint: Play \e[32m#{wanted}\e[0m (#{$harp[wanted][:note]})"
                print "  \e[2m...  the hole sequence is: #{all_wanted.join(' ')}\e[0m" if passed > 6
              end
            end
          end)
    end
    if $ctl_next
      print "\e[#{$line_comment2}H"
      puts_pad "... skipping to next sequence ..."
      $ctl_next = $ctl_loop = false
      sleep 1
      next
    end

    print "\e[#{$line_comment}H"
    figlet_out = %x(figlet -c -f smblock Great !)
    print "\e[32m"
    puts_pad figlet_out
    print "\e[0m"

    print "\e[#{$line_comment2}H"
    if $ctl_loop && !ctl_loop_was
      puts_pad "... infinite loop on these notes, choose next to continue as normal ..."
    else
      puts_pad "You are right: #{all_wanted.join(' ')} ... and \e[32m#{$ctl_loop ? 'again' : 'next'}\e[0m !"
    end
    sleep 1
    ctl_loop_was = $ctl_loop
  end
end

