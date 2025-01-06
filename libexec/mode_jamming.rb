#
#  Support for jamming with harpwise
#

def do_jamming to_handle

  $fifo = "#{Dir.home}/.harpwise/remote_fifo"
  $message = "#{Dir.home}/.harpwise/remote_message"

  err "'harpwise jamming' accepts only a single argument, not #{to_handle}" if to_handle.length > 1

  if to_handle[0] == 'list'
    puts
    puts_underlined "Available jamming-files:",vspace: false
    $jamming_path.each do |jdir|
      puts
      puts_underlined "From #{jdir}:", '-', dim: false
      count = 0
      Dir["#{jdir}/*.json"].each do |jf|
        puts '  ' + File.basename(jf)
        count += 1
      end
      puts "  none" if count == 0
    end
    puts
    exit
  end
  
  arg_w_ending = if to_handle[0].match?(/\.[a-zA-Z0-9]+$/)
                    to_handle[0]
                 else
                   puts "\n\e[32mRemark:\e[0m Adding required ending '.json' to given argument '#{to_handle[0]}' for convenience.\e[0m\n\n"                    
                   to_handle[0] + '.json'
                 end
  
  explain = "\n\n\e[2mSome background on finding the required json-file with settings: The given argument is tried as a filename; if it contains a '/', it is assumed to be an absolute filename and is tried as such; on the contrary: if the filename does not contain a '/', it is searched within these directories: #{$jamming_path.join(', ')}.\e[0m\n\n"

  json_file = if arg_w_ending['/']
                if File.exist?(arg_w_ending)
                  arg_w_ending
                else
                  err "Given file '#{arg_w_ending} does not exist in current directory.#{explain}"
                end
              else
                if File.exist?(arg_w_ending) && !$jamming_path.include?(Dir.pwd)
                  puts "\n\e[32mRemark:\e[0m Skipping file '#{arg_w_ending}' from current directory, use './#{arg_w_ending}' to enforce it.#{explain}"
                  explain = ''
                end
                dir = $jamming_path.find {|dir| File.exist?("#{dir}/#{arg_w_ending}")} or err "Could not find file '#{arg_w_ending}' in any of: #{$jamming_path.join(', ')}#{explain}"
                dir + '/' + arg_w_ending
              end

  puts "Settings from: #{json_file}\n\n"
  
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

  err "Cannot find an instance of 'harpwise listen', that reads from fifo.\n\nYou may try 'harpwise jamming' to learn about the needed steps to get going.\n\n\nFor short, starting this in a second terminal should be enough:\n\n  #{$example % $aux_data}\n\nthen come back and start '#{$full_commandline}' again.\n\n" unless $pid_fifo_listener
  
  # under wsl2 we may actually use explorer.exe (windows-command !) to start playing
  play_with_win = play_command['explorer.exe'] || play_command['wslview']

  # check if all parameters present
  wanted = Set.new(%w(timestamps_to_actions sleep_initially sleep_after_iteration play_command timestamps_multiply timestamps_add comment example_harpwise))
  given = Set.new(params.keys)
  err("Found keys:\n\n  #{given.to_a.sort.join("\n  ")}\n\n, but wanted:\n\n  #{wanted.to_a.sort.join("\n  ")}\n\nin #{json_file}\n" +
      if (given - wanted).length > 0
        "\nthese parameters given in file are unknown: #{(given - wanted).to_a.join(', ')}"
      else
        ''
      end +
      if (wanted - given).length > 0
         "\nthese parameters are missing in given file: #{(wanted - given).to_a.join(', ')}"
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

  #
  # Start doing user-visible things
  #

  puts "Comment:\n\n  \e[32m" + comment + "\e[0m\n\n"
  puts

  puts "Invoke harpwise like this:\n\n  \e[32m" + ( $example % $aux_data ) + "\e[0m\n\n"
  puts

  # allow for testing
  if ENV["HARPWISE_TESTING"]
    puts "Environment variable 'HARPWISE_TESTING' is set; exiting before play."
    exit 0
  end

  # try to figure out file and check if present even before first sleep
  endings = %w(.mp3 .wav .ogg)
  play_command = play_command % $aux_data
  file = CSV::parse_line(play_command,col_sep: ' ').find {|word| endings.any? {|ending| word.end_with?(ending)}} || err("Could not find filename in play_command  '#{play_command}'\nno word ends on any of: #{endings.join(' ')}")
  err("File mentioned in play-command does not exist:  #{file}") unless File.exist?(file)

  # make some room below to have initial error (if any) without scrolling
  print "\n\n\n\n\e[4A"

  if sleep_initially > 0
    jamming_do_action ['message',
                       'sleep initially for %.1d secs' % sleep_initially,
                       [0.0, sleep_initially - 0.2].max.round(1)],
                      0
    sleep sleep_initially
  end

  puts play_command
  puts

  # start play-command
  Thread.new do
    puts "\n\nStarting:\n\n    #{play_command}\n\n"
    if play_with_win
      # avoid spurious output of e.g. media-player
      system "#{play_command} >/dev/null 2>&1"
    else
      system play_command
    end
    puts
    if play_with_win
      puts "Assuming this is played with windows-programs, not waiting for its end.\n\n"
    else
      sleep 1
      puts
      puts "Backing track has ended."
      puts
      exit 0
    end
  end

  at_exit do
    system "killall play >/dev/null 2>&1" unless play_with_win
  end

  sleep_secs = timestamps_to_actions[0][0]
  puts "Initial sleep %.2f sec" % sleep_secs
  sleep sleep_secs
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
    puts

    # one action after the other
    timestamps_to_actions.each_cons(2).each_with_index do |pair,j|
      tsx, tsy = pair[0][0], pair[1][0]
      action = pair[0][1 .. -1]
      puts "Action #{j + 1}/#{timestamps_to_actions.length} (elapsed #{$aux_data[:elapsed]} secs, iteration #{$aux_data[:iteration]}):"

      jamming_do_action action, iter

      sleep_between = tsy - tsx
      puts "at ts %.2f sec" % tsx
      puts "sleep %.2f sec" % sleep_between
      sleep sleep_between
      puts

    end  ## one action after the other

    puts "Final action #{timestamps_to_actions.length}/#{timestamps_to_actions.length} (elapsed #{$aux_data[:elapsed]} secs, iteration #{$aux_data[:iteration]}):"  
    jamming_do_action timestamps_to_actions[-1][1 .. -1], iter
    puts "at ts %.2f sec" % timestamps_to_actions[-1][0]

    if sleep_after_iteration > 0
      puts "and sleep after iteration %.2f sec" % ( sleep_after_iteration * timestamps_multiply ) 
      sleep ( sleep_after_iteration * timestamps_multiply )
    end
    
    if iter == 1
      while timestamps_to_actions[0][1] != 'loop-start'
        timestamps_to_actions.shift
      end
    end
  end  ## endless loop one iteration after the other
  
end

def jamming_send_keys keys
  keys.each do |key|
    begin
      Timeout::timeout(0.5) do
        File.write($fifo, key + "\n")
      end
    rescue Timeout::Error, Errno::EINTR
      err "Could not write '#{key}' to #{$fifo}.\nIs the other instance of harpwise still listening ?"
    end
    puts "sent key \e[32m'#{key}'\e[0m"
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
    $aux_data[:iteration] = iter
    $aux_data[:elapsed] = "%.1f" % ( Time.now.to_f - $ts_prog_start )
    File.write($message, ( action[1].chomp % $aux_data ) + "\n" + action[2].to_s + "\n")
    puts "sent message '#{action[1].chomp % $aux_data}'"
    jamming_send_keys ["ALT-m"]
  elsif action[0] == 'keys'
    return if noop
    jamming_send_keys action[1 .. -1]
  else
    err("Unknown type '#{action[0]}'")
    return if noop
  end
end
