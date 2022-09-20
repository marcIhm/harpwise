#
# Perform quiz and licks
#

def do_quiz_or_licks

  unless $other_mode_saved[:conf]
    make_term_immediate
    start_collect_freqs
  end
  $ctl_can[:next] = true
  $ctl_can[:loop] = true
  $ctl_can[:switch_modes] = true
  $modes_for_switch = [:listen, :quiz]
  $ctl_can[:octave] = $ctl_can[:named] = ( $mode == :licks )
  $ctl_listen[:ignore_recording] = $ctl_listen[:ignore_holes] = $ctl_listen[:ignore_partial] = false
  $write_journal = true
  journal_start
  
  first_round = true
  all_wanted_before = all_wanted = nil
  $all_licks, $licks = read_licks
  lick = lick_idx = lick_idx_before = lick_idx_iter = nil
  lick_cycle = false
  octave_shift = 0
  start_with =  $other_mode_saved[:conf]  ?  nil  :  $opts[:start_with].dup
  puts
  puts
  puts "\n" + ( $mode == :licks  ?  "#{$licks.length} licks, "  :  "" ) +
         "key of #{$key}" unless $other_mode_saved[:conf]
      
  loop do   # forever until ctrl-c, sequence after sequence

    do_write_journal = false

    if first_round
      print "\n\n"
    else
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      print "\e[#{$lines[:message2]}H\e[K"
      print_issue ''
      ctl_issue
    end

    #
    #  First compute and play the sequence that is expected
    #

    # check, if lick-file has changed
    if lick_idx && refresh_licks
      lick = $licks[lick_idx]
      all_wanted = lick[:holes]
      ctl_issue 'Refreshed licks'
    end

    # For licks, the calculation of next one has these cases:
    # - switching back to mode from listen
    # - ctl-command that takes us back
    # - requests for a named lick
    # - change
    # - iteration
    # - simply done with previous lick and next lick is required
    
    # handle $ctl-commands from keyboard-thread, that probably come
    # from a previous loop iteration or from other mode
    # The else-branch further down handles the general case without $ctl-commands
    if $other_mode_saved[:lick_idx]
      lick_idx = $other_mode_saved[:lick_idx]
      lick = $licks[lick_idx]
      all_wanted = lick[:holes]
      $other_mode_saved[:lick_idx] = nil
      lick_idx_before = nil
    elsif $other_mode_saved[:all_wanted]
      all_wanted = $other_mode_saved[:all_wanted]
      $other_mode_saved[:all_wanted] = nil
    elsif $ctl_listen[:back] 
      if lick
        if !lick_idx_before || lick_idx_before == lick_idx
          print "\e[G\e[0m\e[32mNo previous lick; replay\e[K"
          sleep 1
        else
          lick_idx = lick_idx_before
          lick = $licks[lick_idx]
          all_wanted = lick[:holes]
        end
      else
        if !all_wanted_before || all_wanted_before == all_wanted
          print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
          sleep 1
        else
          all_wanted = all_wanted_before
        end
      end
      $ctl_listen[:loop] = true

    elsif $ctl_listen[:named_lick]  # can only happen for mode licks

      make_term_cooked
      input = matching = nil

      old_licks = get_last_lick_idxs_from_journal($licks)
      lnames_abbr = old_licks[0,12].each_with_index.map do |lick_idx,ar_idx|
        case ar_idx
        when 0
          ' l: '
        when (1..9)
          "#{ar_idx}l: "
        else
          '    '
        end + $licks[lick_idx][:name]
      end
      cmnt_print_in_columns 'Recent licks and some', lnames_abbr.map {|ln| ln + '   '} + ['//'] + $licks.map {|l| l[:name]}.sort,
                            ["current lick is #{lick[:name]}"]
      cmnt_print_prompt 'Please enter', 'Name of new lick',
                        '(or part of or l,2l,..)'
                           
      input = STDIN.gets&.chomp || ''
      
      if (md = input.match(/^(\dlast|\dl)$/)) || input == 'last' || input == 'l'
        # one of last licks requested
        lick_idx_before = lick_idx 
        lick_idx = old_licks[md  ?  md[1].to_i - 1  :  0]
        lick = $licks[lick_idx]
        all_wanted = lick[:holes]
      else
        matching = read_lick_name(input, lick_idx)
        if lick_idx != matching[1]
          lick_idx_before = lick_idx 
          lick = matching[0]
          lick_idx = matching[1]
          all_wanted = lick[:holes]
          do_write_journal = true
        end
      end
      lick_idx_iter = nil

      make_term_immediate
      $ctl_listen[:named_lick] = false
      
    elsif $ctl_listen[:change_tags]  # can only happen in licks
      
      doiter = read_tags_and_refresh_licks(lick,
                                           $ctl_listen[:change_tags] == :all ? true : false)
      print "\e[#{$lines[:key]}H\e[k" + text_for_key
      if doiter == :keep
        # keep iteration state
      elsif doiter
        # we treat iter like cycle
        lick_cycle = true
        lick_idx_before = lick_idx = 0
        lick_idx_iter = lick_idx
        lick = $licks[lick_idx]
      else
        lick_idx_before = lick_idx = rand($licks.length)
        lick_idx_iter = nil
        lick = $licks[lick_idx]
      end
      all_wanted = lick[:holes]
      $ctl_listen[:change_tags] = false

    elsif $ctl_listen[:replay]
      
      # nothing to do here, replay will happen at start of next loop

    elsif $ctl_listen[:octave]

      octave_shift_was = octave_shift
      octave_shift += ( $ctl_listen[:octave] == :up  ?  +1  :  -1 )
      all_wanted_was = all_wanted
      all_wanted = lick[:holes].map do |hole|
        if musical_event?(hole) || octave_shift == 0
          hole
        else
          $semi2hole[$harp[hole][:semi] + 12 * octave_shift] || '(*)'
        end
      end
      if all_wanted.reject {|h| musical_event?(h)}.length == 0
        print "\e[#{$lines[:hint_or_message]}H\e[0;101mShifting lick by (one more) octave does not produce any playable notes.\e[0m\e[K"
        print "\e[#{$lines[:message2]}HPress any key to continue ... "
        $ctl_kb_queue.clear
        $ctl_kb_queue.deq
        print "\e[#{$lines[:hint_or_message]}H\e[K\e[#{$lines[:message2]}H\e[K"
        all_wanted = all_wanted_was
        octave_shift = octave_shift_was
        sleep 2
      else
        print "\e[#{$lines[:hint_or_message]}H\e[2mOctave shift \e[0m#{octave_shift}\e[K"
        $message_shown_at = Time.now.to_f
      end

    elsif $ctl_listen[:change_partial]

      read_and_set_partial
      print "\e[#{$lines[:hint_or_message]}H\e[2mPartial is \e[0m'#{$opts[:partial]}'\e[K"
      $message_shown_at = Time.now.to_f

    else # most general case: no $ctl-command. E.g. first or next
         # sequence or $ctl_listen[:next]: go to the next sequence

      all_wanted_before = all_wanted
      lick_idx_before = lick_idx
      octave_shift = 0

      do_write_journal = true

      # figure out holes to play
      if $mode == :quiz

        all_wanted = get_sample($num_quiz)
        jtext = all_wanted.join(' ')

      else # licks

        # continue with iteration through licks
        if lick_idx_iter 
          lick_idx_iter += 1
          if lick_idx_iter >= $licks.length
            if lick_cycle
              lick_idx_iter = 0
              ctl_issue 'Next cycle'
            else
              print "\e[#{$lines[:message2]}H\e[K"
              puts "\nIterated through licks.\n\n"
              exit
            end
          end
          lick_idx = lick_idx_iter

        # most general case: choose random lick
        elsif !start_with 

          if lick_idx_before
            # avoid playing the same lick twice in a row
            lick_idx = (lick_idx + 1 + rand($licks.length - 1)) % $licks.length
          else
            lick_idx = rand($licks.length)
          end

        # start lick iteration
        elsif $conf[:abbrevs_for_iter].include?(start_with)
          lick_cycle = ( start_with[0] == 'c' )
          lick_idx_iter = 0
          lick_idx = lick_idx_iter

        elsif (md = start_with.match(/^(\dlast|\dl)$/)) || start_with == 'last' || start_with == 'l'
          lick_idx = get_last_lick_idxs_from_journal[md  ?  md[1].to_i - 1  :  0]

        # search lick by name and maybe start iteration          
        else 
          doiter = $conf[:abbrevs_for_iter].map {|a| ',' + a}.find {|x| start_with.end_with?(x)}
          if doiter
            lick_cycle = ( doiter[1] == 'c' )
            start_with[-doiter.length .. -1] = ''
          end

          lick_idx = $licks.index {|l| l[:name] == start_with}
          err "Unknown lick: '#{start_with}' (after applying options '--tags' and '--no-tags' and '--max-holes')" unless lick_idx

          lick_idx_iter = lick_idx if doiter
        end # continue with iteration through licks

        start_with = nil

        #
        # now that we have a lick-index, we get the lick and its holes
        #
        
        lick = $licks[lick_idx]
        all_wanted = lick[:holes]
        jtext = sprintf('Lick %s: ', lick[:name]) + all_wanted.join(' ')

      end

      IO.write($journal_file, "#{jtext}\n\n", mode: 'a') if $write_journal && do_write_journal
      $ctl_listen[:loop] = $opts[:loop]

    end # handling $ctl-commands and calculating the next holes

    #
    #  Play the sequence or recording
    #
    if !zero_partial? || $ctl_listen[:replay] || $ctl_listen[:octave] || $ctl_listen[:change_partial]
      
      print_issue('Listen ...') unless first_round

      $ctl_listen[:ignore_partial] = true if zero_partial? && $ctl_listen[:replay]

      # show later comment already while playing
      unless first_round
        lines = comment_while_playing(all_wanted)
        fit_into_comment(lines) if lines
      end

      if $mode == :quiz || !lick[:rec] || $ctl_listen[:ignore_recording] || ($opts[:holes] && !$ctl_listen[:ignore_holes])
        play_holes all_wanted, first_round
      else
        play_recording lick, first_round, octave_shift
      end

      if $ctl_rec[:replay]
        $ctl_listen[:replay] = true
        redo
      end

      print_issue "Listen ... and !" unless first_round
      sleep 0.3

    end

    # reset controls before listening
    $ctl_listen[:back] = $ctl_listen[:next] = $ctl_listen[:replay] = $ctl_listen[:octave] = $ctl_listen[:change_partial] = false

    # these controls are only used during play, but can be set during
    # listening and play
    $ctl_listen[:ignore_recording] = $ctl_listen[:ignore_holes] = $ctl_listen[:ignore_partial] = false

    #
    #  Prepare for listening
    #
    
    if first_round
      clear_screen_and_scrollback
      system('clear')
    else
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      $column_short_hint_or_message = 1
      print "\e[#{$lines[:message2]}H\e[K"
    end
    full_seq_shown = false

    # precompute some values, that do not change during sequence
    min_sec_hold =  $mode == :licks  ?  0.0  :  0.1

    holes_with_scales = scaleify(all_wanted) if $opts[:comment] == :holes_scales
    holes_with_intervals = intervalify(all_wanted) if $opts[:comment] == :holes_intervals
    holes_with_notes = noteify(all_wanted) if $opts[:comment] == :holes_notes

    #
    #  Now listen for user to play the sequence back correctly
    #

    begin   # while looping over one sequence

      round_start = Time.now.to_f
      $ctl_listen[:forget] = false
      idx_refresh_comment_cache = comment_cache = nil
      clear_area_comment
      
      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one iteration while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        handle_holes(
          
          # lambda_issue
          -> () do
            if $ctl_listen[:loop]
              "\e[32mLoop\e[0m at #{idx+1} of #{all_wanted.length} notes "
            else
              if $num_quiz == 1 
                "Play the note you have heard !"
              else
                "Play note \e[32m#{idx+1}\e[0m of" +
                  " #{all_wanted.length} you have heard ! "
              end
            end 
          end,

          
          # lambda_good_done_was_good
          -> (played, since) {[played == wanted || musical_event?(wanted),  
                               $ctl_listen[:forget] ||
                               ((played == wanted || musical_event?(wanted)) &&
                                (Time.now.to_f - since >= min_sec_hold )),
                               idx > 0 && played == all_wanted[idx-1] && played != wanted]}, 

          # lambda_skip
          -> () {$ctl_listen[:next] || $ctl_listen[:back] || $ctl_listen[:replay] || $ctl_listen[:octave] || $ctl_listen[:change_partial]},  

          
          # lambda_comment; this one needs no arguments at all
          -> (*_) do
            if idx != idx_refresh_comment_cache || $ctl_listen[:update_comment]
              idx_refresh_comment_cache = idx
              $perfctr[:lambda_comment_quiz_call] += 1
              idx_refresh_ccache = idx
              comment_cache = 
                case $opts[:comment]
                when :holes_some
                  largify(all_wanted, idx)
                when :holes_scales
                  holes_with_scales ||= scaleify(all_wanted)
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_scales, idx)
                when :holes_intervals
                  holes_with_intervals ||= intervalify(all_wanted)
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_intervals, idx)
                when :holes_notes
                  holes_with_notes ||= noteify(all_wanted)
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_notes, idx)
                when :holes_all
                  wrapify_for_comment($lines[:hint_or_message] - $lines[:comment_tall], all_wanted, idx)
                else
                  fail "Internal error unknown comment style: #{$opts[:comment]}"
                end
              $ctl_listen[:update_comment] = false
            end
            comment_cache
          end,

          
          # lambda_hint
          -> (_) do
            hole_passed = Time.now.to_f - hole_start
            round_passed = Time.now.to_f - round_start
            hole_hint = if hole_passed > 6
                          "\e[0mHint:\e[2m Play \e[0m\e[32m#{wanted}"
                        else
                          if idx > 0
                            isemi, itext, _, _ = describe_inter(wanted, all_wanted[idx - 1])
                            "\e[0mHint:\e[2m Move " + ( itext ? "a \e[0m\e[32m#{itext}" : "\e[0m\e[32m#{isemi}" )
                          else
                            ''
                          end
                        end
            if $mode == :licks
              [ lick[:name],
                lick[:tags].map do |t|
                  t == 'starred'  ?  "#{$starred[lick[:name]] || 0}*#{t}"  :  t
                end.join(','),
                hole_hint,
                lick[:desc] ]
            else
              [ hole_hint ]
            end
          end,
          
          
          # lambda_hole_for_inter
          -> (hole_held_before, hole_ref) do  
            hfi = hole_ref || hole_held_before
            regular_hole?(hfi)  ?  hfi  :  nil
          end,

          
          # lambda_star_lick
          if $mode == :licks
            -> (delta) do
              $starred[lick[:name]] += delta
              startag = if $starred[lick[:name]] > 0
                          'starred'
                        elsif $starred[lick[:name]] < 0
                          'unstarred'
                        end
              %w(starred unstarred).each {|t| lick[:tags].delete(t)}
              lick[:tags] << startag if startag
              $starred.delete([lick[:name]]) if $starred[lick[:name]] == 0
              File.write($star_file, YAML.dump($starred))
              print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mWrote #{$star_file}\e[K"
              $message_shown_at = Time.now.to_f
            end
          else
            nil
          end
        )  # end of get_hole

        
        if $ctl_listen[:switch_modes]
          if $mode == :licks
            $other_mode_saved[:lick_idx] = lick_idx
          else
            $other_mode_saved[:all_wanted] = all_wanted
          end
          return
        end
        
        break if $ctl_listen[:next] || $ctl_listen[:back] || $ctl_listen[:replay] || $ctl_listen[:octave]  || $ctl_listen[:change_partial] || $ctl_listen[:forget] || $ctl_listen[:named_lick] || $ctl_listen[:change_tags]

      end # notes in a sequence
      
      #
      #  Finally judge result
      #

      if $ctl_listen[:forget]
        clear_area_comment
        if [:holes_scales, :holes_intervals].include?($opts[:comment])
          print "\e[#{$lines[:comment] + 2}H\e[0m\e[32m   again"
        else
          print "\e[#{$lines[:comment]}H\e[0m\e[32m"
          do_figlet_unwrapped 'again', 'smblock'
        end
        sleep 0.3
      else
        sleep 0.3
        clear_area_comment if [:holes_all, :holes_scales, :holes_intervals].include?($opts[:comment])
        # update comment
        ctext = if $ctl_listen[:next]
                  'next'
                elsif $ctl_listen[:back]
                  'jump back'
                elsif $ctl_listen[:replay]
                  'replay'
                elsif $ctl_listen[:octave] == :up
                  'octave up'
                elsif $ctl_listen[:octave] == :down
                  'octave down'
                elsif $ctl_listen[:named_lick] || $ctl_listen[:change_tags] || $ctl_listen[:change_partial]
                  # these will issue their own message
                  nil
                else
                  full_seq_shown ? 'Yes ' : 'Great ! '
                end
        if ctext
          clear_area_comment
          if [:holes_scales, :holes_intervals].include?($opts[:comment])
            puts "\e[#{$lines[:comment] + 2}H\e[0m\e[32m   " + ctext
          else
            print "\e[#{$lines[:comment]}H\e[0m\e[32m"
            do_figlet_unwrapped ctext, 'smblock'
          end
          print "\e[0m"
        end

        # update hint
        print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[K"
        $column_short_hint_or_message = 1
        unless $ctl_listen[:replay] || $ctl_listen[:octave] || $ctl_listen[:change_partial] || $ctl_listen[:forget] || $ctl_listen[:next] || $ctl_listen[:named_lick] || $ctl_listen[:change_tags]
          print "\e[0m\e[32mAnd #{$ctl_listen[:loop] ? 'again' : 'next'} !\e[0m\e[K"
          full_seq_shown = true
          sleep 0.5 unless ctext
        end
        sleep 0.5 if ctext
      end
      
    end while ( $ctl_listen[:loop] || $ctl_listen[:forget]) && !$ctl_listen[:back] && !$ctl_listen[:next] && !$ctl_listen[:replay] && !$ctl_listen[:octave] && !$ctl_listen[:change_partial] && !$ctl_listen[:named_lick]  && !$ctl_listen[:change_tags]  # looping over one sequence

    print_issue ''
    first_round = false
  end # forever sequence after sequence
end
      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale and added scale
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

  if $opts[:add_scales]
    # (randomly) replace notes with added ones and so prefer them 
    for i in (1 .. num - 1)
      if rand >= 0.6
        holes[i] = nearest_hole_with_flag(holes[i], :added)
        what[i] = :nearest_added
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


def play_holes all_holes, first_round, terse = false

  if $opts[:partial] && !$ctl_listen[:ignore_partial]
    holes, _, _ = select_and_calc_partial(all_holes, nil, nil)
  else
    holes = all_holes
  end
  
  IO.write($testing_log, all_holes.inspect + "\n", mode: 'a') if $opts[:testing]
  
  $ctl_hole[:skip] = false
  $column_short_hint_or_message = 1
  ltext = "\e[2m(h for help) "
  holes.each_with_index do |hole, idx|
    if terse
      print hole + ' '
    else
      if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
        ltext = "\e[2m(h for help) "
        if first_round
          print "\e[#{$term_height}H\e[K"
          print "\e[#{$term_height-1}H\e[K"
        else
          print "\e[#{$lines[:hint_or_message]}H\e[K"
          print "\e[#{$lines[:message2]}H\e[K"
        end
      end
      if idx > 0
        if !musical_event?(hole) && !musical_event?(holes[idx - 1])
          isemi, itext, _, _ = describe_inter(hole, holes[idx - 1])
          ltext += ' ' + ( itext || isemi ).tr(' ','') + ' '
        else
          ltext += ' '
        end
      end
      ltext += if musical_event?(hole)
                 "\e[0m#{hole}\e[2m"
               elsif $opts[:immediate]
                 "\e[0m#{hole},#{$harp[hole][:note]}\e[2m"
               else
                 "\e[0m#{$harp[hole][:note]}\e[2m"
               end
      if $opts[:add_scales]
        part = '(' +
               $hole2flags[hole].map {|f| {added: 'a', root: 'r'}[f]}.compact.join(',') +
               ')'
        ltext += part unless part == '()'
      end

      if first_round
        print "\e[#{$term_height-1}H#{ltext.strip}\e[K"
      else
        print "\e[#{$lines[:message2]}H\e[K"
        print "\e[#{$lines[:hint_or_message]}H#{ltext.strip}\e[K"
      end
    end

    if musical_event?(hole)
      sleep $opts[:fast]  ?  0.25  :  0.5
    else
      play_hole_and_handle_kb hole
    end

    if $ctl_hole[:show_help]
      display_kb_help 'series of holes',first_round,  <<~end_of_content
        SPACE: pause/continue
        TAB,+: skip to end
      end_of_content
      $ctl_hole[:show_help] = false
    elsif $ctl_hole[:skip]
      print "\e[0m\e[32m skip to end\e[0m"
      sleep 0.3
      break
    end
  end
  puts if terse
end


def play_recording lick, first_round, octave_shift

  if $opts[:partial] && !$ctl_listen[:ignore_partial]
    lick[:rec_length] ||= sox_query("#{$lick_dir}/recordings/#{lick[:rec]}", 'Length')
    _, start, length = select_and_calc_partial([], lick[:rec_start], lick[:rec_length])
  else
    start, length = lick[:rec_start], lick[:rec_length]
  end

  text = "Lick \e[0m\e[32m" + lick[:name] + "\e[0m (h for help) ... " + lick[:holes].join(' ')
  if first_round
    print "\e[#{$term_height}H#{text} \e[K"
  else
    print "\e[#{$lines[:hint_or_message]}H#{text} \e[K"
  end

  skipped = play_recording_and_handle_kb(lick[:rec], start, length, lick[:rec_key], first_round, octave_shift)

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
  per_line = (($term_width * 0.8 - 4)/ max_cell_len).truncate
  line = '   '
  holes_scales.each_with_index do |hole_scale, idx|
    if idx > 0 && idx % per_line == 0
      lines << line
      lines << ''
      line = '   '
    end
    line += " \e[0m" +
            if idx < idx_first_active
              ' ' + "\e[0m\e[2m" + hole_scale[0] + hole_scale[1] + '.' + hole_scale[2]
            else
              hole_scale[0] +
                if idx == idx_first_active
                  "\e[0m\e[92m*"
                else
                  ' '
                end +
                sprintf("\e[0m\e[%dm", get_hole_color_inactive(hole_scale[1],true)) +
                hole_scale[1] + "\e[0m\e[2m" + '.' + hole_scale[2]
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


def scaleify holes
  holes = holes.reject {|h| musical_event?(h)}
  holes_maxlen = holes.max_by(&:length).length
  shorts_maxlen = holes.map {|hole| $hole2scale_shorts[hole]}.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole, $hole2scale_shorts[hole].ljust(shorts_maxlen)]
  end
