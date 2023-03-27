# -*- fill-column: 78 -*-

#
# General helper functions
#

class Symbol
  def o2str
    self.to_s.gsub('_','-') if self
  end
end

class String
  def o2sym
    self.gsub('-','_').to_sym if self
  end

  def to_b
    case self
    when 'true'
      true
    when 'false'
      false
    else
      nil
    end
  end

  def empty2nil
    self.empty?  ?  nil  :  self
  end

  def num_or_str
    begin
      begin
        return Integer(self)
      rescue
        return Float(self)
      end
    rescue
      return self
    end
  end
end

def match_or cand, choices
  return unless cand
  exact_matches = choices.select {|c| c == cand}
  return exact_matches[0] if exact_matches.length == 1
  matches = choices.select {|c| c.start_with?(cand)}
  yield "'#{cand}'", choices.join(', ') + ' (or abbreviated uniquely)' if matches.length != 1
  matches[0]
end


def yaml_parse file
  begin
    YAML.load_file(file)
  rescue Psych::SyntaxError => e
    fail "Cannot parse #{file}: #{e} !"
  rescue Errno::ENOENT => e
    fail "File #{file} does not exist !"
  end
end


def comment_in_chart? cell
  return true if cell.count('-') > 1 || cell.count('=') > 1
  return true if cell.match?(/^[- ]*$/)
  return false
end


def err text
  raise ArgumentError.new(text) if $on_error_raise
  sane_term
  puts
  print "ERROR: #{text}"
  puts ' !' unless text['!']
  puts_err_context
  puts
  puts Thread.current.backtrace if $opts && $opts[:debug]
  exit 1
end


def puts_err_context
  clauses = [:mode, :type, :key, :scale].map do |var|
      val = if $err_binding && eval("defined?(#{var})",$err_binding)
              eval("#{var}", $err_binding)
            elsif eval("defined?($#{var})")
              eval("$#{var}")
            else
              nil
            end
      val  ?  "#{var}=#{val}"  :  "#{var} is not set"  
  end.select(&:itself)
  puts
  puts "(result of argument processing so far: #{clauses.join(', ')})" if clauses.length > 0
  puts "(config from #{$early_conf[:config_file]} and #{$early_conf[:config_file_user]})" if $early_conf
end


def file2scale file, type = $type
  %w(holes notes).each do |what|
    parts = ($scale_files_template % [type, '|', what]).split('|')
    return file[parts[0].length .. - parts[1].length - 1] if file[parts[1]]
  end
end


def scales_for_type type
  Dir[$scale_files_template % [type, '*', '{holes,notes}']].map {|file| file2scale(file,type)}.sort
end


def display_kb_help what, first_round, body
  if first_round
    puts "\n\n\e[0m"
  else
    clear_area_comment
    puts "\e[#{$lines[:help]}H\e[0m"
  end
  puts "Keys available while playing a #{what}:\e[0m\e[32m\n"
  body.lines.each {|l| puts '      ' + l.chomp + "\n"}
  print "\e[0mPress any key to continue ..."
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
  if first_round
    puts "\n\e[0m\e[2mcontinue\e[0m"
  else
    clear_area_comment
    ctl_response 'continue'
  end
end


def write_hole_to_journal hole, since
  IO.write($journal_file,
           "%6.1f %8s %4s\n" % [ Time.now.to_f - since,
                                 hole,
                                 $harp[hole][:note]],
           mode: 'a')
  $journal_listen << hole
end


def journal_start
  text = if $journal_started_count == 0
           "\n;; Start journal at #{Time.now}, key of #{$key}\n" +
             if $mode == :listen
               ";; Columns: duration, hole, note\n\n"
             else
               "\n"
             end
         else
           "\n;; Start #{Time.now.strftime('%T')}\n"
         end
  $journal_started_count += 1
  IO.write($journal_file, text, mode: 'a')
end


def journal_stop
  IO.write($journal_file, "\n;; Stop journal at #{Time.now}\n\n", mode: 'a')
end


