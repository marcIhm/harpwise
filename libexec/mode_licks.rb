#
# Handle mode licks or mode quiz, flavour recall
#

def do_licks_or_quiz quiz_scale_name: nil, quiz_holes_inter: nil, lambda_quiz_hint: nil

  unless $other_mode_saved[:conf]
    # do not start kb thread yet as we need to read current cursor
    # line from terminal below
    prepare_term
    start_collect_freqs
  end
  $modes_for_switch = [:listen, $mode.to_sym]
  $ctl_mic[:ignore_recording] = $ctl_mic[:ignore_holes] = $ctl_mic[:ignore_partial] = false
  
  to_play = PlayController.new
  # below stands for override for line_message2 and is set during
  # initial play, i.e. before builtup of listen-perspective
  oride_l_message2 = nil
  first_round = true
  $all_licks, $licks = read_licks
  start_with =  $other_mode_saved[:conf]  ?  nil  :  $opts[:start_with].dup
  trace_text = nil
  quiz_prevs = Array.new
  
  loop do   # forever until ctrl-c, sequence after sequence

    #
    #  First compute and play the sequence that is expected
    #

    # check, if lick-file has changed
    if to_play[:lick_idx] && refresh_licks
      to_play.set_lick_and_others_from_idx
      ctl_response 'Refreshed licks'
    end

    # For licks, the calculation of next one has these cases:
    # - switching back to mode from listen
    # - ctl-command that take us back
    # - requests for a named lick
    # - simply done with previous lick and next lick is required
    
    # Handle $ctl-commands from keyboard-thread, that probably came
    # from a previous loop iteration or from other mode; handle those
    # here, because they might change the lick, that is to be played
    # next

    # The else-branch further down handles the general case of
    # choosing the next lick without influence from $ctl-commands
    
    if $other_mode_saved[:lick_idx]
      # mode is licks
      to_play.set_lick_and_others_from_idx($other_mode_saved[:lick_idx])
      to_play[:lick_idx_before] = nil
      $other_mode_saved[:lick_idx] = nil

    elsif $other_mode_saved[:all_wanted]
      # happens only for mode quiz
      to_play[:all_wanted] = $other_mode_saved[:all_wanted]
      $other_mode_saved[:all_wanted] = nil

    #
    # Many of the cases below are only possible for mode licks
    #
    elsif $ctl_mic[:back]
      to_play.back_one_lick
      
    elsif $ctl_mic[:change_lick] 
      trace_text = to_play.read_name_change_lick(to_play[:lick])
      
    elsif $ctl_mic[:edit_lick_file] 
      to_play.edit_lick

    elsif $ctl_mic[:change_tags]  
      to_play.change_tags

    elsif $ctl_mic[:reverse_holes]
      to_play[:all_wanted] = to_play[:all_wanted].reverse
      if to_play[:lick][:rec]
        $msgbuf.print 'Holes reverted, ignoring recording', 2, 5, :holes
        $ctl_mic[:ignore_recording] = true
      end

    elsif $ctl_mic[:shuffle_holes]
      to_play[:all_wanted] = to_play[:all_wanted].shuffle
      if to_play[:lick][:rec]
        $msgbuf.print 'Holes shuffled, ignoring recording', 2, 5, :holes
        $ctl_mic[:ignore_recording] = true
      end

    elsif $ctl_mic[:replay]      
    # nothing to do here, (re)playing will happen further down

    elsif $ctl_mic[:shift_inter]
      to_play.read_and_shift_inter

    elsif $ctl_mic[:change_partial]
      read_and_set_partial
      $msgbuf.print "Partial is \e[0m'#{$opts[:partial]}'", 2, 5, :partial

    else
      # most general case: $ctl_mic[:next] or
      # $ctl_mic[:change_num_quiz_replay] or no $ctl-command at all;
      # go to the next lick or sequence of holes

      to_play[:all_wanted_before] = to_play[:all_wanted]
      
      # figure out holes to play
      if $mode == :quiz
        unless first_round
          $opts[:difficulty] = (rand(100) > $opts[:difficulty_numeric] ? :easy : :hard)
          $num_quiz_replay = {easy: 4, hard: 8}[$opts[:difficulty]] if !$num_quiz_replay_explicit && $quiz_flavour == 'replay'
        end

        # erase previous solution if any
        $msgbuf.print '', 1, 1, :quiz_solution

        case $quiz_flavour
        when 'replay'
          if $ctl_mic[:change_num_quiz_replay]
            read_and_set_num_quiz_replay
            $num_quiz_replay_explicit = true
            $ctl_mic[:change_num_quiz_replay] = false
          end
          to_play[:all_wanted] = get_quiz_sample($num_quiz_replay)
          $msgbuf.print Replay.describe_difficulty, 2, 5, :dicu
        when 'play-scale'
          unless first_round
            begin 
              quiz_scale_name = $all_quiz_scales[$opts[:difficulty]].sample
            end while quiz_prevs.include?(quiz_scale_name)
            quiz_prevs << quiz_scale_name
            quiz_prevs.shift if quiz_prevs.length > 2
            clear_area_comment
            print "\e[#{$lines[:comment]}H\e[0m\e[34m"
            do_figlet_unwrapped quiz_scale_name, 'smblock'
            sleep 2
          end
          to_play[:all_wanted], _, _, _ = read_and_parse_scale_simple(quiz_scale_name, $harp)
          $msgbuf.print HearScale.describe_difficulty, 2, 5, :dicu
        when 'play-inter'
          unless first_round
            begin 
              quiz_holes_inter = get_random_interval
            end while quiz_prevs.include?(quiz_holes_inter)
            quiz_prevs << quiz_holes_inter
            quiz_prevs.shift if quiz_prevs.length > 2
            clear_area_comment
            print "\e[#{$lines[:comment]}H\e[0m\e[32m"
            do_figlet_unwrapped quiz_holes_inter[4], 'smblock'
            sleep 2
          end
          to_play[:all_wanted] = quiz_holes_inter[0..1]
          $msgbuf.print AddInter.describe_difficulty, 2, 5, :dicu
        else
          err "Internal error: #{$quiz_flavour}"
        end
        
      else ## $mode == :licks

        to_play[:shift_inter] = 0

        if start_with
          if (md = start_with.match(/^(\dlast|\dl)$/)) || start_with == 'last' || start_with == 'l'
            # start with lick from history
            to_play[:lick_idx] = get_last_lick_idxs_from_trace($licks)[md  ?  md[1].to_i - 1  :  0]
          else
            to_play.choose_lick_by_name(start_with)
          end
          # consumed
          start_with = nil

        elsif $opts[:iterate] == :cycle

          if to_play[:lick_idx]
            # ongoing cycle
            to_play[:lick_idx_before] = to_play[:lick_idx] 
            to_play.continue_with_cycle
          else
            # start cycle
            to_play[:lick_idx] = 0
            to_play[:lick_idx_before] = nil
          end
          
        else # $opts[:iterate] == :random
          to_play[:lick_idx_before] = to_play[:lick_idx] 
          to_play.choose_random_lick
          
        end

        to_play.set_lick_and_others_from_idx
        trace_text = sprintf('Lick %s: ', to_play[:lick][:name]) + to_play[:all_wanted].join(' ')
      end   ## figure out holes to play

      $ctl_mic[:loop] = $opts[:loop]

    end # handling $ctl-commands and calculating the next holes

    # Now that we are past possible commandline errors, we may initialize screen fully
    if !$other_mode_saved[:conf] && first_round
      if !$splashed
        animate_splash_line
        puts "\n" + ( $mode == :licks  ?  "#{$licks.length} licks, "  :  "" ) +
             "key of #{$key}"
        sleep 0.01
        3.times do
          puts
          sleep 0.01
        end
      end

      # get current cursor line, will be used as bottom of two lines for messages
      print "\e[6n"
      reply = ''
      reply += STDIN.gets(1) while reply[-1] != 'R'
      oride_l_message2 = reply.match(/^.*?([0-9]+)/)[1].to_i - 1
      
      # complete term init
      make_term_immediate
    end

    if oride_l_message2
      puts
    else
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      print "\e[#{$lines[:message2]}H\e[K"
      print_mission ''
      ctl_response
    end

    
    #
    #  Play the holes or recording
    #
    IO.write($trace_file, "#{trace_text}\n", mode: 'a') if trace_text
    trace_text = nil
    seq_played_recently = false
    if ( !quiz_scale_name && !quiz_holes_inter && !zero_partial?) ||
       $ctl_mic[:replay] || $ctl_mic[:shift_inter] || $ctl_mic[:change_partial]
      
      print_mission('Listen ...') unless oride_l_message2

      $ctl_mic[:ignore_partial] = true if zero_partial? && $ctl_mic[:replay]

      # show later comment already while playing
      print_comment_adhoc(to_play[:all_wanted]) unless oride_l_message2

      pstart = Time.now.to_f

      play_rec_or_holes to_play, oride_l_message2

      seq_played_recently = true
      pend = Time.now.to_f
      $msgbuf.borrowed(pend - pstart)

      if $ctl_rec[:replay]
        $ctl_mic[:replay] = true
        redo
      end

      print_mission "Listen ... and !" unless oride_l_message2
      sleep 0.3

    end

    # reset controls before listening
    $ctl_mic[:back] = $ctl_mic[:next] = $ctl_mic[:replay] = $ctl_mic[:shift_inter] = $ctl_mic[:reverse_holes] = $ctl_mic[:shuffle_holes] = $ctl_mic[:change_partial] = false

    # these controls are only used during play, but can be set during
    # listening and play
    $ctl_mic[:ignore_recording] = $ctl_mic[:ignore_holes] = $ctl_mic[:ignore_partial] = false

    #
    #  Prepare for listening
    #
    
    if oride_l_message2
      clear_screen_and_scrollback
      system('clear')
    else
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      print "\e[#{$lines[:message2]}H\e[K"
    end
    full_seq_shown = false

    $ulrec.reset_rec
    
    # precompute some values, that do not change during sequence
    min_sec_hold =  $mode == :licks  ?  0.0  :  0.1

    holes_with_scales = scaleify(to_play[:all_wanted]) if $opts[:comment] == :holes_scales
    holes_with_intervals = intervalify(to_play[:all_wanted], prefer_names: true) if $opts[:comment] == :holes_intervals
    holes_with_inter_semis = intervalify(to_play[:all_wanted], prefer_names: false) if $opts[:comment] == :holes_inter_semis
    holes_with_notes = noteify(to_play[:all_wanted]) if $opts[:comment] == :holes_notes

    $hole_was_for_disp = nil
    
    #
    #  Now listen for user to play the sequence back correctly
    #

    hints_rotated_at = Time.now.to_f + 4 ## give first hint some extra time
    hints_rotations = 0
    
    begin   # while looping over the same sequence again and again

      idx_refresh_comment_cache = comment_cache = nil
      clear_area_comment

      if $ulrec.active?
        $ulrec.ensure_end_rec
        if $ulrec.has_rec? && !$ctl_mic[:forget]
          $ulrec.print_rec_sign_mb
          clear_area_comment
          print "\e[#{$lines[:comment]}H\e[0m\e[32m"
          do_figlet_unwrapped 'what  you  played ...', 'smblock'
          sleep 0.5
          $msgbuf.print "See #{$ulrec.rec_file}, #{'%.1fs' % $ulrec.duration} ... (h for help)", 2, 5
          $ulrec.play_rec
          # try not to record, what we just played
          sleep 0.5 
        end
        $ulrec.start_rec
      end

      if $opts[:auto_replay] && !seq_played_recently
        clear_area_comment
        print "\e[#{$lines[:comment]}H\e[0m\e[32m"
        do_figlet_unwrapped 'listen ...', 'smblock'
        play_rec_or_holes to_play, oride_l_message2
        seq_played_recently = true
      end

      $ctl_mic[:forget] = false

      # iterate over holes in sequence, i.e. one iteration while
      # looping over the same sequence again and again
      to_play[:all_wanted].each_with_index do |wanted, idx|  

        hole_start = Time.now.to_f
        pipeline_catch_up
        $ulrec.first_hole_good_at = Time.now.to_f if idx == 1 && $ulrec.active?

        handle_holes(
          
          # lambda_mission
          -> () do
            if quiz_scale_name
              "Play scale #{quiz_scale_name}, #{$scale2count[quiz_scale_name]} holes, #{to_play[:all_wanted][0]} and on"
            elsif quiz_holes_inter
              "Play inter #{quiz_holes_inter[0]}...#{quiz_holes_inter[3]} " + ( quiz_holes_inter[2] > 0 ? 'up' : 'down' )
            elsif $ctl_mic[:loop]
              "\e[32mLoop\e[0m at #{idx+1} of #{to_play[:all_wanted].length} notes"
            else
              if $num_quiz_replay == 1 
                "Play the note you have heard !"
              else
                "Play note \e[32m#{idx+1}\e[0m of" +
                  " #{to_play[:all_wanted].length} you have heard !"
              end
            end
          end,
          
          
          # lambda_good_done_was_good
          -> (played, since) do
            good = (holes_equiv?(played, wanted) || musical_event?(wanted))
            [good,
             
             $ctl_mic[:forget] ||
             (good && (Time.now.to_f - since >= min_sec_hold )),
             
             idx > 0 &&
             holes_equiv?(played, to_play[:all_wanted][idx-1]) &&
             !holes_equiv?(played, wanted)]
          end, 
          
          # lambda_skip
          -> () {$ctl_mic[:next] || $ctl_mic[:back] || $ctl_mic[:replay] || $ctl_mic[:shift_inter] || $ctl_mic[:change_partial]},  

          
          # lambda_comment; this one needs no arguments at all
          -> (*_) do
            if idx != idx_refresh_comment_cache || $ctl_mic[:update_comment]
              idx_refresh_comment_cache = idx
              $perfctr[:lambda_comment_quiz_call] += 1
              comment_cache = 
                case $opts[:comment]
                when :holes_some
                  largify(to_play[:all_wanted], idx)
                when :holes_scales
                  holes_with_scales ||= scaleify(to_play[:all_wanted])
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_scales, idx)
                when :holes_intervals
                  holes_with_intervals ||= intervalify(to_play[:all_wanted], prefer_names: true)
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_intervals, idx)
                when :holes_inter_semis
                  holes_with_inter_semis ||= intervalify(to_play[:all_wanted], prefer_names: false)
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_inter_semis, idx)
                when :holes_notes
                  holes_with_notes ||= noteify(to_play[:all_wanted])
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_notes, idx)
                when :holes_all
                  wrapify_for_comment($lines[:hint_or_message] - $lines[:comment_tall], to_play[:all_wanted], idx)
                else
                  fail "Internal error unknown comment style: #{$opts[:comment]}"
                end
              $ctl_mic[:update_comment] = false
            end
            comment_cache
          end,

          
          # lambda_hint
          -> (_) do
            tntf = Time.now.to_f
            hole_passed = tntf - hole_start
            hole_hint = if hole_passed > 6
                          "\e[0mHint:\e[2m Play \e[0m\e[32m#{wanted}\e[0m\e[2m ; type '.' for replay"
                        else
                          if idx > 0
                            isemi, itext, _, _ = describe_inter(wanted, to_play[:all_wanted][idx - 1])
                            "\e[0mHint:\e[2m Move " + ( itext ? "a \e[0m\e[32m#{itext}" : "\e[0m\e[32m#{isemi}" )
                          else
                            ''
                          end
                        end
            if $mode == :licks
              if tntf - hints_rotated_at > ( hints_rotations < to_play[:lick_hints].length  ?  6  :  12 )
                to_play[:lick_hints].rotate!
                hints_rotations += 1
                hints_rotated_at = tntf
              end
              [ hole_hint,
                to_play[:lick_hints][0] ]
              # every few secs show different parts of hint              
            else  ## $mode == :quiz
              [ hole_hint ]
            end
          end,
          
          
          # lambda_star_lick
          if $mode == :licks
            -> (delta) do
              $starred[to_play[:lick][:name]] += delta
              startag = if $starred[to_play[:lick][:name]] > 0
                          'starred'
                        elsif $starred[to_play[:lick][:name]] < 0
                          'unstarred'
                        end
              %w(starred unstarred).each {|t| to_play[:lick][:tags].delete(t)}
              to_play[:lick][:tags] << startag if startag
              $starred.delete([to_play[:lick][:name]]) if $starred[to_play[:lick][:name]] == 0
              File.write($star_file, YAML.dump($starred))
              $msgbuf.print "Wrote #{$star_file}", 2, 5, :star
            end
          else
            nil
          end
        )  # end of handle_holes

        
        if $ctl_mic[:switch_modes]
          if $mode == :licks
            $other_mode_saved[:lick_idx] = to_play[:lick_idx]
          else
            $other_mode_saved[:all_wanted] = to_play[:all_wanted]
          end
          return
        end

        break if [:next, :back, :replay, :shift_inter, :change_partial, :forget, :change_lick, :edit_lick_file, :change_tags, :reverse_holes, :shuffle_holes, :toggle_record_user, :change_num_quiz_replay, :quiz_hint].any? {|k| $ctl_mic[k]}

      end  # notes in a sequence

      #
      #  Finally judge result and handle display
      #
      
      if $ctl_mic[:forget]
        $ulrec.ensure_end_rec
        clear_area_comment
        if [:holes_scales, :holes_intervals, :holes_inter_semis].include?($opts[:comment])
          print "\e[#{$lines[:comment] + 2}H\e[0m\e[32m   again"
        else
          print "\e[#{$lines[:comment]}H\e[0m\e[32m"
          do_figlet_unwrapped 'again', 'smblock'
        end
        sleep 0.3
      else
        sleep 0.3
        clear_area_comment if [:holes_all, :holes_scales, :holes_intervals, :holes_inter_semis].include?($opts[:comment])
        # update comment
        cmnt_col = 32
        cmnt_text = if $ctl_mic[:next]
                      'next'
                    elsif $ctl_mic[:back]
                      'jump back'
                    elsif $ctl_mic[:replay]
                      'replay'
                    elsif $ctl_mic[:toggle_record_user]
                      if $ulrec.active?
                        cmnt_col = 2
                        'REC  -off-'
                      else
                        cmnt_col = 31
                        'REC   -ON-'
                      end
                    elsif [:change_lick, :edit_lick_file, :change_tags, :reverse_holes, :shift_inter, :shuffle_holes, :change_partial, :change_num_quiz_replay].any? {|k| $ctl_mic[k]}
                      # these will issue their own message
                      nil
                    else
                      full_seq_shown ? 'Yes ' : 'Great ! '
                      seq_played_recently = false
                    end
        if cmnt_text
          clear_area_comment
          if [:holes_scales, :holes_intervals, :holes_inter_semis].include?($opts[:comment])
            puts "\e[#{$lines[:comment] + 2}H\e[0m\e[#{cmnt_col}m   " + cmnt_text
          else
            print "\e[#{$lines[:comment]}H\e[0m\e[#{cmnt_col}m"
            do_figlet_unwrapped cmnt_text, 'smblock'
          end
          print "\e[0m"
        end # updating display

        # update hint
        print "\e[#{$lines[:hint_or_message]}H\e[K"
        unless [:replay, :shift_inter, :change_partial, :forget, :next, :change_lick, :edit_lick_file, :change_tags, :reverse_holes, :shuffle_holes, :toggle_record_user, :change_num_quiz_replay, :quiz_hint].any? {|k| $ctl_mic[k]}
          if $mode == :quiz
            print(' ' * (($term_width - 36) / 2) + "\e[0m\e[32m\e[7mYes\e[0m\e[32m, thats right !  ... and #{$ctl_mic[:loop] ? 'again' : 'next'}\e[0m\e[K")
            color, text, line, font, width_template =
            print_comment_adhoc(to_play[:all_wanted], quiz_and_after: true)
            sleep 0.5
          else
            print "\e[0m\e[32mAnd #{$ctl_mic[:loop] ? 'again' : 'next'} !\e[0m\e[K"
          end
          full_seq_shown = true
          sleep 0.5 unless cmnt_text
        end
        sleep 0.5 if cmnt_text
      end

      sleep 0.5 if $ulrec.recording? # record some more

      # handle user recording during lick
      if $ctl_mic[:toggle_record_user]
        $ulrec.toggle_active
        seq_just_played_initially = true
        $ctl_mic[:toggle_record_user] = false
      end

      if $ctl_mic[:quiz_hint]
        lambda_quiz_hint.call(to_play[:all_wanted], quiz_holes_inter, quiz_scale_name)
        $ctl_mic[:quiz_hint] = false
      end
      
    end while ( $ctl_mic[:loop] || $ctl_mic[:forget] ) && [:back, :next, :replay, :shift_inter, :change_partial, :change_lick, :edit_lick_file, :change_tags, :reverse_holes, :shuffle_holes, :change_num_quiz_replay].all? {|k| !$ctl_mic[k]}   # while looping over the same sequence again and again

    print_mission ''
    oride_l_message2 = nil
    first_round = false

  end # forever sequence after sequence
