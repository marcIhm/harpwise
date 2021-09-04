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
  first_lap_at_all = true
  $ctl_can_next = true
  loop do   # forever, sequence after sequence

    all_wanted = $scale_holes.sample($num_quiz)
    sleep 0.3

    unless first_lap_at_all
      ctl_issue "SPACE to pause"
      print "\e[#{$line_hint}H" 
      puts_pad
      print "\e[#{$line_listen}H"
    end

    all_wanted.each do |hole|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      poll_and_handle_kb true
      print "listen ... "
      play_sound file
    end
    print "\e[32mand !\e[0m"
    sleep 0.5
    print "\e[#{$line_listen}H" unless first_lap_at_all
    puts_pad ''
  
    system('clear') if first_lap_at_all
    print "\e[#{$line_comment2}H"
    puts_pad

    $ctl_loop = $opts[:loop]
    begin   # while $ctl_loop

      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence
        
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
          -> (played, since) {[played == wanted,
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next},
          
          -> () do
            if $num_quiz == 1
              '.  .  .'
            else
              'Yes  ' + '*' * idx + '-' * (all_wanted.length - idx)
            end
          end,
          
          -> (tstart) do
            passed = Time.now.to_f - tstart
            if $ctl_loop
              puts_pad "Looping: the sequence is: #{all_wanted.join(' ')}"
            else
              if passed > 3
                print "Hint: Play \e[32m#{wanted}\e[0m (#{$harp[wanted][:note]})"
                print "  \e[2m...  the complete sequence is: #{all_wanted.join(' ')}\e[0m" if passed > 6
              else
                puts_pad
              end
            end
          end)
      end
        
      if $ctl_next
        print "\e[#{$line_issue}H"
        puts_pad '', true
        print "\e[#{$line_comment2}H"
        puts_pad "Skipping to next sequence ..."
        $ctl_loop = $ctl_next = false
        first_lap_at_all = false
        next
      end
    end while $ctl_loop
    
    print "\e[#{$line_comment}H"
    figlet_out = %x(figlet -c -f smblock Great !)
    print "\e[32m"
    puts_pad figlet_out
    print "\e[0m"
    
    print "\e[#{$line_comment2}H"
    puts_pad "Right, the sequence was: #{all_wanted.join(' ')}   ...   \e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !"
    sleep 1

    first_lap_at_all = false
  end
end

