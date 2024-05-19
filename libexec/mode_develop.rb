#
#  Utility functions for the maintainer or developer of harpwise
#

def do_develop to_handle

  # common error checking
  err_args_not_allowed(to_handle) if to_handle.length > 0

  $man_template = "#{$dirs[:install_devel]}/resources/harpwise.man.erb"
  $man_result = "#{$dirs[:install_devel]}/man/harpwise.1"

  case $extra
  when 'man'
    do_man
  when 'diff'
    do_diff
  when 'selftest', 'st'
    do_selftest
  when 'unittest', 'ut'
    do_unittest
  when 'widgets', 'wt'
    do_widgets
  else
    fail "Internal error: unknown extra '#{$extra}'"
  end
end


def do_man

  # needed in erb
  types_with_scales = get_types_with_scales

  File.write($man_result, ERB.new(IO.read($man_template)).result(binding).chomp)

  puts
  system("ls -l #{$man_template} #{$man_result}")
  puts "\nTo read it:\n\n  man -l #{$dirs[:install_devel]}/man/harpwise.1\n\n"
  puts "\nRedirect stdout to see any errors:\n\n  man --warnings -E UTF-8 -l -Tutf8 -Z -l #{$dirs[:install_devel]}/man/harpwise.1 >/dev/null\n\n"
end


