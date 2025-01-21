#
#  Support for jamming with harpwise
#

def do_jamming to_handle

  if $extra
    
    case $extra
    when 'list'
      
      err_args_not_allowed(to_handle) if to_handle.length > 0
      do_jamming_list
      
    when'edit'
      
      err "'harpwise jamming edit' needs exactly one additional argument, these args cannot be handled: #{to_handle[2..-1]}" if to_handle.length > 1
      err "'harpwise jamming edit' needs exactly one additional argument; none is given however" if to_handle.length == 0
      tool_edit_file get_jamming_json(to_handle[0])
      
    end
    
  else  ## no extra argument
      
    do_the_jamming get_jamming_json(to_handle[0])
    
  end
end


def do_the_jamming json_file
  
  puts
  puts "\e[2mSettings from: #{json_file}\e[0m\n\n"
  
  #
  # Process json-file with settings
  #
  params = JSON.parse(File.read(json_file).lines.reject {|l| l.match?(/^\s*\/\//)}.join)
  timestamps_to_actions = params['timestamps_to_actions']
  sleep_after_iteration = params['sleep_after_iteration']
  timestamps_multiply = params['timestamps_multiply']
  timestamps_add = params['timestamps_add']
  comment = params['comment']
  sleep_initially = params['sleep_initially']
  play_command = params['play_command']
  $ts_prog_start = Time.now.to_f
  $example = params['example_harpwise']
  $aux_data = {comment: comment, iteration: 0, elapsed: 0, install_dir: File.read("#{Dir.home}/.harpwise/path_to_install_dir").chomp}

  # check if all parameters present
  wanted = Set.new(%w(timestamps_to_actions sleep_initially sleep_after_iteration play_command timestamps_multiply timestamps_add comment example_harpwise))
  given = Set.new(params.keys)
  err("Found keys:\n\n  #{given.to_a.sort.join("\n  ")}\n\n, but wanted:\n\n  #{wanted.to_a.sort.join("\n  ")}\n\nin #{json_file}\n" +
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
  err("Value of parameter 'timestamps_to_actions' which is:\n\n#{params['timestamps_to_actions'].pretty_inspect}\nshould be an array but is not (see #{json_file})") unless params['timestamps_to_actions'].is_a?(Array)
  err("Value of parameter 'example_harpwise' cannot be empty (see #{json_file})") if $example == ''

  #
  # preprocess and check list of timestamps
  #

  # preprocess to allow negative timestamps as relative to preceding ones
  while i_neg = (0 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] < 0}
    loc_neg = "negative timestamp at position #{i_neg}, content #{timestamps_to_actions[i_neg]}"
    i_pos_after_neg = (i_neg + 1 .. timestamps_to_actions.length - 1).to_a.find {|i| timestamps_to_actions[i][0] > 0}
    err("#{loc_neg.capitalize} is not followed by positive timestamp") unless i_pos_after_neg
    loc_pos_after_neg = "following positive timestamp at position #{i_pos_after_neg}, content #{timestamps_to_actions[i_pos_after_neg]}"
    ts_abs = timestamps_to_actions[i_pos_after_neg][0] + timestamps_to_actions[i_neg][0]
    err("When adding   #{loc_neg}   to   #{loc_pos_after_neg}   we come up with a negative absolute time: #{ts_abs}") if ts_abs < 0
    timestamps_to_actions[i_neg][0] = ts_abs
  end
  
  # check syntax of timestamps before actually starting
  timestamps_to_actions.sort_by! {|ta| ta[0]}
  loop_start_at = nil
  timestamps_to_actions.each_with_index do |ta,idx|
    err("First word after timestamp must either be 'message', 'keys' or 'loop-start', but here (index #{idx}) it is '#{ta[1]}':  #{ta}") unless %w(message keys loop-start).include?(ta[1])
    err("Timestamp #{ta[0]} (index #{idx}, #{ta}) is less than zero") if ta[0] < 0
    # test actions
    jamming_do_action ta[1 ..], 0, noop: true
    if ta[1] == 'loop-start'
      err("Action 'loop-start' already appeared with index #{loop_start_at}: #{timestamps_to_actions[loop_start_at]}, cannot appear again with index #{idx}: #{ta}") if loop_start_at
      loop_start_at = idx
    end
  end
  err("Need at least one timestamp with action 'loop-start'") unless loop_start_at

  # transformations
  timestamps_to_actions.each_with_index do |ta,idx|
    ta[0] *= timestamps_multiply
    ta[0] += timestamps_add
    ta[0] = 0.0 if ta[0] < 0
  end

  # try to figure out file and check if present
  endings = %w(.mp3 .wav .ogg)
  play_command = play_command % $aux_data
  file = CSV::parse_line(play_command,col_sep: ' ').find {|word| endings.any? {|ending| word.end_with?(ending)}} || err("Could not find filename in play_command  '#{play_command}'\nno word ends on any of: #{endings.join(' ')}")
  err("File mentioned in play-command does not exist:  #{file}") unless File.exist?(file)

  #
  # Start doing user-visible things
  #

  puts "Comment:\n\n\e[32m" + wrap_text(comment,cont: '').join("\n") + "\e[0m\n\n"

  if $runningp_listen_fifo
    puts "\nFound 'harpwise listen'"
  else
    puts "\nCannot find an instance of 'harpwise listen' that reads from fifo.\n\nPlease start it in a second terminal:\n\n  \e[32m#{$example % $aux_data}\e[0m\n\nuntil then this instance of 'harpwise jamming' will check repeatedly and\nstart with the backing track as soon as 'harpwise listen' is running.\nSo you can stay with it and need not come back here.\n\n"
    print "Waiting "
    begin
      pid_listen_fifo = ( File.exist?($pidfile_listen_fifo) && File.read($pidfile_listen_fifo).to_i )
      print '.'
      sleep 1
    end until pid_listen_fifo
    puts ' found it'
  end
  puts
  
  # allow for testing
  if ENV["HARPWISE_TESTING"]
    puts "Environment variable 'HARPWISE_TESTING' is set; exiting before play."
    exit 0
  end

  if sleep_initially > 0
    jamming_do_action ['message',
                       'sleep initially for %.1d secs' % sleep_initially,
                       [0.0, sleep_initially - 0.2].max.round(1)],
                      0
    sleep sleep_initially
  end

  make_term_immediate
  # start play-command
  puts "\n\nStarting:\n\n    #{play_command}\n\n"
  $pplayer = PausablePlayer.new(play_command)
  puts

  at_exit do
    $pplayer&.kill
  end
  
  sleep_secs = timestamps_to_actions[0][0]
  puts "Initial sleep %.2f sec" % sleep_secs
  my_sleep sleep_secs
  ts_iter_start = nil
  
  # endless loop one iteration after the other
  (1 .. ).each do |iter|
    ts_iter_start_prev = ts_iter_start
    ts_iter_start = Time.now.to_f
    puts
    puts "ITERATION #{iter}"
    if ts_iter_start_prev
      puts "%.1f secs after startup, last iteration took %.1f secs" %
           [ts_iter_start - $ts_prog_start, ts_iter_start - ts_iter_start_prev ]
    end
    puts
    pp timestamps_to_actions

    if iter == 1
      puts
      puts "\n\e[32mYou may now go over to 'harpwise listen' ... "
      puts "Come back here only, if you wish to pause the backing track.\e[0m"
    end
    
    puts
    puts "\e[32mPress SPACE to pause.\e[0m"
    puts

    # one action after the other
    timestamps_to_actions.each_cons(2).each_with_index do |pair,j|
      tsx, tsy = pair[0][0], pair[1][0]
      action = pair[0][1 .. -1]
      puts "Action #{j + 1}/#{timestamps_to_actions.length} (elapsed #{$aux_data[:elapsed]} secs, iteration #{$aux_data[:iteration]}) at %.2f sec:" % tsx

      jamming_do_action action, iter

      sleep_between = tsy - tsx
      puts "sleep %.2f sec" % sleep_between
      my_sleep sleep_between
      puts

    end  ## one action after the other

    puts "Final action #{timestamps_to_actions.length}/#{timestamps_to_actions.length} (elapsed #{$aux_data[:elapsed]} secs, iteration #{$aux_data[:iteration]}):"  
    jamming_do_action timestamps_to_actions[-1][1 .. -1], iter
    puts "at ts %.2f sec" % timestamps_to_actions[-1][0]

    if sleep_after_iteration > 0
      puts "and sleep after iteration %.2f sec" % ( sleep_after_iteration * timestamps_multiply ) 
      my_sleep ( sleep_after_iteration * timestamps_multiply )
    end
    
    if iter == 1
      while timestamps_to_actions[0][1] != 'loop-start'
        timestamps_to_actions.shift
      end
    end
  end  ## endless loop one iteration after the other
  
end


def jamming_send_keys keys, silent: false
  fifo = "#{Dir.home}/.harpwise/remote_fifo"
  keys.each do |key|
    begin
      Timeout::timeout(0.5) do
        File.write(fifo, key + "\n")
      end
    rescue Timeout::Error, Errno::EINTR
      err "Could not write '#{key}' to #{fifo}.\nIs 'harpwise listen' still listening ?"
    end
    puts "sent key \e[0m\e[2m'#{key}'\e[0m" unless silent
  end
end


def jamming_do_action action, iter, noop: false
  if action[0] == 'message' || action[0] == 'loop-start'
    if action.length != 3 || !action[1].is_a?(String) || !action[2].is_a?(Numeric)
      err("Need exactly one string and a number after 'message'; not #{action}")
    end
    if action[1].lines.length > 1
      err("Message to be sent can only be one line, but this has more: #{action[1]}")
    end
    return if noop
    $aux_data[:iteration] = iter if iter
    $aux_data[:elapsed] = "%.1f" % ( Time.now.to_f - $ts_prog_start )
    File.write("#{Dir.home}/.harpwise/remote_message",
               ( action[1].chomp % $aux_data ) + "\n" + action[2].to_s + "\n")
    puts "sent message \e[2m'#{action[1].chomp % $aux_data}'\e[0m"
    jamming_send_keys ["ALT-m"], silent: true
  elsif action[0] == 'keys'
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


def get_jamming_json arg, extra_allowed: false
  # get json-file to handle
  if arg.match?(/^\d+$/)
    num = arg.to_i
    cont = $jamming_dirs_content.values.flatten
    explain = "Use 'harpwise jamming list' to see the available jamming-files with numbers"
    err "Given number '#{arg}' is less than one. #{explain}" if num < 1
    err "Given number '#{arg}' is larger than maximum of #{cont.length}. #{explain}" if num > cont.length
    json_file = cont[num - 1]
  else
    arg_w_ending = if arg.match?(/\.[a-zA-Z0-9]+$/)
                     arg
                   else
                     puts "\n\e[32mRemark:\e[0m Adding required ending '.json' to given argument '#{arg}' for convenience.\e[0m\n\n"                    
                     arg + '.json'
                   end
    
    explain = "\n\n\e[2mSome background on finding the required json-file with settings: If the given argument is a plain number, it is treated The given argument is tried as a filename; if it starts with a '/', it is assumed to be an absolute filename and is tried as such; on the contrary: if the filename does not start with '/', it is searched within these directories: #{$jamming_path.join(', ')}.\e[0m\n\n"

    json_file = if arg_w_ending[0] == '/'
                  arg_w_ending
                else                
                  dir = $jamming_path.find {|dir| File.exist?("#{dir}/#{arg_w_ending}")} or err "Could not find file '#{arg_w_ending}' in any of: #{$jamming_path.join(', ')}#{explain}"
                  dir + '/' + arg_w_ending
                end
  end
  json_file
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
      else
        ppfx = pfx = ''
      end
      print "\e[0m\e[2m%2d:\e[0m" % tcount
      if pfx.length == 0 || pfx != ppfx
        puts "\e[0m  " + jfs
        ppfx = pfx
      else
        puts "  \e[0m\e[2m" + pfx + "\e[0m" + jfs[pfx.length .. -1]
      end
      count += 1
      tcount += 1
    end
    puts "\e[0m  none" if count == 0
  end
  puts
end


def my_sleep secs
  start_at = Time.now.to_f
  hinted = false
  begin
    if $ctl_kb_queue.length > 0
      space_seen = false
      while $ctl_kb_queue.length > 0
        char = $ctl_kb_queue.deq
        if char == ' '
          space_seen = true
        elsif !hinted
          puts "\n\e[0m\e[2mSPACE to pause, all other keys are ignored.\e[0m"
          hinted = true
        end
      end
      if space_seen
        $ctl_kb_queue.clear
        $pplayer&.pause
        print "\n\n\e[32mPaused: \e[0m"
        space_to_cont
        puts "\e[0m\e[32mgo\e[0m"        
        $pplayer&.continue
      end
    end
    if !$pplayer.alive?
      puts
      puts "Backing track has ended."
      puts
      jamming_do_action ["message","Backing track has ended.",1], nil
      exit 0
    end
    sleep 0.1
  end while Time.now.to_f - start_at < secs + ($pplayer  ?  $pplayer.sum_pauses  :  0)
  $pplayer.sum_pauses = 0 if $pplayer
end
