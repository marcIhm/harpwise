#
#  Support for jamming with harpwise
#

def do_jamming to_handle

  $jamming_dirs_content = get_jamming_dirs_content
  
  $to_pause = "\e[0mPress   \e[92mSPACE or 'j'\e\[0m   here or  \e[92m'j'\e[0m  in harpwise listen to %s,\n\e[92mctrl-z\e[0m   here to start over.\e[0m"
  $jam_help_while_play = ["Press:   SPACE,j   to pause / continue",
                          "        RETURN,t   to mark a timestamp",
                          "  BACKSPACE,LEFT   to skip back 10 secs",
                          "           RIGHT      skip forward 10",
                          "             TAB   to jump to a timestamp",
                          "               q   to quit"]
  $jam_play_prev_trim = 0
  $jam_pretended_sleep = 0
  $jam_pretended_actions_ts = []
  
  if ENV['HARPWISE_RESTARTED']
    do_animation 'jamming', $term_height - $lines[:comment_tall] - 1
    puts "\e[0m\e[2mStarting over due to signal \e[0m\e[32mctrl-z\e[0m\e[2m (quit, tstp).\e[0m"
  end
  
  if to_handle.length == 0 && !%w(list ls).include?($extra)
    do_jamming_list
    err "'harpwise jamming #{$extra}' needs an argument but none is given; please choose a filename, even partially, as given above"
  end

  [:print_only, :over_again].each do |opt|
    puts "\e[0m\e[2m\nPlease note, that option   --#{opt.o2str}   has no effect for   'harpwise jam #{$extra}'   ; it is only useful for 'harpwise jam along'   ; accepting it nonetheless for commandline-convernience ...\e[0m" if $opts[opt] && $extra != 'along'
  end

  unless %w(list ls).include?($extra)
    err "'harpwise jamming #{$extra}' needs at least one additional argument but none is given" if to_handle.length == 0
  end
  
  case $extra
  when 'along'
    
    json_file = match_jamming_file(to_handle)
    
    do_the_jamming(json_file)
    
  when 'list', 'ls'
    
    err_args_not_allowed(to_handle) if to_handle.length > 0
    
    do_jamming_list
    
  when 'edit'

    json_file = match_jamming_file(to_handle)
    
    tool_edit_file(json_file)
    
  when 'play'

    file = if to_handle.length == 1 && to_handle[0].end_with?('.mp3')
             to_handle[0]
           else
             match_jamming_file(to_handle)
           end

    do_the_playing(file)
    
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
  # Remark: We do slow scrolling with initial output, so that the user
  # at least know, what has scrolled by
  #
  
  # 
  # Transform timestamps; see also below for some further changes to list of actions
  #
  ["Transforming timestamps:\e[0m\e[2m",
   "- timestamps_add = #{$jam_pms['timestamps_add']}",
   "  - if positive, add it to each timestamp",
   "  - if negative, delay track accordingly",
   "- sleep_after_iteration = #{$jam_pms['sleep_after_iteration']}",
   "  - if negative, subtract it from last timestamp only",
   "  - if positive, add a new matching sleep-action",
   "  - if an array (numbers only or pairs [number, text]), use each element",
   "    one after the other for one iteration as described above;",
   "    issue text (e.g. 'solo'), if given",
   "- timestamps_multiply = #{$jam_pms['timestamps_multiply']}: multiply each timestamp with this\e[0m",
   ""].each {|l| puts l; sleep 0.02}

  #
  # Preprocess sleep_after_iteration as far as possible already
  #
  sl_a_iter = $jam_pms['sleep_after_iteration']  
  if sl_a_iter.is_a?(Numeric)
    # turn number into sufficiently large array of identical Arrays with one number each
    sl_a_iter = Array.new(1000, [sl_a_iter, nil])
  else
    # Sleep is different for each iteration; for now, check its type only and bring them
    # into a common structure
    err "Parameter 'sleep_after_iteration' can only be a number or an array, however its type is '#{sl_a_iter.class}' and its value: #{sl_a_iter}" unless sl_a_iter.is_a?(Array)
    sl_a_iter.map! do |sai|
      case sai
      in Numeric
        [sai, nil]
      in Numeric, String
        err "If an element of 'sleep_after_iteration' has text, the duration needs to be >= 2 (to allow message to show); however this does not hold true for this element: #{sai}"  if sai[0] < 2
        sai
      else
        err "Parameter 'sleep_after_iteration' should be an array (which is the case). Each element of this array can either be a  PLAIN NUMBER  or an  ARRAY  with a number and a string; however (and thats the problem) element #{idx} in #{sl_a_iter} is none of these but rather: #{sai}"
      end
    end
  end

  # process other time-parameters
  actions.each_with_index do |ta,idx|
    # Remark: negative timestamps have already been resolved above in
    # parse_and_preprocess_jamming_json; therefore we do not need to check for
    # negative-values below (negative timestampts_add); because from now own only diffs
    # between timestamps are used.
    ta[0] += $jam_pms['timestamps_add'] if $jam_pms['timestamps_add'] > 0
    ta[0] *= $jam_pms['timestamps_multiply']
  end

  [$to_pause % 'pause', "", ""].each {|l| puts l; sleep 0.02}
    
  ["Comment:\e[32m", "",
   wrap_text($jam_pms['comment'],cont: ''),
   "\e[0m",""].flatten.each {|l| puts l; sleep 0.02}

  if $opts[:paused] && !$opts[:print_only]
    puts "\e[0m\e[32mPaused due to option --paused:\e[0m"
    puts $to_pause % 'CONTINUE'    
    jamming_sleep_wait_for_go
    puts
    puts
  end
  
  #
  # Wait for listener
  #
  if $opts[:print_only]
    puts "Will not search for 'harpwise listen' and will not sleep due to given option --print-only"
  else
    if $runningp_listen_fifo
      puts "Found 'harpwise listen' running."
    else
      ["Cannot find an instance of 'harpwise listen' that reads from fifo.",
       "",
       "Please start it in a second terminal:",
       "\n",
       "    \e[32m#{$example % $jam_data}\e[0m",
       "\nuntil then this instance of 'harpwise jamming' will check repeatedly and",
       "start with the backing track as soon as 'harpwise listen' is running.",
       "This way you can stay with 'listen' and need not come back here.",
       ""].each {|l| puts l}
      print "\e[32m"
      "Waiting ".each_char {|c| print c; sleep 0.02}
      begin
        pid_listen_fifo = ( File.exist?($pidfile_listen_fifo) && File.read($pidfile_listen_fifo).to_i )
        print '.'
        if my_sleep(1)
          print "\nStill waiting for 'harpwise listen' "
          break if ENV['HARPWISE_TESTING']
        end
      end until pid_listen_fifo
      puts ' found it !'
      print "\e[0m"
      sleep 1
    end
  end
  #
  # Do not remove $remote_jamming_ps_rs initially, because we may want to start paused
  #
  puts

  jamming_do_action ['message',
                     "sleep initially for %.1d secs; length of track is #{$jam_pms['sound_file_length']}" % $jam_pms['sleep_initially'],
                     [0.0, $jam_pms['sleep_initially'] - 0.2].max.round(1)]
                   
  my_sleep $jam_pms['sleep_initially']
  puts "Initial sleep %.2f sec" % $jam_pms['sleep_initially']    

  # start playing
  puts
  initial_silence = if $jam_pms['timestamps_add'] < 0
                      $jam_pms['timestamps_add'].abs * $jam_pms['timestamps_multiply']
                    else
                      0
                    end
  puts("Inserting %.2f secs of silence at beginning of sound_file\nto handle negative value of parameter 'timestamps_add'.\n\n" % initial_silence) if initial_silence >= 0
  play_command = jam_get_play_command(initial_silence: initial_silence)
  puts "Starting:\n\n    #{play_command}\n\n"
  $pplayer = PausablePlayer.new(play_command)
  puts

  # sleep up to timestamp of first action
  sleep_secs = actions[0][0]
  puts "Sleep before first action %.2f sec; total length is #{$jam_pms['sound_file_length']}" % sleep_secs
  my_sleep sleep_secs
  disp_idx_offset = 0
  disp_idx_max = $jam_loop_start_idx

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

    # Actions for each iteration can be different due to 'sleep_after_iteration'; need to
    # clone deep because we may do some deep modifications below
    this_actions = Marshal.load(Marshal.dump(actions))
    sl_a_iter << 0 if sl_a_iter.length == 0

    #
    # Maybe create artificial sleep-actions after last given action
    #
    
    # initially, we made sure, that sl_a_iter is an array of arrays
    slp = sl_a_iter[0][0] * $jam_pms['timestamps_multiply']
    if slp <= 0.5
      # not enough time to actually display something
      this_actions[-1][0] += slp
    else
      this_actions << [this_actions[-1][0], 'message',
                       sl_a_iter[0][1] || 'Sleep after iteration',
                       0]
      this_actions << [this_actions[-1][0] + slp, 'message', 'Done', 0]
    end
    sl_a_iter.shift
    
    #
    # Loop: each pair of actions with sleep between
    #
    this_actions.each_cons(2).each_with_index do |pair,j|

      tsx, tsy = pair[0][0], pair[1][0]
      action = pair[0][1 .. -1]

      #
      # In first iteration, for user-visible output, we need to distinguish between actions
      # before and after start-loop; later however all the actions before start-loop will be
      # removed.
      #
      if j == 0 && iter == 1
        puts
        puts_underlined "BEFORE FIRST ITERATION"
        this_actions[0 .. $jam_loop_start_idx - 1].each {|a| pp a}
        puts
      end

      if action[0] == 'loop-start'
        # after first iteration $jam_loop_start_idx will be adjusted and is itself 0 
        disp_idx_max = this_actions.length - $jam_loop_start_idx
        disp_idx_offset = $jam_loop_start_idx
        $jam_data[:iteration] = iter
        puts
        puts_underlined "ITERATION #{iter}"
        this_actions[j .. -1].each {|a| pp a}
        puts
      end
        
      puts "Action   #{j + 1 - disp_idx_offset}/#{disp_idx_max}   (%.2f sec since start); Iteration #{$jam_data[:iteration]} (each #{$jam_data[:iteration_duration]})" % tsx
      if $opts[:print_only]
        $jam_pretended_actions_ts << [$jam_pretended_sleep, "iteration #{$jam_data[:iteration]}, action #{j + 1 - disp_idx_offset}/#{disp_idx_max}" % $jam_data, action]
      end
      puts "Backing-track: total: #{$jam_pms['sound_file_length']}, elapsed: #{$jam_data[:elapsed]}, remaining: #{$jam_data[:remaining]}"

      jamming_do_action action

      sleep_between = tsy - tsx
      puts "sleep until next:    \e[0m\e[34m%.2f sec\e[0m" % sleep_between
      my_sleep sleep_between
      puts

    end  ## loop: each pair of actions with sleep between

    # last action has not been included above, as we did only the first action of each pair;
    # so we have to do it now
    puts "Final action #{this_actions.length}/#{this_actions.length} (elapsed #{$jam_data[:elapsed]} secs, iteration #{$jam_data[:iteration]}):"
    if $opts[:print_only]
      $jam_pretended_actions_ts << [$jam_pretended_sleep, "iteration #{$jam_data[:iteration]}, action #{this_actions.length}/#{this_actions.length}" % $jam_data,this_actions[-1][1 .. -1]]
    end
    jamming_do_action this_actions[-1][1 .. -1]
    puts "at ts %.2f sec" % this_actions[-1][0]

    # as the actions before actual loop-start (e.g. intro) have been done once and should
    # not be done again, we have to remove them now; we are acting on 'actions' rather then
    # 'this_actions'
    if iter == 1
      while actions[0][1] != 'loop-start'
        actions.shift
        $jam_loop_start_idx -= 1
      end
      disp_idx_offset = 0
      puts "\nAfter first iteration: removed all actions before loop-start.\n\n"
    end
    if $opts[:print_only] && $jam_pretended_sleep > $jam_pms['sound_file_length_secs']
      puts
      puts
      puts "\e[0m\e[32mPretended sleep (#{jam_ta($jam_pretended_sleep)} secs) has exceeded length of sound file (#{jam_ta($jam_pms['sound_file_length_secs'])}).\nPlay would have ended naturally.\e[0m"
      puts "\n\nCollected #{$jam_pretended_actions_ts.length} timestamps and descriptions:"
      puts
      fname = "#{$jamming_timestamps_dir}/derived-in-jam-along.txt"
      file = File.open(fname, 'w')
      file.write "#\n# #{$jam_pretended_actions_ts.length.to_s.rjust(6)} timestamps for:   #{$jam_pms['sound_file']}\n#\n#          according to:   #{$jam_json}   (#{$jam_pms['sound_file_length']})\n#\n#          collected at:   #{Time.now.to_s}\n#\n"
      $jam_pretended_actions_ts.each do |ts,desc,act|
        text = "  %6.2f  (#{jam_ta(ts)}):  #{desc}" % ts
        text += ",  #{act}" unless $opts[:terse]
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
  puts "sent keys:           \e[0m\e[34m#{keys.join(',')}\e[0m" unless silent
  return if $opts[:print_only]
  keys.each do |key|
    begin
      Timeout::timeout(0.5) do
        File.write($remote_fifo, key + "\n") unless ENV['HARPWISE_TESTING']
      end
    rescue Timeout::Error, Errno::EINTR
      err "Could not write '#{key}' to #{$remote_fifo}.\n\nIs 'harpwise listen' still alive ?"

    end
  end