end


def intervalify holes
  holes = holes.reject {|h| musical_event?(h)}
  holes_maxlen = holes.max_by(&:length).length
  inters = []
  holes.each_with_index do |hole,idx|
    isemi ,_ ,itext, _ = describe_inter(hole,
                                     idx == 0 ? hole : holes[idx - 1])
    idesc = itext || isemi
    idesc.gsub!(' ','')
    inters << idesc
  end
  holes_maxlen = holes.max_by(&:length).length
  inters_maxlen = inters.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole, inters.shift.ljust(inters_maxlen)]
  end
end


def noteify holes
  holes = holes.reject {|h| musical_event?(h)}
  holes_maxlen = holes.max_by(&:length).length
  notes_maxlen = holes.map {|hole| $harp[hole][:note]}.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole, $harp[hole][:note].ljust(notes_maxlen)]
  end
end


def largify holes, idx
  line = $lines[:comment_low]
  if $num_quiz == 1
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
      # inactive figlet-line, because it also contain active holes;
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
  

def read_lick_name input, curr_lick_idx
  curr_lick = $licks[curr_lick_idx]
  begin
    matching = $licks.map.with_index.select {|li| li[0][:name][input]}
    if matching.length != 1
      if matching.length == 0
        cmnt_print_in_columns "No lick contains '#{input}'; all",
                              $licks.map {|l| l[:name]}.sort,
                              ["current is '#{curr_lick[:name]}'"]
      else
        cmnt_print_in_columns "Multiple licks (#{matching.length}) contain '#{input}'",
                              matching.map {|m| m[0][:name]}.sort,
                              ["current is '#{curr_lick[:name]}'"]
      end
      cmnt_print_prompt 'Enter a', 'new name', 'or just press RETURN to keep'
      input = STDIN.gets.chomp
      matching = [[curr_lick,curr_lick_idx]] if input == ''
    end
  end while matching.length != 1
  print "\e[#{$lines[:comment]}H\e[0m\e[J"
  matching[0]
