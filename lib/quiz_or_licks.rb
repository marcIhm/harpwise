#
# Perform quiz or licks
#

def do_quiz_or_licks

  unless $other_mode_saved[:conf]
    # do not start kb thread yet as we need to read current cursor
    # line from terminal below
    prepare_term
    start_collect_freqs
  end
  $ctl_can[:next] = true
  $ctl_can[:loop] = true
  $ctl_can[:switch_modes] = true
  $ctl_can[:no_progress] = true
  $modes_for_switch = [:listen, $mode.to_sym]
  $ctl_can[:octave] = $ctl_can[:named] = ( $mode == :licks )
  $ctl_mic[:ignore_recording] = $ctl_mic[:ignore_holes] = $ctl_mic[:ignore_partial] = false
  $journal_active = true

  to_play = PlayController.new
  oride_l_message2 = nil
  $all_licks, $licks = read_licks
  start_with =  $other_mode_saved[:conf]  ?  nil  :  $opts[:start_with].dup
  splashed = false
  jtext = nil

  loop do   # forever until ctrl-c, sequence after sequence

    #
    #  First compute and play the sequence that is expected
    #

    # check, if lick-file has changed
    if to_play[:lick_idx] && refresh_licks
      to_play[:lick] = $licks[to_play[:lick_idx]]
      to_play[:all_wanted] = to_play[:lick][:holes]
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
      to_play[:lick_idx] = $other_mode_saved[:lick_idx]
      to_play[:lick] = $licks[to_play[:lick_idx]]
      to_play[:all_wanted] = to_play[:lick][:holes]
      $other_mode_saved[:lick_idx] = nil
      to_play[:lick_idx_before] = nil

    elsif $other_mode_saved[:all_wanted]
      # mode is quiz
      to_play[:all_wanted] = $other_mode_saved[:all_wanted]
      $other_mode_saved[:all_wanted] = nil

    elsif $ctl_mic[:back]
      to_play.back_one_lick
      
    elsif $ctl_mic[:named_lick]  # can only happen for mode licks
      jtext = to_play.read_name_change_lick
      
    elsif $ctl_mic[:edit_lick_file]  # can only happen for mode licks
      to_play.edit_lick

    elsif $ctl_mic[:change_tags]  # can only happen in licks
      to_play.change_tags

    elsif $ctl_mic[:reverse_holes]
      to_play[:all_wanted] = to_play[:all_wanted].reverse

    elsif $ctl_mic[:replay]      
    # nothing to do here, (re)playing will happen further down

    elsif $ctl_mic[:octave]
      to_play[:octave_shift_was] = to_play[:octave_shift]
      to_play[:octave_shift] += ( $ctl_mic[:octave] == :up  ?  +1  :  -1 )
      to_play.change_octave

    elsif $ctl_mic[:change_partial]
      read_and_set_partial
      print "\e[#{$lines[:hint_or_message]}H\e[2mPartial is \e[0m'#{$opts[:partial]}'\e[K"
      $message_shown_at = Time.now.to_f

    else
      # most general case: $ctl_mic[:next] or no $ctl-command;
      # go to the next lick or sequence of holes

      to_play[:all_wanted_before] = to_play[:all_wanted]
      to_play[:lick_idx_before] = to_play[:lick_idx]
      to_play[:octave_shift] = 0

      # figure out holes to play
      if $mode == :quiz
        to_play[:all_wanted] = get_sample($num_quiz)
        jtext = to_play[:all_wanted].join(' ')

      else # $mode == :licks

        if start_with
          if (md = start_with.match(/^(\dlast|\dl)$/)) || start_with == 'last' || start_with == 'l'
            # start with lick from history
            to_play[:lick_idx] = get_last_lick_idxs_from_journal[md  ?  md[1].to_i - 1  :  0]
          else
            to_play.choose_lick_by_name(start_with)
          end
          # consumed
          start_with = nil

        elsif $opts[:iterate] == :cycle
          if to_play[:lick_idx]
            # ongoing cycle
            to_play.continue_with_cycle
          else
            # start cycle
            to_play[:lick_idx] = 0
          end
          
        else # $opts[:iterate] == :random
          to_play.choose_random_lick
          
        end

        to_play[:lick] = $licks[to_play[:lick_idx]]
        to_play[:all_wanted] = to_play[:lick][:holes]
        jtext = sprintf('Lick %s: ', to_play[:lick][:name]) + to_play[:all_wanted].join(' ')
      end

      $ctl_mic[:loop] = $opts[:loop]

    end # handling $ctl-commands and calculating the next holes

    # Now that we are past possible commandline errors, we may initialize screen fully
    if !$other_mode_saved[:conf] && !splashed
      # write banner, provide smooth animation
      animate_splash_line
      puts "\n" + ( $mode == :licks  ?  "#{$licks.length} licks, "  :  "" ) +
           "key of #{$key}"
      sleep 0.01
      3.times do
        puts
        sleep 0.01
      end

      # get current cursor line, will be used as bottom of two lines for messages
      print "\e[6n"
      reply = ''
      reply += STDIN.gets(1) while reply[-1] != 'R'
      oride_l_message2 = reply.match(/^.*?([0-9]+)/)[1].to_i - 1
      
      # complete term init
      make_term_immediate
      splashed = true
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
    IO.write($journal_file, "#{jtext}\n", mode: 'a') if $journal_active && jtext
    jtext = nil
    if !zero_partial? || $ctl_mic[:replay] || $ctl_mic[:octave] || $ctl_mic[:change_partial]
      
      print_mission('Listen ...') unless oride_l_message2

      $ctl_mic[:ignore_partial] = true if zero_partial? && $ctl_mic[:replay]

      # show later comment already while playing
      unless oride_l_message2
        lines = comment_while_playing(to_play[:all_wanted])
        fit_into_comment(lines) if lines
      end

      if $mode == :quiz || !to_play[:lick][:rec] || $ctl_mic[:ignore_recording] ||
         (to_play[:all_wanted] == to_play[:lick][:holes].reverse) ||
         ($opts[:holes] && !$ctl_mic[:ignore_holes])
        play_holes to_play[:all_wanted], oride_l_message2, false, to_play[:lick]
      else
        play_recording to_play[:lick], oride_l_message2, to_play[:octave_shift]
      end

      if $ctl_rec[:replay]
        $ctl_mic[:replay] = true
        redo
      end

      print_mission "Listen ... and !" unless oride_l_message2
      sleep 0.3

    end

    # reset controls before listening
    $ctl_mic[:back] = $ctl_mic[:next] = $ctl_mic[:replay] = $ctl_mic[:octave] = $ctl_mic[:reverse_holes] = $ctl_mic[:change_partial] = false

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
      $column_short_hint_or_message = 1
      print "\e[#{$lines[:message2]}H\e[K"
    end
    full_seq_shown = false

    # precompute some values, that do not change during sequence
    min_sec_hold =  $mode == :licks  ?  0.0  :  0.1

    holes_with_scales = scaleify(to_play[:all_wanted]) if $opts[:comment] == :holes_scales
    holes_with_intervals = intervalify(to_play[:all_wanted]) if $opts[:comment] == :holes_intervals
    holes_with_notes = noteify(to_play[:all_wanted]) if $opts[:comment] == :holes_notes

    #
    #  Now listen for user to play the sequence back correctly
    #

    begin   # while looping over one sequence

      round_start = Time.now.to_f
      $ctl_mic[:forget] = false
      idx_refresh_comment_cache = comment_cache = nil
      clear_area_comment

      # iterate over notes in sequence, i.e. one iteration while looping
      to_play[:all_wanted].each_with_index do |wanted, idx|  

        hole_start = Time.now.to_f
        pipeline_catch_up

        handle_holes(
          
          # lambda_mission
          -> () do
            if $ctl_mic[:loop]
              "\e[32mLoop\e[0m at #{idx+1} of #{to_play[:all_wanted].length} notes"
            else
              if $num_quiz == 1 
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
          -> () {$ctl_mic[:next] || $ctl_mic[:back] || $ctl_mic[:replay] || $ctl_mic[:octave] || $ctl_mic[:change_partial]},  

          
          # lambda_comment; this one needs no arguments at all
          -> (*_) do
            if idx != idx_refresh_comment_cache || $ctl_mic[:update_comment]
              idx_refresh_comment_cache = idx
              $perfctr[:lambda_comment_quiz_call] += 1
              idx_refresh_ccache = idx
              comment_cache = 
                case $opts[:comment]
                when :holes_some
                  largify(to_play[:all_wanted], idx)
                when :holes_scales
                  holes_with_scales ||= scaleify(to_play[:all_wanted])
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_scales, idx)
                when :holes_intervals
                  holes_with_intervals ||= intervalify(to_play[:all_wanted])
                  tabify_colorize($lines[:hint_or_message] - $lines[:comment_tall], holes_with_intervals, idx)
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
            hole_passed = Time.now.to_f - hole_start
            round_passed = Time.now.to_f - round_start
            hole_hint = if hole_passed > 6
                          "\e[0mHint:\e[2m Play \e[0m\e[32m#{wanted}"
                        else
                          if idx > 0
                            isemi, itext, _, _ = describe_inter(wanted, to_play[:all_wanted][idx - 1])
                            "\e[0mHint:\e[2m Move " + ( itext ? "a \e[0m\e[32m#{itext}" : "\e[0m\e[32m#{isemi}" )
                          else
                            ''
                          end
                        end
            if $mode == :licks
              [ to_play[:lick][:name],
                to_play[:lick][:tags].map do |t|
                  t == 'starred'  ?  "#{$starred[to_play[:lick][:name]] || 0}*#{t}"  :  t
                end.join(','),
                hole_hint,
                to_play[:lick][:desc] ]
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
              print "\e[#{$lines[:hint_or_message]};#{$column_short_hint_or_message}H\e[2mWrote #{$star_file}\e[K"
              $message_shown_at = Time.now.to_f
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
        
        break if [:next, :back, :replay, :octave, :change_partial, :forget, :named_lick, :edit_lick_file, :change_tags, :reverse_holes].any? {|k| $ctl_mic[k]}

      end # notes in a sequence
      
      #
      #  Finally judge result
      #

      if $ctl_mic[:forget]
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
        ctext = if $ctl_mic[:next]
                  'next'
                elsif $ctl_mic[:back]
                  'jump back'
                elsif $ctl_mic[:replay]
                  'replay'
                elsif $ctl_mic[:octave] == :up
                  'octave up'
                elsif $ctl_mic[:octave] == :down
                  'octave down'
                elsif $ctl_mic[:reverse_holes] == :down
                  'octave down'
                elsif [:named_lick, :edit_lick_file, :change_tags, :reverse_holes, :change_partial].any? {|k| $ctl_mic[k]}
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
        unless [:replay, :octave, :change_partial, :forget, :next, :named_lick, :edit_lick_file, :change_tags, :reverse_holes].any? {|k| $ctl_mic[k]}
          print "\e[0m\e[32mAnd #{$ctl_mic[:loop] ? 'again' : 'next'} !\e[0m\e[K"
          full_seq_shown = true
          sleep 0.5 unless ctext
        end
        sleep 0.5 if ctext
      end
      
    end while ( $ctl_mic[:loop] || $ctl_mic[:forget]) && [:back, :next, :replay, :octave, :change_partial, :named_lick, :edit_lick_file, :change_tags, :reverse_holes].all? {|k| !$ctl_mic[k]}  # looping over one sequence

    print_mission ''
    oride_l_message2 = nil
  end # forever sequence after sequence