end


def jamming_do_action action, noop: false
  if action[0] == 'message' || action[0] == 'loop-start'
    if action.length == 3 && ( !action[1].is_a?(String) || !action[2].is_a?(Numeric) )
      err("A 3-element #{action[0]} needs one string and a number after '#{action[0]}'; not #{action}")
    end
    if action.length == 2 && !action[1].is_a?(String)
      err("A 2-element #{action[0]} needs one string after '#{action[0]}'; not #{action}")
    end
    if action[1].lines.length > 1
      err("Message to be sent can only be one line, but this has more: #{action[1]}")
    end
    return if noop
    $jam_data[:elapsed] = jam_ta($pplayer.time_played) if $pplayer
    $jam_data[:remaining] = jam_ta($jam_pms['sound_file_length_secs'] - $pplayer.time_played) if $pplayer
    puts "sent message:       \e[0m\e[34m'#{action[1].chomp % $jam_data}'\e[0m"
    return if $opts[:print_only]
    File.write("#{Dir.home}/.harpwise/remote_message",
               ( action[1].chomp % $jam_data ) + "\n" +
               ( action[2] || 2 ).to_s + "\n")
    jamming_send_keys ["ALT-m"], silent: true
  elsif action[0] == 'keys'
    err("Need at least one string (giving the key to be sent) after 'keys'; not #{action}") if action.length == 1
    err("Only strings allowed after 'keys'; not #{action}") unless action[1..-1].all? {|a| a.is_a?(String)}
    return if noop
    jamming_send_keys action[1 .. -1]
  else
    err("Unknown type '#{action[0]}'")
    return if noop
  end