end


def read_tags_and_refresh_licks curr_lick, all
  tag_opts = %w( --tags-any --tags-all --no-tags-any --no-tags-all )
  tag_opt = nil
  make_term_cooked
  if all
    begin
      cmnt_print_in_columns 'There are four relevant options',
                            tag_opts.map.with_index {|to,idx| "#{idx+1}: '#{to}'        "},
                            ['the other options will be set to the empty string']
      cmnt_print_prompt 'Please choose', 'which option to set',
                        '(1,2,3,4 or just RETURN for 1 or q to quit)'
      input = STDIN.gets.chomp
      input = '1' if input == ''
      if %w( 1 2 3 4 ).include?(input)
        tag_opt = tag_opts[input.to_i - 1][2..-1].o2sym
      elsif input == 'q'
        return :keep
      else
        cmnt_report_error_wait_key "Invalid input: '#{input}'; none of 1..4,q !"
      end
    end until tag_opt
  else
    tag_opt = :tags_any
  end
  tag_opts.map {|to| to[2..-1].o2sym}.
    each {|ts| $opts[ts] = '' unless ts == tag_opt}

  all_tags = $all_licks.map {|l| l[:tags]}.flatten.uniq.sort
  cmnt_print_in_columns "Tags of current lick #{curr_lick[:name]} and some",
                        curr_lick[:tags] + ['//'] + all_tags,
                        ["maybe with ',cycle' or ',iter', SPACE to list, RETURN to go without"]
  topt = '--' + tag_opt.o2str
  opof = "(or part of; current value is '#{$opts[tag_opt]}')"
  cmnt_print_prompt 'New value for', topt, opof
  input = STDIN.gets.chomp
  doiter = $conf[:abbrevs_for_iter].map {|a| ',' + a}.find {|x| input.end_with?(x)}
  input[-doiter.length .. -1] = '' if doiter
  begin
    mtags = if input == ' '
              all_tags
            elsif input == ''
              [nil] 
            elsif input[',']
              [input]
            else
              all_tags.select {|t| t[input]}
            end
    done = false
    
    if mtags.length == 1 || input[',']
      $opts[tag_opt] = mtags[0]
      $all_licks, $licks = read_licks true
      if $licks.length == 0
        cmnt_print_in_columns "No licks match '--tags #{input}'; these tags are available\n",
                              all_tags
      else
        done = true
      end
    elsif mtags.length == 0
      cmnt_print_in_columns "No tags match your input '#{input}'; these are available",
                            all_tags
    else
      cmnt_print_in_columns(
        if input == ' '
          'All tags'
        else
          'Multiple tags match your input'
        end,
        mtags.sort)
    end
    unless done
      cmnt_print_prompt 'Enter a new value for', topt, opof
      input = STDIN.gets.chomp
    end
  end while !done || $licks.length == 0
  make_term_immediate
  print "\e[#{$lines[:comment_tall]}H\e[0m\e[J"
  return doiter