end


$quiz_sample_stats = Hash.new {|h,k| h[k] = 0}

def get_quiz_sample num
  # construct chains of holes within scale and added scale
  holes = Array.new
  what = Array.new(num)
  rnd = rand
  # favor lower starting notes
  if rnd > 0.7
    holes[0] = $scale_holes[0 .. $scale_holes.length/2].sample
    what[0] = :start_sample_from_lower_scale
  elsif rnd > 0.4
    holes[0] = $scale_holes.sample
    what[0] = :start_sample_from_scale
  else
    holes[0] = $hole_root
    what[0] = :start_root
  end

  for i in (1 .. num - 1)
    tries = 0
    if rand > 0.5
      what[i] = :middle_nearby_hole
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(-6 .. 6)
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    else
      what[i] = :middle_interval
      begin
        # semitone distances 4,7,10 and 12 are major third, perfect
        # fifth, flat seventh and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + $std_semi_shifts.sample
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    end
  end

  if $used_scales.length > 1
    # (randomly) replace notes with added ones and so prefer them 
    for i in (1 .. num - 1)
      if rand >= 0.6
        holes[i] = nearest_hole_with_flag(holes[i], :added)
        what[i] = :middle_nearest_hole_from_added_scale
      end
    end
  end
  
  # (randomly) make last note a root note
  if rand >= 0.6
    holes[-1] = nearest_hole_with_flag(holes[-1], :root)
    what[-1] = :end_nearest_root
  end

  for i in (1 .. num - 1)
    # make sure, there is a note in every slot
    unless holes[i]
      holes[i] = $scale_holes.sample
      what[i] = :middle_end_fallback
    end
    $quiz_sample_stats[what[i]] += 1
  end

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


