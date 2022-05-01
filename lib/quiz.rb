#
# Perform quiz and memorize
#

def do_quiz

  prepare_term
  start_kb_handler
  start_collect_freqs
  $ctl_can_next = true
  $ctl_can_loop = true
  $ctl_can_change_comment = false
  $ctl_ignore_recording = false
  $write_journal = true
  journal_start
  
  first_lap = true
  all_wanted_before = all_wanted = nil
  $licks = read_licks
  lick = lick_idx = nil
  puts
  puts "#{$licks.length} licks." if $mode == :memorize
  
  loop do   # forever until ctrl-c, sequence after sequence

    if first_lap
      print "\n"
      print "\e[#{$term_height}H\e[K"
      print "\e[#{$term_height-1}H\e[K"
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
      print "\e[#{$line_issue}H\e[0mListen ...\e[K"
      ctl_issue
    end

    #
    #  First compute and play the sequence that is expected
    #
    
    # handle $ctl-commands from keyboard-thread
    if $ctl_back
      if !all_wanted_before || all_wanted_before == all_wanted
        print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
        sleep 1
      else
        all_wanted = all_wanted_before
      end
      $ctl_loop = true

    elsif $ctl_replay
    # just check, if lick has changed

      if lick_idx && refresh_licks
        lick = $licks[lick_idx]
        ctl_issue 'Refreshed licks'
      end

    else # e.g. $ctl_next
      all_wanted_before = all_wanted

      # figure out holes to play
      if $mode == :quiz

        all_wanted = get_sample($num_quiz)

      else # memorize

        if $opts[:start_with]
          lick_idx = 0
          $licks.each do |l|
            break if l[:remark] == $opts[:start_with]
            lick_idx += 1
          end
          err "Unknown lick: '#{$opts[:start_with]}'" if lick_idx > $licks.length
          $opts[:start_with] = nil
        else
          lick_idx = rand($licks.length)
        end
        lick = $licks[lick_idx]
        all_wanted = lick[:holes]

      end
      $ctl_loop = $opts[:loop]

    end
    $ctl_back = $ctl_next = $ctl_replay = false
    
    sleep 0.3

    if $mode == :quiz || lick[:recording].length == 0 || $ctl_ignore_recording
      play_holes all_wanted, lick, first_lap
    else
      play_recording lick, first_lap
    end
    
    redo if $ctl_back || $ctl_next || $ctl_replay
    $ctl_ignore_recording = false

    print "\e[0m\e[32m and !\e[0m"
    sleep 1

    if first_lap
      system('clear')
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
    end
    full_hint_shown = false

    #
    #  Now listen for user to play the sequence back correctly
    #

    begin   # while looping over one sequence

      lap_start = Time.now.to_f
      $ctl_forget = false
      
      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        pipeline_catch_up
        
        get_hole( -> () do      # lambda_issue
                    if $ctl_loop
                      "\e[32mLooping\e[0m at #{idx} of #{all_wanted.length} notes" + ( $mode == :memorize ? lick[:desc] : '' )
                    else
                      if $num_quiz == 1 
                        "Play the note you have heard !"
                      else
                        "Play note \e[32m#{idx+1}\e[0m of #{all_wanted.length} you have heard !" +
                          ($mode == $memorize ? sprintf(' (%s)', lick[:desc]) : '')
                      end
                    end 
                  end,
                  -> (played, since) {[played == wanted || event_not_hole?(wanted),  # lambda_good_done
                                       $ctl_forget ||
                                       ( ( played == wanted || event_not_hole?(wanted) ) && 
                                         ( Time.now.to_f - since > ( $mode == :memorize ? 0.1 : 0.2 ) ))]}, # return okay immediately only for memorize
                  
                  -> () {$ctl_next || $ctl_back || $ctl_replay},  # lambda_skip
                  
                  -> (_, _, _, _, _, _, _) do  # lambda_comment
                    if $num_quiz == 1
                      [ "\e[2m", '.  .  .', 'smblock', nil ]
                    elsif $opts[:immediate]
                      empty = idx > 8 ? ". . # . ." : ' .' * idx
                      [ "\e[2m",
                        'Play  ' + empty + all_wanted[idx .. -1].join(' '),
                        'smblock',
                        'play  ' + '--' * all_wanted.length,
                        :right ]
                    else
                      empty = all_wanted.length - idx > 8  ? " _ _ # _ _" : ' _' * (all_wanted.length - idx)
                      [ "\e[2m",
                        'Yes  ' + all_wanted.slice(0,idx).join(' ') + empty,
                        'smblock',
                        'yes  ' + '--' * [6,all_wanted.length].min,
                        :left ]
                    end
                  end,
                  
                  -> (_) do  # lambda_hint
                    hole_passed = Time.now.to_f - hole_start
                    lap_passed = Time.now.to_f - lap_start
                    
                    hint = if $opts[:immediate] 
                             "\e[2mPlay: " + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(' ')) + "\e[0m\e[92m*\e[0m" + all_wanted[idx .. -1].join(' ')
                           elsif all_wanted.length > 1 &&
                                 hole_passed > 4 &&
                                 lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
                             full_hint_shown = true
                             "\e[0mSolution: The complete sequence is: #{all_wanted.join(' ')}" 
                           elsif hole_passed > 4
                             "\e[2mHint: Play \e[0m\e[32m#{wanted}\e[0m"
                           else
                             if idx > 0
                               isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                               if isemi
                                 "Hint: Move " + ( itext ? "a #{itext}" : isemi )
                               end
                             end
                           end
                    ( hint || '' ) + ( $mode == :memorize ? sprintf("\e[2m (%s)", lick[:desc]) : '' )
                  end,

                  -> (_, _) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter

        break if $ctl_next || $ctl_back || $ctl_replay || $ctl_forget

      end # notes in a sequence

      #
      #  Finally judge result
      #

      if $ctl_forget
        print "\e[#{$line_comment}H\e[2m\e[32m"
        do_figlet 'again', 'smblock'
        sleep 0.5
      else
        text = if $ctl_next
                 "next"
               elsif $ctl_back
                 "jump back"
               elsif $ctl_replay
                 "replay"
               else
                 ( full_hint_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
               end
        print "\e[#{$line_comment}H\e[2m\e[32m"
        do_figlet text, 'smblock'
        print "\e[0m"
        
        print "\e[#{$line_hint_or_message}H\e[K"
        unless $ctl_replay || $ctl_forget
          print "\e[0m#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{all_wanted.join(' ')}   ...   "
          print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
          full_hint_shown = true
          sleep 1
        end
      end
      
    end while ( $ctl_loop || $ctl_forget) && !$ctl_back && !$ctl_next && !$ctl_replay # looping over one sequence

    print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
    first_lap = false
  end # forever sequence after sequence
end

      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale and merged scale
  holes = Array.new
  # favor lower starting notes
  if rand > 0.5
    holes[0] = $scale_holes[0 .. $scale_holes.length/2].sample
  else
    holes[0] = $scale_holes.sample
  end

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
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    else
      what[i] = :interval
      begin
        # semitone distances 4,7 and 12 are major third, perfect fifth
        # and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * [-1,1].sample
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    end
  end

  if $opts[:merge]
    # (randomly) replace notes with merged ones and so prefer them 
    for i in (1 .. num - 1)
      if rand >= 0.6
        holes[i] = nearest_hole_with_flag(holes[i], :merged)
        what[i] = :nearest_merged
      end
    end
    # (randomly) make last note a root note
    if rand >= 0.6
      holes[-1] = nearest_hole_with_flag(holes[-1], :root)
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

  IO.write($debug_log, "\n#{Time.now}:\n#{$sample_stats.inspect}\n", mode: 'a') if $opts[:debug]
  holes
end


def nearest_hole_with_flag hole, flag
  delta_semi = 0
  found = nil
  begin
    [delta_semi, -delta_semi].shuffle.each do |ds|
      try_semi = $harp[hole][:semi] + ds
      try_hole = $semi2hole[try_semi]
      if try_hole
        try_flags = $hole2flags[try_hole]
        found = try_hole if try_flags && try_flags.include?(flag)
      end
      return found if found
    end
    # no near hole found
    return nil if delta_semi > 8
    delta_semi += 1
  end while true
end


def play_holes holes, lick, first_lap
  ltext = "\e[2m"
  if $mode == :memorize
    ltext += sprintf('%s: ', lick[:desc])
    jtext = sprintf('%s: ', lick[:desc]) + holes.join(' ')
  else
    jtext = holes.join(' ')
  end
  IO.write($journal_file, "#{jtext}\n\n", mode: 'a') if $write_journal
  pp $write_journal
  
  holes.each_with_index do |hole, idx|

    if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
      ltext = "\e[2m"
      if first_lap
        print "\e[#{$term_height}H\e[K"
        print "\e[#{$term_height-1}H\e[K"
      else
        print "\e[#{$line_hint_or_message}H\e[K"
        print "\e[#{$line_call2}H\e[K"
      end
    end
    if idx > 0
      if !event_not_hole?(hole) && !event_not_hole?(holes[idx - 1])
        isemi, itext = describe_inter(hole, holes[idx - 1])
        ltext += ' ' + ( itext || isemi ).tr(' ','') + ' '
      else
        ltext += ' '
      end
    end
    ltext += if event_not_hole?(hole)
               "\e[0m#{hole}\e[2m"
             elsif $opts[:immediate]
               "\e[0m#{hole},#{$harp[hole][:note]}\e[2m"
             else
               "\e[0m#{$harp[hole][:note]}\e[2m"
             end
    if $opts[:merge]
      part = '(' +
             $hole2flags[hole].map {|f| {merged: 'm', root: 'r'}[f]}.compact.join(',') +
             ')'
      ltext += part unles part == '()'
    end

    if first_lap
      print "\e[#{$term_height-1}H#{ltext.strip}\e[K"
    else
      print "\e[#{$line_call2}H\e[K"
      print "\e[#{$line_hint_or_message}H#{ltext.strip}\e[K"
    end

    if event_not_hole?(hole)
      sleep $opts[:fast]  ?  0.25  :  0.5
    else
      play_hole_and_handle_kb hole
    end
    
    if $ctl_back || $ctl_next || $ctl_replay
      sleep 1
      break
    end
  end
end


def play_recording lick, first_lap
  issue = "Lick \e[0m\e[32m" + lick[:desc] + "\e[0m (SPACE: pause, TAB,+: skip to end) ... " + lick[:holes].join(' ')
  if first_lap
    print "\e[#{$term_height}H#{issue}\e[K"
  else
    print "\e[#{$line_hint_or_message}H#{issue}\e[K"
  end

  jtext = sprintf('%s: ', lick[:desc]) + lick[:holes].join(' ')
  IO.write($journal_file, jtext + "\n\n", mode: 'a') if $write_journal

  skipped = play_recording_and_handle_kb lick[:recording], lick[:start], lick[:duration]
  print skipped ? " skip rest" : " done"
end
