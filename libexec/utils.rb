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

  def underscore
    self.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("-", "_").
      downcase
  end

end


def match_or cand, choices
  return unless cand
  cand = cand.to_s
  exact_matches = choices.select {|c| c == cand}
  return exact_matches[0] if exact_matches.length == 1
  head_matches = choices.select {|c| c.start_with?(cand)}
  yield("'#{cand}'",
        choices.join(', ') + ' (or abbreviated uniquely)',
        head_matches) if head_matches.length != 1
  head_matches[0]
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
  print "\e[0mERROR: #{text}"
  if $initialized
    puts
  else
    puts_err_context
  end
  puts
  puts Thread.current.backtrace if $opts && $opts[:debug]
  exit 1
end


def puts_err_context
  clauses = [:mode, :type, :key, :scale, :extra].map do |var|
      val = if $err_binding && eval("defined?(#{var})",$err_binding)
              eval("#{var}", $err_binding)
            elsif eval("defined?($#{var})")
              eval("$#{var}")
            else
              nil
            end
      if val
        "%-5s = #{val} (#{$source_of[var] || 'commandline'})" % var
      else
        "#{var} is not set"
      end
                                 
                                  
  end.select(&:itself)
  puts
  print "\e[0m\e[2m"
  print "\n(result of argument processing so far: "
  if clauses.length == 0
    puts 'none'
  else
    puts
    clauses.each_slice(2) do |slice|
      puts '  ' + slice.map {|x| '%-32s' % x}.join.strip
    end
  end
  if $early_conf
    puts " config from #{$early_conf[:config_file]}\n         and #{$early_conf[:config_file_user]})"
  else
    puts " early config has not yet been initialized)"
  end
  print "\e[0m"
end


def file2scale file, type = $type
  %w(holes notes).each do |what|
    parts = ($scale_files_template % [type, '|', what]).split('|')
    return file[parts[0].length .. - parts[1].length - 1] if file[parts[1]]
  end
end


def scales_for_type type
  Dir[$scale_files_template % [type, '*', '{holes,notes}']].map {|file| file2scale(file, type)}.sort
end


def describe_scales_maybe scales, type
  desc = Hash.new
  count = Hash.new
  scales.each do |scale|
    sfile = $scale_files_template % [type, scale, 'holes']
    begin 
      _, holes_rem = YAML.load_file(sfile).partition {|x| x.is_a?(Hash)}
      holes = holes_rem.map {|hr| hr.split[0]}
      desc[scale] = "holes #{holes.join(',')}"
      count[scale] = holes.length
    rescue Errno::ENOENT, Psych::SyntaxError
    end
  end
  [desc, count]
end


def display_kb_help what, scroll_allowed, body
  if scroll_allowed
    puts "\n\e[0m"
  else
    clear_area_comment
    puts "\e[#{$lines[:help]}H\e[0m"
  end
  puts "Keys available while playing #{what}:\e[0m\e[32m\n"
  maxlen = body.lines.map(&:length).max
  indent = ($term_width - maxlen) / 3
  indent = 2 if indent < 0
  body.lines.each do |l|
    puts ( ' ' * indent ) + l.gsub(/(\S+): /, "\e[92m\\1\e[32m: ").chomp + "\n"
  end
  print "\e[0m#{$resources[:any_key]}"
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
  if scroll_allowed
    puts "\n\e[0m\e[2mcontinue\e[0m"
    puts
  else
    clear_area_comment
    ctl_response 'continue'
  end
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


def truncate_text text, len = $term_width - 5
  if text.length > len
    text[0,len] + ' ...'
  else
    text
  end
end


# prepare byebug
def dbg 
  make_term_cooked if $opts
  Kernel::print "\e[0m"
  require 'byebug'
  byebug
end