def play_recording_quiz lick, at_line:, shift_inter:
      
  if $opts[:partial] && !$ctl_mic[:ignore_partial]
    lick[:rec_length] ||= sox_query("#{$lick_dir}/recordings/#{lick[:rec]}", 'Length')
    _, start, length = select_and_calc_partial([], lick[:rec_start], lick[:rec_length])
  else
    start, length = lick[:rec_start], lick[:rec_length]
  end

  text = "Lick \e[0m\e[32m" + lick[:name] + "\e[0m (h for help) ... "
  lick[:holes].each do |hole|
    text += hole + ' '
    if text.length - 4 * text.count("\e") > $term_width * 1.5
      text[-1] = '...'
      break
    end
  end           
  if at_line
    print "\e[#{at_line}H#{text} \e[K"
  else
    print "\e[#{$lines[:hint_or_message]}H#{text} \e[K"
  end

  skipped = play_recording_and_handle_kb(lick[:rec], start, length, lick[:rec_key], !!at_line, shift_inter)

  print skipped ? " skip rest" : " done"
end


def zero_partial?
  $opts[:partial] && %w[0@ 0.0@ 0/].any? {|hd| $opts[:partial].start_with?(hd)}
end


def select_and_calc_partial all_holes, start_s, length_s
  start = start_s.to_f
  length = length_s.to_f
  if md = $opts[:partial].match(/^1\/(\d)@(b|x|e)$/)
    numh = (all_holes.length/md[1].to_f).round
    pl = length / md[1].to_f
    pl = [1,length].min if pl < 1
    ps = case md[2]
         when 'b'
           start
         when 'e'
           start + length - pl
         else
           start + pl * rand(md[1].to_i)/md[1].to_f
         end
  elsif md = $opts[:partial].match(/^(\d*\.?\d*)@(b|x|e)$/)
    if md[1].length == 0
      err "Argument for option '--partial' should have digits before '@'; '#{$opts[:partial]}' does not"
    end
    numh = md[1].to_f.round
    pl = md[1].to_f
    pl = length if pl > length
    ps = case md[2]
         when 'b'
           start
         when 'e'
           start + length - pl
         else
           start + (length - pl) * rand
         end
  else
    err "Argument for option '--partial' must be like 1/3@b, 1/4@x, 1/2@e, 1@b, 2@x or 0.5@e but not '#{$opts[:partial]}'"
  end
  
  numh = all_holes.length if numh > all_holes.length
  holes = if numh == 0
            []
          else
            case md[2]
            when 'b'
              all_holes[0 ... numh]
            when 'e'
              all_holes[-numh .. -1]
            else
              pos = rand(all_holes.length - numh + 1)
              all_holes[pos .. pos+numh-1]
            end
          end
  [holes, sprintf("%.1f",ps), sprintf("%.1f",pl)]
