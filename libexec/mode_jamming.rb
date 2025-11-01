#
#  Support for jamming with harpwise
#

def do_jamming to_handle
  
  $to_pause = "\e[0mPress   \e[92mSPACE\e\[0m    \e[2mhere or in 'harpwise listen'\e[0m   to %s,\npress   \e[92mctrl-z\e[0m   \e[2mhere\e[0m   to start over.\e[0m"
  
  if ENV['HARPWISE_RESTARTED']
    do_animation 'jamming', $term_height - $lines[:comment_tall] - 1
    puts "\e[0m\e[2mStarting over due to signal \e[0m\e[32mctrl-z\e[0m\e[2m (quit, tstp).\e[0m"
  end

  if to_handle.length == 0 && !%w(list ls).include?($extra)
    do_jamming_list
    err "'harpwise jamming #{$extra}' needs an argument but none is given; please select a single file from those given above. Do this by giving one or multiple words (sequences of chars), so that only the wanted filename contains them all. Mostly that means, that you only need to type a characteristic word from the filename; e.g. 'baz' to match 'foo-bar-baz' and distinguish it from 'foo-bar-qux'."
  end

  [:print_only, :over_again].each do |opt|
    puts "\e[0m\e[2m\nPlease note, that option   --#{opt.o2str}   has no effect for   'harpwise jam #{$extra}'   ; it is only useful for 'harpwise jam along'   ; accepting it nonetheless for command-line-convernience ...\e[0m" if $opts[opt] && $extra != 'along'
  end

  unless %w(list ls).include?($extra)
    err "'harpwise jamming #{$extra}' needs at least one additional argument but none is given" if to_handle.length == 0
  end
  
  case $extra
  when 'along'
    
    json_file = match_jamming_file(to_handle)
    
    do_the_jamming json_file
    
  when 'list', 'ls'

    if to_handle.length > 0
      $all_licks, $licks, $all_lick_progs = read_licks    
    end
    
    if to_handle.length == 0
      do_jamming_list
    elsif to_handle == ['all']
      files = $jamming_dirs_content.values.flatten
      puts "\n\nShowing details for all   \e[32m#{files.length}\e[0m   known jamming files:"
      puts
      files.each do |file|
        puts "\e[2m" + ('~' * 60 ) + "\e[0m\n\n"
        do_jamming_list_single file, multi: true
      end
    else
      json_file = match_jamming_file(to_handle)
      do_jamming_list_single json_file
    end

    
  when 'edit'

    json_file = match_jamming_file(to_handle)
    
    tool_edit_file(json_file)
    
  when 'play'

    file = if to_handle.length == 1 && to_handle[0].end_with?('.mp3')
             to_handle[0]
           else
             match_jamming_file(to_handle)
           end

    do_the_jam_playing(file)

  when 'notes', 'note'

    json_file = match_jamming_file(to_handle)
    do_the_jam_edit_notes json_file
    
  else
    
    fail "Internal error: unknown extra '#{$extra}'"
    
  end
    
end


