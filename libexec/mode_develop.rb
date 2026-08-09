#
#  Utility functions for the maintainer or developer of harpwise
#

module ModeDevelop
  extend self
  def do_develop to_handle
    # common error checking
    Util::err_args_not_allowed(to_handle) if $extra && !%w[lickfile lf read-scale-with-notes rswn].include?($extra) && to_handle.length > 0

    case $extra
    when 'docs-make-org-txt'
      do_docs_make_org_txt
    when 'docs-make-html'
      do_docs_make_html
    when 'docs-all'
      %w[do_docs_make_org_txt do_docs_make_html].each do |met|
        puts "\e[34m"
        Text::do_figlet_unwrapped met, 'smblock'
        puts "\e[0m"
        sleep 0.5
        eval(met)
        sleep 1
      end
    when 'selftest'
      do_selftest
    when 'unittests'
      do_unittests
    when 'widgets'
      do_widgets
    when 'lickfile'
      do_lickfile to_handle
    when 'check-frequencies'
      do_check_frequencies
    when 'read-scale-with-notes'
      do_read_scale_with_notes to_handle
    when 'dump'
      Util::write_dump
    else
      raise "Internal error: unknown extra '#{$extra}'"
    end
  end

  def do_docs_make_org_txt
    src_erb_dir = "#{$dirs[:install]}/docs/erb-org"
    dst_txt_dir = "#{$dirs[:install]}/docs/_txt"
    dst_org_dir = "#{$dirs[:install]}/docs/_org"
    src_files_short = Dir["#{src_erb_dir}/*"].map {|f| File.basename(f).chomp('.erb.org')}
    found = src_files_short.map {|f| "#{f}.erb.org"}
    expected = $early_conf[:modes].map {|m| "usage_#{m}.erb.org"}
    expected.append('index.erb.org', 'usage.erb.org')
    expected.sort!
    raise "Inernal error for dir #{src_erb_dir}: List of files found\n  " + found.sort.join("\n  ") + "\ndiffers from expected\n  " + expected.sort.join("\n  ") + "\n" unless found == expected

    dir_suff = [[dst_org_dir, '.org'],
                [dst_txt_dir, '.txt']]

    Args::get_types_with_scales_for_usage

    puts "\nWriting files ...\n\n"
    src_files_short.each do |file_short|
      dir_suff.each do |dir, suff|
        dst_file = "#{dir}/#{file_short}#{suff}"

        Dir.chdir(src_erb_dir) do
          if suff == '.org'
            File.write(dst_file,
                       ERB.new(IO.read("#{src_erb_dir}/#{file_short}.erb.org"))
                         .result(binding).gsub(/(^\s*\n)+\Z/, ''))
          else
            next if file_short == 'index'

            cmd = '/usr/bin/emacs -Q --batch ' +
                  "-eval \"(require 'org)\" " +
                  "--insert #{dst_org_dir}/#{file_short}.org " +
                  '--eval "(setq org-export-with-toc nil)" ' +
                  '--eval "(setq org-export-with-author nil)" ' +
                  '--eval "(setq org-export-with-section-numbers nil)" ' +
                  "--eval \"(org-ascii-export-as-ascii nil nil nil nil '(:ascii-charset ascii))\" " +
                  "--eval \"(write-file \\\"#{dst_file}\\\")\" " +
                  '--kill'
            system(cmd) or raise("Command failed; see above for output: #{cmd}")
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
    raise("#{$org_theme_file} not used in #{odir}/index.org") unless File.read("#{odir}/index.org").lines.select {|l| l["#+SETUPFILE: #{$org_theme_file}"]}.length > 0

    puts
    puts "\e[32mPublish html\e[0m"
    Dir.chdir(ddir) do
      cmd = '/usr/bin/emacs -Q --batch -l publish.el'
      puts cmd
      system(cmd) or raise("\nError, see above")
    end

    puts
    puts "\e[32mRemove timestamp-comments\e[0m"
    Dir["#{hdir}/*.html"].each do |html|
      puts html
      File.write(html, IO.read(html).lines.reject {|l| l.start_with?('<!-- ')}.join)
    end

    puts "\n\e[32mMove index.html, replace random IDs, correct links\e[0m"
    FileUtils.mv "#{hdir}/index.html", ddir
    lines = IO.read("#{ddir}/index.html").lines
    href_ids = Hash.new
    id_cnt = 0
    File.open("#{ddir}/index.html", 'w') do |html|
      lines.each do |line|
        # collect and replace random ids with predictable ones
        if md = line.match(/^<li><a href="#(org[0-9a-z]+)"/) ||
                line.match(/^<div id="(org[0-9a-z]+)"/)
          href_ids[md[1]] = 'org%07d' % id_cnt
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
        line.gsub!(%r{src="\.\./images/}, 'src="images/')

        html.write line
      end
    end

    win_url = `wslpath -m #{ddir}/index.html`
    puts "\n\e[32mSuccessfully published to\e[0m   file:#{win_url}"
    puts
  end

  def do_selftest
    puts
    Text::puts_underlined 'Performing selftest'

    Text::puts_underlined 'Check installation', '-', dim: false
    Cfg::check_installation verbose: true

    puts
    Text::puts_underlined 'Invoking figlet for fontname on all fonts', '-', dim: false
    # Remark: output of figlet is suppressed to allow selftest to pass
    # even in non-utf8 environments. See test for encoding above
    expected = { 'smblock' => [2, '▝▀▖▌▐ ▌▌ ▌▐ ▌ ▌▌ ▖▛▚'],
                 'mono12' => [4, ' ██ ██ ██  ██▀  ▀██  ██▀   ██  ██▀  ▀██     ██         ▄█▀'],
                 'mono9' => [4, '█ █ █  █   █  █   █  █   █   ▀▀▀ █'] }

    $early_conf[:figlet_fonts].each do |font|
      output = Text::get_figlet_wrapped(font, font)
      puts output
      line = expected[font][0]
      text = expected[font][1]
      err "Line #{line} from text above '#{output[line]}' does not match expected: '#{text}'" unless output[line][text]
    end

    test_hole = '+1'
    puts
    Text::puts_underlined 'Generating sound with sox', '-', dim: false
    Sound::synth_sound test_hole, $helper_wave
    system("ls -l #{$helper_wave}")

    puts
    Text::puts_underlined 'Frequency pipeline from previously generated sound', '-', dim: false
    cmd = Sound::get_pipeline_cmd(:sox, $helper_wave)
    puts "Command is: #{cmd}"
    puts
    puts "Note: Some errors in first lines are expected, because\n      multiple codecs are tried and some of them give up."
    puts
    _, stdout_err, wait_thr = Open3.popen2e(cmd)
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
        Process.kill('KILL', wait_thr.pid)
        break
      end
    end
    puts 'Some samples from the middle of the interval:'
    mid = to_test.length / 2
    to_test = to_test[mid - 5..mid + 5]
    pp to_test
    puts

    max_pct = 5
    to_test.each_cons(2) do |a, b|
      tss = b[0] - a[0]
      pct = ( 100 * ( tss - $time_slice_secs ) / $time_slice_secs ).abs.round(2)
      raise "Actual time slice #{b[0]} - #{a[0]} = #{tss} is too different from expected value #{$time_slice_secs}: #{pct}% percent > #{max_pct}%" if pct > max_pct
    end
    puts "Test Okay: time differences are near expected time-slice #{'%.6f' % $time_slice_secs} secs"
    freq = Theory::semi2freq_et($harp[test_hole][:semi])
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
    puts 'Selftest okay.'
    puts
  end

  def do_unittests
    puts
    Text::puts_underlined 'show help'
    %i[quiz listen licks].each do |mode|
      # needed in help
      $modes_for_switch = %i[quiz listen]
      # will throw error on problems
      ShowMic::show_help mode, true
      puts mode.to_s.ljust(6) + "\e[32m ... okay\e[0m"
    end

    puts
    Text::puts_underlined 'init all quiz classes'
    $opts[:difficulty] = :easy
    bad = 0
    what = ''
    $quiz_flavour2class.each do |name, qclass|
      begin
        what = 'init'
        flavour = $quiz_flavour2class[name].new(false)
        what = 'selfcheck'
        flavour.selfcheck
      rescue => e
        bad += 1
        puts e if $opts[:verbose]
        puts "   \e[31m#{what} #{name}\e[0m"
      end
    end
    utreport(bad, 0, 'no bad?')

    puts
    Text::puts_underlined 'Semitone calculations'
    found = Theory::note2semi('a4')
    expected = 0
    utreport(found, expected, 'note2semi')

    found = Theory::semi2note(0)
    expected = 'a4'
    utreport(found, expected, 'semi2note')

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
      found = Theory::diff_semitones(params[0], params[1], strategy: params[2])
      utreport(found, expected, "diff_semitones,#{params[0]},#{params[1]},#{params[2]}")
    end

    puts
    Text::puts_underlined 'note2semi'
    utreport(%w[bs4 cs4 d4 ds4 ff4 es4 fs4 g4 gs4 a4 as4 cf4].map {|n| Theory::note2semi(n, shadowed: true)},
             (-9..2).to_a)

    puts
    Text::puts_underlined 'days_ago_in_words'
    [[1, 'yesterday'], [73, '10 weeks ago']].each do |num, words|
      utreport(Util::days_ago_in_words(num), words)
    end

    puts
    Text::puts_underlined '$msgbuf'

    $msgbuf.clear
    len = 42
    $msgbuf.ready
    # print long string, that wil be wrapped to three lines
    $msgbuf.print %w[a b c].map {|ch| ch * len}.join(' '), 1, 1, wrap: true, truncate: false
    puts "\n\nHINT: if appropriate, set HARPWISE_TESTING to 'msgbuf' to use a minimum terminal width\n" if ENV['HARPWISE_TESTING'] != 'msgbuf'

    found = $msgbuf.get_lines_durations
    [['c' * len, 1, 1, nil],
     ['b' * len, 1, 1, nil],
     ['a' * len, 1, 1, nil]]
    expected = [['cccccccccccccccccccccccccccccccccccccccccc', 1, 1, nil],
                ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ...', 1, 1, nil],
                ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...', 1, 1, nil]]
    utreport(found, expected, 'Wrap long text')

    # from the three lines only one has already been printed; the others wait in backlog
    found = $msgbuf.printed
    expected = [['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...', 1, 1, nil]]
    utreport(found, expected, 'Sequence of lines, part 1')

    # let messages age away
    sleep 2
    $msgbuf.update
    sleep 2
    $msgbuf.update
    sleep 2
    found = $msgbuf.printed
    expected = [['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ...', 1, 1, nil],
                ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ...', 1, 1, nil],
                ['cccccccccccccccccccccccccccccccccccccccccc', 1, 1, nil]]
    utreport(found, expected, 'Sequence of lines, part 2')
    $msgbuf.ready(false)

    $msgbuf.clear
    $msgbuf.print 'abc' * len, 1, 1
    found = $msgbuf.get_lines_durations
    expected = [['abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc ...', 1, 1, nil]]
    utreport(found, expected, 'Truncate text')

    $msgbuf.clear
    $msgbuf.print %w[foo bar], 1, 3
    found = $msgbuf.get_lines_durations
    expected = [['bar', 1, 3, nil],
                ['foo', 1, 3, nil]]
    utreport(found, expected, 'Print array')

    $msgbuf.clear
    $msgbuf.print 'a', 1, 3
    $msgbuf.print 'b', 1, 3
    # one :foo should overwrite the other
    $msgbuf.print 'c', 1, 3, :foo
    $msgbuf.print 'd', 1, 3, :foo
    found = $msgbuf.get_lines_durations
    expected = [['a', 1, 3, nil],
                ['b', 1, 3, nil],
                ['d', 1, 3, :foo]]
    utreport(found, expected, 'Symbols override')

    $msgbuf.clear
    $msgbuf.print 'c', 1, 3, :foo
    $msgbuf.print 'a', 1, 3
    $msgbuf.print 'b', 1, 3
    # one :foo should overwrite the other
    $msgbuf.print 'd', 1, 3, :foo
    found = $msgbuf.get_lines_durations
    expected = [['a', 1, 3, nil],
                ['b', 1, 3, nil],
                ['d', 1, 3, :foo]]
    utreport(found, expected, 'Symbols deep override')

    $msgbuf.clear
    $msgbuf.print 'd', 1, 3
    sleep 2
    found = $msgbuf.update
    expected = true
    utreport(found, expected, 'Update')

    found = $msgbuf.get_lines_durations
    expected = [['d', 1, 3, nil]]
    utreport(found, expected, 'Not age away for hint')

    $msgbuf.print 'e', 1, 3
    found = $msgbuf.get_lines_durations
    expected = [['e', 1, 3, nil]]
    utreport(found, expected, 'Age away for message')

    sleep 4
    $msgbuf.update
    found = $msgbuf.get_lines_durations
    expected = []
    utreport(found, expected, 'Age away for hint')

    puts
    puts 'Unittests okay'
    puts
  end

  def do_widgets
    Text::puts_underlined 'Widgets to be driven in tmux'
    Text::puts_underlined 'one_char', '-', dim: false
    puts "Echoing input, type 'q' to quit"
    cnt = 0
    begin
      char = Interact::one_char
      cnt += 1
      puts "Input ##{cnt}: -#{char}-"
    end while char != 'q'
    puts "#{cnt} chars read."

    %w[one two].each do |count|
      Text::puts_underlined "choose_interactive #{count}", '-', dim: false
      Interact::make_term_immediate
      ($term_height - $lines[:comment_tall] + 1).times { puts }
      answer = Choose::choose_interactive('testprompt', ['1', ';comment'] + (2..100).to_a.map(&:to_s)) {|name| 'Selected: ' + name}
      Interact::clear_area_comment
      Interact::clear_area_message
      Interact::make_term_cooked
      print "\e[#{$lines[:comment_tall]}H"
      puts "Answer #{count}: #{answer}"
    end
  end

  def utreport found, expected, desc = ''
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
    $all_licks, $licks, $all_lick_progs = Licks::read_licks(lick_file: to_handle[0])
    Util::report_name_collisions_mb
    pp({ all_licks: $all_licks.length,
         licks: $licks.length })
  end

  def do_check_frequencies
    puts
    hole2freq_read = Util::yaml_parse($freq_file)
    hole_was = nil
    freq_was = 0
    semi_was = 0
    puts "Comparing #{$harp_holes.length} frequencies for type #{$type} and key of #{$key}:\n\n  - from file #{$freq_file}\n  - with measurement from aubiopitch\n  - with calculated frequencies for equal tempererament\n\nand checking for beeing strict ascending.\n\n"

    $harp_holes.each do |hole|
      semi = $harp[hole][:semi]

      freq_measured = Sound::analyze_with_aubio("#{$sample_dir}/#{$harp[hole][:note]}.mp3")
      freq_calculated = Theory::semi2freq_et($harp[hole][:semi])
      puts "  #{hole.ljust(8)}, #{$harp[hole][:note].ljust(4)}   measured = %8.2f\n                 calculated = %8.2f\n                  from file = %8.2f" % [freq_measured.round(2), freq_calculated, hole2freq_read[hole]]

      err "Frequencies measured for holes   #{hole_was} = #{freq_was} Hz   and   #{hole} = #{freq_measured} Hz   are not ascending" if hole_was && semi != semi_was && !(freq_was < freq_measured)

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
    pp Cfg::read_and_parse_scale_simple(sname, override_file: file)
  end
end