end


def tabify_colorize max_lines, holes_scales, idx_first_active
  lines = Array.new
  max_cell_len = holes_scales.map {|hs| hs.map(&:length).sum + 2}.max
  per_line = (($term_width * 0.8 - 4) / max_cell_len).truncate
  line = '   '
  holes_scales.each_with_index do |hole_scale, idx|
    if idx > 0 && idx % per_line == 0
      lines << line
      lines << ''
      line = '   '
    end
    mb_w_dot = if hole_scale[2].strip.length > 0
                 '.' + hole_scale[2]
               else
                 ' '
               end
    line += " \e[0m" +
            if idx < idx_first_active
              ' ' + "\e[0m\e[2m" + hole_scale[0] + hole_scale[1] + mb_w_dot
            else
              hole_scale[0] +
                if idx == idx_first_active
                  "\e[0m\e[92m*"
                else
                  ' '
                end +
                sprintf("\e[0m\e[%dm", get_hole_color_inactive(hole_scale[1],true)) +
                hole_scale[1] + "\e[0m\e[2m" + mb_w_dot
            end
  end
  lines << line
  lines << ''
  if lines.length > max_lines
    lines = lines.select {|l| l.length > 0}
  end
  if lines.length > max_lines
    lines = lines[0 .. max_lines - 1]
    lines[-1] = lines[-1].ljust(per_line)
    lines[-1][-6 .. -1] = "\e[0m  ... "
  end
  lines[-1] += "\e[0m"
  lines