end


def read_and_set_partial
  make_term_cooked
  cmnt_print_in_columns 'Examples for --partial',
                        %w(1/3@b 1/4@x 1/2@e 1@b, 1@e 2@x 0),
                        ["current value is '#{$opts[:partial]}'",
                         'RETURN to keep, SPACE to clear',
                         'see usage info for more explanations']
  cmnt_print_prompt 'Please enter', 'new value'
  input = STDIN.gets.chomp
  old = $opts[:partial]
  $opts[:partial] = if input == ''
                      $opts[:partial]
                    elsif input.strip.empty?
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
    cmnt_report_error_wait_key e
    $opts[:partial] = old
  end
  print "\e[#{$lines[:comment]}H\e[0m\e[J"
end


def comment_while_playing holes
  # Show all lines in case of immediate or if the comment would show them anyway
  if $opts[:comment] == :holes_scales
    holes_with_scales = scaleify(holes)
    tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_scales, 0)
  elsif $opts[:comment] == :holes_intervals
    holes_with_intervals = intervalify(holes)
    tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_intervals, 0)
  elsif $opts[:comment] == :holes_all || $opts[:immediate]
    wrapify_for_comment($lines[:hint_or_message] - $lines[:comment_tall], holes, 0)
  else
    nil
  end
end