end


def get_jamming_dirs_content
  cont = Hash.new
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

  cont
end


def do_jamming_list
  #
  # Try to make output pretty but also easy for copy and paste
  #
  puts
  puts "Available jamming-files:\e[2m"
  tcount = 1
  $jamming_path.each do |jdir|
    puts
    puts "\e[2mFrom \e[0m\e[32m#{jdir}\e[0m\e[2m/"
    puts
    count = 0
    # prefixes for coloring
    ppfx = pfx = ''
    # sort files in toplevel dir first and then all subdirs
    $jamming_dirs_content[jdir].each do |jf|
      jfs = jf[(jdir.length + 1) .. -1]
      # dim, if there is a prefix, that did not change
      if md = jfs.match(/^(.*?\/)/)
        pfx = md[1]
        puts if pfx != ppfx
      else
        ppfx = pfx = ''
      end
      if pfx.length == 0 || pfx != ppfx
        puts "\e[0m  " + jfs
        ppfx = pfx
      else
        puts "  \e[0m\e[2m" + pfx + "\e[0m" + jfs[pfx.length .. -1]
      end
      count += 1
      sleep 0.02
      tcount += 1
    end
    puts "\e[0m  none" if count == 0
  end
  puts
  puts "\e[2mTotal count: #{tcount}"
  puts
  sleep 0.05