end


def tabify_hl max_lines, holes, idx_hl = nil
  lines = Array.new
  lines << "\e[K"
  cell_len = $harp_holes.map {|h| h.length}.max + 2
  per_line = (($term_width * 0.9 - 4) / cell_len).truncate
  per_line -= 1 if per_line % 2 == 1
  to_del = 0
  line = ''
  holes.each_with_index do |hole, idx|
    if idx > 0 && idx % per_line == 0
      lines << line + "\e[K"
      lines << "\e[K"
      line = ''
    end
    line += ( ( hole['('] || idx_hl )  ?  "\e[2m"  :  "\e[0m" ) +
            ( idx == idx_hl  ?  "\e[0m\e[32m"  :  '') +
            hole.rjust(cell_len) +
            "\e[0m"
  end
  lines << line + "\e[K"
  lines << "\e[K"
  if lines.length > max_lines
    lines = lines.select {|l| l != "\e[K"}
  end
  if lines.length > max_lines
    lines.shift
    to_del = per_line
  end
  return lines, to_del
end


def scaleify holes_or_notes
  hon_maxlen = holes_or_notes.max_by(&:length).length
  shorts_maxlen = holes_or_notes.map {|hon| $hole2scale_shorts[$note2hole[hon] || hon]}.max_by(&:length).length
  holes_or_notes.each.map do |hon|
    [' ' * (hon_maxlen - hon.length), hon, $hole2scale_shorts[$note2hole[hon] || hon].ljust(shorts_maxlen)]
  end
