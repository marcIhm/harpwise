#
# Handle user-interaction (e.g. printing and reading of input)
#


def prepare_screen
  h, w = %x(stty size).split.map(&:to_i)
  err_b "Terminal is too small: [width, height] = #{[w,h].inspect} < [94,28]" if w < 84 || h < 32

  STDOUT.sync = true

  [h, w]
end


def err_h text
  puts "ERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  exit 1
end


def err_b text
  puts "ERROR: #{text} !"
  exit 1
end


def puts_pad text
  text.lines.each do |line|
    puts line.chomp.ljust($term_width - 2) + "\n"
  end
end


def install_ctl
  Signal.trap('SIGQUIT') do
    system("stty quit '^\'")
    print "\e[s"
    text = $ctl_can_skip ? "SPACE to continue, TAB to skip" : "SPACE to continue"
    print "\e[1;#{$term_width-text.length-1}H#{text}"
    system("stty raw -echo")
    begin
      key = STDIN.getc
    end until key == " " || ( key == "\t" && $ctl_can_skip )
    system("stty -raw")
    system("stty quit ' '")
    print "\e[1;#{$term_width-text.length-1}H#{' ' * text.length}"
    print "\e[u"
    $ctl_paused = true
    $ctl_skip = ( key == "\t" )
  end
  system("stty quit ' '")
  $ctl_pause_continue = "\e[2m[SPACE to pause]\e[0m"
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
    print "Your choice (press a single key): "
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
