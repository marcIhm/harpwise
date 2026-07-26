
module Choose
  extend self

  #
  # These functions and variables need to be in accord about the sematics
  # of indexing into their respective arrays of names:
  #
  # choose_interactive: index is in the array of currently matching
  # names, ignoring frame_start
  #
  # print_in_columns: index is in the current frame of matching
  # names plus more-marker (added to front, if any)
  #
  # $choose_loc_cache, move_loc: index is similar to that of
  # print_in_columns but never includes the more-marker
  #
  def choose_interactive prompt, names, &block
    prompt_orig = prompt
    names.uniq!
    Interact::clear_area_comment
    Interact::clear_area_message
    $choose_more_text = '...more'
    raise "Internal error: one of the passed names contains reserved string '#{$choose_more_text}: #{names}" if names.include?($choose_more_text)

    Interact::handle_win_change if $ctl_sig_winch

    $choose_padding = if names.map(&:length).sum / names.length > 10 ||
                       names.any? {|name| name[' ']}
                      '  '
                    else
                      ' '
                    end

    $choose_total_chars = padded(names).join.length
    prompt_template = "\e[%dH\e[0m%s \e[K"
    help_template = "\e[%dH\e[2many char or cursor keys to select, ? for help and full item-desc"
    print prompt_template % [$lines[:comment_tall] + 1, prompt]
    $choose_no_matches_text = nil
    print help_template % ( $lines[:comment_tall] + 2 )

    frame_start = 0
    frame_start_was = Array.new
    idx_hili_min = idx_hili = idx_helper(names, frame_start)

    input = ''
    matching = names
    idx_last_shown = print_in_columns(matching, frame_start, idx_hili, input)
    print desc_helper(matching[idx_hili], block) if block_given? && matching[idx_hili]
    loop do
      key = if $ctl_sig_winch
              Interact::handle_win_change
              'CTRL-L'
            else
              $ctl_kb_queue.deq
            end
      key.downcase! if key.length == 1

      if key == '?'
        Interact::clear_area_comment
        Interact::clear_area_message
        offset = ( $term_height - $lines[:comment_tall] > 8 ? 1 : 0 )
        print "\e[#{$lines[:comment_tall] + offset}H\e[0m"
        puts "Help on selecting:\e[32m   Just type  -or-  use cursor keys:"
        puts ' - Any char adds to search, which narrows choices'
        puts ' - Cursor keys move selection, CTRL-L redraws'
        puts ' - RETURN accepts, ESC aborts'
        puts " - TAB and S-TAB go to next/prev page if '...more'"
        print "\e[0mBottom line shows description of choices"
        print "\e[2m; full desc\e[2m for \e[0m#{matching[idx_hili]}\e[2m is '#{block.call(matching[idx_hili])}'" if block_given? && matching[idx_hili]
        print "\e[0m\e[32m ... #{$resources[:any_key]}\e[0m"
        $ctl_kb_queue.deq
        Interact::clear_area_comment
        Interact::clear_area_message

      elsif key.match?(/^[[:print:]]$/)
        if (prompt + input).length > $term_width - 4
          prompt = '(...): '
          input += key if (prompt + input).length <= $term_width - 4
        else
          prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
          input += key
        end
        matching = names.select {|n| n.downcase[input]}
        frame_start = idx_hili = idx_hili_min = 0
        frame_start_was = Array.new

      elsif key == 'BACKSPACE'
        input[-1] = '' if input.length > 0
        matching = names.select {|n| n[input]}
        idx_hili = idx_hili_min
        prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
        $choose_no_matches_text = nil

      elsif key == 'CTRL-BACKSPACE'
        input = '' if input.length
        matching = names
        idx_hili = idx_hili_min
        prompt = prompt_orig
        $choose_no_matches_text = nil

      elsif %w[LEFT RIGHT UP DOWN].include?(key)
        idx_hili = move_loc(idx_hili, key,
                            idx_hili_min,
                            idx_last_shown,
                            frame_start)

      elsif key == 'RETURN'

        if matching.length == 0
          $choose_no_matches_text = "\e[0;101m NO MATCHES! \e[0m Please shorten input '#{input}' above or type ESC to abort!"

        elsif matching[idx_hili][0] == ';'
          Interact::clear_area_comment(2)
          Interact::clear_area_message
          print "\e[#{$lines[:comment_tall] + 4}H\e[0m\e[2m  '#{matching[idx_hili]}'\e[0m is a comment, please choose another item."
          print "\e[#{$lines[:comment_tall] + 5}H\e[0m\e[2m    #{$resources[:any_key]}\e[0m"
          $ctl_kb_queue.deq

        else
          Interact::clear_area_comment
          Interact::clear_area_message
          print "\e[0m"
          return matching[idx_hili]
        end

      elsif key == 'CTRL-L'
        print "\e[2J"
        print prompt_template % [$lines[:comment_tall] + 1, prompt]
        print "\e[0m\e[92m#{input}\e[0m\e[K"
        print help_template % ( $lines[:comment_tall] + 2 )

      elsif key == 'ESC'
        Interact::clear_area_comment
        Interact::clear_area_message
        print "\e[0m"
        return nil

      elsif key == 'TAB'
        if idx_last_shown < matching.length - 1
          frame_start_was << frame_start
          frame_start = idx_last_shown + 1
          idx_hili_min = idx_hili = idx_helper(matching, frame_start)
        end

      elsif key == 'SHIFT-TAB'
        if frame_start > 0
          frame_start = frame_start_was.pop || 0
          idx_hili_min = idx_hili = idx_helper(matching, frame_start)
        end
      end

      print prompt_template % [$lines[:comment_tall] + 1, prompt]
      print "\e[0m\e[92m#{input}\e[0m\e[K"
      print help_template % ( $lines[:comment_tall] + 2 )

      idx_last_shown = print_in_columns(matching, frame_start, idx_hili, input)

      print desc_helper(matching[idx_hili], block) if block_given? && matching[idx_hili]
    end
  end
  
  def idx_helper names, frame_start
    # leave out initial '...more' if present (although it will only be
    # added later in print_in_columns)
    idx_hili = ( frame_start > 0 ? frame_start : 0 )
    idx_hili += 1 while names[idx_hili][0] == ';'
    idx_hili
  end

  def print_in_columns names, frame_start, idx_hili, input
    lines_offset = ( $choose_total_chars > $term_width * 3 ? 3 : 4)
    print "\e[#{$lines[:comment_tall] + lines_offset}H\e[0m\e[2m"
    # x,y-pairs of elements shown in most recent call of
    # print_in_columns; never contains '...more'
    $choose_loc_cache = Array.new
    max_lines = $lines[:hint_or_message] - $lines[:comment_tall] - 4
    # idx2cidx: index to caller index (this functions semantics of)
    idx2cidx = if frame_start > 0
                 names = [$choose_more_text + ' '] + names[frame_start..-1]
                 frame_start - 1
               else
                 0
               end
    cidx2idx = -idx2cidx
    idx_last_shown = names.length - 1
    idx_hili += cidx2idx

    # General processing: prepare array and print it over existing lines
    # to avoid flicker
    lines = (0..max_lines).map {|_x| ''}
    if names.length == 0
      Interact::clear_area_comment(2)
      lines[0] = '  ' + ( $choose_no_matches_text || "\e[0mNO MATCHES for input '#{input}' above, please shorten ..." )
    else
      has_more_above = false
      lines_count = 0
      line_was = nil
      line = '  '
      padded(names).each_with_index do |name, idx|
        break if lines_count > max_lines

        has_more = ( name == $choose_more_text )
        if (line + name).length > $term_width - 4
          if lines_count == max_lines && idx < names.length - 1
            # this is the last line; we cannot output the current
            # element, so we overwrite even the previous one to tell
            # about this
            line = line_was + ' ' + $choose_more_text
            $choose_loc_cache.pop
            idx_last_shown = idx - 2
            has_more = has_more_above = true
          end
          # finish line
          lines[lines_count] = line_helper(line)
          lines_count += 1
          line_was = line
          line = '  '
        end
        $choose_loc_cache << [line.length, lines_count] unless has_more
        # insert markers {[]} for later highlighting
        line[-1] = ( name[0] == ';' ? '{' : '[' ) if idx == idx_hili
        line_was = line
        line += name
        line[line.rstrip.length] = ( name[0] == ';' ? '}' : ']' )  if idx == idx_hili
      end
      # output any line, that has not yet been finished
      lines[lines_count] = line_helper(line) unless has_more_above || line.strip.empty?
    end

    lines.each_with_index do |line, idx|
      print "\e[#{$lines[:comment_tall] + lines_offset + idx}H#{line}\e[K"
    end
    idx_last_shown + idx2cidx
  end

  def line_helper line
    line.gsub('[', " \e[0m\e[32m\e[7m").gsub(']', "\e[0m\e[2m ")
      .gsub('{', " \e[0m\e[2m\e[7m").gsub('}', "\e[0m\e[2m ")
  end

  def desc_helper text, block
    "\e[#{$lines[:message_bottom]}H\e[0m" +
      if text[0] == ';'
        "\e[2m" + 'This is a comment and cannot be chosen ...'
      else
        "\e[32m" +
          Text::truncate_text( block ? block.call(text) : text )
      end +
    + "\e[0m\e[K"
  end

  def move_loc idx_hili_old, dir, idx_hili_min, idx_last_shown, frame_start
    return idx_hili_old if $choose_loc_cache.length == 0

    # idx2cidx: index to caller index (this functions semantics of)
    idx2cidx = ( frame_start > 0 ? frame_start : 0 )
    cidx2idx = -idx2cidx
    idx_hili_old += cidx2idx
    idx_hili_min += cidx2idx
    idx_last_shown += cidx2idx

    column_old, line_old = $choose_loc_cache[idx_hili_old]
    line_max = $choose_loc_cache[-1][1]

    if dir == 'LEFT'
      idx_hili_new = idx_hili_old - 1

    elsif dir == 'RIGHT'
      idx_hili_new = idx_hili_old + 1

    elsif dir == 'UP'
      idx_hili_new = idx_hili_old
      if line_old > 0
        line_new = line_old - 1
        $choose_loc_cache[0..idx_hili_old].each_with_index do |pos, idx_of_this|
          column_of_this, line_of_this = pos
          next unless line_of_this == line_new

          column_of_next, line_of_next = $choose_loc_cache[idx_of_this + 1]
          # keep updating until break below
          idx_hili_new = idx_of_this
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end

    elsif dir == 'DOWN'
      idx_hili_new = idx_hili_old
      if line_old < line_max
        # there is one line below, so try it
        line_new = line_old + 1
        # idx in loop below starts at 0
        $choose_loc_cache[idx_hili_old..idx_last_shown].each_with_index do |pos, idx|
          column_of_this, line_of_this = pos
          idx_of_this = idx_hili_old + idx
          next unless line_of_this == line_new

          # keep updating until break below
          idx_hili_new = idx_of_this
          # no further entries
          break if idx_of_this == idx_last_shown

          column_of_next, line_of_next = $choose_loc_cache[idx_of_this + 1]
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end
    end

    # wrap around from left to right and vice versa
    idx_hili_new = idx_last_shown if idx_hili_new < idx_hili_min
    idx_hili_new = idx_hili_min if idx_hili_new > idx_last_shown

    idx_hili_new + idx2cidx
  end

  def padded names
    names
      .map {|name| name + $choose_padding}
      .map {|name| name + ' ' * (-name.length % 8)}
  end

  def clean_up skip_term: false
    Interact::clear_area_comment
    Interact::clear_area_message
    Interact::make_term_cooked unless skip_term
    print "\e[#{$lines[:comment_tall] - 1}H\e[K"
  end

  def prepare_for skip_term: false
    Interact::prepare_term
    Interact::make_term_immediate unless skip_term
    $ctl_kb_queue.clear
    ($term_height - $lines[:comment_tall] + 2).times do
      sleep 0.01
      puts
    end
    print "\e[#{$lines[:comment_tall] - 1}H" + Text::get_dim_hline + "\e[0m"
  end
end