end


def remarkify holes_or_notes
  hon_maxlen = holes_or_notes.max_by(&:length).length
  remarks_maxlen = holes_or_notes.map {|hon| $hole2rem[$note2hole[hon] || hon] || ''}.max_by(&:length).length
  holes_or_notes.each.map do |hon|
    [' ' * (hon_maxlen - hon.length), hon, ($hole2rem[$note2hole[hon] || hon] || '').ljust(remarks_maxlen)]
  end
end


def intervalify holes_or_notes, prefer_names: true
  inters = []
  holes_or_notes.each_with_index do |hon, idx|
    j = idx - 1
    j = 0 if j < 0
    j -= 1 while j > 0 && musical_event?(holes_or_notes[j])
    isemi ,_ ,itext, _ = describe_inter(hon, holes_or_notes[j])
    idesc = if prefer_names
              itext || isemi || ''
            else
              isemi || itext || ''
            end
    idesc.gsub!(' ','')
    inters << idesc
  end
  hon_maxlen = holes_or_notes.max_by(&:length).length
  inters_maxlen = inters.max_by(&:length).length
  holes_or_notes.each.map do |hon|
    [' ' * (hon_maxlen - hon.length), hon, inters.shift.ljust(inters_maxlen)]
  end
end


def intervalify_to_first holes, prefer_names: true
  inters = []
  holes.each_with_index do |hole,idx|
    isemi ,_ ,itext, _ = describe_inter(hole, holes[0])
    idesc = if prefer_names
              itext || isemi || ''
            else
              isemi || itext || ''
            end
    idesc.gsub!(' ','')
    inters << idesc
  end
  holes_maxlen = holes.max_by(&:length).length
  inters_maxlen = inters.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole, inters.shift.ljust(inters_maxlen)]
  end
end


def noteify holes_or_notes
  holes_maxlen, notes_maxlen = holeify_noteify_get_maxlens(holes_or_notes)
  holes_or_notes.each.map do |hon|
    [' ' * (holes_maxlen - hon.length), hon,
     if musical_event?(hon)
       ''
     else
       $harp.dig(hon, :note) || '-'
     end.ljust(notes_maxlen)]
  end
end


def holeify holes_or_notes
  holes_maxlen, notes_maxlen = holeify_noteify_get_maxlens(holes_or_notes)
  holes_or_notes.each.map do |hon|
    [' ' * (holes_maxlen - hon.length), hon,
     if musical_event?(hon)
       ''
     else
       $note2hole[hon] || '-'
     end.ljust(notes_maxlen)]
  end
end


def holeify_noteify_get_maxlens holes_or_notes
  holes_maxlen = holes_or_notes.max_by(&:length).length
  notes_maxlen = holes_or_notes.map do |hon|
    if musical_event?(hon)
      ''
    elsif $harp[hon]
      $harp[hon][:note]
    else
      hon
    end
  end.max_by(&:length).length
  return [holes_maxlen, notes_maxlen]
end


def largify holes, idx
  line = $lines[:comment_low]
  if $num_quiz_replay == 1
    [ "\e[2m", '...', line, 'smblock', nil ]
  elsif $opts[:immediate] # show all unplayed
    hidden_holes = if idx > 6
                     ".. # .."
                   else
                     '.' * idx
                   end
    [ "\e[2m",
      'Play  ' + hidden_holes + holes[idx .. -1].join('  '),
      line,
      'smblock',
      'play  ' + '--' * holes.length,  # width_template
      :right ]  # truncate at
  else # show all played
    hidden_holes = if holes.length - idx > 8
                     " _ _ # _ _" # abbreviation for long sequence of ' _'
                   else
                     ' _' * (holes.length - idx)
                   end
    [ "\e[2m",
      'Yes  ' + holes.slice(0,idx).join('  ') + hidden_holes,
      line,
      'smblock',
      'yes  ' + '--' * [6,holes.length].min,  # width_template
      :left ]  # truncate at
  end
end


def wrapify_for_comment max_lines, holes, idx_first_active
  # get output from figlet
  lines_all = get_figlet_wrapped(holes.join('  '),'smblock')
  lines_inactive = get_figlet_wrapped(holes[0 ... idx_first_active].join('  '),'smblock')
  # we know that each figlet-line has 4 screen lines; integer arithmetic on purpose
  fig_lines_max = max_lines / 4
  fig_lines_all = lines_all.length / 4
  fig_lines_inactive = lines_inactive.length / 4
  
  # truncate if necessary
  # use offset instead of shifting from arrays to avoid caching issues
  offset = 0
  if fig_lines_all > fig_lines_max
    if fig_lines_inactive <= 1
    # This happens during begin of replay: need to show first
    # inactive figlet-line, because it also contains active holes;
    # screen lines at bottom will be truncated below
    elsif fig_lines_all - fig_lines_inactive <= 1
      # This happens during end of replay: show the last two lines
      offset = (fig_lines_all - 2) * 4
    else
      # In between begin and end of replay (if at all)
      offset = (fig_lines_inactive - 1) * 4
    end
  end
  offset = 0 if offset < 0

  # construct final set of lines
  lines = []
  lines_all[offset .. -1].each_with_index do |line, idx|
    break if idx >= max_lines
    lines << "\e[0m#{line.chomp}\e[K"
    lines[-1] += "\e[G\e[0m\e[38;5;236m#{lines_inactive[idx + offset]}" if idx + offset < lines_inactive.length
  end
  lines[-1] += "\e[0m"
  lines
end