def write_dump marker
  dumpfile = '/tmp/' + File.basename($0) + "_testing_dumped_#{marker}.json"
  File.delete(dumpfile) if File.exist?(dumpfile)
  structure = {scale: $scale, scale_holes: $scale_holes, licks: $licks, opts: $opts, conf: $conf, conf_system: $conf_system, conf_user: $conf_user, key: $key, messages_printed: $msgbuf.printed}
  File.write(dumpfile, JSON.pretty_generate(structure))
end


def print_mission text
  print "\e[#{$lines[:mission]}H\e[0m#{text.ljust($term_width - $ctl_response_width)}\e[0m"
  $ulrec.print_rec_sign_mb
end


def print_in_columns names, indent: 2, pad: :space
  head = ' ' * indent
  line = ''
  padded_names = case pad
                 when :tabs
                   names.map {|nm| ' ' + nm + ' '}.
                     map {|nm| nm + ' ' * (-nm.length % 4)}
                 when :space
                   names.map {|nm| '  ' + nm}
                 when :fill
                   names_maxlen = names.max_by(&:length).length
                   names.map {|nm| '  ' + ' ' * (names_maxlen - nm.length) + nm}
                 else
                   err "Internal error, unknown padding type: #{pad}"
                 end
  padded_names.each do |nm|
    if (head + line + nm).length > $term_width - 4
      puts head + line.strip
      line = ''
    end
    line += nm
  end
  puts head + line.strip unless line.strip.empty?
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
  if $perfctr[:handle_holes_this_first_freq]
    $perfctr[:handle_holes_this_loops_per_second] = $perfctr[:handle_holes_this_loops] / ( Time.now.to_f - $perfctr[:handle_holes_this_first_freq] )
  end
  puts '$perfctr:'
  pp $perfctr
  puts '$freqs_queue.length:'
  puts $freqs_queue.length    
end


def print_afterthought

  afterthought = ''

  if $lagging_freqs_lost > 0 && $total_freq_ticks > 0
    afterthought += <<~end_of_content


         Lagging detected !
         ------------------

         harpwise has been lagging behind at least once;
         #{$lagging_freqs_lost} of #{$lagging_freqs_lost + $total_freq_ticks} samples #{'(= %.1f%%)' % (100 * $lagging_freqs_lost / ($lagging_freqs_lost + $total_freq_ticks))} have been lost.

         If you notice such a lag frequently and and want to reduce it, you
         may try to set option '--time-slice' or config 'time_slice'
         (currently '#{$opts[:time_slice]}') to 'medium' or 'long'. See config file
         #{$conf[:config_file_user]}
         and usage info of harpwise for more details.

         Note however, that changing these values too far, may make
         harpwise sluggish in sensing holes.


         end_of_content
  end

  if $max_jitter > 0.2
    afterthought += <<~end_of_content


         Jitter detected !
         -----------------

         The frequency pipeline had a maximum jitter of #{'%.2f' % $max_jitter} secs, which
         happened #{(Time.now.to_f - $max_jitter_at).to_i} seconds ago, #{($max_jitter_at - $program_start).to_i} secs after program start.

         As a result your playing and its display by harpwise were out of sync
         at least once.

         This is probably out of control of harpwise and might be caused by
         external factors, like system-load or simply by hibernation of your
         computer.


         end_of_content

  end

  if afterthought.length > 0
    puts "\e[#{$lines[:message2]}H\e[0m\n" 
    afterthought.lines.each {|line| puts line.chomp + "\e[K\n"}
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
    testing_clause = "\e[0;101mWARNING: env HARPWISE_TESTING is set !\e[0m"
    if single_line
      print testing_clause
    else
      puts testing_clause
    end
    sleep 0.3
  else
    version_clause = "\e[2m#{$version}\e[0m"
    print "\e[0m\e[2m" + ('| ' * 10) + "|\e[1G|"
    '~HARPWISE~'.each_char do |c|
      print "\e[0m\e[32m#{c}\e[0m\e[2m|\e[0m"
      sleep 0.04
    end
    puts unless single_line
    sleep 0.01
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