def do_the_jamming json_file

  make_term_immediate if STDOUT.isatty
  $ctl_kb_queue.clear
  jamming_check_and_prepare_sig_handler  

  $jam_pms, actions = parse_and_preprocess_jamming_json(json_file)    

  sleep 0.2
  
  #
  #  Remark: We do slow scrolling with initial output, so that the user
  #  at least know, what has scrolled by
  #
  
  # 
  #  Transform timestamps; see also below for some further changes to list of actions
  #

  # Abbreviations for convenience
  sl_a_iter = $jam_pms['sleep_after_iteration']
  ts_mult = $jam_pms['timestamps_multiply']
  ts_add = $jam_pms['timestamps_add']
  
  #
  #  Preprocess sleep_after_iteration as far as possible already; use timestamps_multiply
  #  only further down below
  #
  sl_a_iter = if sl_a_iter.is_a?(Numeric)
                # turn number into array
                [[sl_a_iter * ts_mult, nil]]
              else
                # Sleep is different for each iteration; for now, check its type only and bring them
                # into a common structure
                err "Parameter 'sleep_after_iteration' can only be a number or an array, however its type is '#{sl_a_iter.class}' and its value: #{sl_a_iter}" unless sl_a_iter.is_a?(Array)
                sl_a_iter.map do |sai|
                  case sai
                  in Numeric
                    [sai * ts_mult, nil]
                  in Numeric, String
                    err "If an element of 'sleep_after_iteration' has text, the duration needs to be >= 2 (to allow message to show); however this does not hold true for this element: #{sai}"  if sai[0] < 2
                    [sai[0] * ts_mult, sai[1]]
                  else
                    err "Parameter 'sleep_after_iteration' should be an array (which is the case). Each element of this array can either be a  PLAIN NUMBER  or an  ARRAY  with a number and a string; however (and thats the problem) element #{idx} in #{sl_a_iter} is none of these but rather: #{sai}"
                  end
                end
              end

  # Process other time-parameters
  ts_prev = nil
  actions.each_with_index do |ta, idx|
    ta[0] += ts_add if ts_add > 0
    ta[0] *= ts_mult
    err "Timstamp of action #{idx}: #{ta} is earlier than its predecessor (action #{idx-1}: #{actions[idx-1]})" if ts_prev && ta[0] < ts_prev
    ts_prev = ta[0]
  end

  #
  #  Make contact with user and 'harpwise listen'
  #
      
  ['',"\e[0mDescription:\e[32m",'',
   [$jam_pms['description']].flatten.map do |cl|
     wr = wrap_text(cl, term_width: -4, cont: '')
     if wr.length == 0
       ['    ']
     else 
       wr.map {|l| '    ' + l}
     end
   end,
   "\e[0m", ''].flatten.each {|l| puts l; sleep 0.02}

  if $opts[:paused] && !$opts[:print_only]
    ["\e[0mPaused due to option --paused; not yet waiting for 'harpwise listen'.", '', '',
     $to_pause % 'CONTINUE', ''].each {|l| puts l; sleep 0.02}
    jamming_sleep_wait_for_go
    puts
    puts
    # mabye user has stopped 'harpwise listen' while we were paused; so check state again
    mostly_avoid_double_invocations
  end
  
  #
  #  Wait for listener
  #
  if $opts[:print_only]
    puts "Will not search for 'harpwise listen' and will not sleep due to given option --print-only"
  else
    if $runningp_listen_fifo
      puts "Found 'harpwise listen' running."
    else
      ["Cannot find a running instance of 'harpwise listen' with option --jamming.",
       "",
       "For jamming you need to start it in a   \e[32msecond terminal:\e[0m",
       "\n",
       "    \e[32m#{$example % $jam_data}\e[0m",
       "\nuntil then this instance of  'harpwise jamming'  will check repeatedly and",
       "start with the backing track as soon as  'harpwise listen'  is running.",
       "",
       "This way you can stay with  'listen'  and need not come back here.",
       ""].each {|l| puts l; sleep 0.01}
      print "\e[32m"
      "Waiting ".each_char {|c| print c; sleep 0.04}
      2.times {puts; sleep 0.08}
      print "\e[2AWaiting "
      begin
        pid_listen_fifo = ( File.exist?($pidfile_listen_fifo) && File.read($pidfile_listen_fifo).to_i )
        print '.'
        print "\nStill waiting for 'harpwise listen' " if my_sleep(1)
        break if ENV['HARPWISE_TESTING'] == 'remote'
      end until pid_listen_fifo

      puts ' found it !'
      print "\e[0m"
      sleep 0.5
    end

    # Remember last-used time only late, if we already did at least some real jamming
    base = File.basename(json_file)
    (($pers_data['jamming_last_used_days'] ||= Hash.new)[base] ||= Array.new).then do |jluds|
      day = DateTime.now.mjd
      jluds << day unless jluds[-1] == day
      # remove old entries
      while day - jluds[0] > $jamming_last_used_days_max
        jluds.shift
      end 
    end

    puts

  end

  # Do not remove $remote_jamming_ps_rs initially, because we may want to start paused
  
  puts

  # switch key of harpwise listen to be in sync with jamming
  jamming_do_action ['key', $key]
  jamming_do_action ['mission',"Jam: intro" % $jam_data]

  jamming_do_action ['message',
                     "Jam: initial sleep for %.1d secs; length of track is #{$jam_pms['sound_file_length']}, switched key to #{$key}" % $jam_pms['sleep_initially'],
                     [0.0, $jam_pms['sleep_initially'] - 0.2].max.round(1)]
                   
  puts "Initial sleep %.2f sec" % $jam_pms['sleep_initially']    
  my_sleep $jam_pms['sleep_initially']


  # start playing
  puts
  init_silence = if ts_add < 0
                   ts_add.abs * ts_mult
                 else
                   0
                 end
  puts("Inserting %.2f secs of silence at beginning of sound_file\nto handle negative value of parameter 'timestamps_add'.\n\n" % init_silence) if init_silence > 0

  play_command, text = jam_get_play_command(init_silence: init_silence)
  puts "Starting:\n\n    #{play_command}\n\n"
  puts "#{text}\n\n" if text
  $pplayer = PausablePlayer.new(play_command)
  play_started = Time.now.to_f
  sum_sleeps = 0
  puts

  # sleep up to timestamp of first action
  sleep_secs = actions[0][0]
  puts "Sleep before first action %.2f sec; total length is #{$jam_pms['sound_file_length']}" % sleep_secs
  $jam_data[:num_action_offset] = 0
  my_sleep sleep_secs
  sum_sleeps += sleep_secs

  puts
  puts "\n\e[32mYou may now go over to 'harpwise listen' ...\e[0m"
  puts

  
  #
  # Endless loop: one iteration after the other
  #
  (1 .. ).each do |iter|
    
    puts
    puts $to_pause % 'pause'
    puts

    # Actions (= this_actions) and timestamps for each iteration can be different due to two
    # reasons: First, because we have actions before loop, which are removed (further down)
    # after first iteration.  Second, because 'sleep_after_iteration' can be an array with
    # different values for each iteration.  Therefore we cannot do our calculations
    # once-and-for-all (and on actions) initially.
    
    # We need to clone deep, because we may do some deep modifications below
    this_actions = Marshal.load(Marshal.dump(actions))

    #
    # Maybe create artificial sleep-actions after last given action
    #
    
    # Initially, we made sure, that sl_a_iter is an array of arrays, but we did not add it yet
    slp = sl_a_iter[0][0]
    if slp < 1
      # not enough time to actually display something (maybe even negative); so add slp
      # into last action
      this_actions[-1][0] += slp
      err "After adding sleep_after_iter #{slp} to last timestamp, they are no longer ascending: #{this_actions[-2 .. -1]}" if this_actions[-1][0] < this_actions[-2][0]
      sl_a_iter_msg = "(sleep_after_iteration #{slp} has been added to last timestamp)"
    else
      # add dedicated message and sleep
      last_ts = this_actions[-1][0]
      this_actions << [last_ts, 'message',
                       sl_a_iter[0][1] || 'Sleep after iteration',
                       0]
      this_actions << [last_ts + slp, 'message', 'Done', 0]
      sl_a_iter_msg = "(new action for sleep_after_iteration #{slp} has been added above)"
    end
    sl_a_iter.shift unless sl_a_iter.length == 1

    $jam_data[:num_timer] = 0
    
    #
    # Loop: each action
    #
    this_actions.each_with_index do |action, idx|

      #
      # In first iteration, for user-visible output, we need to distinguish between actions
      # before and after start-loop; later however all the actions before start-loop will be
      # removed.
      #
      if idx == 0 && iter == 1
        puts
        puts_underlined "BEFORE FIRST ITERATION"
        this_actions[0 .. $jam_loop_start_idx - 1].each {|a| pp a}
        puts
      end

      if action[1] == 'loop-start'
        # In second and any further iteration $jam_loop_start_idx will be 0
        $jam_data[:num_action_offset] = $jam_loop_start_idx
        $jam_data[:iteration] = iter
        $jam_data[:loop_starter] = $jam_loop_starter_template % $jam_data
        puts
        puts_underlined "ITERATION #{iter}"
        this_actions[idx .. -1].each {|a| pp a}
        jamming_do_action ['mission',"Jam: iter %{iteration}/%{iteration_max}" % $jam_data]
        puts
        puts sl_a_iter_msg
        puts
      end

      $jam_data[:num_action] = idx + 1 - $jam_data[:num_action_offset]
      $jam_data[:num_action_max] = this_actions.length - $jam_loop_start_idx

      head = ( idx == this_actions.length - 1  ?  'Final action'  :  'Action' )
      puts "#{head}   #{$jam_data[:num_action]}/#{$jam_data[:num_action_max]}   (%.2f sec since start); Iteration #{$jam_data[:iteration]} (each #{$jam_data[:iteration_duration]})" % action[0]

      $jam_pretended_actions_ts << jamming_make_pretended_action_data(action[1 .. -1]) if $opts[:print_only]
      puts "Backing-track: total: #{$jam_pms['sound_file_length']}, elapsed #{$jam_data[:elapsed]}, remaining #{$jam_data[:remaining]}"

      #
      # Handle timer
      #
      if action[1] == 'timer'
        if idx > $jam_loop_start_idx
          $jam_data[:num_timer] += 1
          jamming_do_action ['mission',"Jm: it %{iteration}/%{iteration_max}, tm %{num_timer}/%{num_timer_max}" % $jam_data]
        end
          
        if action.length == 2
          # No duration given, so search for next timer and calculate duration
          next_timer_idx = nil
          secs_to_next_timer = -action[0]
          # Search from first action; if nothing found search again from loop start.  We can
          # mostly be sure to find at least the current timer.
          next_timer_idx = nil
          [idx + 1, $jam_loop_start_idx].each do |start_search|
            next_timer_idx = (start_search ... this_actions.length).
                               find {|ix| this_actions[ix][1] == 'timer'}
            if next_timer_idx
              # Found next timer
              secs_to_next_timer += this_actions[next_timer_idx][0]
              break
            else
              # Our search wraps around; add duration of whole loop. We do not need to care
              # for sleep_after_iteration, because this has already been worked into actions
              # above.
              secs_to_next_timer += $jam_data[:iteration_duration_secs]
            end
          end
          if !next_timer_idx
            # This happens, if there is only one timer and placed before loop start
            secs_to_next_timer = this_actions[$jam_loop_start_idx][0] - action[0]
          end
          action.append('up-to-next-timer', secs_to_next_timer.round(1))
        end
      end

      
      #
      # Actually do the action
      #
      
      jamming_do_action action[1 .. -1]
      
      if idx < this_actions.length - 1
        tntf = Time.now.to_f
        sleep_between = this_actions[idx + 1][0] - action[0]

        # Actions (above) and other parts of the loop may take up some small amount of time
        # too; this adds up and leads to drift between the actual elapsed time and the sum
        # of sleeps; therefore we need to adjust.

        # When playing is paused (which is possible only during sleep), the sleep is
        # extended by the pause-time; however this is not counted in sum_sleeps, so we have
        # to adjust explicitly
        sleep_and_pause = sum_sleeps + $pplayer.sum_pauses

        puts("Sum:   sleep:  \e[0m\e[34m%.2f sec\e[0m,   pause:  \e[0m\e[34m%.2f sec\e[0m" %
             [sum_sleeps, $pplayer.sum_pauses]) if $pplayer.sum_pauses > 0.1
        
        # Would be zero, if all actions were instantanous
        secs_lost =  if $opts[:print_only]
                       0
                     else
                       tntf - play_started - sleep_and_pause
                     end
        
        puts(("Since start:   " +
              "elapsed:  \e[0m\e[34m%.2f sec\e[0m,   " +
              "sleep + pause:  \e[0m\e[34m%.2f sec\e[0m,   " +
              "lost:  \e[0m\e[34m%.2f sec\e[0m") %
             [tntf - play_started, sleep_and_pause, secs_lost])

        sleep_between_adjusted = [sleep_between - secs_lost, 0].max
        
        puts(("Sleep until next:    \e[0m\e[34m%.2f sec\e[0m,      " +
              "adjusted:    \e[0m\e[34m%.2f sec\e[0m") %
             [sleep_between, sleep_between_adjusted])
        
        my_sleep sleep_between_adjusted

        # If beeing paused, my_sleep will actually take exactly that much longer (for a good
        # reason; see there). However we still just add he requested sleep-intervals and
        # count the pauses seperately.  Also: dont used sleep_between_adjusted here, because
        # sum_sleeps is our purely theoretical value, which we compare with reality elsewhere
        sum_sleeps += sleep_between
        puts
      end

    end  ## loop: each action 
    
    # as the actions before actual loop-start (e.g. intro) have been done once and should
    # not be done again, we need to remove them now; we are acting on 'actions' rather then
    # 'this_actions'
    if iter == 1
      while actions[0][1] != 'loop-start'
        actions.shift
        $jam_loop_start_idx -= 1
      end
      err "Internal error: not zero: #{$jam_loop_start_idx}" if $jam_loop_start_idx != 0
      $jam_data[:num_action_offset] = 0
      puts "\nAfter first iteration: removed all actions before loop-start.\n\n"
    end

    if $opts[:print_only] && $jam_pretended_sleep > $jam_pms['sound_file_length_secs']
      puts
      puts
      puts "\e[0m\e[32mPretended sleep (#{jam_ta($jam_pretended_sleep)} secs) has exceeded length of sound file (#{jam_ta($jam_pms['sound_file_length_secs'])}).\nPlay would have ended naturally.\e[0m"
      puts "\n\nCollected #{$jam_pretended_actions_ts.length} timestamps and descriptions:"
      puts
      fname = "#{$jamming_timestamps_dir}/along.txt"
      file = File.open(fname, 'w')
      file.write "#\n# #{$jam_pretended_actions_ts.length.to_s.rjust(6)} timestamps for:   #{$jam_pms['sound_file']}\n#\n#          according to:   #{$jam_json}   (#{$jam_pms['sound_file_length']})\n#\n#          collected at:   #{Time.now.to_s}\n#\n"
      $jam_pretended_actions_ts.each do |ts, desc, act|
        text = "  %6.2f  (#{jam_ta(ts)}):  #{desc}" % ts
        text += ",  #{act}" unless $opts[:brief]
        puts text
        file.puts text
      end
      file.close
      puts
      puts "#{$jam_pretended_actions_ts.length} entries."
      puts
      puts "Find this list in:   #{fname}"
      puts
      
      exit 0
    end
      
  end  ## Endless loop: one iteration after the other
  