end


$quiz_sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
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
        # semitone distances 4,7 and 12 are major third, perfect fifth
        # and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * [-1,1].sample
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


def play_holes all_holes, oride_l_message2, terse = false, lick = nil

  if $opts[:partial] && !$ctl_mic[:ignore_partial]
    holes, _, _ = select_and_calc_partial(all_holes, nil, nil)
  else
    holes = all_holes
  end
  
  IO.write($testing_log, all_holes.inspect + "\n", mode: 'a') if $testing
  
  $ctl_hole[:skip] = false
  $column_short_hint_or_message = 1
  ltext = if lick
            "\e[2mLick \e[0m#{lick[:name]}\e[2m (h for help) ... "
          else
            "\e[2m(h for help) ... "
          end
  holes.each_with_index do |hole, idx|
    if terse
      print hole + ' '
    else
      if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
        ltext = "\e[2m(h for help)  "
        if oride_l_message2
          print "\e[#{oride_l_message2}H\e[K"
          print "\e[#{oride_l_message2-1}H\e[K"
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
      if $used_scales.length > 1
        part = '(' +
               $hole2flags[hole].map {|f| {added: 'a', root: 'r'}[f]}.compact.join(',') +
               ')'
        ltext += part unless part == '()'
      end

      if oride_l_message2
        print "\e[#{oride_l_message2}H\e[K"
        print "\e[#{oride_l_message2-1}H#{ltext.strip}\e[K"
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
      display_kb_help 'series of holes', !!oride_l_message2,  <<~end_of_content
        SPACE: pause/continue
        TAB,+: skip to end
      end_of_content
      # continue below help (first round only)
      print "\n\n"
      oride_l_message2 = [oride_l_message2 + 10, $term_height].min if oride_l_message2
      $ctl_hole[:show_help] = false
    elsif $ctl_hole[:skip]
      print "\e[0m\e[32m skip to end\e[0m"
      sleep 0.3
      break
    end
  end
  puts if terse