end


def my_sleep secs, fast_w_animation: false, &blk
  start_at = Time.now.to_f
  space_seen = false
  paused = false

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
      print "\n\e[0m\e[32mPaused:\e[0m\e[2m      (because "
      if space_seen
        print "SPACE or 'j' has been pressed here"
      else
        print "'j' has been pressed in 'harpwise listen'"
      end
      puts ")\e[0m"
      puts $to_pause % 'CONTINUE'
      space_seen = jamming_sleep_wait_for_go
      print "\e[2m(because "
      if space_seen
        print "SPACE or 'j' has been pressed here"
      else
        print "'j' has been pressed in 'harpwise listen'"
      end
      puts ")\e[0m"
      puts
      space_seen = false
      $pplayer&.continue
    end
    
    if $pplayer && !$pplayer.alive?
      if anm_pending
        print anm_pending 
        anm_pending = nil
        anm_cnt = anm_cnt_prev + anm_mod
      end

      if $opts[:over_again] && $extra == 'along'
        # due to prior checks we are sure to have $extra == 'along' 
        puts "\nBacking track has ended, but playing it again because of option '--over-again'\n\n"
        jamming_do_action ['message','Backing track has ended; starting over again',1]
        sleep 1
        jamming_prepare_for_restart
        exec($full_commandline)
      end

      puts "\nBacking track has ended.\n\n"
      jamming_do_action ['message','Backing track has ended.',1] if $extra == 'along'
      
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
      sleep 0.1
    end
    
  end while Time.now.to_f - start_at < secs + ($pplayer  ?  $pplayer.sum_pauses  :  0)
  $pplayer.sum_pauses = 0 if $pplayer
  print anm_pending if anm_pending

  paused