end


def jamming_send_keys keys, silent: false
  puts "\e[0m\e[32mSENT KEYS:           #{keys.join(',')}\e[0m" unless silent
  return if $opts[:print_only]
  keys.each do |key|
    begin
      Timeout::timeout(0.5) do
        File.write($remote_fifo, key + "\n") unless ENV['HARPWISE_TESTING']
      end
    rescue Timeout::Error, Errno::EINTR
      err "Could not write '#{key}' to #{$remote_fifo}.\n\nIs 'harpwise listen' still alive?"
    end
  end
end


def jamming_do_action act_wo_ts, noop: false
  if %w(message loop-start mission key timer).include?(act_wo_ts[0])
    if act_wo_ts.length == 3
      if act_wo_ts[0] == 'timer'
        if act_wo_ts[1] != 'up-to-next-timer' || !act_wo_ts[2].is_a?(Numeric)
          err("A 3-element timer needs to start with 'timer', followed by 'up-to-next-timer' and finally a number; but not #{act_wo_ts}")
        end
      elsif !act_wo_ts[1].is_a?(String) || !act_wo_ts[2].is_a?(Numeric) 
        err("A 3-element #{act_wo_ts[0]} needs one string and an (optional) number after '#{act_wo_ts[0]}'; not #{act_wo_ts}")
      end
    end
    if act_wo_ts.length == 2 && !act_wo_ts[1].is_a?(String)
      err "A 2-element #{act_wo_ts[0]} needs one string after '#{act_wo_ts[0]}'; not #{act_wo_ts}"
    end
    if %w(mission key).include?(act_wo_ts[0]) && act_wo_ts.length != 2
      err "An action of type '#{act_wo_ts[0]}' needs exactly one more element; not #{act_wo_ts}"
    end
    if act_wo_ts.length > 1
      if act_wo_ts[1].lines.length > 1
        err "Message to be sent can only be one line, but this has more: #{act_wo_ts[1]}"
      end
      if act_wo_ts[1]['{{']
        err "Message may not contain special string '{{', but this does: #{act_wo_ts[1]}"
      end
    end
    return if noop
    # update jamming data at least at loop start (or more often)
    if $opts[:print_only]
      $jam_data[:elapsed_secs] = $jam_pretended_sleep.round(2)
      $jam_data[:remaining] = jam_ta(($jam_pms['sound_file_length_secs'] - $jam_pretended_sleep).round(2))
    else
      $jam_data[:elapsed_secs] = $pplayer.time_played if $pplayer
      $jam_data[:remaining] = jam_ta($jam_pms['sound_file_length_secs'] - $pplayer.time_played) if $pplayer
    end
    $jam_data[:elapsed] = jam_ta($jam_data[:elapsed_secs])
    $jam_data[:loop_starter] = $jam_loop_starter_template % $jam_data
    content = if act_wo_ts[0] == 'timer'
                dura = if act_wo_ts[1] == 'up-to-next-timer'
                         act_wo_ts[2]
                       elsif act_wo_ts[1].is_a?(number)
                         act_wo_ts[1]
                       else
                         err "Argument to action of type 'timer' must be a number. However, this has been found: '#{expr}'"
                       end
                Time.now.to_f + dura * $jam_pms['timestamps_multiply']
              else
                act_wo_ts[1].chomp % $jam_data
              end
    case act_wo_ts[0]
    when 'mission'
      print "Sent mission:"
    when 'key'
      print "Sent key of harp:"
    when 'timer'
      print "Sent start timer ('#{act_wo_ts[1]}'):"
    else
      print "Sent message:"
    end
    puts "       \e[0m\e[34m'#{content}'\e[0m"
    return if $opts[:print_only]
    if $remote_message_count == 0
      Dir[$remote_message_dir + '/[0-9]*.txt'].each {|fnm| FileUtils.rm(fnm)}
    end
    msg_file = $remote_message_dir + ('/%04d.txt' % $remote_message_count)
    $remote_message_count += 1
    txt, dur = case act_wo_ts[0]
               when 'mission', 'key', 'timer'
                 ["{{#{act_wo_ts[0]}}}#{content}", 1]
               else
                 [content, act_wo_ts[2] || 2 ]
               end
    File.write(msg_file, txt + "\n" + dur.to_s + "\n")
    jamming_send_keys ["ALT-m"], silent: true
  elsif act_wo_ts[0] == 'keys'
    err("Need at least one string (giving the key to be sent) after 'keys'; not #{act_wo_ts}") if act_wo_ts.length == 1
    err("Only strings allowed after 'keys'; not #{act_wo_ts}") unless act_wo_ts[1..-1].all? {|a| a.is_a?(String)}
    return if noop
    jamming_send_keys act_wo_ts[1 .. -1]
  else
    err("Unknown type '#{act_wo_ts[0]}'")
    return if noop
  end
