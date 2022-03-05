#
# Perform quiz
#

def do_quiz

  prepare_term
  start_kb_handler
  start_collect_freqs
  $ctl_can_next = true
  $ctl_can_journal = false
  $ctl_can_loop = true
  $ctl_can_change_comment = false
  
  first_lap = true
  all_wanted_before = all_wanted = nil
  jtext_prev = Set.new
  puts
  
  loop do   # forever until ctrl-c, sequence after sequence

    if first_lap
      print "\n"
      print "\e[#{$term_height}H\e[K"
      print "\e[#{$term_height-1}H\e[K"
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call}H\e[K"
      print "\e[#{$line_issue}H\e[K"
      ctl_issue
    end

    if $ctl_back
      if !all_wanted_before || all_wanted_before == all_wanted
        print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
        sleep 1
      else
        all_wanted = all_wanted_before
      end
      $ctl_loop = true
    elsif $ctl_replay
      # nothing to do
    else # also good for $ctl_next
      all_wanted_before = all_wanted
      all_wanted = get_sample($num_quiz)
      $ctl_loop = $opts[:loop]
    end
    $ctl_back = $ctl_next = $ctl_replay = false
    
    sleep 0.3

    jtext = ''
    ltext = "\e[2m"
    all_wanted.each_with_index do |hole, idx|
      if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
        ltext = "\e[2m"
        if first_lap
          print "\e[#{$term_height}H\e[K"
          print "\e[#{$term_height-1}H\e[K"
        else
          print "\e[#{$line_hint_or_message}H\e[K"
          print "\e[#{$line_call}H\e[K"
        end
      end
      if idx > 0
        isemi, itext = describe_inter(hole, all_wanted[idx - 1])
        part = ' ' + ( itext || isemi ).tr(' ','') + ' '
        ltext += part
        jtext += " #{part} "
      end
      ltext += if $opts[:immediate]
                 "\e[0m#{$harp[hole][:note]},#{hole}\e[2m"
               else
                 "\e[0m#{$harp[hole][:note]}\e[2m"
               end
      jtext += "#{$harp[hole][:note]},#{hole}"
      if $opts[:prefer] && $hole2rem[hole]
        part = "(#{$hole2rem[hole]})" 
        ltext += part
        jtext += part
      end
      print "\e[#{first_lap ? $term_height-1 : $line_hint_or_message }H#{ltext.strip}\e[K"
      play_thr = Thread.new { play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]) }
      begin
        sleep 0.1
        handle_kb_listen
      end while play_thr.alive?
      play_thr.join   # raises any errors from thread
      if $ctl_back || $ctl_next || $ctl_replay
        sleep 1
        break
      end
    end
    File.write('quiz_journal', "\n#{Time.now}:\n#{jtext}\n", mode: 'a') unless jtext_prev.include?(jtext)
    jtext_prev << jtext
    redo if $ctl_back || $ctl_next || $ctl_replay
    print "\e[0m\e[32m and !\e[0m"
    sleep 1

    if first_lap
      system('clear')
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call}H\e[K"
    end
    full_hint_shown = false

    begin   # while looping over one sequence

      lap_start = Time.now.to_f

      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        get_hole( -> () do
                    if $ctl_loop
                      "\e[32mLooping\e[0m over #{all_wanted.length} notes"
                    else
                      if $num_quiz == 1 
                        "Play the note you have heard !"
                      else
                        "Play note \e[32m#{idx+1}\e[0m of #{$num_quiz} you have heard !"
                      end
                    end
                  end,
          -> (played, since) {[played == wanted,  # lambda_good_done
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next || $ctl_back || $ctl_replay},  # lambda_skip
          
          -> (_, _, _, _, _, _, _) do  # lambda_comment
                    if $num_quiz == 1
                      [ "\e[2m", '.  .  .', 'smblock', nil ]
                    else
                      [ "\e[2m", 'Yes  ' + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(' ')) + ' _' * (all_wanted.length - idx), 'smblock', 'yes' + '--' * all_wanted.length ]
                    end
                  end,
          
          -> (_) do  # lambda_hint
            hole_passed = Time.now.to_f - hole_start
            lap_passed = Time.now.to_f - lap_start

            if $opts[:immediate] 
              "\e[2mPlay: " + all_wanted.join(', ')
            elsif all_wanted.length > 1 &&
               hole_passed > 4 &&
               lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
              full_hint_shown = true
              "\e[0mSolution: The complete sequence is: #{all_wanted.join(', ')}" 
            elsif hole_passed > 4
              "\e[2mHint: Play \e0m\e[32m#{wanted}\e[0m"
            else
              if idx > 0
                isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                if isemi
                  "Hint: Move " + ( itext ? "a #{itext}" : isemi )
                end
              end
            end
          end,

          -> (_, _) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter


      end # notes in a sequence

      if $ctl_next || $ctl_back || $ctl_replay
        print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
        first_lap = false
        next
      end
    
      print "\e[#{$line_comment}H"
      text = if $ctl_next
               "skip"
             elsif $ctl_back
               "jump back"
             elsif $ctl_replay
               "replay"
             else
               ( full_hint_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
             end
      print "\e[32m"
      do_figlet text, 'smblock'
      print "\e[0m"
      
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[0m#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{all_wanted.join(', ')}   ...   "
      print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
      full_hint_shown = true
    
      sleep 1
    end while $ctl_loop && !$ctl_back && !$ctl_next && !$ctl_replay # looping over one sequence

    first_lap = false
  end # sequence after sequence
end

      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale and preferred scale
  holes = Array.new
  # favor lower starting notes
  if rand > 0.5
    holes[0] = $scale_holes[0 .. $scale_holes.length/2].sample
  else
    holes[0] = $scale_holes.sample
  end
  semi2hole = $scale_holes.map {|hole| [$harp[hole][:semi], hole]}.to_h

  what = Array.new(num)
  for i in (1 .. num - 1)
    ran = rand
    tries = 0
    if ran > 0.7
      what[i] = :nearby
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(-6 .. 6)
        tries += 1
        break if tries > 100
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    else
      what[i] = :interval
      begin
        # semitone distances 4,7 and 12 are major third, perfect fifth
        # and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * [-1,1].sample
        tries += 1
        break if tries > 100
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    end
  end

  if $opts[:prefer]
    # (randomly) replace notes with preferred ones
    for i in (1 .. num - 1)
      if rand >= 0.5
        holes[i] = nearest_hole_with_remark(holes[i], 'pref', semi2hole)
        what[i] = :nearest_pref
      end
    end
    # (randomly) make last note a root note
    if rand >= 0.5
      holes[-1] = nearest_hole_with_remark(holes[-1], 'root', semi2hole)
      what[-1] = :nearest_root
    end
  end

  for i in (1 .. num - 1)
    # make sure, there is a note in every slot
    unless holes[i]
      holes[i] = $scale_holes.sample
      what[i] = :fallback
    end
    $sample_stats[what[i]] += 1
  end

  File.write('sample_stats', "\n#{Time.now}:\n#{$sample_stats.inspect}\n", mode: 'a') if $opts[:debug]
  holes
end


def nearest_hole_with_remark hole, remark, semi2hole
  delta_semi = 0
  found = nil
  begin
    [delta_semi, -delta_semi].shuffle.each do |ds|
      try_semi = $harp[hole][:semi] + ds
      try_hole = semi2hole[try_semi]
      if try_hole
        try_rem = $hole2rem[try_hole]
        found = try_hole if try_rem && try_rem[remark]
      end
      return found if found
    end
    # no near hole found
    return nil if delta_semi > 8
    delta_semi += 1
  end while true
end