end


def parse_and_preprocess_jamming_json json
  
  $jam_json = json
  
  puts
  puts "\e[2mSettings from:   #{$jam_json}\e[0m"
  sleep 0.05
  
  #
  # Process json-file with settings
  #
  $jam_pms = JSON.parse(File.read($jam_json).lines.reject {|l| l.match?(/^\s*\/\//)}.join)
  actions = $jam_pms['timestamps_to_actions']
  $ts_prog_start = Time.now.to_f
  $example = $jam_pms['example_harpwise']
  $jam_data = {comment: $jam_pms['comment'], iteration: 0, elapsed: '??:??', install_dir: File.read("#{Dir.home}/.harpwise/path_to_install_dir").chomp, remaining: '??:??', iteration_duration: '??:??'}
  
  at_exit do
    $pplayer&.kill
  end  

  # check if all parameters present
  wanted = Set.new(%w(timestamps_to_actions sleep_initially sleep_after_iteration sound_file timestamps_multiply timestamps_add comment example_harpwise))
  given = Set.new($jam_pms.keys)
  err("Found keys:\n\n  #{given.to_a.sort.join("\n  ")}\n\n, but wanted:\n\n  #{wanted.to_a.sort.join("\n  ")}\n\nin #{$jam_json}\n" +
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
  err("Value of parameter 'timestamps_to_actions' which is:\n\n#{actions.pretty_inspect}\nshould be an array but is not (see #{$jam_json})") unless actions.is_a?(Array)
  err("Value of parameter 'example_harpwise' cannot be empty (see #{$jam_json})") if $example == ''

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
  
  # check syntax of timestamps before actually starting
  actions.sort_by! {|ta| ta[0]}
  $jam_loop_start_idx = nil
  actions.each_with_index do |ta,idx|
    err("First word after timestamp must either be 'message', 'keys' or 'loop-start', but here (index #{idx}) it is '#{ta[1]}':  #{ta}") unless %w(message keys loop-start).include?(ta[1])
    err("Timestamp #{ta[0]} (index #{idx}, #{ta}) is less than zero") if ta[0] < 0
    # test actions
    jamming_do_action ta[1 ..], noop: true
    if ta[1] == 'loop-start'
      err("Action 'loop-start' already appeared with index #{$jam_loop_start_idx}: #{actions[$jam_loop_start_idx]}, cannot appear again with index #{idx}: #{ta}") if $jam_loop_start_idx
      $jam_loop_start_idx = idx
    end
  end
  err("Need at least one timestamp with action 'loop-start'") unless $jam_loop_start_idx
  $jam_data[:iteration_duration] = jam_ta(actions[-1][0] - actions[$jam_loop_start_idx][0])

  # check if sound-file is present
  file = $jam_pms['sound_file'] = $jam_pms['sound_file'] % $jam_data
  if File.exist?(file)
    puts "\e[0m\e[2mBacking track:   #{file}"
    print "Duration:   --:--"
    $jam_pms['sound_file_length_secs'] = sox_query(file, 'Length').to_i
    $jam_pms['sound_file_length'] = jam_ta($jam_pms['sound_file_length_secs'])
    print "\rDuration:   #{$jam_pms['sound_file_length']}\e[K"
    2.times {sleep 0.1; puts}
  else
    err("\nFile given as sound_file does not exist:  #{file}") unless File.exist?(file)
  end
  
  [$jam_pms, actions]
end


def do_the_playing json_or_mp3

  make_term_immediate
  $ctl_kb_queue.clear
  jamming_check_and_prepare_sig_handler
  
  if json_or_mp3.end_with?('.mp3')
    err "Named mp3-file does not exist:   #{json_or_mp3}" unless File.exist?(json_or_mp3)
    $jam_pms = Hash.new
    $jam_pms['sound_file_length_secs'] = sox_query(json_or_mp3, 'Length').to_i
    $jam_pms['sound_file_length'] = jam_ta($jam_pms['sound_file_length_secs'])
    $jam_pms['sound_file'] = json_or_mp3
  else
    $jam_pms, _ = parse_and_preprocess_jamming_json(json_or_mp3)
    sleep 0.2
  end
    
  play_command = jam_get_play_command

  puts
  puts "Starting:\n\n    #{play_command}\n\n"
  puts"\e[0m\e[32m"
  $jam_help_while_play.each {|l| puts l}
  puts "\e[0m"
    
  $pplayer = PausablePlayer.new(play_command)
  $jam_ts_collected = [$jam_pms['sound_file_length_secs']]
  $jam_idxs_events = {skip_fore: [],
                      skip_back: [],
                      jump: []}
  fname_tpl = "#{$jamming_timestamps_dir}/marked-by-user-in-jam-play-%d.txt"
  backups_done = false
  fname = ( fname_tpl % 1 )

  my_sleep(1000000, fast_w_animation: true) do |char|

    case char

    when 't','RETURN'
      #
      # Generate full output on every invocation, even though only one timetamp has been
      # added
      #
      $jam_ts_collected.insert(-2, $pplayer.time_played + $jam_play_prev_trim)
      unless backups_done
        (1..8).to_a.reverse.each do |idx|
          next unless File.exist?(fname_tpl % idx)
          FileUtils.mv(fname_tpl % idx, fname_tpl % (idx + 1))
        end
        puts "\e[0m\n\nPlease note, that the human reaction time and other factors may introduce a constant\n  delay in recorded timestamps.   However, this can later be compensated with a\n  negative value (e.g. -1.0) for parameter 'timestamps_add' in the json-file."
        backups_done = true
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
      $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim))
      jamming_play_print_current('Backward 10 secs to', trim)
      $jam_play_prev_trim = trim
      $jam_idxs_events[:skip_back] << $jam_ts_collected.length - 1
      :handled

    when 'RIGHT'

      trim = $jam_play_prev_trim + $pplayer.time_played + 10
      trim = $jam_pms['sound_file_length_sec'] if trim > $jam_pms['sound_file_length_secs']
      $pplayer.kill
      $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim))
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
        $pplayer = PausablePlayer.new(jam_get_play_command(trim: trim))
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