end


def get_jamming_dirs_content
  cont = Hash.new
  rel2abs = Hash.new
  # files directly in any dir of $jamming_path should come first. Otherwise all should be
  # sorted alphabetically
  $jamming_path.each do |jdir|
    cont[jdir] = Dir["#{jdir}/**/*.json"].sort do |a,b|
      # short versions without dir from jpath
      as = a[(jdir.length + 1) .. -1]
      bs = b[(jdir.length + 1) .. -1]
      if as['/'] && bs['/']
        as <=> bs
      elsif as['/']
        +1
      elsif bs['/']
        -1
      else
        as <=> bs
      end
    end
  end
  cont.map do |jdir, files|
    files.each do |file|
      short = file[(jdir.length + 1) .. -6]
      err("Two files map to the same relative name #{short}:\n  #{file}\n  #{rel2abs[short]}\nplease rename one.") if rel2abs[short]
      rel2abs[short] = file
    end
  end
  rel2abs.keys.each {|jm| $name_collisions_mb[jm] << 'jam'}
  return [cont, rel2abs]
end


def do_jamming_list
  #
  # Try to make output pretty but also easy for copy and paste
  #
  puts
  puts "Available jamming-files:\n\e[2m\e[34m# with keys harp,song  \e[32m; day last used + count of more days from last #{$jamming_last_used_days_max}\e[0m"
  tcount = 0
  
  $jamming_path.each do |jdir|

    puts
    puts "\e[0m\e[2mFrom   \e[0m\e[32m#{jdir}\e[0m\e[2m/"
    puts
    count = 0
    # prefixes for coloring
    ppfx = pfx = ''

    # Sort files in toplevel dir first and then all subdirs
    $jamming_dirs_content[jdir].each do |jf|

      # path relative to jdir
      jfs = jf[(jdir.length + 1) .. -1]

      #
      # Print common part of filenames dim, if there is an unchanged directory prefix
      #

      # Compute unchanged prefix, current and previous
      if md = jfs.match(/^(.*?\/)/)
        # file is within subdir of jdir
        pfx = md[1]
        puts if pfx != ppfx
      else
        ppfx = pfx = ''
      end

      # Use prefixes for coloring
      if pfx.length == 0 || pfx != ppfx
        print "\e[0m  " + jfs.gsub('.json','')
        ppfx = pfx
      else
        print "  \e[0m\e[2m" + pfx + "\e[0m" + jfs[pfx.length .. -1]
      end

      #
      # Append keys and time-information
      #
      pms = parse_jamming_json(jf)
      print ' ' * (-jfs.length % 4)
      print "  \e[0m\e[34m    #  #{pms['harp_key']},#{pms['sound_file_key']}"
      ago, more = get_and_age_jamming_last_used_days(jf)
      print("\e[0m\e[32m  ; " + days_ago_in_words(ago)) if ago
      print(" + #{more} more") if more
      puts

      #
      # Add notes (if any)
      #
      notes = $pers_data.dig('jamming_notes',File.basename(jf))
      if !$opts[:brief]
        print "\e[0m\e[2m"
        if notes && notes.length > 0
          notes[1..-1].each {|nl| puts "    #{nl}"}
        end
      end
      
      count += 1
      tcount += 1
      sleep 0.02

    end  ## each jamming file
    puts "\e[0m  none" if count == 0
  end
  puts
  puts "\e[0m\e[2mTotal count: #{tcount}\e[0m"
  puts
  sleep 0.05
end