def get_files_journal_trace
  trace = if $mode == :licks || $mode == :play || $mode == :print
            # modes licks and play both play random licks and report needs to read them
            "#{$dirs[:data]}/trace_#{$type}_modes_licks_and_play.txt"
          elsif $mode == :quiz
            "#{$dirs[:data]}/trace_#{$type}_mode_quiz.txt"
          else
            nil
          end
  return ["#{$dirs[:data]}/journal_#{$type}.txt", trace]
end


#
# Volumes for sox
#

class Volume
  # we keep this class var to make this a singleton
  @@vol = nil
  def initialize(vol)
    fail 'Internal error: Volume object has already been initialized' if @@vol
    @@vol = $pers_data['volume']
    # help for nil or for older formats (Hash)
    @@vol = vol unless [Float, Integer].include?(@@vol.class)
    # keep volume from last run of harpwise, if it is lower than default
    @@vol = vol unless @@vol < vol
    confine
  end

  def confine
     @@vol = 12 if @@vol >= 12
     @@vol = -24 if @@vol <= -24
     $pers_data['volume'] = @@vol
  end

  def inc
    @@vol += 3
    confine
  end
  
  def dec
    @@vol -= 3
    confine
  end

  def to_s
    return "%+ddB" % @@vol
  end

  def to_i
    return @@vol
  end
end


def puts_underlined text, char = '=', dim: :auto, vspace: :auto
  puts "\e[" +
       if dim == :auto
         char == '=' ? '0' : '2'
       elsif dim
         '2'
       else
         '0'
       end + "m" + text
  puts char * text.length
  print "\e[0m"
  puts if ( vspace == :auto && char == '=' ) || vspace == true
end


def switch_modes
  $ctl_mic[:switch_modes] = false
  mode_prev = $mode
  $mode = ($modes_for_switch - [$mode])[0]
  $mode_switches += 1

  if $mode_switches == 1
    # switching the first time to a new mode so we need to save initial
    # config; later we just switch back and forth between these configs
    $other_mode_saved[:conf] = $conf.clone
    $other_mode_saved[:opts] = $opts.clone
  end

  # switch configs
  $conf, $other_mode_saved[:conf] = $other_mode_saved[:conf], $conf
  $opts, $other_mode_saved[:opts] = $other_mode_saved[:opts], $opts

  if $mode_switches == 1
    # switching the first time to a new mode; make some guesses on its
    # arguments, that could have never been given on the commandline
    if $mode == :listen && [:quiz, :licks].include?(mode_prev)
      $opts[:no_progress] = false
      $opts[:comment] = :note
    elsif $mode == :licks && [:listen].include?(mode_prev)
      $opts[:comment] = :holes_notes
      $opts[:iterate] = :random
      $opts[:tags_any] = 'journal' if $journal.select {|h| !musical_event?(h)}.length > 0
    else
      err "Internal error: invalid mode switch #{mode_prev} to #{$mode}"
    end
  end

  # Prepare conditions similar to program start; reset some flags and
  # recalculate things, that are mode-dependant
  
  $lines = calculate_screen_layout
  $first_round_ever_get_hole = true
  
  $journal_file, $trace_file = get_files_journal_trace
  $journal_all = false
  
  clear_area_comment
  clear_area_message

  # animate
  print "\e[#{$lines[:comment_tall] + 1}H\e[0m\e[#{$mode == :listen ? 34 : 32}m"
  do_figlet_unwrapped "> > >   #{$mode}", 'smblock'
  tag = "switch to #{$mode}"
  sleep( $messages_seen[tag]  ?  0.5  :  1 )
  $messages_seen[tag] = 1

  $mode_start = Time.now.to_f
  $freqs_queue.clear

end