def read_tags_and_refresh_licks curr_lick
  all_tags = if curr_lick[:tags].length > 0
               [';OF-CURR-LICK->', curr_lick[:tags], ';ALL-OTHER->']
             else
               []
             end
  all_tags << $all_licks.map {|l| l[:tags]}.flatten.uniq.sort
  # count
  tag2licks = Hash.new {|h,k| h[k] = Array.new}
  $all_licks.each do |lick|
    lick[:tags].each do |tag|
      tag2licks[tag] << lick[:name]
    end
  end
  input = choose_interactive("Choose new tag for --tags-any, aka -t (current lick is #{curr_lick[:name]}): ", all_tags.flatten) do |tag|
    if tag2licks[tag]
      "#{tag2licks[tag].length} licks, e.g. #{tag2licks[tag].sample(5).join(',')}"
    else
      'no licks with this tag'
    end
  end
  return false unless input
  $opts[:tags_any] = input
  $all_licks, $licks = read_licks(true)
  input = choose_interactive('Choose new value for --iterate: ', %w(random cycle))
  return true unless input
  $opts[:iterate] = input.to_sym
  return true
end


def read_and_set_partial
  make_term_cooked
  clear_area_comment
  puts "\e[#{$lines[:comment_tall]}H\e[0m\e[32mPlease enter new value for option '--partial'."
  puts
  puts "\e[0m\e[2m Examples would be: 0 1/3@b 1/4@x 1/2@e 1@b 1@e 2@x"
  puts " type RETURN to unset"
  puts " Current value is '#{$opts[:partial]}'"
  puts
  print "\e[0mYour input: "
  input = STDIN.gets.chomp
  old = $opts[:partial]
  $opts[:partial] = if input.strip.empty?
                      nil
                    elsif input == '0'
                      '0@b'
                    else
                      input
                    end

  make_term_immediate
  begin
    # test with some artifical arguments
    $on_error_raise = true
    select_and_calc_partial($harp_holes, 0, 1) if $opts[:partial] && !$opts[:partial].empty?
    $on_error_raise = false
  rescue ArgumentError => e
    report_condition_wait_key e
    $opts[:partial] = old
  end
  print "\e[#{$lines[:comment]}H\e[0m\e[J"
end


def read_and_set_num_quiz_replay
  make_term_cooked
  clear_area_comment
  puts "\e[#{$lines[:comment_tall] + 1}H\e[0m\e[32mPlease enter new number of holes to be replayed."
  puts
  puts "\e[0m\e[2m Any integer number larger zero is allowed (e.g. 2, 3, 10)"
  puts " anything invalid keeps the current value of: #{$num_quiz_replay}"
  puts
  print "\e[0mYour input: "
  input = STDIN.gets.chomp
  new = input.to_i
  $num_quiz_replay = new if new > 0
  make_term_immediate
  print "\e[#{$lines[:comment]}H\e[0m\e[J"
end


def print_comment_adhoc holes, quiz_and_after: false
  # this is either used during initial play (e.g. in mode lick) or as
  # confirmation in quiz
  idx = ( quiz_and_after  ?  holes.length  :  0 )
  lines = if $opts[:comment] == :holes_scales
            clear_area_comment
            holes_with_scales = scaleify(holes)
            tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall],
                            holes_with_scales, idx)
          elsif $opts[:comment] == :holes_intervals
            clear_area_comment
            holes_with_intervals = intervalify(holes, prefer_names: true)
            tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall],
                            holes_with_intervals, idx)
          elsif $opts[:comment] == :holes_inter_semis
            clear_area_comment
            holes_with_inter_semis = intervalify(holes, prefer_names: false)
            tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall],
                            holes_with_inter_semis, idx)
          elsif $opts[:comment] == :holes_notes
            clear_area_comment
            holes_with_notes = noteify(holes)
            tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall],
                            holes_with_notes, idx)
          elsif $opts[:comment] == :holes_all
            wrapify_for_comment($lines[:hint_or_message] - $lines[:comment_tall],
                                holes, idx)
          elsif $opts[:comment] == :holes_some && ( quiz_and_after || $opts[:immediate] )
            color, text, line, font, width_template = largify(holes, idx)
            color = "\e[32m" if quiz_and_after
            print "\e[#{line}H#{color}"
            do_figlet_unwrapped text, font, width_template
            nil
          else
            nil
          end
  fit_into_comment(lines) if lines
end


def play_rec_or_holes to_play, oride_l_message2
  if $mode == :quiz || !to_play[:lick][:rec] || $ctl_mic[:ignore_recording] ||
     (to_play[:all_wanted] == to_play[:lick][:holes].reverse) ||
     ($opts[:holes] && !$ctl_mic[:ignore_holes])
    play_holes to_play[:all_wanted],
               at_line: oride_l_message2,
               verbose: true,
               lick: to_play[:lick]
  else
    play_recording_quiz to_play[:lick],
                        at_line: oride_l_message2,
                        shift_inter: to_play[:shift_inter]
  end
end