def do_jamming_list_single file, multi: false

  pms, _ = parse_and_preprocess_jamming_json(file, simple: true)
  
  jam_data = jamming_make_jam_data(pms)  
  notes = $pers_data.dig('jamming_notes',File.basename(file))
  puts unless multi
  print(multi  ?  "  "  :  "Details for:  ")
  puts "\e[32m" + File.basename(file).gsub('.json','')
  puts

  puts "\e[0m       Path:  #{file}"
  
  ago, more = get_and_age_jamming_last_used_days(file)
  print "  Last used:  "
  if ago
    print(days_ago_in_words(ago))
    print("\e[2m and on \e[0m#{more} more \e[2mdays from last #{$jamming_last_used_days_max}\e[0m") if more
    puts
  else
    puts 'unknown'
  end
  puts "Key of harp:  \e[34m#{pms['harp_key']}\e[0m"
  puts "    of song:  \e[34m#{pms['sound_file_key']}\e[0m"

  puts
  puts " Sound File:  " + (pms['sound_file'] % jam_data)
  puts " Ex. Listen:  #{pms['example_harpwise']}"
  prg = pms['example_harpwise'].match(/--lick-prog\S*\s+(\S+)/)&.to_a&.at(1) ||
        err("Could not find option  --lick-prog  in example-command:  '#{pms['example_harpwise']}'")
  err "Unknown lick progression: '#{prg}'" unless $all_lick_progs[prg]
  print "  Lick Prog:  "
  if prg
    puts prg + "      \e[2m#{$all_lick_progs[prg][:licks].length} licks\e[0m"
  else
    puts 'unknown'
  end
  puts " Num Timers:  #{$jam_data[:num_timer_max].to_s.ljust(2)}        \e[2mPer loop\e[0m"
  puts "   Duration:  #{$jam_data[:iteration_duration]}     \e[0m"
  puts 
  print "\e[0m"
  puts "    Description:\e[2m"
  [pms['description']].flatten.each do |cl|
    puts if cl.strip.length == 0
    wr = wrap_text(cl, term_width: -8, cont: '')
    wr.each {|l| puts '        ' + l}
  end
  puts "\e[0m"
  if notes && notes.length > 0
    puts "      Notes:   (from  #{Time.at(notes[0]).to_datetime.strftime('%Y-%m-%d %H:%M')})\e[2m"
    notes[1..-1].each {|nl| puts "        #{nl}"}
  else
    puts "      Notes:   \e[2mnone"
  end
  puts "\e[0m"
  puts unless multi
end


def get_and_age_jamming_last_used_days jf
  ago = more = nil
  jluds = $pers_data['jamming_last_used_days']&.dig(File.basename(jf))
  if jluds
    day = DateTime.now.mjd
    ago = day - jluds[-1]
    # remove old entries
    while day - jluds[0] > $jamming_last_used_days_max
      jluds.shift
    end 
    if jluds.length > 1
      more = jluds.length - 1
    end
  end
  return [ago, more]
end


def my_sleep secs, fast_w_animation: false, &blk
  start_at = Time.now.to_f
  space_seen = false
  paused = false
  sum_pauses_initially = $pplayer&.sum_pauses || 0.0

  #
  # Sleep but also check for pause-request and chars for actions
  #

  $jam_pretended_sleep += secs
  return(false) if $opts[:print_only]
  
  puts if fast_w_animation
  wheel = $resources[:hl_long_wheel]
  anm_mod = 100
  anm_cnt_prev = 0
  # make sure that first loop will already print animation
  anm_cnt = anm_cnt_prev + anm_mod
  anm_txt = 'Playing ...'
  anm_pending = nil
  
  begin  ## loop untils secs elapsed

    space_seen, pending_printed = check_for_space_etc(blk, print_pending: anm_pending)
    if pending_printed
      anm_pending = nil 
      anm_cnt = anm_cnt_prev + anm_mod
    end
    if space_seen || File.exist?($remote_jamming_ps_rs)
      if anm_pending      
        print anm_pending
        anm_pending = nil
        anm_cnt = anm_cnt_prev + anm_mod
      end
      paused = true
      $ctl_kb_queue.clear
      $pplayer&.pause
      print "\n\e[0m\e[32m\nPaused:\e[0m\e[2m      (because "
      if space_seen
        print "SPACE has been pressed here"
      else
        print "SPACE has been pressed in 'harpwise listen'"
      end
      puts ")\e[0m"
      puts
      puts $to_pause % 'CONTINUE'
      puts
      space_seen = jamming_sleep_wait_for_go
      print "\e[2m(because "
      if space_seen
        print "SPACE has been pressed here"
      else
        print "SPACE has been pressed in 'harpwise listen'"
      end
      puts ")\e[0m"
      puts
      space_seen = false
      $pplayer&.continue
    end
    
    if $pplayer && !$pplayer.alive?
      $pplayer.check
      if anm_pending
        print anm_pending 
        anm_pending = nil
        anm_cnt = anm_cnt_prev + anm_mod
      end

      if $opts[:over_again] && $extra == 'along'
        puts "\nBacking track has ended, but playing it again because of option '--over-again'\n\n"
        jamming_do_action ['message','Backing track has ended; starting over again',1]
        jamming_do_action ['mission','Starting over']
        sleep 1
        jamming_prepare_for_restart
        exec($full_command_line)
      end

      puts "\nBacking track has ended.\n\n"
      if $extra == 'along'
        jamming_do_action ['message','Backing track has ended.',1] 
        jamming_do_action ['mission','Track has ended']
      end
      puts
      
      exit 0
    end

    if fast_w_animation
      sleep 0.01
      if anm_cnt >= anm_cnt_prev + anm_mod
        print "\e[0m\e[#{wheel[( anm_cnt / 100 ) % wheel.length]}m#{anm_txt}\e[0m"
        print "\r"
        anm_pending = "\e[0m\e[2m#{anm_txt}\e[0m\n"
        anm_cnt_prev = anm_cnt
      end
      anm_cnt += 1
    else
      sleep 0.01
    end

    sum_pauses_here = ( $pplayer&.sum_pauses || 0.0 ) - sum_pauses_initially
    # If sleep and therefore play have been paused, we add the amount of pause to our
    # sleep-time
  end while Time.now.to_f - start_at < secs + sum_pauses_here
  print anm_pending if anm_pending

  paused
end


