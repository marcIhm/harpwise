#
#  Utility functions for the maintainer or developer of harpwise
#

def do_develop to_handle

  # common error checking
  err_args_not_allowed(to_handle) if $extra && !%w(lickfile lf read-scale-with-notes rswn).include?($extra) && to_handle.length > 0

  case $extra
  when 'docs-make-org-txt'
    do_docs_make_org_txt
  when 'docs-make-html'
    do_docs_make_html
  when 'docs-all'
    %w(do_docs_make_org_txt do_docs_make_html).each do |met|
      puts "\e[34m"
      do_figlet_unwrapped met , 'smblock'
      puts "\e[0m"
      sleep 0.5
      eval(met)
      sleep 1
    end
  when 'selftest'
    do_selftest
  when 'unittest'
    do_unittest
  when 'widgets'
    do_widgets
  when 'lickfile'
    do_lickfile to_handle
  when 'check-frequencies'
    do_check_frequencies
  when 'read-scale-with-notes'
    do_read_scale_with_notes to_handle
  when 'dump'
    write_dump
  else
    fail "Internal error: unknown extra '#{$extra}'"
  end
end


def do_docs_make_org_txt
  src_erb_dir = "#{$dirs[:install]}/docs/erb-org"
  dst_txt_dir = "#{$dirs[:install]}/docs/_txt"
  dst_org_dir = "#{$dirs[:install]}/docs/_org"
  src_files_short = Dir["#{src_erb_dir}/*"].map {|f| File.basename(f).chomp(".erb.org")}
  found = src_files_short.map {|f| "#{f}.erb.org"}
  expected = $early_conf[:modes].map {|m| "usage_#{m}.erb.org"}
  expected.append('index.erb.org', 'usage.erb.org')
  expected.sort!
  fail "Inernal error for dir #{src_erb_dir}: List of files found\n  " + found.sort.join("\n  ") + "\ndiffers from expected\n  " + expected.sort.join("\n  ") + "\n" unless found == expected

  dir_suff = [[dst_org_dir, '.org'],
              [dst_txt_dir, '.txt']]

  # needed for erb
  types_with_scales = get_types_with_scales_for_usage
  
  puts "\nWriting files ...\n\n"
  src_files_short.each do |file_short|
    dir_suff.each do |dir, suff|
      dst_file = "#{dir}/#{file_short}#{suff}"

      Dir.chdir(src_erb_dir) do
        if suff == '.org'
          File.write(dst_file,
                    ERB.new(IO.read("#{src_erb_dir}/#{file_short}.erb.org")).
                      result(binding).gsub(/(^\s*\n)+\Z/,''))
        else
          next if file_short == 'index'          
          cmd = "/usr/bin/emacs -Q --batch " +
                "-eval \"(require 'org)\" " +
                "--insert #{dst_org_dir}/#{file_short}.org " +
                "--eval \"(setq org-export-with-toc nil)\" " +
                "--eval \"(setq org-export-with-author nil)\" " +
                "--eval \"(org-ascii-export-as-ascii nil nil nil nil '(:ascii-charset ascii))\" " +
                "--eval \"(write-file \\\"#{dst_file}\\\")\" " +
                "--kill"
          system(cmd) or fail("Command failed; see above for output: #{cmd}") 
        end
      end
      puts dst_file
    end
  end
end