def do_diff

  abort("\nFile\n\n  #{$man_result}\n\nis older than\n\n  #{$man_template}\n\nProbably you should process the man page first ...\n\n") if File.mtime($man_result) < File.mtime($man_template)

  # needed in erb
  types_with_scales = get_types_with_scales

  lines = Hash.new
  line = Hash.new
  srcs = [:usage, :man]

  # Modifications for usage
  erase_line_usage_if_part = [/Version \d/]

  # Modifications for man; element seen: will be modified
  man_sections = {:desc => {rx: /^DESCRIPTION$/,
                            seen: false},
                  :prim_start => {rx: /The primary documentation/,
                                  seen: false},
                  :prim_end => {rx: /not available as man-pages/,
                                seen: false},
                  :exa_start => {rx: /^EXAMPLES$/,
                                 seen: false},
                  :exa_end => {rx: /^COPYRIGHT$/,
                               seen: false}}
  
  erase_part_man = ['<hy>', '<beginning of page>']
  erase_line_man = %w(MODE ARGUMENTS OPTIONS)
  replaces_man = {'SUGGESTED READING' => 'SUGGESTED READING:',
                  'USER CONFIGURATION' => 'USER CONFIGURATION:',
                  'DIAGNOSIS' => 'DIAGNOSIS:',
                  'COMMANDLINE OPTIONS' => 'COMMANDLINE OPTIONS:',
                  'QUICK START' => 'QUICK START:'}

  #
  # Bring usage information and man page into canonical form by
  # applying modifications
  #

  # handling usage is simpler, because it does not contain formatting commands
  lines[:usage] = ERB.new(IO.read("#{$dirs[:install_devel]}/resources/usage.txt")).
                    result(binding).lines.
                    map do |l|
                      erase_line_usage_if_part.any? {|rgx| l.match?(rgx)} ? nil : l
                    end.compact.
                    map {|l| l.chomp.strip.downcase}.
                    reject(&:empty?)

  # Man pages are more formal and need more processing
  lines[:man] = %x(groff -man -a -Tascii #{$dirs[:install_devel]}/man/harpwise.1).lines.
                  map {|l| l.strip}.
                  # use only some sections of man page
                  map do |l|
                    on_section_head = false
                    man_sections.each do |nm, sec|
                      if l.strip.match?(sec[:rx])
                        sec[:seen] = true
                        on_section_head = true
                      end
                    end
                    # omit lines based on our position within man page
                    if on_section_head
                      nil
                    elsif !man_sections[:desc][:seen]
                      nil
                    elsif man_sections[:prim_start][:seen] && !man_sections[:prim_end][:seen]
                      nil
                    elsif man_sections[:exa_start][:seen] && !man_sections[:exa_end][:seen]
                      nil
                    else
                      l
                    end
                  end.compact.
                  map do |l|
                    # erase parts of lines
                    erase_part_man.each {|e| l.gsub!(e,'')}
                    l
                  end.
                  map do |l|
                    # erase whole lines
                    erase_line_man.any? {|e| e == l.strip} ? nil : l
                  end.compact.
                  map {|l| replaces_man[l] || l}.
                  map {|l| l.strip.downcase}.reject(&:empty?).compact

  srcs.each {|s| line[s] = lines[s].shift}

  last_common = Array.new

  # compare results by eating up usage and man against each other
  while srcs.all? {|s| lines[s].length > 0}
    clen = 0
    clen += 1 while line[:usage][clen] && line[:usage][clen] == line[:man][clen]
    if clen > 0
      last_common << [line[:usage][0, clen], line[:man][0, clen]] 
      srcs.each do |s|
        line[s][0, clen] = ''
        line[s].strip!
        line[s] = lines[s].shift.strip if line[s].empty?
      end
    else
      puts "\nLast two pairs of common lines or line-fragments between usage and man:"
      pp last_common[-2 .. -1]
      puts "\nThe first pair of lines or line-fragments, that differ:"
      pp [line[:usage], line[:man]]
      puts "\nError: #{srcs} differ; see above"
      puts
      puts "Hint: Make sure to edit the file\n  #{$man_template}\ninstead of the processed man page"
      puts
      puts "Hint: A common problem would be a line of text starting with a single quote (') in, which would be misinterpreted by man."
      puts
      exit 1
    end
  end
end


def do_selftest

  puts
  puts_underlined "Performing selftest"

  puts_underlined "Check installation", '-', dim: false
  check_installation verbose: true

  puts
  puts_underlined "Invoking figlet for fontname on all fonts", '-', dim: false
  # Remark: output of figlet is suppressed to allow selftest to pass
  # even in non-utf8 environments. See test for encoding above
  expected = {'smblock' => [2, '▝▀▖▌▐ ▌▌ ▌▐ ▌ ▌▌ ▖▛▚'],
              'mono12' => [4, ' ██ ██ ██  ██▀  ▀██  ██▀   ██  ██▀  ▀██     ██         ▄█▀'],
              'mono9' => [4, '█ █ █  █   █  █   █  █   █   ▀▀▀ █']}
              
  $early_conf[:figlet_fonts].each do |font|
    output = get_figlet_wrapped(font, font)
    puts output
    line = expected[font][0]
    text = expected[font][1]
    err "Line #{line} from text above '#{output[line]}' does not match expected: '#{text}'" unless output[line][text]
  end

  test_hole = '+1'
  puts
  puts_underlined "Generating sound with sox", '-', dim: false
  synth_sound test_hole, $helper_wave
  system("ls -l #{$helper_wave}")

  puts
  puts_underlined "Frequency pipeline from previously generated sound", '-', dim: false
  cmd = get_pipeline_cmd(:sox, $helper_wave)
  puts "Command is: #{cmd}"
  puts
  puts "Note: Some errors in first lines are expected, because\n      multiple codecs are tried and some of them give up."
  puts
  _, stdout_err, wait_thr  = Open3.popen2e(cmd)
  output = Array.new
  to_test = Array.new
  loop do
    line = stdout_err.gets
    output << line
    if output.length > 10
      begin
        line or raise ArgumentError
        to_test << line.split(' ', 2).map {|f| Float(f)}
      rescue ArgumentError
        err "Unexpected output of: #{cmd}\n:#{output.compact}"
      end
    end
    if output.length == 40
      Process.kill('KILL',wait_thr.pid)
      break
    end
  end
  puts 'Some samples from the middle of the interval:'
  mid = to_test.length / 2
  to_test = to_test[mid - 5 .. mid + 5]
  pp to_test
  puts
  
  max_pct = 5
  to_test.each_cons(2) do |a, b|
    tss = b[0] - a[0]
    pct = ( 100 * ( tss - $time_slice_secs ) / $time_slice_secs ).abs.round(2)
    fail "Actual time slice #{b[0]} - #{a[0]} = #{tss} is too different from expected value #{$time_slice_secs}: #{pct}% percent > #{max_pct}%" if pct > max_pct
  end
  puts "Test Okay: time differences are near expected time-slice #{'%.6f' % $time_slice_secs} secs"
  freq = semi2freq_et($harp[test_hole][:semi])
  to_test.each do |tf|
    pct = ( 100 * ( tf[1] - freq ) / freq ).abs.round(2)
    err "Actual frequency #{tf[1]} is too different from expected value #{freq}: #{pct}% percent > #{max_pct}%" if pct > max_pct
  end
  puts "Test Okay: detected frequencies are near expected frequency #{'%.2f' % freq}"

  puts
  err "Internal error: no user config directory yet: #{$dirs[:data]}" unless File.exist?($dirs[:data])
  if $dirs_data_created
    puts "Remark: user config directory has been created: #{$dirs[:data]}"
  else
    puts "Remark: user config directory already existed: #{$dirs[:data]}"
  end

  puts
  puts
  puts "Selftest okay."
  puts
end


def do_unittest

  puts
  puts_underlined 'Semitone calculations'
  found = note2semi('a4')
  expected = 0
  utreport('note2semi', found, expected)

  found = semi2note(0)
  expected = 'a4'
  utreport('semi2note', found, expected)

  [[['c', 'g', :g_is_lowest], 5],
   [['c', 'g', :minimum_distance], 5],
   [['g', 'c', :g_is_lowest], -5],
   [['g', 'c', :minimum_distance], -5],
   [['c', 'a', :g_is_lowest], 3],
   [['c', 'a', :minimum_distance], 3],
   [['a', 'c', :g_is_lowest], -3],
   [['a', 'c', :minimum_distance], -3],
   [['c', 'd', :g_is_lowest], -2],
   [['c', 'd', :minimum_distance], -2],
   [['d', 'c', :g_is_lowest], 2],
   [['d', 'c', :minimum_distance], 2],
   [['a', 'g', :g_is_lowest], 2],
   [['a', 'g', :minimum_distance], 2],
   [['g', 'a', :g_is_lowest], -2],
   [['g', 'a', :minimum_distance], -2],
   [['g', 'd', :g_is_lowest], -7],
   [['g', 'd', :minimum_distance], 5]].each do |params, expected|
   
    found = diff_semitones(params[0], params[1], strategy: params[2])
    utreport("diff_semitones,#{params[0]},#{params[1]},#{params[2]}", found, expected)

  end

  puts
  puts_underlined '$msgbuf'

  # we do not set $msgbuf ready, so we dont get any output
  $msgbuf.print 'a', 1, 3, later: true
  $msgbuf.print 'b', 1, 3
  # one :foo should overwrite the other
  $msgbuf.print 'c', 1, 3, :foo
  $msgbuf.print 'd', 1, 3, :foo
  found = $msgbuf.get_lines_durations
  expected = [["a", 1, 3, nil],
              ["b", 1, 3, nil],
              ["d", 1, 3, :foo]] 
  utreport('Symbols override', found, expected)

  $msgbuf.clear
  $msgbuf.print 'd', 1, 3
  sleep 2
  found = $msgbuf.update
  expected = true
  utreport('Update', found, expected)
  
  found = $msgbuf.get_lines_durations
  expected = [["d", 1, 3, nil]]
  utreport('Not age away for hint', found, expected)

  $msgbuf.print 'e', 1, 3
  found = $msgbuf.get_lines_durations
  expected = [["e", 1, 3, nil]]
  utreport('Age away for message', found, expected)
  
  sleep 4
  $msgbuf.update
  found = $msgbuf.get_lines_durations
  expected = []
  utreport('Age away for hint', found, expected)

  puts
  puts_underlined 'Subclasses of QuizFlavour'
  found = $quiz_flavour2class.keys.to_a.sort
  expected = $extra_kws[:quiz].to_a.sort - $quiz_tag2flavours[:meta]
  utreport('subclasses and extra', found, expected)
  found = $quiz_flavour2class.keys.select {|f| $quiz_flavour2class[f].respond_to?(:describe_difficulty)}.sort
  expected = ($extra_kws[:quiz].to_a.sort - $quiz_tag2flavours[:meta]).sort
  utreport('describe_difficulty implemented', found, expected)  

  puts
  puts "All unittests okay."
  puts
end


def do_widgets
  puts_underlined "Excercising widgets"
  puts_underlined "one_char", '-', dim: false
  puts "Echoing input, type 'q' to quit"
  cnt = 0
  begin
    char = one_char
    cnt += 1
    puts "Input ##{cnt}: -#{char}-"
  end while char != 'q'
  puts "#{cnt} chars read."

  %w(one two).each do |count|
    puts_underlined "choose_interactive #{count}", '-', dim: false
    make_term_immediate
    ($term_height - $lines[:comment_tall] + 1).times { puts }
    answer = choose_interactive('testprompt', ['1', ';comment'] + (2..100).to_a.map(&:to_s)) {|name| 'Selected: ' + name}
    clear_area_comment
    clear_area_message
    make_term_cooked
    print "\e[#{$lines[:comment_tall]}H"
    puts "Answer #{count}: #{answer}"
  end
end


def utreport desc, found, expected
  print desc.ljust(38) + ' ... '
  if found == expected
    puts "\e[32mOkay\e[0m"
  else
    puts "\e[31mError\e[0m\n  found = #{found}\n  expected = #{expected}\n"
    exit 1
  end
end