def parse_and_preprocess_jamming_json json, simple: false

  unless simple
    puts
    puts "\e[0mSettings from:   #{json}\e[0m"
    sleep 0.05
  end
  
  #
  # Process json-file with settings
  #
  jam_pms = parse_jamming_json(json)
  $jam_json = json
  actions = jam_pms['timestamps_to_actions']

  # some checks
  err("Value of parameter 'timestamps_to_actions' which is:\n\n#{actions.pretty_inspect}\nshould be an array but is not (see #{$jam_json})") unless actions.is_a?(Array)
  err("Value of parameter 'description' which is:\n\n#{jam_pms['description']}\n\nshould be a string or an array of strings but is not (see #{$jam_json})") unless jam_pms['description'].is_a?(String) || (jam_pms['description'].is_a?(Array) && jam_pms['description'].all? {|e| e.is_a?(String)})
  err("Value of parameter 'example_harpwise' cannot be empty (see #{$jam_json})") if $example == ''
  %w(sound_file_key harp_key).each do |pm|
    key = jam_pms[pm]
    err("Value of parameter '#{pm}' which is '#{key} is none of the available keys: #{$conf[:all_keys]} (see #{$jam_json})") unless $conf[:all_keys].include?(key)  
  end
  err("Value of parameter 'sleep_initially' is negative (#{jam_pms['sleep_initially']}) but should be > 0 (see #{$jam_json}); maybe try negative value of 'timestamp_add' for a similar effect.") if jam_pms['sleep_initially'] < 0
  
  # initialize some vars
  $ts_prog_start = Time.now.to_f
  $example = jam_pms['example_harpwise']
  $jam_loop_starter_template = "Start of iteration %{iteration}/%{iteration_max} (each %{iteration_duration}); elapsed %{elapsed}, remaining %{remaining}"
  $jam_data = jamming_make_jam_data(jam_pms)
  $jam_data[:loop_starter] = $jam_loop_starter_template % $jam_data
  at_exit do
    $pplayer&.kill
  end  

  #
  # preprocess and check list of timestamps
  #

  # preprocess to allow negative timestamps as relative to preceding ones
  while i_neg = (0 .. actions.length - 1).to_a.find {|i| actions[i][0] < 0}
    loc_neg = "negative timestamp at position #{i_neg}, content #{actions[i_neg]}"
    i_pos_after_neg = (i_neg + 1 .. actions.length - 1).to_a.find {|i| actions[i][0] > 0}
    err("#{loc_neg.capitalize} is not followed by positive timestamp") unless i_pos_after_neg
    loc_pos_after_neg = "following positive timestamp at position #{i_pos_after_neg}, content #{actions[i_pos_after_neg]}"
    ts_abs = actions[i_pos_after_neg][0] + actions[i_neg][0]
    err("When adding   #{loc_neg}   to   #{loc_pos_after_neg}   we come up with a negative absolute time: #{ts_abs}") if ts_abs < 0
    actions[i_neg][0] = ts_abs
  end

  # preprocess to allow a timestamp of 0 to be the same as the preceding one
  (1 .. actions.length - 1).to_a.each do |idx|
    actions[idx][0] = actions[idx - 1][0] if actions[idx][0] == 0
  end

  # Check syntax of actions before actually starting
  $jam_loop_start_idx = nil
  actions.each_with_index do |ta, idx|
    err("First word after timestamp must either be 'message', 'keys' or 'loop-start', but here (index #{idx}) it is '#{ta[1]}':  #{ta}") unless %w(message keys loop-start timer).include?(ta[1])
    err("Timestamp #{ta[0]} (index #{idx}, #{ta}) is less than zero") if ta[0] < 0
    # test actions
    jamming_do_action ta[1 ..], noop: true
    if ta[1] == 'loop-start'
      err("Action 'loop-start' already appeared with index #{$jam_loop_start_idx}: #{actions[$jam_loop_start_idx]}, cannot appear again with index #{idx}: #{ta}") if $jam_loop_start_idx
      $jam_loop_start_idx = idx
    elsif ta[1] == 'timer'
      $jam_data[:num_timer_max] += 1 if $jam_loop_start_idx
    end
  end

  err("Need at least one timestamp with action 'loop-start'") unless $jam_loop_start_idx
  $jam_data[:iteration_duration_secs] = actions[-1][0] - actions[$jam_loop_start_idx][0]
  $jam_data[:iteration_duration] = jam_ta($jam_data[:iteration_duration_secs])

  return([jam_pms, actions]) if simple
  
  # check if sound-file is present
  file = jam_pms['sound_file'] = jam_pms['sound_file'] % $jam_data
  err("\nFile given as sound_file does not exist:  #{file}") unless File.exist?(file)
  puts "\e[0mBacking track:   #{file}"
  print "Duration:   --:--  \e[2m(calculating)\e[0m"
  3.times {sleep 0.05; puts}
  jam_pms['sound_file_length_secs'] = sox_query(file, 'Length').to_i
  jam_pms['sound_file_length'] = jam_ta(jam_pms['sound_file_length_secs'])
  $jam_data[:iteration_max] = 1 + (jam_pms['sound_file_length_secs'] / $jam_data[:iteration_duration_secs]).to_i  
  print "\e[3A"
  puts "Duration:   #{jam_pms['sound_file_length']}\e[K"
  puts "%{iteration_max}  iterations (%{iteration_duration} each);   each with  %{num_timer_max}  timers" % $jam_data    
  sleep 0.1

  # change my own key if appropriate
  puts "Keys   song: #{jam_pms['sound_file_key']}   harp: #{jam_pms['harp_key']}"
  sleep 0.02
  puts
  
  if note2semi(jam_pms['harp_key'] + '4') != note2semi($key + '4')
    if $source_of[:key] == 'command-line'
      puts "Got harp key   \e[32m#{$key}\e[0m   from command line;  \e[32mchanging pitch of track accordingly!\e[0m\n\n\e[2mIf you want to play the track unchanged, just omit the key (here: #{$key}) from the\ncommandline.  But for this you will need to have a harmonica in the key of #{jam_pms['harp_key']}.\n"      
    else
      $key = jam_pms['harp_key']
      set_global_vars_late
      set_global_musical_vars
      puts "Switching to harp key   \e[32m#{jam_pms['harp_key']}\e[0m   as given in json file."
    end
  else
    puts "Already at harp key   #{jam_pms['harp_key']}   as given in json file."
  end
  
  [jam_pms, actions]
end