end


def play_recording lick, oride_l_message2, octave_shift

  if $opts[:partial] && !$ctl_mic[:ignore_partial]
    lick[:rec_length] ||= sox_query("#{$lick_dir}/recordings/#{lick[:rec]}", 'Length')
    _, start, length = select_and_calc_partial([], lick[:rec_start], lick[:rec_length])
  else
    start, length = lick[:rec_start], lick[:rec_length]
  end

  text = "Lick \e[0m\e[32m" + lick[:name] + "\e[0m (h for help) ... " + lick[:holes].join(' ')
  if oride_l_message2
    print "\e[#{oride_l_message2}H#{text} \e[K"
  else
    print "\e[#{$lines[:hint_or_message]}H#{text} \e[K"
  end

  skipped = play_recording_and_handle_kb(lick[:rec], start, length, lick[:rec_key], !!oride_l_message2, octave_shift)

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


def scaleify holes
  holes_maxlen = holes.max_by(&:length).length
  shorts_maxlen = holes.map {|hole| $hole2scale_shorts[hole]}.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole, $hole2scale_shorts[hole].ljust(shorts_maxlen)]
  end
end


def intervalify holes
  holes_maxlen = holes.max_by(&:length).length
  inters = []
  holes.each_with_index do |hole,idx|
    j = idx - 1
    j = 0 if j < 0
    j -= 1 while j > 0 && musical_event?(holes[j])
    isemi ,_ ,itext, _ = describe_inter(hole, holes[j])
    idesc = itext || isemi || ''
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
  holes_maxlen = holes.max_by(&:length).length
  notes_maxlen = holes.map do |hole|
    if musical_event?(hole)
      ''
    else
      $harp[hole][:note]
    end
  end.max_by(&:length).length
  holes.each.map do |hole|
    [' ' * (holes_maxlen - hole.length), hole,
     if musical_event?(hole)
       ''
     else
       $harp[hole][:note]
     end.ljust(notes_maxlen)]
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