class PlayController < Struct.new(:all_wanted, :all_wanted_before, :lick, :lick_idx, :lick_idx_before, :lick_hints, :shift_inter)

  def initialize
    self[:shift_inter] = 0
  end

  
  def read_name_change_lick curr_lick
    input = matching = trace_text = nil
    $ctl_mic[:change_lick] = false

    old_licks = get_last_lick_idxs_from_trace($licks, true).map {|lick_idx| $licks[lick_idx][:name]}
    choices = if old_licks.length > 0
                [';RECENT->', old_licks[0 .. 3], ';ALL-OTHER->']
              else
                []
              end
    choices << $licks.map {|li| li[:name]}.sort
    input = choose_interactive("Please choose lick (current is #{curr_lick[:name]}): ", choices.flatten) do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      if lick
        "[#{lick[:tags].join(',')}] #{lick[:holes].length} holes, #{lick[:desc]}"
      else
        'no description'
      end
    end
    return nil unless input
    
    new_idx = $licks.map.with_index.find {|lick, idx| lick[:name] == input}[1]
    if self[:lick_idx] != new_idx
      self[:lick_idx_before] = self[:lick_idx]
      self.set_lick_and_others_from_idx(new_idx)
      trace_text = sprintf('Lick %s: ', self[:lick][:name]) + self[:all_wanted].join(' ')
    end
    
    trace_text
  end


  def back_one_lick
    if self[:lick]
      if !self[:lick_idx_before] || self[:lick_idx_before] == self[:lick_idx]
        print "\e[G\e[0m\e[32mNo previous lick; replay\e[K"
        sleep 1
      else
        self.set_lick_and_others_from_idx(self[:lick_idx_before])
        self[:lick_idx_before] = nil
      end
    else
      if !self[:all_wanted_before] || self[:all_wanted_before] == self[:all_wanted]
        print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
        sleep 1
      else
        self[:all_wanted] = self[:all_wanted_before]
      end
    end
    $ctl_mic[:loop] = true
  end


  def edit_lick
    if self[:lick][:tags].include?('not-from-lickfile')
      report_condition_wait_key "This lick (#{self[:lick][:name]}) is not from lick file; cannot edit here.\nRather switch to mode 'listen' to edit.", :info
    else
      if edit_file($lick_file, self[:lick][:lno])
        if self[:lick_idx] && refresh_licks
          # rare edge case, e.g. when we remove tag 'fav' from last lick
          self[:lick_idx] = 0 if !$licks[self[:lick_idx]] 
          self.set_lick_and_others_from_idx
          ctl_response 'Refreshed licks'
        end
      end
    end
    $ctl_mic[:redraw] = Set[:silent, :clear]
    $ctl_mic[:edit_lick_file] = false
  end


  def change_tags
    start_new_iteration = read_tags_and_refresh_licks(self[:lick])
    if start_new_iteration
      self[:lick_idx] = ( $opts[:iteration] == :cycle  ?  0  :  rand($licks.length) )
      self[:lick_idx_before] = nil
      self.set_lick_and_others_from_idx
    end
    $ctl_mic[:change_tags] = false
    print "\e[#{$lines[:key]}H\e[k" + text_for_key
  end


  def read_and_shift_inter
    num_holes_playable = [0, $std_semi_shifts].flatten.map do |shift|
      [shift,
       self[:lick][:holes].inject(0) do |sum, hole|
         sum + ( musical_event?(hole)  ?  0  :
                   ( $harp[hole][:shifted_by][shift]  ?  1  :  0 ) )
       end]
    end.to_h
    choices_desc = Hash.new
    choices_desc['no shift'] = 'use original, unshifted lick'
    $std_semi_shifts.each do |shift|
      choices_desc[$intervals[shift.abs][0] + ' ' + ( shift > 0  ?  'UP'  :  'DOWN' )] =
        "#{num_holes_playable[shift]} of #{num_holes_playable[0]} holes playable"
    end
    
    answer = choose_interactive('Choose interval to shift original, unshifted lick:', choices_desc.keys) do |inter|
      choices_desc[inter] 
    end&.strip

    self[:shift_inter] = 0
    self[:all_wanted] = self[:lick][:holes]
    
    if answer
      shift = $intervals_inv[answer.downcase] || 0
      if num_holes_playable[shift] > 0
        self[:shift_inter] = shift
        self[:all_wanted] = self[:lick][:holes].map do |hole|
          if musical_event?(hole) 
            hole
          else
            $harp[hole][:shifted_by][shift] || '(*)'
          end
        end
        if shift == 0
          $msgbuf.print "Holes not shifted", 2, 5, :shift
        else
          $msgbuf.print "Shifted holes by '#{answer}'", 2, 5, :shift
        end
      else
        $msgbuf.print "Shifting by '#{answer}' does not produce any playable holes; holes not shifted", 2, 5, :shift
      end
    else
      $msgbuf.print "No interval chosen, holes not shifted", 2, 5, :shift
    end
  end


  def continue_with_cycle
    self[:lick_idx] += 1
    if self[:lick_idx] >= $licks.length
      self[:lick_idx] = 0
      ctl_response 'Next cycle'
    end
  end


  def choose_random_lick
    if self[:lick_idx_before]
      # avoid playing the same lick twice in a row
      self[:lick_idx] = (self[:lick_idx] + 1 + rand($licks.length - 1)) % $licks.length
    else
      self[:lick_idx] = rand($licks.length)
    end
  end


  def choose_lick_by_name start_with
    mnames = $licks.map {|l| l[:name]}.select {|n| n.start_with?(start_with)}
    case mnames.length
    when 1
      self[:lick_idx] = $licks.index {|l| l[:name][start_with]}
    when 0
      err "Unknown lick: '#{start_with}' after applying these options:#{desc_lick_select_opts}"
    else
      exact = $licks.map {|l| l[:name]}.select {|n| n == start_with}
      if exact.length == 1
        self[:lick_idx] = $licks.index {|l| l[:name] == exact[0]}
      else
        err "Multiple licks start with '#{start_with}': #{mnames}"
      end
    end
  end


  def set_lick_and_others_from_idx idx = nil
    self[:lick_idx] = idx || self[:lick_idx]
    self[:lick] = $licks[self[:lick_idx]]
    self[:all_wanted] = self[:lick][:holes]
    self[:lick_hints] = ['Lick Name: ' + self[:lick][:name],
                         'Tags: ' + self[:lick][:tags].join(',')]
    self[:lick_hints] << 'Desc: ' + self[:lick][:desc] if self[:lick][:desc] != ''
  end

end