def edit_file file, lno = nil
  print "\e[#{$lines[:hint_or_message]}H\e[0m\e[32mEditing \e[0m\e[2m#{file} with: \e[0m#{$editor}\e[k"
  stime = $messages_seen[file]  ?  0.5  :  1
  $messages_seen[file] = true
  sleep stime
  print "\e[#{$lines[:message2]}H\e[K"
  make_term_cooked
  if system($editor + ' ' + (lno ? "+#{lno}" : '') + ' ' + file)
    make_term_immediate
    print "\e[#{$lines[:hint_or_message]}H\e[0m\e[32mEditing done.\e[K"
    sleep stime
    return true
  else
    make_term_immediate
    puts "\e[0;101mEDITING FAILED !\e[0m\e[k"
    puts "#{$resources[:any_key]}\e[K"
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
    return false
  end
end


def rotate_among value, direction, all_values
  if direction == :up || direction == :next
    all_values[(all_values.index(value) + 1) % all_values.length]
  elsif direction == :down || direction == :prev
    all_values[(all_values.index(value) - 1) % all_values.length]
  else
    fail "Internal error: unknown direction '#{direction}'"
  end
end


$among_all_lnames = nil

def recognize_among val, choices
 
  return nil unless val
  choices = [choices].flatten
  choices.each do |choice|
    # keys must be the same as in print_amongs
    if choice == :hole
      return choice if $harp_holes.include?(val)
    elsif choice == :note
      return choice if note2semi(val, 2..8, true)
    elsif [:semi_note, :semi_inter].include?(choice)
      return choice if val.match(/^[+-]?\d+st$/)
    elsif choice == :scale
      sc = get_scale_from_sws(val, true)
      return choice if $all_scales.include?(sc)
    elsif choice == :lick
      $among_all_lnames ||= $licks.map {|l| l[:name]}
      return choice if $among_all_lnames.include?(val)
    elsif choice == :extra
      return choice if $extra_kws[$mode].include?(val)
    elsif choice == :inter
      return choice if $intervals_inv[val]
    elsif choice == :last
      return choice if val.match(/^(\dlast|\dl)$/) || val == 'last' || val == 'l'
    else
      fail "Internal error: Unknown among-choice #{choice}" 
    end
  end
  return false
end


def print_amongs *choices
  choices.flatten.each do |choice|
    case choice
    # keys must be the same set of values as in recognize_among
    when :hole
      puts "\n- musical events in () or []\n    e.g. comments like '(warble)' or '[123]'"
      puts "\n- holes:"
      print_in_columns $harp_holes, indent: 4, pad: :tabs
    when :note
      puts "\n- notes:"
      puts '    all notes from octaves 2 to 8, e.g. e2, fs3, g5, cf7'
    when :semi_note
      puts "\n- Semitones (as note values):"
      puts '    e.g. 12st, -2st, +3st'
    when :semi_inter
      puts "\n- Semitones (as intervals):"
      puts '    e.g. 12st, -2st, +3st'
    when :scale
      puts "\n- scales:"
      print_in_columns $all_scales, indent: 4, pad: :tabs
    when :extra
      puts "\n- extra arguments:"
      puts get_extra_desc_all.join("\n")
    when :inter
      puts "\n- named interval, i.e. one of: "
      print_in_columns $intervals_inv.keys.reject {_1[' ']}, indent: 4, pad: :tabs
    when :lick
      all_lnames = $licks.map {|l| l[:name]}
      puts "\n- licks:"
      print_in_columns all_lnames, indent: 4, pad: :tabs
    when :last
      puts "\n- A symbolic name for one of the last licks"
      puts '    e.g. l, 2l, last'
    else
      fail "Internal error: Unknown choice #{choice}" 
    end
  end  
end


def get_extra_desc_all for_usage: false, exclude_meta: false
  lines = []
  $extra_desc[$mode].each do |k,v|
    ks = k.split(',').map(&:strip)
    next if exclude_meta && ks.any? {|kk| $quiz_tag2flavours[:meta].include?(kk)}
    lines << (for_usage ? '  ' : '') + "  - #{k}:"
    lines.append(v.lines.map {|l| (for_usage ? '  ' : '') + "\e[2m    #{l.strip}\e[0m"})
  end
  lines