def do_the_jam_playing json_or_mp3

  make_term_immediate
  $ctl_kb_queue.clear
  jamming_check_and_prepare_sig_handler
  
  if json_or_mp3.end_with?('.mp3')
    err "Named mp3-file does not exist:   #{json_or_mp3}" unless File.exist?(json_or_mp3)
    $jam_pms = Hash.new
    $jam_pms['sound_file_length_secs'] = sox_query(json_or_mp3, 'Length').to_i
    $jam_pms['sound_file_length'] = jam_ta($jam_pms['sound_file_length_secs'])
    $jam_pms['sound_file'] = json_or_mp3
    # just assume something for
    $jam_pms['sound_file_key'] = $key
    $jam_pms['harp_key'] = $key 
  else
    $jam_pms, _ = parse_and_preprocess_jamming_json(json_or_mp3)
    sleep 0.2
  end
    
  play_command, text = jam_get_play_command
  puts
  puts "Starting:\n\n    #{play_command}\n\n"
  puts "#{text}\n\n" if text  
  sleep 0.1
  puts"\e[0m\e[32m"
  $jam_help_while_play.each {|l| puts l; sleep 0.02}
  puts "\e[0m"
    
  $pplayer = PausablePlayer.new(play_command)
  $jam_ts_collected = [$jam_pms['sound_file_length_secs']]
  $jam_idxs_events = {skip_fore: [],
                      skip_back: [],
                      jump: []}

  
  fname_tpl = "#{$jamming_timestamps_dir}/play-%s.txt"
  fname = fname_tpl % Time.now.strftime("%F_%T")
  cleanup_done = false

  my_sleep(1000000, fast_w_animation: true) do |char|

    case char

    when 't','RETURN'
      #
      # Generate full output on every invocation, even though only one timetamp has been
      # added
      #
      $jam_ts_collected.insert(-2, $pplayer.time_played + $jam_play_prev_trim)
      unless cleanup_done
        rmcnt = 0
        Dir[fname_tpl % '*'].each do |fn|
          next if Time.now - File.mtime(fn) < 7 * 86400
          FileUtils.rm(fn)
          rmcnt += 1
        end
        puts "\e[0m\n\nPlease note, that the human reaction time and other factors may introduce a constant\n  delay in recorded timestamps.   However, this can later be compensated with a\n  negative value (e.g. -1.0) for parameter 'timestamps_add' in the json-file."
        puts "\e[0m\e[2m\nRemoved #{rmcnt} old timestamp-files." if rmcnt > 0
        cleanup_done = true
      end
      file = File.open(fname, 'w')
      file.write "#\n# #{($jam_ts_collected.length - 1).to_s.rjust(6)} timestamps for:   #{$jam_pms['sound_file']}\n#\n#          collected at:   #{Time.now.to_s}\n#\n"
      # handle collection of timestamps
      puts "\n\n\e[0mNew timestamp recorded, #{$jam_ts_collected.length - 1} in total:"
      puts
      $jam_ts_collected.each_cons(2).each_with_index do |pair,idx|
        x,y = pair
        jam_puts_log("... skipped backward ...",file,"\e[2m") if $jam_idxs_events[:skip_back].include?(idx)
        jam_puts_log("... skipped forward ...",file,"\e[2m") if $jam_idxs_events[:skip_fore].include?(idx)
        jam_puts_log("... jumped ...",file,"\e[2m") if $jam_idxs_events[:jump].include?(idx)
        jam_puts_log("  %s   %%{n}%6.2f%%{c} sec  (%s),   %%{c}diff to next:  %6.2f " %
                     [('# ' + (idx + 1).to_s).rjust(5), x, jam_ta(x), y-x],file,"\e[2m")
      end
      jam_puts_log("End at:   %6.2f sec  (%s)" % [$jam_pms['sound_file_length_secs'],
                                                       $jam_pms['sound_file_length']],file,"\e[2m")

      file.close
      puts
      puts "\e[2mFind this list in:   #{fname}\e[0m"
      puts
      :handled

    when 'LEFT','BACKSPACE'

      trim = $jam_play_prev_trim + $pplayer.time_played - 10
      trim = 0 if trim < 0
      $pplayer.kill
      $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim)[0])
      jamming_play_print_current('Backward 10 secs to', trim)
      $jam_play_prev_trim = trim
      $jam_idxs_events[:skip_back] << $jam_ts_collected.length - 1
      :handled

    when 'RIGHT'

      trim = $jam_play_prev_trim + $pplayer.time_played + 10
      trim = $jam_pms['sound_file_length_sec'] if trim > $jam_pms['sound_file_length_secs']
      $pplayer.kill
      $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim)[0])
      jamming_play_print_current('Forward 10 secs to', trim)
      $jam_play_prev_trim = trim
      $jam_idxs_events[:skip_fore] << $jam_ts_collected.length - 1
      :handled

    when 'TAB'

      $pplayer.pause
      curr = $jam_play_prev_trim + $pplayer.time_played + 10
      puts "\e[0m\nPlease enter an absolute timestamp to jump to; '-' to count from end;\neither a number of   seconds   or   mm:ss\n\nCurrent location is:    %.2f  (#{jam_ta(curr)})" % curr
      puts
      print "Timestamp: "
      make_term_cooked
      inp = gets_with_cursor
      make_term_immediate
      puts
      neg = ( inp[0] == '-' )
      inp[0] = '' if neg
      trim = if md = inp.match(/^(\d+)$/)
               md[1].to_i
             elsif md = inp.match(/^(\d+\.\d+)$/)
               md[1].to_f
             elsif md = inp.match(/^(\.\d+)$/)
               md[1].to_f
             elsif md = inp.match(/^(\d+):(\d+)$/)
               md[1].to_i * 60 + md[2].to_i
             else
               nil
             end
      if trim && neg
        trim = $jam_pms['sound_file_length_secs'] - trim
        puts "Subtracting input (-#{inp}) from length of sound file (#{$jam_pms['sound_file_length']})"
        puts
      end
      if !trim
        puts "Invalid input: '#{inp}'; cannot jump"
        $pplayer.continue
      elsif trim > $jam_pms['sound_file_length_secs']
        puts "Your input is beyond length of sound_file (#{$jam_pms['sound_file_length']}); cannot jump."
        $pplayer.continue
      elsif trim < 0
        puts "Your input is before start of sound_file; cannot jump."
        $pplayer.continue        
      else
        $pplayer.kill
        $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim)[0])
        jamming_play_print_current('Jumped to', trim)
        $jam_play_prev_trim = trim
        $jam_idxs_events[:jump] << $jam_ts_collected.length - 1
      end
      :handled

    when 'q'

      print "\n\e[0m#{$resources[:term_on_quit]}\n\n"
      exit 0

    else

      false

    end ## case char
  end ## block passed to my_sleep
end