def truncate_colored_text text, len
  ttext = ''
  tlen = 0
  trunced = ''
  begin
    if md = text.match(/^(\e\[\d+m)(.*)$/)
      # escape-sequence: just copy into ttext but do not count in tlen
      ttext += md[1]
      text = md[2]
    elsif md = text.match(/^\e/)
      fail "Internal error: Unknown escape"
    else
      # no escape a start, copy to ttext and count
      md = text.match(/^([^\e]+)/)
      ttext += md[1][0,len - tlen]
      tlen += md[1].length
      text[0,md[1].length] = ''
    end
  end while text.length > 0 && tlen < len
  ttext += ' ...' if tlen >= len
  return ttext
end


def truncate_text text, len
  if text.length > len
    text[0,len] + ' ...'
  else
    text
  end
end


def dbg # prepare byebug
  make_term_cooked
  print "\e[0m"
  require 'byebug'
  byebug
end


def write_dump marker
  dumpfile = '/tmp/' + File.basename($0) + "_testing_dumped_#{marker}.json"
  File.delete(dumpfile) if File.exists?(dumpfile)
  structure = {scale: $scale, scale_holes: $scale_holes, licks: $licks, opts: $opts, conf: $conf, conf_system: $conf_system, conf_user: $conf_user, key: $key, }
  File.write(dumpfile, JSON.pretty_generate(structure))
end


def print_mission text
  print "\e[#{$lines[:mission]}H\e[0m#{text.ljust($term_width - $ctl_response_width)}\e[0m"
end


def print_in_columns names
  line = '  '
  names.
    map {|nm| nm + ' '}.
    map {|nm| nm + ' ' * (-nm.length % 8)}.each do |nm|
    if (line + nm).length > $term_width - 4
      puts line
      line = '  '
    end
    line += nm
  end
  puts line unless line.strip.empty?
end


def holes_equiv? h1,h2
  if h1.is_a?(String) && h2.is_a?(String)
    h1 == h2 || $harp[h1][:equiv].include?(h2)
  else
    false
  end
end


def print_debug_info
  puts "\e[#{$lines[:message2]}H\e[0m\n\n\n"
  puts '$quiz_sample_stats:'
  pp $quiz_sample_stats
  if $perfctr[:handle_holes_this_loops] > 0
    $perfctr[:handle_holes_this_loops_per_second] = $perfctr[:handle_holes_this_loops] / ( Time.now.to_f - $perfctr[:handle_holes_this_started] )
  end
  puts '$perfctr:'
  pp $perfctr
  puts '$freqs_queue.length:'
  puts $freqs_queue.length    
end

def print_lagging_info
  puts "\e[#{$lines[:message2]}H\e[0m\n\n\n"
  puts
  puts <<~end_of_content

         harpwise has been lagging behind at least once;
         #{$lagging_freqs_lost} of #{$lagging_freqs_lost + $total_freqs} samples #{'(= %.1f%%)' % (100 * $lagging_freqs_lost / ($lagging_freqs_lost + $total_freqs))} have been lost.

         If you notice such a lag frequently and and want to reduce it, 
         you may try to increase option '--time-slice' or config
         'time_slice' from its default of #{$opts[:time_slice]} to something larger.
         (See config file #{$conf[:config_file_user]} 
          and usage info for more details.)

         Note however, that increasing this value too far, may make
         harpwise sluggish in sensing holes.

         end_of_content
    puts
end


def animate_splash_line single_line = false
  print "\e[J"
  puts unless single_line
  if $testing
    testing_clause = "\e[0;101mWARNING: env HARPWISE_TESTING is set !\e[0m"
    if single_line
      print testing_clause
    else
      puts testing_clause
    end
    sleep 0.3
  else
    print "\e[0m\e[2m" + ('| ' * 10) + "|\e[1G|"
    '~HARPWISE~'.each_char do
      |c| print "\e[0m\e[32m#{c}\e[0m\e[2m|\e[0m"
      sleep 0.04
    end
    puts unless single_line
    sleep 0.01
    version_clause = "\e[2m#{$version}\e[0m"
    if single_line
      print '  ' + version_clause + '  '
    else
      puts version_clause
    end
    sleep 0.2
  end
  puts unless single_line
  sleep 0.01
end


def get_journal_file
  if $mode == :licks || $mode == :play || $mode == :report
    # modes licks and play both play random licks and report needs to read them
    "#{$dirs[:data]}/journal_#{$type}_modes_licks_and_play.txt"
  else
    "#{$dirs[:data]}/journal_#{$type}_mode_#{$mode}.txt"
  end
end

#
# Volumes for sox
#

class Volume
  @@vols = nil
  def initialize(tag, vol)
    unless @@vols
      $pers_data['volume'] ||= Hash.new
      @@vols = $pers_data['volume']
    end
    @tag = tag
    # keep volume from last run of harpwise, if it is lower than default
    @@vols[@tag] = vol unless @@vols[@tag] && @@vols[@tag] < vol
    confine
  end

  def confine
     @@vols[@tag] = 12 if @@vols[@tag] >= 12
     @@vols[@tag] = -24 if @@vols[@tag] <= -24
  end

  def inc
    @@vols[@tag] += 3
    confine
  end
  
  def dec
    @@vols[@tag] -= 3
    confine
  end

  def db
    return "%+ddB" % @@vols[@tag]
  end

  def clause
    return ( @@vols[@tag] == 0  ?  ''  :  ('vol %ddb' % @@vols[@tag]) )
  end
end


def cplread_one_of prompt, names
  prompt_orig = prompt
  names.uniq!
  prompt_template = "\e[#{$lines[:comment_tall]}H\e[0m%s\e[J"
  help_text = "\e[#{$lines[:comment_tall] + 1}H\e[0m\e[2m(type to narrow; cursor keys to move; BACKSPACE,RETURN,ESC,ctrl-l as usual)\e[J"
  print prompt_template % prompt
  print help_text
  $column_short_hint_or_message = 1
  $cplread_loc_cache = nil
  $cplread_no_matches = nil
  idx_hl = 0
  idx_hl += 1 while names[idx_hl][';']
    
  input = ''
  matching = names
  idx_last_shown = cplread_print_in_columns(names, idx_hl)
  loop do
    key = $ctl_kb_queue.deq.downcase
    if key.match?(/^[[:print:]]$/)
      if (prompt + input).length > $term_width - 4
        prompt = '(...): '
        input += key if (prompt + input).length <= $term_width - 4
      else
        prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
        input += key
      end
      matching = names.select {|n| n.downcase[input]} 
      idx_hl = 0
    elsif key.ord == 127
      input[-1] = '' if input.length > 0
      matching = names.select {|n| n[input]} 
      idx_hl = 0
      prompt = prompt_orig if (prompt_orig + input).length <= $term_width - 4
      $cplread_no_matches = nil
    elsif key.ord == 8
      input= '' if input.length
      matching = names
      idx_hl = 0
      prompt = prompt_orig
      $cplread_no_matches = nil
    elsif %w(left right up down).include?(key)
      idx_hl = cplread_move_loc(idx_hl, key, idx_last_shown)
    elsif key == "\n"
      if matching.length == 0
        $cplread_no_matches ="\e[0;101mNO MATCHES !\e[0m Please shorten input or type ESC to abort !"
      elsif matching[idx_hl][';']
        clear_area_comment(2)
        print "\e[#{$lines[:comment_tall] + 4}H\e[0m\e[34m  '#{matching[idx_hl]}'\e[0m is a comment, please choose another item."
        print "\e[#{$lines[:comment_tall] + 5}H\e[0m\e[2m    Press any key to continue ...\e[0m"
        $ctl_kb_queue.deq
        clear_area_comment(2)        
      else
        clear_area_comment
        return matching[idx_hl]
      end
    elsif key.ord == 12
      print "\e[2J"
      handle_win_change
      print prompt_template % prompt
      print "\e[0m\e[32m#{input}\e[0m\e[K"
      print help_text
      cplread_print_in_columns(matching, idx_hl)
    elsif key == "\e"
      clear_area_comment
      return nil
    end
    print prompt_template % prompt
    print "\e[0m\e[32m#{input}\e[0m\e[K"
    print help_text
    idx_last_shown = cplread_print_in_columns(matching, idx_hl)
  end
end


def cplread_print_in_columns names, idx_hl
  print "\e[#{$lines[:comment_tall] + 2}H\e[0m\e[2m"
  $cplread_loc_cache = Array.new
  if names.length == 0
    clear_area_comment(2)
    print "\e[#{$lines[:comment_tall] + 4}H\e[0m  " + ( $cplread_no_matches || 'No matches, please shorten input ...' )

    return 0 
  else
    lns = 0
    max_lns = $lines[:hint_or_message] - $lines[:comment_tall] - 3
    idx_last_shown = names.length - 1
    line = '  '
    wrote_more = false
    names.
      map {|nm| nm + ' '}.
      map {|nm| nm + ' ' * (-nm.length % 8)}.each_with_index do |nm,idx|
      break if lns > max_lns
      if (line + nm).length > $term_width - 4
        if lns == max_lns && idx < names.length - 1
          # we cannot output the current element, so we overwrite event the
          # previous one to tell about this
          text_more = ' ... more'
          line[-text_more.length ..] = text_more
          $cplread_loc_cache.pop
          idx_last_shown = idx - 2
          wrote_more = true
        end
        # we know that we have reached the end, so we output our line
        puts cplread_line_helper(line)
        lns += 1
        line = '  '
      end
      $cplread_loc_cache << [line.length, lns] unless wrote_more
      line[-1] = (nm[';'] ? '{' : '[') if idx == idx_hl
      line += nm
      line[line.rstrip.length] = (nm[';'] ? '}' : ']')  if idx == idx_hl
    end
    # only output, if not already done above
    puts cplread_line_helper(line) unless wrote_more || line.strip.empty?
    (max_lns - lns).times {puts "\e[K\n"}

    return idx_last_shown
  end
end


def cplread_line_helper line
  line.gsub('['," \e[0m\e[32m\e[7m").gsub(']', "\e[0m\e[2m ").
    gsub('{'," \e[0m\e[34m\e[7m").gsub('}',"\e[0m\e[2m ") + "\e[K"
end


def cplread_move_loc idx_old, dir, idx_last_shown
  column_old, line_old = $cplread_loc_cache[idx_old]
  line_max = $cplread_loc_cache[-1][1]
  if dir == 'left'
    idx_new = idx_old - 1
  elsif dir == 'right'
    idx_new = idx_old + 1
  elsif dir == 'up'
    idx_new = idx_old
    if line_old > 0 
      line_new = line_old - 1
      $cplread_loc_cache[0 .. idx_old].each_with_index do |pos, idx_of_this|
        column_of_this, line_of_this = pos
        if line_of_this == line_new
          column_of_next, line_of_next = $cplread_loc_cache[idx_of_this + 1]
          # keep updating until break below
          idx_new = idx_of_this
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end
    end
  elsif dir == 'down'
    idx_new = idx_old
    if line_old < line_max
      # there is one line below, so try it
      line_new = line_old + 1
      # idx in loop below stats at 0
      $cplread_loc_cache[idx_old .. idx_last_shown ].each_with_index do |pos, idx|
        column_of_this, line_of_this = pos
        idx_of_this = idx_old + idx
        if line_of_this == line_new
#          dbg
          # keep updating until break below
          idx_new = idx_of_this
          # no further entries
          break if idx_of_this == idx_last_shown
          column_of_next, line_of_next = $cplread_loc_cache[idx_of_this + 1]
          # next item is already on different line
          break if line_of_next != line_of_this
          # next item is more distant columnwise than current
          break if (column_of_this - column_old).abs <= (column_of_next - column_old).abs
        end
      end
    end
  end
  # make sure to be in range
  idx_new = [idx_new, 0].max
  idx_new = [idx_new, idx_last_shown ].min

  return idx_new
end


def report_error_wait_key etext
  clear_area_comment
  print "\e[#{$lines[:comment_tall]}H\e[J\n\e[0;101mAn error has happened:\e[0m\n"
  print etext
  print "\n\e[2mPress any key to continue ... \e[K"
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
end


def puts_underlined text
  puts text
  puts '=' * text.length
  puts
end