def check_for_space_etc blk, print_pending: nil
  space_seen = pending_printed = false
  if $ctl_kb_queue.length > 0
    if print_pending
      print print_pending
      pending_printed = true
    end
    while $ctl_kb_queue.length > 0
      char = $ctl_kb_queue.deq
      if char == ' ' || char == 'j'
        space_seen = true
      elsif blk&.(char) == :handled
        # The important things have already happened in the call to blk ...
      else
        puts
        puts "\n\e[0m\e[32mUnknown key: '#{char}'\e[0m\n\n" unless %w(h ?).include?(char)
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
      exec($full_commandline)
    end
  end
  
  if ENV['HARPWISE_RESTARTED_PROMPT']
    puts "\n\n\e[0m\e[32mPaused after signal ctrl-z:\e[0m"
    puts $to_pause % 'CONTINUE'    
    jamming_sleep_wait_for_go
    puts
    puts
  end
end


def jamming_sleep_wait_for_go
  print "\e[0mPaused \e[0m"
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
  print " \e[0m\e[32mgo\e[0m    "
  
  space_seen
end


def jam_get_play_command trim: 0, initial_silence: 0
  err "Internal error: both parameters trim and initial_silence are given" if trim > 0 && initial_silence > 0
  if ENV["HARPWISE_TESTING"] || $opts[:print_only]
    "sleep #{$jam_pms['sound_file_length_secs']}"
  else
    "play -q #{$jam_pms['sound_file']}" +
      if initial_silence == 0
        ''
      else
        " pad %.2f 0" % initial_silence
      end +
      if trim == 0
        ''
      else
        " trim #{trim}"
      end
  end
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
    err "None of the available jamming-files (see above) are matched by your input,\nwhich is:   #{words.join(' ')}\n\nPlease check against the complete list of files above and change or shorten your input."
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
    File.write($pers_file, JSON.pretty_generate($pers_data))
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