def do_the_jam_edit_notes file

  short = File.basename(file)
  
  tfile = Tempfile.new('harpwise')
  old = $pers_data.dig('jamming_notes',short)
  tfile.write("#\n#   Current notes for   #{short}\n#\n#")
  tfile.write("   last change at  " + Time.at(old[0]).to_datetime.strftime('%Y-%m-%d %H:%M')) if old
  tfile.write("\n#   #{file}\n#\n\n")
  tfile.write([old].flatten[1..-1].map {|l| l + "\n"}.join) if old
  tfile.close
  puts
  system("#{$editor} +7 #{tfile.path}") || err("Editing  #{tfile.path}  failed; see above")

  rlines = File.readlines(tfile.path).map {|l| l.gsub(/#.*/,"").chomp.strip}
  rlines.pop while rlines.length > 0 && rlines[-1].length == 0
  rlines.shift while rlines.length > 0 && rlines[0].length == 0

  puts
  if rlines.length > 0 
    ($pers_data['jamming_notes'] ||= Hash.new)[short] = [Time.now.to_i, rlines].flatten
    puts "Stored  #{rlines.length}  lines of notes for   \e[32m#{short}\e[0m\n\nRead them in   harpwise jam ls"
  else
    $pers_data['jamming_notes']&.delete(short)
    puts "Removed notes for   #{short}"
  end
  maybe_write_pers_data
  puts
  
end


def check_for_space_etc blk, print_pending: nil
  space_seen = pending_printed = false
  if $ctl_kb_queue.length > 0
    if print_pending
      print print_pending
      pending_printed = true
    end
    while $ctl_kb_queue.length > 0
      char = $ctl_kb_queue.deq
      if char == ' '
        space_seen = true
      elsif blk&.(char) == :handled
        # The important things have already happened in the call to blk ...
      else
        puts
        puts "\n\e[0m\e[32mInvalid key: '#{char}'\e[0m\n\n" unless %w(h ?).include?(char)
        print "\e[0m"
        print "\e[2m" if blk
        puts $jam_help_while_play[0]
        puts ($jam_help_while_play[1 .. -1].join("\n") + "\n") if blk
        puts "All other keys ignored.\e[0m"
        puts
        print "\e[0mPaused \e[0m" unless blk
      end
    end
  end
  [space_seen, pending_printed]
end
  

def jamming_check_and_prepare_sig_handler
  
  %w(TSTP QUIT).each do |sig|
    Signal.trap(sig) do
      # do some actions of at_exit-handler here
      jamming_prepare_for_restart
      ENV['HARPWISE_RESTARTED_PROMPT'] = 'yes'      
      exec($full_command_line)
    end
  end
  
  if ENV['HARPWISE_RESTARTED_PROMPT']
    puts "\n\n\e[0mPaused after signal ctrl-z."
    puts
    puts $to_pause % 'CONTINUE'
    puts
    jamming_sleep_wait_for_go
    puts
    puts
  end
end


def jamming_sleep_wait_for_go
  print "\e[32mPaused ."
  space_seen = false
  FileUtils.rm($remote_jamming_ps_rs) if File.exist?($remote_jamming_ps_rs)
  
  space_seen = false
  count = 0
  loop do
    sleep 0.1
    paused = true
    print "." if count % 10 == 0
    count += 1
    if File.exist?($remote_jamming_ps_rs)
      FileUtils.rm($remote_jamming_ps_rs)
      break
    end
    space_seen, _ = check_for_space_etc(nil)
    break if space_seen
  end
  print " \e[0m\e[32mgo!\e[0m    "
  
  space_seen
end


def jam_get_play_command trim: 0, init_silence: 0
  err "Internal error: both parameters trim and init_silence are given" if trim > 0 && init_silence > 0
  
  dsemi = diff_semitones($key, $jam_pms['harp_key'], strategy: :minimum_distance)
  sf_key = $jam_pms['sound_file_key']
  sf_key_new = semi2note(note2semi( sf_key + '4') + dsemi)[0..-2]
  pitch_clause, text = if dsemi == 0
                         ['', nil]
                       else
                         [" pitch #{dsemi * 100}",
                          "shifted from #{sf_key} to #{sf_key_new} by   #{dsemi}   semitones" +
                          (dsemi.abs >= 3  ?  ",   \e[32mwhich is a lot!\e[0m"  :  '')]
                       end

  cmd = if ENV["HARPWISE_TESTING"] || $opts[:print_only]
          "sleep #{$jam_pms['sound_file_length_secs']}"
        else
          "play -q #{$jam_pms['sound_file']}" +
            if init_silence == 0
              ''
            else
              " pad %.2f 0" % init_silence
            end +
            if trim == 0
              ''
            else
              " trim #{trim}"
            end +
            pitch_clause
        end

  [cmd, text]
end


def jam_ta secs
  Time.at(secs.round(0)).utc.strftime("%M:%S")
end


def jam_puts_log text, file, col = "\e[0m"
  puts col + ( text % {'n': "\e[0m", 'c': col})
  file&.puts text % {'n': '', 'c': ''}
end


def match_jamming_file words
  candidates = []
  short2full = Hash.new
  $jamming_dirs_content.each do |dir,files|
    files.each do |file|
      short = file[dir.length + 1 .. -1]
      short2full[short] = file
      does = true
      offset = 0
      words.each do |word|
        idx = short[offset .. -1].index(word)
        if idx
          offset += idx
        else
          does = false
        end
      end
      candidates << short if does
    end
  end
  case candidates.length
  when 0
    do_jamming_list
    err "None of the available jamming-files (see above) is matched by your input:   #{words.join(' ')}\n\nPlease check against the complete list of files above and change or shorten your input."
  when 1
    return short2full[candidates[0]]
  else
    err "Multiple files:\n\n" + candidates.map {|c| '  ' + c + "\n"}.join + "\nare matched by your input, which is:   #{words.join(' ')}\n\nPlease extend you input (longer or more strings) to make in uniq."   
  end
end


def jamming_prepare_for_restart
  sane_term
  $pplayer&.kill
  puts
  puts
  puts "\e[0m\e[34m ... jamming start over ... \e[0m\e[K"
  sleep 0.2
  if $pers_file && $pers_data.keys.length > 0 && $pers_fingerprint != $pers_data.hash
    File.write($pers_file, JSON.pretty_generate($pers_data) + "\n")
  end
  ENV['HARPWISE_RESTARTED'] = 'true'
  ENV.delete('HARPWISE_RESTARTED_PROMPT')
end


def jamming_play_print_current txt, ts
  rmng = $jam_pms['sound_file_length_secs'] - ts
  puts(("\e[0m#{txt}:  %8.2f  (" + jam_ta(ts) + ")") % ts)
  puts(("\e[0m\e[2m" + 'remaining'.rjust(txt.length) +
        ":  %8.2f  (" + jam_ta(rmng) + ")\e[0m") % rmng)
  puts
end


def jamming_make_pretended_action_data act_wo_ts
  [$jam_pretended_sleep,
   "iteration #{$jam_data[:iteration]}, action #{$jam_data[:num_action]}/#{$jam_data[:num_action_max]}",
   act_wo_ts.map {|x| x.is_a?(String)  ?  x % $jam_data  :  x}]
end


def parse_jamming_json jam_json
  jam_pms = JSON.parse(File.read(jam_json).lines.reject {|l| l.match?(/^\s*\/\//)}.join)
  # check if all parameters present
  wanted = Set.new(%w(timestamps_to_actions sleep_initially sleep_after_iteration sound_file sound_file_key harp_key timestamps_multiply timestamps_add description example_harpwise))
  given = Set.new(jam_pms.keys)
  err("Found keys:\n\n  #{given.to_a.sort.join("\n  ")}\n\n, but wanted:\n\n  #{wanted.to_a.sort.join("\n  ")}\n\nin #{jam_json}\n" +
      if (given - wanted).length > 0
        "\nthese parameters given are unknown:  #{(given - wanted).to_a.join(', ')}"
      else
        ''
      end +
      if (wanted - given).length > 0
        "\nthese parameters are missing:  #{(wanted - given).to_a.join(', ')}"
      else
        ''
      end + "\n") if given != wanted

  jam_pms
end


def jamming_make_jam_data jam_pms
  {description: jam_pms['description'],
   install_dir: File.read("#{$dirs[:data]}/path_to_install_dir").chomp,
   elapsed: '??:??',
   elapsed_secs: 0,
   remaining: '??:??',
   iteration: 0,
   iteration_max: 0,
   iteration_duration: '??:??',
   num_action: 0,
   num_action_max: 0,
   num_timer: 0,
   num_timer_max: 0,
   key: '?'}
end