def read_tags_and_refresh_licks curr_lick
  all_tags = if curr_lick[:tags].length > 0
               [';OF-CURR-LICK->', curr_lick[:tags], ';ALL-BUT->']
             else
               []
             end
  all_tags << $all_licks.map {|l| l[:tags]}.flatten.uniq.sort
  input = choose_interactive('Choose new tag for --tags_any (aka -t): ', all_tags.flatten)
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
  puts "\e[0m\e[2m Examples would be: 1/3@b 1/4@x 1/2@e 1@b 1@e 2@x 0"
  puts " Current value is '#{$opts[:partial]}'"
  puts
  print "\e[0mYour input: "
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
    report_error_wait_key e
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


class PlayController < Struct.new(:all_wanted, :all_wanted_before, :lick, :lick_idx, :lick_idx_before, :octave_shift, :octave_shift_was)

  def initialize
    self[:octave_shift] = 0
  end

  
  def read_name_change_lick
    input = matching = jtext = nil
    $ctl_mic[:named_lick] = false

    old_licks = get_last_lick_idxs_from_journal($licks, true).map {|lick_idx| $licks[lick_idx][:name]}
    choices = if old_licks.length > 0
                [';RECENT->', old_licks[0 .. 3], ';ALL-BUT->']
              else
                []
              end
    choices << $licks.map {|li| li[:name]}.sort
    input = choose_interactive('Please choose lick: ', choices.flatten) do |name|
      lick = $licks.find {|l| l[:name] == name}
      if lick
        "[#{lick[:tags].join(',')}] #{lick[:desc]}"
      else
        "no description"
      end
    end
    return nil unless input
    
    new_idx = $licks.map.with_index.find {|lick, idx| lick[:name] == input}[1]
    if self[:lick_idx] != new_idx
      self[:lick_idx_before] = self[:lick_idx] 
      self[:lick_idx] = new_idx
      self[:lick] = $licks[new_idx]
      self[:all_wanted] = self[:lick][:holes]
      jtext = sprintf('Lick %s: ', self[:lick][:name]) + self[:all_wanted].join(' ')
    end
    
    jtext
  end


  def back_one_lick
    if self[:lick]
      if !self[:lick_idx_before] || self[:lick_idx_before] == self[:lick_idx]
        print "\e[G\e[0m\e[32mNo previous lick; replay\e[K"
        sleep 1
      else
        self[:lick_idx] = self[:lick_idx_before]
        self[:lick] = $licks[self[:lick_idx]]
        self[:all_wanted] = self[:lick][:holes]
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
    editor = ENV['EDITOR'] || ['editor'].find {|e| system("which #{e} >/dev/null 2>&1")} || 'vi'
    print "\e[#{$lines[:hint_or_message]}H\e[0m\e[32mEditing \e[0m\e[2m#{$lick_file} with: \e[0m#{editor}\e[k"
    sleep $editing_message_seen  ?  0.5  :  1
    print "\e[#{$lines[:message2]}H\e[K"
    make_term_cooked
    system("#{editor} +#{self[:lick][:lno]} #{$lick_file}")
    # note: we cannot make_term_immediate in this line without spoiling $?
    if $? == 0
      make_term_immediate
      print "\e[#{$lines[:message2]}H\e[0m\e[32mEditing done.\e[K"
      if self[:lick_idx] && refresh_licks
        self[:lick] = $licks[self[:lick_idx]]
        self[:all_wanted] = self[:lick][:holes]
        ctl_response 'Refreshed licks'
      end
      sleep $editing_message_seen  ?  0.5  :  1
    else
      make_term_immediate
      puts "\e[0;101mEDITING FAILED !\e[0m\e[k"
      puts "Press any key to continue ...\e[K"
      $ctl_kb_queue.clear
      $ctl_kb_queue.deq
    end
    
    $ctl_mic[:redraw] = Set[:silent, :clear]
    $ctl_mic[:edit_lick_file] = false
    $editing_message_seen = true
  end


  def change_tags
    start_new_iteration = read_tags_and_refresh_licks(self[:lick])
    if start_new_iteration
      if $opts[:iteration] == :cycle
        self[:lick_idx_before] = self[:lick_idx] = 0
      else
        self[:lick_idx_before] = self[:lick_idx] = rand($licks.length)
      end
      self[:lick] = $licks[self[:lick_idx]]
      self[:all_wanted] = self[:lick][:holes]
    end
    $ctl_mic[:change_tags] = false
    print "\e[#{$lines[:key]}H\e[k" + text_for_key
  end


  def change_octave
    all_wanted_was = self[:all_wanted]
    self[:all_wanted] = self[:lick][:holes].map do |hole|
      if musical_event?(hole) || self[:octave_shift] == 0
        hole
      else
        $semi2hole[$harp[hole][:semi] + 12 * self[:octave_shift]] || '(*)'
      end
    end
    if self[:all_wanted].reject {|h| musical_event?(h)}.length == 0
      print "\e[#{$lines[:hint_or_message]}H\e[0;101mShifting lick by (one more) octave does not produce any playable notes.\e[0m\e[K"
      print "\e[#{$lines[:message2]}HPress any key to continue ... "
      $ctl_kb_queue.clear
      $ctl_kb_queue.deq
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[#{$lines[:message2]}H\e[K"
      self[:all_wanted] = all_wanted_was
      self[:octave_shift] = self[:octave_shift_was]
      sleep 2
    else
      print "\e[#{$lines[:hint_or_message]}H\e[2mOctave shift \e[0m#{self[:octave_shift]}\e[K"
      $message_shown_at = Time.now.to_f
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
      err "Unknown lick: '#{start_with}' (after applying options '--tags' and '--no-tags' and '--max-holes')"
    else
      err "Multiple licks start with '#{start_with}': #{mnames}"
    end
  end
end
