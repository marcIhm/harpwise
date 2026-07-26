
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
    return if $splashed

    print "\e[J"
    unless single_line
      3.times do
        puts
        sleep 0.08
      end
      print "\e[A\e[A"
    end
    if $testing
      testing_clause = "\e[0;101mWARNING: env HARPWISE_TESTING is set!\e[0m"
      if single_line
        print testing_clause
      else
        puts testing_clause
      end
      sleep 0.3
    else
      version_clause = "\e[2m#{$version}\e[0m"
      print "\e[0m\e[2m" + ('| ' * 10) + "|\e[1G"
      sleep 0.08
      print "\e[0m|\e[92m~\e[0m|\e[3D"
      sleep 0.04
      '~HARPWISE~'.each_char.each_cons(2) do |c1, c2|
        print "\e[0m\e[2m|\e[0m\e[32m#{c1}\e[0m|\e[0m\e[1m\e[92m#{c2}\e[0m|\e[3D"
        sleep 0.04
      end
      print "\e[0m\e[2m|\e[0m\e[32m~\e[0m\e[2m|\e[0m"
      puts unless single_line
      sleep 0.04
      if single_line
        print '  ' + version_clause + '  '
      else
        puts version_clause
      end
      sleep 0.2
    end
    puts unless single_line
    sleep 0.04
    $splashed = true
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
end
