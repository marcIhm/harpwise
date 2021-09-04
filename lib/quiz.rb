#
# Perform quiz
#

def do_quiz
  system("stty -echo")
  puts "\n\nAgain and again: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  [2,1].each do |c|
    puts c
    sleep 1
  end

  all_wanted = nil
  first_lap_this_seq = first_lap_at_all = true
  $ctl_can_next = true
  $ctl_loop = $opts[:loop]
  loop do
    if !$ctl_loop || first_lap_this_seq
      all_wanted = $scale_holes.sample($num_quiz)
      sleep 0.3
      print "\e[#{$line_listen}H" unless first_lap_at_all
      all_wanted.each do |hole|
        file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
        print "listen ... "
        play_sound file
      end
      print "\e[32mand !\e[0m"
      sleep 0.5
      print "\e[#{$line_listen}H" unless first_lap_at_all
      puts_pad ''
    end
    system('clear') if first_lap_at_all
    print "\e[#{$line_comment2}H"
    puts_pad
      
    all_wanted.each_with_index do |wanted, idx|

      tstart = Time.now.to_f
        get_hole(
          if !$ctl_loop || first_lap_this_seq
            if $num_quiz == 1 
              "Play the note you have heard !"
            else
              "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
            end
          else
            "Looping these notes silently: #{all_wanted.join(' ')}"
          end,
          -> (played, since) {[played == wanted,
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next},

          -> () do
            if first_lap_at_all
              ''
            elsif all_wanted.length == 1
              '.  .  .'
            else
              'Yes  ' + '*' * idx + '-' * (all_wanted.length - idx)
            end
          end,
          
          -> (tstart) do
            passed = Time.now.to_f - tstart
            if !$ctl_loop || first_lap_this_seq
              if passed > 3
                print "Hint: Play \e[32m#{wanted}\e[0m (#{$harp[wanted][:note]})"
                print "  \e[2m...  the sequence is: #{all_wanted.join(' ')}\e[0m" if passed > 6
              end
            else
              puts_pad "Looping: the sequence is: #{all_wanted.join(' ')}"
            end
          end)
    end
    if $ctl_next
      print "\e[#{$line_issue}H"
      puts_pad '', true
      print "\e[#{$line_comment2}H"
      puts_pad "... skipping to next sequence ..."
      print "\e[#{$line_hint}H"
      puts_pad
      $ctl_next = false
      first_lap_this_seq = true
      first_lap_at_all = false
      $ctl_loop = $opts[:loop]
      next
    end

    print "\e[#{$line_comment}H"
    figlet_out = %x(figlet -c -f smblock Great !)
    print "\e[32m"
    puts_pad figlet_out
    print "\e[0m"

    print "\e[#{$line_comment2}H"
    puts_pad "You are right: #{all_wanted.join(' ')}   ...   \e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !"
    sleep 1
    first_lap_this_seq = first_lap_at_all = false
  end
end