def do_docs_make_html
  
  ddir = $dirs[:install] + '/docs'
  hdir = $dirs[:install] + '/docs/_html'
  odir = $dirs[:install] + '/docs/_org'

  puts
  puts "\e[32mCopy theme from #{ddir} to #{odir} and checking index.org\e[0m"
  puts $org_theme_file
  FileUtils.cp "#{ddir}/#{$org_theme_file}", odir
  fail("#{$org_theme_file} not used in #{odir}/index.org") unless File.read("#{odir}/index.org").lines.select {|l| l["#+SETUPFILE: #{$org_theme_file}"]}.length > 0
  
  puts
  puts "\e[32mPublish html\e[0m"
  Dir.chdir(ddir) do
    cmd = "/usr/bin/emacs -Q --batch -l publish.el"
    puts cmd
    system(cmd) or fail("\nError, see above")
  end

  puts
  puts "\e[32mRemove timestamp-comments\e[0m"
  Dir["#{hdir}/*.html"].each do |html|
    puts html
    File.write(html, IO.read(html).lines.reject {|l| l.start_with?("<!-- ")}.join)
  end

  puts "\n\e[32mMove index.html, replace random IDs, correct links\e[0m"
  FileUtils.mv "#{hdir}/index.html", ddir
  lines = IO.read("#{ddir}/index.html").lines
  href_ids = Hash.new
  id_cnt = 0
  File.open("#{ddir}/index.html", 'w') do |html|
    lines.each do |line|
      # collect and replace random ids with predictable ones
      if md = ( line.match(/^<li><a href=\"#(org[0-9a-z]+)\"/) ||
                line.match(/^<div id=\"(org[0-9a-z]+)\"/))
        href_ids[md[1]] = "org%07d" % id_cnt
        id_cnt += 1
        puts line
      end
      href_ids.keys.each do |oid|
        line.sub! oid, href_ids[oid]
      end

      # correct directory of usage files; this is necessary, because we have moved
      # index.html up one directory
      line.gsub!(/href="(usage[_a-z]*.html")/, 'href="_html/\1')
      
      # correct directory of image files
      line.gsub!(/src="\.\.\/images\//, 'src="images/')
      
      html.write line
    end
  end

  puts "\n\e[32mSuccessfully published to\e[0m #{ddir}/index.html"
  puts
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
  puts_underlined 'show_help'
  [:quiz, :listen, :licks].each do |mode|
    # needed in help
    $modes_for_switch = [:quiz, :listen]
    # will throw error on problems
    show_help mode, true
    puts mode.to_s.ljust(6) + "\e[32m ... okay\e[0m"
  end

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

  $msgbuf.clear
  len = 42
  $msgbuf.ready
  # print long string, that wil be wrapped to three lines
  $msgbuf.print %w(a b c).map {|ch| ch * len}.join(' '), 1, 1, wrap: true, truncate: false
  puts "HINT: set HARPWISE_TESTING to 'msgbuf' to use a minimum terminal width" if ENV['HARPWISE_TESTING'] != 'msgbuf'
  
  found = $msgbuf.get_lines_durations
  expected = [['c' * len, 1, 1, nil],
              ['b' * len, 1, 1, nil],
              ['a' * len, 1, 1, nil]]
  expected = [["cccccccccccccccccccccccccccccccccccccccccc", 1, 1, nil],
              ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ...", 1, 1, nil],
              ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...", 1, 1, nil]]
  utreport('Wrap long text', found, expected)

  # from the three lines only one has already been printed; the others wait in backlog
  found = $msgbuf.printed
  expected = [["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...", 1, 1, nil]]
  utreport('Sequence of lines, part 1', found, expected)

  # let messages age away
  sleep 2
  $msgbuf.update
  sleep 2
  $msgbuf.update
  sleep 2
  found = $msgbuf.printed
  expected = [["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...", 1, 1, nil],
              ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ...", 1, 1, nil],
              ["cccccccccccccccccccccccccccccccccccccccccc", 1, 1, nil]]
  utreport('Sequence of lines, part 2', found, expected)
  $msgbuf.ready(false)

  $msgbuf.clear
  $msgbuf.print 'abc' * len, 1, 1
  found = $msgbuf.get_lines_durations
  expected = [["abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc ...", 1, 1, nil]]
  utreport('Truncate text', found, expected)

  
  $msgbuf.clear
  $msgbuf.print ['foo','bar'], 1, 3
  found = $msgbuf.get_lines_durations
  expected = [['bar', 1, 3, nil],
              ['foo', 1, 3, nil]]
  utreport('Print array', found, expected)

  
  $msgbuf.clear
  $msgbuf.print 'a', 1, 3
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
  $msgbuf.print 'c', 1, 3, :foo
  $msgbuf.print 'a', 1, 3
  $msgbuf.print 'b', 1, 3
  # one :foo should overwrite the other
  $msgbuf.print 'd', 1, 3, :foo
  found = $msgbuf.get_lines_durations
  expected = [["a", 1, 3, nil],
              ["b", 1, 3, nil],
              ["d", 1, 3, :foo]] 
  utreport('Symbols deep override', found, expected)

  
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


def do_lickfile to_handle
  err "Need exactly one argument, not #{to_handle}" if to_handle.length != 1
  $all_licks, $licks, $all_lick_progs = read_licks(lick_file: to_handle[0])
  report_name_collisions_mb
  pp({all_licks: $all_licks.length,
      licks: $licks.length})
end


def do_check_frequencies
  puts
  hole2freq_read = yaml_parse($freq_file)
  hole_was = nil
  freq_was = 0
  semi_was = 0
  puts "Comparing #{$harp_holes.length} frequencies for type #{$type} and key of #{$key}:\n\n  - from file #{$freq_file}\n  - with measurement from aubiopitch\n  - with calculated frequencies for equal tempererament\n\nand checking for beeing strict ascending.\n\n"

  $harp_holes.each do |hole|
    semi = $harp[hole][:semi]

    freq_measured = analyze_with_aubio("#{$sample_dir}/#{$harp[hole][:note]}.mp3")
    freq_calculated = semi2freq_et($harp[hole][:semi])
    puts "  #{hole.ljust(8)}, #{$harp[hole][:note].ljust(4)}   measured = %8.2f\n                 calculated = %8.2f\n                  from file = %8.2f" % [freq_measured.round(2), freq_calculated, hole2freq_read[hole]]

    if hole_was && semi != semi_was
      err "Frequencies measured for holes   #{hole_was} = #{freq_was} Hz   and   #{hole} = #{freq_measured} Hz   are not ascending" unless freq_was < freq_measured
    end

    [['measured', freq_measured],
     ['calculated', freq_calculated]].each do |what, freq_other|
      err "Frequencies for hole #{hole}   #{what} = #{freq_other} Hz   and   read from file = #{hole2freq_read[hole]} Hz   are too different" if ( freq_other - hole2freq_read[hole] ).abs > 0.005 * ( freq_other + hole2freq_read[hole] )
    end
    
    freq_was = freq_measured
    hole_was = hole
    semi_was = semi
  end
  puts "\n\nAll checks passed.\n\n"
end


def do_read_scale_with_notes to_handle
  err 'Need two args: name of scale and filename to read it from' unless to_handle.length == 2
  sname, file = to_handle
  puts "Trying to read scale #{sname} from file #{file}"
  pp read_and_parse_scale_simple(sname, override_file: file)
end
