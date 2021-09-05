#
# Handle user-interaction (e.g. printing and reading of input)
#


def prepare_screen
  h, w = %x(stty size).split.map(&:to_i)
  err_b "Terminal is too small: [width, height] = #{[w,h].inspect} < [84,32]" if w < 84 || h < 32
  STDOUT.sync = true
  [h, w]
end


def err_h text
  puts "ERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  puts
  exit 1
end


def err_b text
  puts "ERROR: #{text} !"
  puts
  exit 1
end


def dbg text
  puts "DEBUG: #{text}" if $opts[:debug] && $opts[:debug] > 1
  text
end


def puts_pad text = nil, top = false
  text = ' ' unless text && text.length > 0
  text.lines.each do |line|
    puts line.chomp.ljust($term_width - ( top ? 36 : 1 )) + "\n"
  end
end


def do_figlet text, font
  figlet_out = %x(figlet -f #{font} -c " #{text}")
  puts_pad figlet_out
  print"\e[0m"
end


def poll_and_handle_kb space_only = false
  return unless Time.now.to_f - $ctl_last_poll > 1
  $ctl_last_poll = Time.now.to_f 
  key = ''
  system("stty raw")
  begin
      key = STDIN.read_nonblock(1)
  rescue IO::EAGAINWaitReadable
  end
  
  if key == ' '
    if space_only
      print "SPACE to continue ... "
    else
      ctl_issue "SPACE to continue"
    end
    begin
      key = STDIN.getc
    end until key == " "
    if space_only
      system("stty -raw")
      return
    end
  elsif space_only
    system("stty -raw")
    return
  elsif ( key == 'n' || key == "\n" ) && $ctl_can_next
    $ctl_next = true
    text = "Skip"
  elsif key == 'l'  && $ctl_can_next && !$opts[:loop]
    $ctl_loop = true
    text = "Loop started"
  elsif key.length > 0
    text = "Invalid key '#{key.match?(/[[:print:]]/) ? key : '?'}'"
  end
  system("stty -raw")
  ctl_issue text
end


def ctl_issue text = nil
  text ||= $ctl_default_issue
  $ctl_last_text ||= ''
  padded_text = text.rjust($ctl_last_text.length)
  print "\e[1;#{$term_width - padded_text.length - 1}H\e[2m#{padded_text}\e[0m"
  $ctl_last_text = text
end
  

def read_answer answer2keys_desc
  klists = Hash.new
  answer2keys_desc.each do |an, ks_d|
    klists[an] = ks_d[0].join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  answer2keys_desc.each do |an, ks_d|
    puts "  %*s :  %s" % [maxlen, klists[an], ks_d[1]]
  end

  begin
    print "\nYour choice (press a single key): "
    system("stty raw -echo")
    char = STDIN.getc
    system("stty -raw echo")
    char = case char
           when "\r"
             'RETURN'
           when ' '
             'SPACE'
           else
             char
           end
    if char.ord == 3
      puts "ctrl-c; aborting ..."
      exit 1
    end
    puts char
    puts
    answer = nil
    answer2keys_desc.each do |an, ks_d|
      answer = an if ks_d[0].include?(char)
    end
    puts "Invalid key: '#{char}' (#{char.ord})" unless answer
  end while !answer
  answer
end
