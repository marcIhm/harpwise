module Text
  extend self

  def do_animation info, nlines, sleep1 = 0.04, sleep2 = 0.03
    puts "\e[?25l"  ## hide cursor
    $splashed = true
    dots = '...'
    push_front = dots + info
    shift_back = info + dots
    txt = dots + info + dots + info + dots
    ilen = txt.length
    prev = nil
    nlines.times do
      len = push_front.length
      txt[0..len - 1] = push_front if txt[0..len - 1] == ' ' * len
      puts "\e[G\e[2m\e[34m#{prev}\e[0m" if prev
      txt.prepend(' ')
      txt.chomp!(shift_back) if txt.length > ilen + shift_back.length - 3
      print "\e[0m\e[34m#{txt}\e[0m\e[K"
      prev = txt
      sleep sleep1
    end
    puts "\e[G\e[2m\e[34m#{txt}\e[0m"
    puts "\e[K"
    sleep sleep2
  end

  $figlet_cache = Hash.new
  def do_figlet_unwrapped text, font, width_template = nil, truncate = :left
    raise "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)

    cmd = "figlet -w 400 -f #{font} -d #{$font2dir[font]} -l  -- \"#{text}\""
    cmdt = cmd + truncate.to_s
    unless $figlet_cache[cmdt]
      out = Util::sys(cmd).force_encoding('UTF-8')
      $perfctr[:figlet_1] += 1
      lines = out.lines.map {|l| l.rstrip}

      # strip common spaces at front
      common = lines.select {|l| l.lstrip.length > 0}
                    .map {|l| l.length - l.lstrip.length}.min
      lines.map! {|l| l[common..-1] || ''}

      # overall length from figlet
      maxlen = lines.map {|l| l.length}.max

      # calculate offset from width_template (if available) or from actual output of figlet
      offset_specific = 0.4 * ( $term_width - maxlen )
      if width_template
        if width_template.start_with?('fixed:')
          offset = ( $term_width - figlet_text_width(width_template[6..-1], font) ) * 0.5
        else
          twidth = figlet_text_width(width_template, font)
          offset = ( twidth.to_f / $term_width < 0.6 ? 0.4 : 0.8 ) * ( $term_width - twidth )
        end
      else
        offset = offset_specific
      end
      offset = 0.3 * $term_width if offset + maxlen < $term_width * 0.3
      offset = offset_specific if offset + maxlen > 0.9 * $term_width
      offset = 0 if offset < 0 || offset + maxlen > 0.9 * $term_width
      $figlet_cache[cmdt] = lines.each_with_index.map do |l, i|
        if maxlen + 2 < $term_width
          ' ' * offset + l.chomp
        elsif truncate == :left
          '/\\'[i % 2] + '   ' + sprintf("%-#{maxlen}s", l.chomp)[-$term_width + 6..-1]
        else
          (l.chomp + ' ' * maxlen)[0..$term_width - 6] + '   ' + '/\\'[i % 2]
        end
      end
    end
    return unless $figlet_cache[cmdt]  ## may save us after resize

    $figlet_cache[cmdt].each do |line|
      print "#{line.chomp}\e[K\n"
    end
    print "\e[0m"
  end

  $figlet_wrap_cache = Hash.new
  def get_figlet_wrapped text, font
    raise "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)

    cmd = "figlet -w #{$term_width - 4} -f #{font} -d #{$font2dir[font]} -l -- \"#{text}\""
    unless $figlet_wrap_cache[cmd]
      out = Util::sys(cmd).force_encoding('UTF-8')
      $perfctr[:figlet_2] += 1
      lines = out.lines.map {|l| l.rstrip}

      # strip common spaces at front in groups of four, known to be figlet line height
      lines = lines.each_slice(4).map do |lpl| # lines (terminal) per line (figlet)
        common = lpl.select {|l| l.lstrip.length > 0}
                    .map {|l| l.length - l.lstrip.length}.min || 0
        lpl.map {|l| l[common..-1] || ''}
      end.flatten

      $figlet_wrap_cache[cmd] = lines.map {|l| '  ' + l}
    end
    $figlet_wrap_cache[cmd]
  end

  def figlet_char_height font
    raise "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)

    # high and low chars
    out = Util::sys("figlet -f #{font} -d #{$font2dir[font]} -l Igq")
    $perfctr[:figlet_3] += 1
    out.lines.length
  end

  $figlet_text_width_cache = Hash.new
  def figlet_text_width text, font
    unless $figlet_text_width_cache[text + font]
      raise "Unknown font: #{font}" unless $conf[:figlet_fonts].include?(font)

      out = Util::sys("figlet -f #{font} -d #{$font2dir[font]} -l -- \"#{text}\"").force_encoding('UTF-8')
      $perfctr[:figlet_4] += 1
      $figlet_text_width_cache[text + font] = out.lines.map {|l| l.strip.length}.max
    end
    $figlet_text_width_cache[text + font]
  end

  def largify holes, idx
    line = $lines[:comment_flat]
    if $num_quiz_replay == 1
      ["\e[2m", '...', line, 'smblock', nil]
    elsif $opts[:immediate] # show all unplayed
      hidden_holes = if idx > 6
                       '.. # ..'
                     else
                       '.' * idx
                     end
      ["\e[2m",
       'Play  ' + hidden_holes + holes[idx..-1].join('  '),
       line,
       'smblock',
       'play  ' + '--' * holes.length,  # width_template
       :right]  # truncate at
    else # show all played
      hidden_holes = if holes.length - idx > 8
                       ' _ _ # _ _' # abbreviation for long sequence of ' _'
                     else
                       ' _' * (holes.length - idx)
                     end
      ["\e[2m",
       'Yes  ' + holes.slice(0, idx).join('  ') + hidden_holes,
       line,
       'smblock',
       'yes  ' + '--' * [6, holes.length].min,  # width_template
       :left]  # truncate at
    end
  end

  # idx_first_active is a special case used for comment :lick_holes_large
  def wrapify_for_comment max_lines, holes, idx_first_active
    # get output from figlet
    lines_all = Text::get_figlet_wrapped(holes.join('  '), 'smblock')
    lines_inactive = if idx_first_active == -1
                       lines_all
                     else
                       Text::get_figlet_wrapped(holes[0...idx_first_active].join('  '), 'smblock')
                     end
    # we know that each figlet-line has 4 screen lines; integer arithmetic on purpose
    fig_lines_max = max_lines / 4
    fig_lines_all = lines_all.length / 4
    fig_lines_inactive = lines_inactive.length / 4

    # truncate if necessary
    # use offset instead of shifting from arrays to avoid caching issues
    offset = 0
    if fig_lines_all > fig_lines_max
      $msgbuf.print('Warning: Wrapped text has been truncated', 1, 2, :warning) if $opts[:jamming]
      if fig_lines_inactive <= 1
      # This happens during begin of replay: need to show first
      # inactive figlet-line, because it also contains active holes;
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
    lines_all[offset..-1].each_with_index do |line, idx|
      break if idx >= max_lines

      lines << "\e[0m#{line.chomp}\e[K"
      next unless idx + offset < lines_inactive.length

      lines[-1] += if idx_first_active == -1
                     # two types of grey, but not the usual one \e[2m
                     "\e[G\e[0m\e[38;5;244m"
                   else
                     "\e[G\e[0m\e[38;5;236m"
                   end
      lines[-1] += lines_inactive[idx + offset]
    end
    lines[-1] += "\e[0m"
    lines
  end

  def print_chart skip_hole = nil
    xoff, yoff, = $conf[:chart_offset_xyl]
    if %i[chart_intervals chart_inter_semis].include?($opts[:display]) && !$hole_ref
      print "\e[0m\e[#{$lines[:display] + yoff + 4}H  You need to set a reference hole, before this chart can be displayed."
    else
      print "\e[#{$lines[:display] + yoff}H"
      $charts[$opts[:display]].each_with_index do |row, ridx|
        print ' ' * ( xoff - 1)
        row[0..-2].each_with_index do |cell, cidx|
          hole = $note2hole[$charts[:chart_notes][ridx][cidx].strip]
          if skip_hole && skip_hole == hole
            print "\e[#{cell.length}C"
          else
            print (Util::comment_in_chart?(cell) ? "\e[0m\e[2m" : "\e[0m" + get_hole_color_inactive(hole)) +
                  cell
          end
        end
        puts "\e[0m\e[2m#{row[-1]}\e[0m"
      end
    end
  end

  def update_chart hole, state, good = nil, was_good = nil, was_good_since = nil
    return if %i[chart_intervals chart_inter_semis].include?($opts[:display]) && !$hole_ref

    # a hole can appear at multiple positions in the chart
    $hole2chart[hole].each do |xy|
      x = $conf[:chart_offset_xyl][0] + xy[0] * $conf[:chart_offset_xyl][2]
      y = $lines[:display] + $conf[:chart_offset_xyl][1] + xy[1]
      cell = $charts[$opts[:display]][xy[1]][xy[0]]
      hole_color = if state == :inactive
                     "\e[0m" + get_hole_color_inactive(hole)
                   else
                     "\e[0m\e[7m" + get_hole_color_active(hole, good, was_good, was_good_since)
                   end
      print "\e[#{y};#{x}H#{hole_color}#{cell}\e[0m"
    end
  end

  # a hole, that is beeing currently played
  def get_hole_color_active hole, good, was_good, was_good_since
    if !hole
      "\e[2m"
    elsif good || (was_good && (Time.now.to_f - was_good_since) < 0.5)
      if $hole2flags[hole].include?(:main)
        "\e[92m"
      else
        "\e[94m"
      end
    elsif was_good && (Time.now.to_f - was_good_since) < 1
      if $hole2flags[hole].include?(:main)
        "\e[32m"
      else
        "\e[34m"
      end
    elsif was_good
      "\e[33m"
    else
      "\e[31m"
    end
  end

  # a hole, that is not played
  def get_hole_color_inactive hole, bright = false
    if $all_scales_holes.include?(hole)
      if $hole2flags[hole].include?(:main)
        $hole2flags[hole].include?(:root) ? "\e[1m\e[92m" : "\e[32m"
      else
        bright ? "\e[94m" : "\e[34m"
      end
    else
      "\e[2m"
    end
  end

  def get_dim_hline
    "\e[2m" + ( '-' * ( $term_width * 0.5 )) + "\e[0m"
  end

  def print_in_columns names, indent: 2, pad: :space, highlight: nil, lowlights: nil
    raise 'Internal error: highlight and lowlights are both given' if highlight and lowlights

    head = ' ' * indent
    line = ''
    lowl_at = if lowlights
                (0...names.length).to_a.select {|idx| lowlights.include?(names[idx])}
              else
                []
              end
    padded_names = case pad
                   when :tabs
                     names.map {|nm| ' ' + nm + ' '}
                          .map {|nm| nm + ' ' * (-nm.length % 4)}
                   when :long_tabs
                     names.map {|nm| ' ' + nm + ' '}
                          .map {|nm| nm + ' ' * (-nm.length % 8)}
                   when :space
                     names.map {|nm| '  ' + nm}
                   when :fill
                     names_maxlen = names.max_by(&:length).length
                     names.map {|nm| '  ' + ' ' * (names_maxlen - nm.length) + nm}
                   else
                     raise "Internal error, unknown padding type: #{pad}"
                   end
    padded_names.each_with_index do |nm, idx|
      if (head + line + nm).length > $term_width - 4
        line = highlight_helper(line, highlight)
        puts head + line.strip
        line = ''
      end
      line += if lowl_at.include?(idx)
                "\e[0m\e[31m#{nm}\e[0m"
              else
                nm
              end
    end
    line = highlight_helper(line, highlight)
    puts head + line.strip unless line.strip.empty?
  end

  def wrap_words head, words, sep = ',', width: $term_width
    line = head
    lines = Array.new
    words.each_with_index do |word, idx|
      if line.length + sep.length + word.length >= width - 1
        lines << line.rstrip
        line = (' ' * head.length) + word
      else
        line += sep unless idx == 0
        line += word
      end
    end
    lines << line.rstrip unless line.rstrip == ''
    lines.join("\n")
  end

  def wrap_text text, term_width: nil, cont: ' ...'
    line = ''
    lines = Array.new
    term_width ||= $term_width
    term_width = $term_width + term_width if term_width < 0
    cont_len = cont&.length || 0
    # keeps the spaces in tokens
    text.split(/( +)/).each_with_index do |token, _idx|
      if line.length + token.length > term_width - 2 - cont_len
        lines << line.strip
        line = token.strip
      else
        line += token
      end
    end
    lines << line.strip unless line.strip == ''
    lines[0..-2].each {|l| l << cont } if cont_len > 0
    lines
  end

  def truncate_colored_text text, len = nil
    # cannot use default for argument, because we allow beeing called with one
    # argument only
    len ||= $term_width - 4
    text = text.dup
    ttext = ''
    tlen = 0
    begin
      if md = text.match(/^(\e\[[\d;,]+m)(.*)$/)
        # escape-sequence: just copy into ttext but do not count in tlen
        ttext += md[1]
        text = md[2]
      elsif md = text.match(/^\e/)
        raise 'Internal error: Unknown escape'
      else
        # no escape a start, copy upto next escape to ttext and count
        md = text.match(/^([^\e]*)/)
        ttext += md[1][0, len - tlen]
        tlen += md[1].length
        text[0, md[1].length] = ''
      end
    end while text.length > 0 && tlen < len
    ttext += ' ...' if tlen >= len
    ttext
  end

  def truncate_text text, len = $term_width - 5
    if text.length > len
      text[0, len] + ' ...'
    else
      text
    end
  end

  def animate_splash_line single_line = false, as_string: false
    return nil if $splashed

    print "\e[J"
    printed = ''
    unless single_line
      3.times do
        puts
        sleep 0.08
      end
      print "\e[A\e[A"
    end
    if $testing
      testing_clause = "\e[0;101mWARNING: env HARPWISE_TESTING is set!\e[0m"
      printed = testing_clause
      if single_line
        print testing_clause
      else
        puts testing_clause
        printed += "\n"
      end
      sleep 0.3
    else
      print "\e[0m\e[2m" + ('| ' * 10) + "|\e[1G"
      sleep 0.08
      print "\e[0m|\e[92m~\e[0m|\e[3D"
      sleep 0.04
      printed += "\e[0m\e[2m|"
      text = '~HARPWISE~'
      text.each_char.each_cons(2) do |c1, c2|
        print "\e[0m\e[2m|\e[0m\e[32m#{c1}\e[0m|\e[0m\e[1m\e[92m#{c2}\e[0m|\e[3D"
        printed += "\e[0m\e[32m#{c1}\e[0m\e[2m|"
        sleep 0.04
      end
      printed += "\e[0m\e[32m#{text[-1]}\e[0m\e[2m|\e[0m"
      print "\e[0m\e[2m|\e[0m\e[32m~\e[0m\e[2m|\e[0m"
      puts unless single_line
      sleep 0.04
      if single_line
        print '  '
        ($version + ' ').each_char.each_cons(2) do |c1, c2|
          print "\e[0m\e[2m#{c1}\e[0m\e[1m#{c2}\e[0m\e[D"
          sleep 0.01
        end
        print '  '
        printed += '  '
      else
        puts "\e[2m#{$version}\e[0m"
        printed += "\n"
      end
      sleep 0.2
      printed += "\e[2m#{$version}\e[0m"
    end
    puts unless single_line
    sleep 0.04
    $splashed = true
    return printed
  end

  def puts_underlined text, char = '=', dim: :auto, vspace: :auto
    puts "\e[" +
         if dim == :auto
           char == '=' ? '0' : '2'
         elsif dim
           '2'
         else
           '0'
         end + 'm' + text
    puts char * text.length
    print "\e[0m"
    puts if ( vspace == :auto && char == '=' ) || vspace == true
  end

  def highlight_helper text, highlight
    # do highlight and count their number
    if highlight
      text.gsub(highlight[:what]) do |m|
        highlight[:count] += 1
        "\e[0m\e[7m\e[92m" + m + "\e[0m"
      end || text
    else
      text
    end
  end

  def tabify_plain holes, dense = false
    text = ''
    cell_len = $harp_holes.map {|h| h.length}.max + 2
    holes.each_slice(10) do |slice|
      text += slice.map do |hole|
        hole.rjust(cell_len)
      end.join + (dense ? "\n" : "\n\n")
    end
    text
  end

  def tabify_colorize max_lines, holes_etc, idx_first_active
    lines = Array.new
    max_cell_len = holes_etc.map {|he| he.map(&:length).sum + 2}.max
    per_line = (($term_width * 0.8 - 4) / max_cell_len).truncate
    line = '   '
    holes_etc.each_with_index do |hole_etc, idx|
      if idx > 0 && idx % per_line == 0
        lines << line
        lines << ''
        line = '   '
      end
      mb_w_dot = if hole_etc[2].strip.length > 0
                   '.' + hole_etc[2]
                 else
                   ' '
                 end
      line += " \e[0m" +
              if idx < idx_first_active
                ' ' + "\e[0m\e[2m" + hole_etc[0] + hole_etc[1] + mb_w_dot
              else
                hole_etc[0] +
                if idx == idx_first_active
                  "\e[0m\e[92m*"
                else
                  ' '
                end + ( "\e[0m" + Text::get_hole_color_inactive(hole_etc[1], true) +
                          hole_etc[1] + "\e[0m\e[2m" + mb_w_dot )
              end
    end
    lines << line
    lines << ''
    lines = lines.select {|l| l.length > 0} if lines.length > max_lines
    if lines.length > max_lines
      lines = lines[0..max_lines - 1]
      lines[-1] = lines[-1].ljust(per_line)
      lines[-1][-6..-1] = "\e[0m  ... "
    end
    lines[-1] += "\e[0m"
    lines
  end

  def tabify_hl max_lines, holes, idx_hl = nil
    lines = Array.new
    lines << "\e[K"
    cell_len = $harp_holes.map {|h| h.length}.max + 2
    per_line = (($term_width * 0.9 - 4) / cell_len).truncate
    per_line -= 1 if per_line.odd?
    to_del = 0
    line = ''
    holes.each_with_index do |hole, idx|
      if idx > 0 && idx % per_line == 0
        lines << line + "\e[K"
        lines << "\e[K"
        line = ''
      end
      line += (  hole['('] || idx_hl ? "\e[2m" : "\e[0m" ) +
              ( idx == idx_hl ? "\e[0m\e[32m" : '') +
              hole.rjust(cell_len) +
              "\e[0m"
    end
    lines << line + "\e[K"
    lines << "\e[K"
    lines = lines.select {|l| l != "\e[K"} if lines.length > max_lines
    if lines.length > max_lines
      lines.shift
      to_del = per_line
    end
    [lines, to_del]
  end
end