end


# this can handle keys like 'ran, random'
def get_extra_desc_single key
  lines = []
  $extra_desc[$mode].each do |k,v|
    ks = k.split(',').map(&:strip)
    next unless ks.include?(key)
    lns = v.lines.map(&:strip)
    return [k] + [lns[0].sub(/\S/,&:upcase)] + lns[1 .. -1]
  end
  fail "Internal error: key #{key} not found"
end


class FamousPlayers

  attr_reader :structured, :printable, :all_groups, :stream_current

  def initialize
    pfile = "#{$dirs[:install]}/resources/players.yaml"
    raw = YAML.load_file(pfile)
    @lines_pool = ['',
                   'Notes about famous players will be drifting by ...',
                   '(use "p" or "print players" to read them on their own)']
    @lines_pool_last = nil
    @lines_pool_when = Time.now.to_f - 1000
    @stream_current = nil
    @structured = Hash.new
    @printable = Hash.new
    @names = Array.new
    @has_details = Hash.new
    @with_details = Array.new
    @all_groups = %w(name bio notes source songs)
    raw.each do |info|
      sorted_info = Hash.new
      name = sorted_info['name'] = info['name']
      fail "Internal error: No 'name' given for #{info}" unless name
      fail "Internal error: Name '#{name}' given for\n#{info}\nhas already appeared for \n#{structured[name]}" if @structured[name]
      pplayer = [name]
      @has_details[name] = false
      fail "Internal error: Set of allowed Groups #{@all_groups.sort} is different from set of groups for #{name} in #{pfile}: #{info.keys.sort}" unless @all_groups.sort == info.keys.sort 
      # print information in order given by @all_groups
      lcount = 0
      @all_groups.each do |group|
        lines = info[group] || []
        next if group == 'name'
        @has_details[name] = true if lines.length > 0
        sorted_info[group] = lines = ( lines.is_a?(String)  ?  [lines]  :  lines )
        lines.each {|l| err "Internal error: Has not been read as a string: '#{l}'" unless l.is_a?(String)}
        next if group == 'image'
        lines.map {|l| "#{group.capitalize}: #{l}"}.each do |l|
          lcount += 1
          pplayer << "(about #{info['name']})" if lcount % 4 == 0
          pplayer.append(l)
        end
      end
      if pplayer.length == 1
        pplayer[0] = "Not yet featured: #{name}"
      else
        pplayer[0] = "Featuring: #{name}"
        pplayer.unshift pplayer[0]
        pplayer << "Done for: #{name}"
      end
      pplayer.each do |line|
        fail "Internal error: This line has #{line.length} chars, which is more than maximum of #{$conf[:term_min_width] - 1}: '#{line}'" if line.length >= $conf[:term_min_width]
      end

      # handle pictures
      picture_dir = $dirs[:players_pictures] + '/' +
                     name.gsub(/[^\w\s_-]+/,'').gsub(/\s+/,'_')
      FileUtils.mkdir(picture_dir) unless File.directory?(picture_dir)
      sorted_info['image'] = Dir[picture_dir + '/*'].
                               # convenient for wsl2
                               reject {_1.end_with?('Zone.Identifier')}.
                               sample
      @picture_dirs ||= Hash.new
      @picture_dirs[name] = picture_dir
      
      @structured[name] = sorted_info
      @printable[name] = pplayer
      @with_details << name if @has_details[name]
      @names << name
    end
  end

  def select parts
    result_in_names = []
    result_in_printable = []
    @names.each do |name|
      result_in_names << name if parts.all? {|p| name.downcase[p.downcase]}
    end
    @with_details.each do |name|
      result_in_printable << name if parts.all? {|pa| @printable[name].any? {|pr| pr.downcase[pa]}}
    end
    result_in_printable = result_in_printable - result_in_names
    [result_in_names, result_in_printable]
  end

  def all
    @names
  end

  def all_with_details
    @with_details
  end
  
  def has_details?
    @has_details
  end

  def dimfor name
    if @has_details[name]
      "\e[0m"
    else
      "\e[2m"
    end
  end

  def line_stream_current
    if Time.now.to_f - @lines_pool_when > 8
      if @lines_pool.length == 0
        @lines_pool << ['']
        # We add those players, which have info multiple times to give them
        # more weight; if all players have info, this does no harm either
        names = @names.clone
        while names.length < 4 * @names.length
          names.append(*@with_details)
        end
        names.shuffle.each do |name|
          @lines_pool << nil
          @lines_pool << name
          @lines_pool << @printable[name]
          @lines_pool << ( @has_details[name]  ?  ['', '']  :  [''] )
        end
        @lines_pool.flatten!
      end
      @lines_pool_last = @lines_pool.shift
      if !@lines_pool_last
        # remember last player
        @stream_current = name = @lines_pool.shift
        $pers_data['players_last'] = name if @has_details[name]
        @lines_pool_last = @lines_pool.shift
      end
      @lines_pool_when = Time.now.to_f
    end
    @lines_pool_last
  end

  def view_picture file, name, in_loop
    needed = []
    puts "\e[32mImage:\e[0m"

    if !file
      puts "\e[2m  You may store a player image to be shown in:\n    #{@picture_dirs[name]}\e[0m"
      return
    end
    
    case $opts[:viewer]
    when 'none'
      puts "\e[2m  (to view the image, set option or config '--viewer')\e[0m"
      return
    when 'feh'
      needed = %w(xwininfo feh)
    when 'chafa'
      needed = %w(chafa)
    else
      err "Internal error: Unknown viewer: '#{$opts[:viewer]}'"
    end
    not_found = needed.reject {|x| system("which #{x} >/dev/null 2>&1")}
    err "These programs are needed to view player images but cannot be found: #{not_found}" if not_found.length > 0
    if $opts[:viewer] == 'feh'
      puts "\e[2m  #{file}\e[0m"
      if in_loop
        puts "\e[2m  Viewing image with feh, type 'q' for next, type ctrl-c in terminal to quit\e[0m"
      else
        puts "\e[2m  Viewing image with feh, type 'q' to quit\e[0m"
      end
      sys("xwininfo -root")
      sw = sys("xwininfo -root").lines.find {|l| l["Width"]}.scan(/\d+/)[0].to_i
      pw, ph = sys("feh -l #{file}").lines[1].split.slice(2,2).map(&:to_i)
      scale = $conf[:viewer_scale_to].to_f / ( pw > ph ? ph : pw )
      command = "feh -Z --borderless --geometry #{(pw*scale).to_i}x#{(ph*scale).to_i}+#{(sw-pw*scale-100).to_i}+100 #{file}"
      sys command
      puts command if $opts[:debug]
    else
      sleep 1
      puts "\e[2m  #{file}\e[0m" 
      puts sys("chafa #{file}")
    end
  end
end


def err_args_not_allowed args
  if args.length == 1 && $conf[:all_keys].include?(args[0])
    err "'harpwise #{$mode} #{$extra}' does not take any arguments; however your argument '#{args[0]}' is a key, which might be placed further left on the commandline, if you wish"
  else
    err "'harpwise #{$mode} #{$extra}' does not take any arguments, these cannot be handled: #{args}"
  end
end


def wrap_words head, words
  line = head
  lines = Array.new
  words.each_with_index do |word, idx|
    line += ',' unless line[-1] == ' ' || idx == 0
    if line.length + word.length > $term_width - 2
      lines << line
      line = (' ' * head.length) + word
    else
      line += word
    end
  end
  lines << line unless line == ''
  return lines.join("\n")
end
