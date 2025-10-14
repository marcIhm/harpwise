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

  def o2sym2
    self.gsub('.','_').to_sym if self
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
    err "Cannot parse #{file}: #{e.message}"
  rescue Errno::ENOENT => e
    err "File #{file} does not exist !"
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
  puts "\e[0mERROR: #{text}"
  $msgbuf&.flush_to_term  
  puts_context_sources if $opts && $opts[:debug]
  puts
  puts Thread.current.backtrace if $opts && $opts[:debug]
  exit 1
end


def puts_context_sources
  clauses = [:mode, :type, :key, :scale, :extra].map do |var|
    val = if $err_binding && eval("defined?(#{var})",$err_binding)
            eval("#{var}", $err_binding)
          elsif eval("defined?($#{var})")
            eval("$#{var}")
          else
            nil
          end
    if val
      "%-5s = #{val} (#{$source_of[var] || 'command-line'})" % var
    else
      "#{var} is not set"
    end
  end.compact
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
  $scale_files_templates.each do |template|
    %w(holes notes).each do |what|
      parts = (template % [type, '|', what]).split('|')
      return file[parts[0].length .. - parts[1].length - 1] if file[parts[0]]
    end
  end
end


def scales_for_type type, check
  files = $scale_files_templates.map do |template|
    Dir[template % [type, '*', '{holes,notes}']]
  end.flatten
  if check
    scale2file = Hash.new
    files.each do |file|
      scale = file2scale(file,type)
      err "Duplicate scale   #{scale}   has already been defined in:\n#{scale2file[scale]}\ncannot redefine it in:\n#{file}"  if scale2file[scale]
      scale2file[scale] = file
    end
    return scale2file.keys.sort, scale2file
  else
    return files.map {|file| file2scale(file, type)}.sort
  end
end


def describe_scales_maybe scales, type
  desc = Hash.new
  count = Hash.new
  scales.each do |scale|
    begin
      _, holes_rem = YAML.load_file($scale2file[scale]).partition {|x| x.is_a?(Hash)}
      holes = holes_rem.map {|hr| hr.split[0]}
      desc[scale] = "holes #{holes.join(',')}"
      count[scale] = holes.length
    rescue Errno::ENOENT, Psych::SyntaxError
    end
  end
  [desc, count]
end


def display_kb_help what, scroll_allowed, body, wait_for_key: true
  if scroll_allowed
    puts "\n\e[0m"
  else
    clear_area_comment
    print "\e[#{$lines[:help]}H\e[0m"
  end
  puts "Keys available while playing #{what}:\e[0m\e[32m\n"
  maxlen = body.lines.map(&:length).max
  indent = ($term_width - maxlen) / 4
  indent = 2 if indent < 0
  body.lines.each do |l|
    puts ( ' ' * indent ) + l.gsub(/(\S+): /, "\e[92m\\1\e[32m: ").chomp + "\n"
  end
  if wait_for_key
    print "\e[0m#{$resources[:any_key]}"
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
    puts
  end
  if scroll_allowed
    puts "\e[0m\e[2mdone with help.\e[0m"
    puts
  else
    clear_area_comment
    ctl_response 'continue'
  end
end


def truncate_colored_text text, len = nil
  # cannot use default for argument, because we allow beeing called with one
  # argument only
  len ||= $term_width - 4
  text = text.dup
  ttext = ''
  tlen = 0
  trunced = ''
  begin
    if md = text.match(/^(\e\[[\d;,]+m)(.*)$/)
      # escape-sequence: just copy into ttext but do not count in tlen
      ttext += md[1]
      text = md[2]
    elsif md = text.match(/^\e/)
      fail "Internal error: Unknown escape"
    else
      # no escape a start, copy upto next escape to ttext and count
      md = text.match(/^([^\e]*)/)
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


def write_dump marker = nil
  if marker
    dumpfile = "#{$dirs[:exch_tester_tested]}/harpwise_testing_dumped_#{marker}.json"
    File.delete(dumpfile) if File.exist?(dumpfile)
  end
  structure = {scale: $scale, scale_holes: $scale_holes, licks: $licks, lick_progs: $all_lick_progs, opts: $opts, conf: $conf, conf_system: $conf_system, conf_user: $conf_user, key: $key, messages_printed: $msgbuf.printed, dirs: $dirs, pulse_server: ENV['PULSE_SERVER']}
  if marker
    File.write(dumpfile, JSON.pretty_generate(structure))
  else
    pp structure
  end
end


def print_mission text, ncol = 0
  print "\e[#{$lines[:mission]}H\e[0m#{text.ljust($term_width - $ctl_response_width + ncol)}\e[0m"
end


def print_in_columns names, indent: 2, pad: :space
  head = ' ' * indent
  line = ''
  padded_names = case pad
                 when :tabs
                   names.map {|nm| ' ' + nm + ' '}.
                     map {|nm| nm + ' ' * (-nm.length % 4)}
                 when :long_tabs
                   names.map {|nm| ' ' + nm + ' '}.
                     map {|nm| nm + ' ' * (-nm.length % 8)}
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
  puts 'Time.now.to_f:'
  puts Time.now.to_f

  puts
  puts '$debug_info:'
  pp $debug_info

  if $perfctr[:handle_holes_this_first_mic]
    $perfctr[:handle_holes_this_loops_per_second] = $perfctr[:handle_holes_this_loops] / ( Time.now.to_f - $perfctr[:handle_holes_this_first_mic] )
  end
  puts
  puts '$perfctr:'
  pp $perfctr

  puts
  puts '$freqs_queue.length:'
  puts $freqs_queue.length

  if $opts[:comment] == :warbles
    puts
    puts '$warbles:'
    pp $warbles
  end
end


def print_afterthought

  # collect this in string, so we may print it starting slow
  thought = []

  this_happened = <<~end_of_content
     This happened for the instance of harpwise beeing started at:
        #{Time.at($program_start)}
     Note, that this might not have been the most recent invocation.
  end_of_content
  
  if $lagging_freqs_lost > 0 && $total_freq_ticks > 0
    lagging_file = "#{$dirs[:data]}/lagging_info"
    pct_lost = "%.1f%%" % (100 * $lagging_freqs_lost / ($lagging_freqs_lost + $total_freq_ticks))
    thought << "Lagging detected (#{pct_lost} loss), see #{lagging_file} for details."
    content = <<~end_of_content    
    
     Lagging detected
     ----------------

     #{this_happened}
     Harpwise has been lagging behind at least once; i.e. harpwise
     sensed the hole you were playing only with a (small) delay; and to
     catch up, it discarded some of your playing.
     Therefore #{$lagging_freqs_lost} of #{$lagging_freqs_lost + $total_freq_ticks} samples (= #{pct_lost}) have been lost.

     If you notice such a lag frequently and and want to reduce it,
     you may try to set option   --time-slice   or config   time_slice
     (currently: '#{$opts[:time_slice]}') to 'medium' or 'long'. See config file

       #{$conf[:config_file_user]}

     Note however, that setting this to 'long' without need could make
     harpwise sluggish in sensing holes.

     end_of_content
    IO.write lagging_file, content
  end

  # $max_jitter is only set, if it exceeds $jitter_threshold
  if $max_jitter > 0
    jitter_file = "#{$dirs[:data]}/jitter_info"
    jitter_secs = "%.2f secs" % $max_jitter
    thought << "Jitter detected (#{jitter_secs}), see #{jitter_file} for details."
    content = <<~end_of_content

     Jitter detected
     ---------------

     #{this_happened}
     The frequency pipeline had a maximum jitter of #{jitter_secs}, which
     happened #{($max_jitter_at - $program_start).to_i} secs after program start, #{(Time.now.to_f - $max_jitter_at).to_i} secs before its end.

     A total of #{$jitter_checks_total} jitter-checks have been performed, one every #{$jitter_check_after_iters} iterations;
     #{$jitter_checks_bad} of them were above the threshold of #{$jitter_threshold} secs.

     [ts_harpwise, [ts_aubio, freq]] maximum jitter:
       #{$max_jitter_info[0]}
       #{$max_jitter_info[1]}

     As a result your playing and its display by harpwise were out of sync
     at least once.

     This is probably out of control of harpwise and might be caused by
     external factors, like system-load or simply by hibernation of your
     computer.

     end_of_content
    IO.write jitter_file, content
  end

  if thought.length > 0
    print "\e[#{$lines[:message2]}H\e[0m\e[2m" 
    thought.each do |line|
      puts line.chomp + "\e[K\n"
    end
    puts
  end
  print "\e[0m"
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
    print "\e[0m\e[2m" + ('| ' * 10) + "|\e[1G"
    sleep 0.08
    print "|\e[0m\e[92m~\e[0m\e[2m|\e[2D"
    sleep 0.04
    '~HARPWISE~'.each_char.each_cons(2) do |c1, c2|
      print "\e[0m\e[32m#{c1}\e[0m\e[2m|\e[0m\e[92m#{c2}\e[0m\e[2m|\e[0m\e[2D"
      sleep 0.04
    end
    print "\e[32m~\e[0m\e[2m|\e[0m"
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


$last_history_data = nil
$first_history_written = false
def write_history play_type, name, holes = []

  # check for file size
  if !$first_history_written && File.exist?($history_file) && File.size($history_file) > 100_000
    tlines = File.read($history_file).lines
    # keep only last half
    File.write($history_file, tlines[tlines.length/2 .. -1].join)
  end

  File.open($history_file, 'a') do |history|
    tstamps = [Time.now.strftime('%Y-%m-%d %H:%M'), Time.now.to_i]
    data = { rec_type: 'start',
             mode: $mode,
             timestamps: tstamps }
    history.write("\n" + JSON.generate(data) + "\n\n") unless $first_history_written
    # must match formats in next function
    data = { rec_type: 'entry',
             mode: $mode,
             play_type: play_type,
             name: name}
    return if data == $last_history_data
    $last_history_data = data.clone 
    data[:timestamps] = tstamps
    data[:holes] = holes 
    history.write(JSON.generate(data) + "\n\n")
  end
  $first_history_written = true
end


def get_prior_history_records *for_modes

  for_modes.each do |m|
    err "Internal error: unknown mode: #{m}" unless $early_conf[:modes].include?(m.to_s)
  end
  num_entries_wanted = 16
  num_entries = 0
  records = []
  return [] if !File.exist?($history_file)

  File.foreach($history_file).each_with_index do |line, lno|
    line.strip!
    next if line == ''
    begin
      data = JSON.parse(line, symbolize_names: true)
    rescue JSON::ParserError
      err "Cannot parse line #{lno} from history-file #{$history_file}: '#{line}'"
    end

    # must match formats in previous function
    unless ( data in { rec_type: 'start',
                       mode: _, 
                       timestamps: [ _, _ ] } ) ||
           ( data in { rec_type: 'entry',
                       mode: _,
                       play_type: _,
                       name: _,
                       holes: [*],
                       timestamps: [ _, _ ] } )
      err "Cannot parse line #{lno} from history-file #{$history_file}: '#{line}'"
    end
    [:mode, :rec_type].each do |key|
      data[key] = data[key].to_sym if data[key]
    end

    if for_modes.include?(data[:mode])
      if records.length == 0 && data[:rec_type] == :entry
        # we did not find start-record; maybe due to prior truncation
        records << { rec_type: :start,
                     mode: data[:mode], 
                     timestamps: [ 'unknown', -1 ] }
      end
      records << data
      num_entries += 1 if data[:rec_type] == :entry
    end
  end
  
  # return if no records, so that further down below we can be sure to have at
  # least one record for each type of :start and :entry
  return [] if records.length == 0

  # wipe out entries beyound num_entries
  eidx = 0
  loop do
    eidx = (0 ... records.length).find {|i| records[i][:rec_type] == :entry}
    break if num_entries <= num_entries_wanted
    # avoid building two or more :skipping-entries in a row
    if records[eidx - 1][:rec_type] != :skipping
      records[eidx] = { rec_type: :skipping }
    else
      records.delete_at(eidx)
    end
    num_entries -= 1
  end
  
  # go down to matching start-index (which is guaranteed to exist, see above)
  sidx = eidx
  sidx -= 1 while records[sidx][:rec_type] != :start
  records.shift(sidx)

  records.reverse
end


def shortcut2history_record short
  md = nil
  return false unless ( md = short.match(/^(\dlast|\dl)$/) ) || short == 'last' || short == 'l'
  idx = if md
          md[1].to_i - 1
        else
          0
        end

  # must be consistent with selection in print_last_licks_from_history
  records = get_prior_history_records(:licks, :play).
              select {|r| r[:play_type] == 'lick'}

  err "Shortcut '#{short}' is beyound end of #{records.length} available history records" if idx >= records.length
    
  $all_licks, $licks, $all_lick_progs = read_licks unless $licks
  lnames = $licks.map {|l| l[:name]}
  rname = records[idx][:name]
  lidx = lnames.index(rname)
  err "Shortcut '#{short}' maps to lick '#{rname}', which is unknown among currently selected licks: #{lnames}" unless lidx

  records[idx][:lick_idx] = lidx
  records[idx]
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
    # arguments, that could have never been given on the command line
    if $mode == :listen && [:quiz, :licks].include?(mode_prev)
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
    print "\e[#{$lines[:hint_or_message]}H\e[0m\e[32mEditing done.\e[K\e[0m"
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


def recognize_among val, choices, licks: $licks
  return nil unless val
  choices = [choices].flatten
  err("Internal error: :extra_wwos should always be last, if it appears at all: #{choices}") if choices.index(:extra_wwos)&.!=(choices.length - 1)
  choices.each do |choice|
    next if $opts[:what] && $opts[:what] != choice    
    # keys must be the same as in $amongs
    if choice == :hole
      return choice if $harp_holes.include?(val)
    elsif choice == :note
      return choice if note2semi(val, 2..8, true)
    elsif [:semi_note, :semi_inter].include?(choice)
      return choice if val.match(/^[+-]?\d+st$/)
    elsif choice == :event
      return choice if musical_event?(val)
    elsif choice == :scale
      sc = get_scale_from_sws(val, true)
      return choice if $all_scales.include?(sc)
    elsif choice == :scale_prog
      return choice if $all_scale_progs[val]
    elsif choice == :lick
      return choice if licks.any? {|l| l[:name] == val}
    elsif choice == :lick_prog
      return choice if $all_lick_progs.keys.any? {|lpn| lpn == val}
    elsif choice == :inter
      return choice if $intervals_inv[val]
    elsif choice == :last
      return choice if val.match(/^(\dlast|\dl)$/) || val == 'last' || val == 'l'
    elsif choice == :jam
      return choice if $jamming_rel2abs[val]
    elsif choice == :extra
      return choice if $extra_kws[$mode].include?(val)
    elsif choice == :extra_wwos
      # As a unique exception, we take here the liberty to err-out if we think so; therefore
      # :extra_wwos should always be last in amongs (see above)
      should = $extra_kws_wwos2canon[$mode][val]
      if should
        puts
        puts "Did you mean '#{should}' instead of '#{val}' ?"
        puts
        puts "Its description is:   #{should}:"
        puts get_extra_desc_single(should)[1..-1].
               map {|l| '  ' + l + "\n"}.
               join.chomp +
             ".\n"
        err "Extra argument might have been spelled wrong (with or without letter 's'; see above)"
      end
    else
      fail "Internal error: Unknown among-choice '#{choice}'" 
    end
  end
  return false
end


def print_amongs *choices, **kws
  choices.flatten.each do |choice|
    next if $opts[:what] && $opts[:what] != choice
    adc = $amongs_desc[choice]
    case choice
        # keys must be the same set of values as $amongs
    when :event
      puts "\n- #{adc[0]}"
      puts "    #{adc[1]}:"
    when :hole
      puts "\n- #{adc[0]}:"
      print_in_columns $harp_holes, indent: 4, pad: :tabs
    when :note
      puts "\n- #{adc[0]}"
      puts "    #{adc[1]}:"
    when :semi_note
      puts "\n- #{adc[0]}"
      puts "    #{adc[1]}:"
    when :semi_inter
      puts "\n- #{adc[0]}"
      puts "    #{adc[1]}:"
    when :scale
      puts "\n- #{adc[0]}:"
      print_in_columns $all_scales, indent: 4, pad: :tabs
    when :scale_prog
      puts "\n- #{adc[0]}:"
      print_in_columns $all_scale_progs.keys.sort, indent: 4, pad: :tabs      
    when :extra
      puts "\n- #{adc[0]}:"
      puts get_extra_desc_all(highlight: kws[:highlight_extra]).join("\n")
    when :inter
      puts "\n- #{adc[0]}:"
      print_in_columns $intervals_inv.keys.reject {_1[' ']}, indent: 4, pad: :tabs
    when :lick
      all_lnames = $licks.map {|l| l[:name]}
      puts "\n- #{adc[0]}:"
      print_in_columns all_lnames.sort, indent: 4, pad: :tabs
      if $licks == $all_licks
        puts "  , where set of licks has not been restricted by tags"
      else
        puts "  , where lick selection is done with these options: #{desc_lick_select_opts(indent: '  ')}"
      end
    when :lick_prog
      puts "\n- #{adc[0]}:"
      print_in_columns $all_lick_progs.keys.sort, indent: 4, pad: :tabs
    when :last
      puts "\n- #{adc[0]}"
      puts "    #{adc[1]}:"
    when :jam
      puts "\n- #{adc[0]}:"
      print_in_columns $jamming_rel2abs.keys.sort, indent: 4, pad: :long_tabs
    else
      fail "Internal error: Unknown choice: '#{choice}'" 
    end
  end  
end


def get_extra_desc_all highlight: nil, for_usage: false, exclude_meta: false
  lines = []
  $extras_joined_to_desc[$mode].each do |k,v|
    ks = k.split(',').map(&:strip)
    next if exclude_meta && ks.any? {|kk| $quiz_tag2flavours[:meta].include?(kk)}
    khl = if highlight
            k.gsub(highlight, "\e[0m\e[32m" + highlight + "\e[0m")
          else
            k
          end
    lines << (for_usage ? '  ' : '') + "  - #{khl}:"
    lines.append(v.lines.map {|l| (for_usage ? '  ' : '') + "\e[2m    #{l.strip}\e[0m"})
  end
  lines
end


# this can handle keys like 'ran, random'
def get_extra_desc_single key
  lines = []
  $extras_joined_to_desc[$mode].each do |k,v|
    ks = k.split(',').map(&:strip)
    next unless ks.include?(key)
    lns = v.lines.map(&:strip)
    return [k] + [lns[0].sub(/\S/,&:upcase)] + lns[1 .. -1]
  end
  fail "Internal error: key #{key} not found"
end


class FamousPlayers

  attr_reader :structured, :printable, :all_groups, :stream_current, :text_width

  def initialize
    
    @lines_pool = ['',
                   'Notes about famous players will be drifting by ...',
                   "(use 'p' or 'harpwise print players' to read them on their own)"]
    @lines_pool_last = nil
    @lines_pool_when = Time.now.to_f - 1000
    @stream_current = nil
    @structured = Hash.new
    @printable = Hash.new
    @names = Array.new
    @has_details = Hash.new
    @with_details = Array.new
    @all_groups = %w(name bio notes songs sources)
    @all_text_width = 0

    pfile = "#{$dirs[:install]}/resources/players.org"
    #
    # We process the well-known org-format into a hash equivalent to the prior yaml-file,
    # which should looks like this:
    #
    # [{'name'    => 'name1',
    #   'bio'     => ['line', 'line'],
    #   'notes'   => ['line', 'line'],
    #   'sources' => ['line', 'line'],
    #   'songs'   => ['line', 'line']},
    #  {'name'    => 'name1',
    #   'bio'     => ['line', 'line'],
    #   'notes'   => ['line', 'line'],
    #   'sources' => ['line', 'line'],
    #   'songs'   => ['line', 'line']}]
    #
    semiraw = []
    inner = []
    group = nil
    # Add artificial heading to trigger processing of last regular one
    (File.read(pfile) + "\n* end").lines.to_a.each_with_index do |line, lno|
      # ignore initial comment
      next if lno == 0
      line.chomp!
      if line.start_with?('*')
        if inner.length > 0
          fail "Internal error: no prior group (#{group}), #{pfile}, line #{lno}" unless group
          inner.each do |ils|  # item-lines, for items that have multiple line
            next if ils.length == 1
            next if %w(. ? ! ; ,).include?(ils[-1][-1])
            ils[-1] += '.'
          end
          semiraw[-1][group] = inner.flatten
          inner = []
        end
      end

      if line.strip == ''
      # ignore empty lines
      elsif md = line.match(/^\* (.*)$/)
        name = md[1].strip
        break if name == 'end'
        semiraw << {'name' => name}
      elsif md = line.match(/^\*\* (.*)$/)
        fail "Internal error: no name yet, #{pfile}, line #{lno}" unless semiraw[-1]
        group = md[1].strip
        fail "Internal error: Unknown group #{group}, #{pfile}, line #{lno}" unless @all_groups.include?(group)
      elsif md = line.match(/^ +-(.*)$/)
        inner << [md[1].strip]
      else
        fail "Internal error: not in list, #{pfile}, line #{lno}" if inner.length == 0
        inner[-1] << line.strip
      end
    end
    
    semiraw.each do |info|
      sorted_info = Hash.new
      name = sorted_info['name'] = info['name']
      fail "Internal error: No 'name' given for #{info}" unless name
      fail "Internal error: Name '#{name}' given for\n#{info}\nhas already appeared for \n#{structured[name]}" if @structured[name]
      pplayer = [name]
      @has_details[name] = true

      # print information in order given by @all_groups
      lcount = 0
      @all_groups.each do |group|
        lines = info[group] || []
        next if group == 'name'
        @has_details[name] = false if lines.length == 0
        sorted_info[group] = lines
        next if group == 'image'
        next if group == 'sources'
        lines.each do |l|
          gl = "#{group.capitalize}: #{l}"
          lcount += 1
          @all_text_width = [@all_text_width, l.length].max
          pplayer << "(about #{info['name']})" if lcount % 4 == 0
          pplayer.append(gl)
        end
      end
      if pplayer.length == 1
        pplayer[0] = "Nothing known about #{name} yet"
      else
        pplayer[0] = "Featuring #{name}"
        pplayer.unshift pplayer[0]
        pplayer << "Featured #{name}"
      end
      pplayer.each do |line|
        fail "Internal error: This line from #{pfile} has #{line.length} chars, which is more than maximum of #{$conf[:term_min_width]}: '#{line}'" if line.length > $conf[:term_min_width]
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

  
  def show_picture file, name, in_loop, txt_lines, txt_width

    # txt_lines and txt_width are only used to compute size of image;
    # txt_width will be handled again further down for pixel images
    
    # add two spaces of indent plus safety margin
    txt_width += 3
    # three more lines (adding to those, that have already been printed) will
    # be printed below
    txt_lines += 2

    needed = []
    puts "\e[0m\e[2mImage:\e[0m"

    if !file
      puts "\e[2m  You may store player images to be shown in:\n    #{@picture_dirs[name]}\e[0m"
      return
    end
    
    case $opts[:viewer]

    when 'none'

      puts "\e[2m  (to view the image, set option or config '--viewer')\e[0m"
      return

    when 'window'

      check_needed_viewer_progs %w(xwininfo feh)

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

    when 'char'

      check_needed_viewer_progs %w(chafa)

      puts "\e[2m  #{file}\e[0m" 
      puts sys("chafa -f symbols #{file}")

    when 'pixel'

      # get term size in characters
      cheight_term, cwidth_term = %x(stty size).split.map(&:to_i)
      # avoid picture beeing too large by limiting its available space
      txt_width = [txt_width, cwidth_term*2.0/3].max.to_i
      puts "\e[2m  #{file}\e[0m"
      
      if ENV['TERM']['kitty']
        
        check_needed_viewer_progs %w(kitty)
        if cwidth_term > txt_width * 1.25
          # enough room to show image right beside text
          print "\e[s"
          sleep 2
          puts sys("kitty +kitten icat --stdin=no --scale-up --z-index -1 --place #{cwidth_term - txt_width}x#{cheight_term}@#{txt_width}x#{cheight_term - txt_lines} --align right #{file}")
          print "\e[u"
         else
           # not enough room, place image below text
           (cheight_term/2).times {puts}
           print "\e[s"        
           puts sys("kitty +kitten icat --stdin=no --scale-up --z-index -1 --place #{cwidth_term}x#{cheight_term/2}@0x#{cheight_term/2} --align left #{file}")
           print "\e[u"
        end

      else
        # we hope for sixel support
        
        check_needed_viewer_progs %w(img2sixel)

        # get pixel width of one character cell.

        # Note, for windows terminal: This will always return 10x20 (i.e. 1:2) regardless of
        # chosen font (by design of the sixel-feature in windows-terminal); and as the
        # picture takes up character cells according to its own pixel-size and this assumed
        # pixel-size of a character cell, the aspect ratio of an image might be wrong, if
        # the current font has an actual aspect ratio, that differs from 1:2. As a result
        # pictures are shown stretched horizontally if the font is e.g. "Lucida Console"
        # (which has a more quadratic character cell), even though the command img2sixel
        # below uses only the width-argument and therefore places no constraints on the
        # aspect ratio of the image.
        prepare_term
        reply = ''
        begin
          Timeout.timeout(1) do          
            print "\e[16t"
            reply += STDIN.gets(1) while reply[-1] != 't'
          end
        rescue Timeout::Error
          err 'Could not get pixel width of terminal'
        end
        sane_term
        Kernel::print "\e[?25h"  ## show cursor
        mdata = reply.match(/^.*?([0-9]+);([0-9]+);([0-9]+)/)
        pwidth_cell = mdata[3]
        pheight_cell = mdata[2]
        pwidth_img = pwidth_cell.to_i * [cwidth_term - txt_width, cwidth_term * 0.5].min.to_i
        
        if cwidth_term > txt_width * 1.25
          # enough room to show image right beside text
          # move up and right
          print "\e[s\e[#{txt_lines}F\e[#{txt_width}G"
          puts sys("img2sixel --width #{pwidth_img} #{file}")
          print "\e[u"
          sane_term
        else
          # not enough room, place image below text
          puts sys("img2sixel --height #{pheight_cell.to_i * cheight_term / 2} #{file}")
          sane_term
        end
      end
    else
      err "Internal error: Unknown viewer: '#{$opts[:viewer]}'"
    end
  end
end


def err_args_not_allowed args
  if args.length == 1 && $conf[:all_keys].include?(args[0])
    err "'harpwise #{$mode} #{$extra}' does not take any arguments; however your argument '#{args[0]}' is a key, which might be placed further left on the command line, if you wish"
  else
    err "'harpwise #{$mode} #{$extra}' does not take any arguments, these cannot be handled:  #{args.join(' ')}"
  end
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
  return lines.join("\n")
end


def wrap_text text, term_width: nil, cont: ' ...'
  line = ''
  lines = Array.new
  term_width ||= $term_width
  term_width = $term_width + term_width if term_width < 0
  cont_len = ( cont&.length || 0 )
  # keeps the spaces in tokens
  text.split(/( +)/).each_with_index do |token, idx|
    if line.length + token.length > term_width - 2 - cont_len
      lines << line.strip
      line = token.strip
    else
      line += token
    end
  end
  lines << line.strip unless line.strip == ''
  if cont_len > 0
    lines[0 .. -2].each {|l| l << cont }
  end
  return lines
end


def report_name_collisions_mb
  collisions = $name_collisions_mb.select {|_, s| s.length > 1}
  return if collisions.length == 0
  puts
  puts "There are #{collisions.length} name collisions:"
  puts
  maxnm = collisions.keys.map(&:length).max
  collisions.each do |name, set|
    puts "  -  '#{name}'" + (' ' * (maxnm - name.length)) + "  can be any of:   #{set.to_a.sort.join(', ')}"
  end
  err "Please fix them; probably by giving a unique name to those entries in:\n  #{$lick_file}"
end


def write_invocation
  #
  # See also:   utils/harpwise_historic_with_fzf.sh
  #
  # for an application of the files written here.
  #
  ts_clause = "   #  " + Time.now.to_s.split[0..1].join('  ')

  # Take ENV into account, just like the script above does
  command_line = if ENV['HARPWISE_COMMAND']
                   ENV['HARPWISE_COMMAND'] + ' ' + $full_command_line.split(' ',2)[1]
                 else
                   $full_command_line
                 end
  
  # Timestamps should be right-aligned within minimum terminal width if possible
  # or at boundaries of 4
  room = $conf[:term_min_width] - 4 - command_line.length - ts_clause.length
  padding = ( room > 0  ?  (' ' * room)  :  ( ' ' * ( -command_line.length % 4 )))
  file = "#{$invocations_dir}/#{$type}_#{$mode}" + ( $extra  ?  "_#{$extra_aliases[$mode][$extra]}"  :  '' )
  lines = if File.exist?(file)
            # remove repetitions, disrecarding time comments
            File.read(file).lines.reject {|l| l.chomp.gsub(/ *\#.*/,'') == command_line}
          else
            []
          end.append(command_line + padding + ts_clause + "\n")
  File.write(file, lines.last(20).join)

  # And finally do something totally unrelated; the content of path_to_install_dir is used
  # within jammin-files
  File.write "#{$dirs[:data]}/path_to_install_dir", "#{$dirs[:install]}\n"  
end


def set_testing_vars_mb
  testing = !!ENV["HARPWISE_TESTING"]
  testing_what = nil
  tw_allowed = %w(1 true t yes y)
  if testing && !tw_allowed.include?(ENV['HARPWISE_TESTING'].downcase)
    testing_what = ENV["HARPWISE_TESTING"].downcase
    tw_allowed.append(*%w(lag jitter player argv opts msgbuf none remote extra))
    err "Environment variable HARPWISE_TESTING is '#{ENV["HARPWISE_TESTING"]}', none of the allowed values #{tw_allowed.join(',')} (case insensitive)" unless tw_allowed.include?(testing_what)
    testing_what = testing_what.to_sym
  end
  if testing_what == :none
    testing = false
    testing_what = nil
  end

  return [testing, testing_what]
end


# Hint or message buffer for main loop in variou places. Makes sure, that all
# messages are shown long enough
class MsgBuf

  def self.reset
    # central data structure, used as a stack
    @@lines_durations = Array.new
    # used for testing
    @@printed = Array.new
  end
  
  def reset
    self.class.reset
    @@reset_at << Time.now
  end

  # for debugging
  def dump
    pp ({ lines_durations: @@lines_durations,
          printed: @@printed,
          printed_at: @@printed_at,
          reset_at: @@reset_at})
  end
    
  self.reset
  @@ready = false
  @@printed_at = nil
  @@reset_at = Array.new
  
  def print text, min, max, group = nil, truncate: true, wrap: false

    # min: keep message on stack and display it that long at minimum; is used in
    # print_internal only, so this is checked only if a new message is about to be printed
    #
    # max: remove currently shown message, even if no new message is to be printed; is used
    # in update only, which however is called in every loop of handle_holes
    
    # remove any outdated stuff
    if group
      # of each group there should only be one element in messages;
      # older ones are removed. group is only useful, if min > 0
      idx = @@lines_durations.each_with_index.find {|x| x[0][3] == group}&.at(1)
      @@lines_durations.delete_at(idx) if idx
    end
    
    if text
      if truncate && wrap
        fail "Internal error: both :truncate and :wrap are set" 
      elsif wrap || text.is_a?(Array)
        lines = if text.is_a?(Array)
                  text
                else
                  wrap_text(text,
                            term_width:  $testing_what == :msgbuf  ?  $conf[:term_min_width]  :  nil )
                end
        lines.each {|l| fail "Internal error: text to wrap contains escape: '#{l}'" if l["\e"]}
        lines[1 .. -1].reverse.each do |l|
          print_internal l, min, max, group, true
        end
        print_internal lines[0], min, max, group, false
      elsif truncate
        print_internal truncate_colored_text(text,
                                             $testing_what == :msgbuf  ?  $conf[:term_min_width]  :  nil),
                       min, max, group, false
      else
        fail "Internal error: neither :truncate nor :wrap are set"
      end
    else
      print_internal text, min, max, group, false
    end
  end
  
    
  def print_internal text, min, max, group, later

    # use min duration for check
    @@lines_durations.pop if @@lines_durations.length > 0 && @@printed_at && @@printed_at + @@lines_durations[-1][1] < Time.now.to_f
    @@lines_durations << [text, min, max, group] if @@lines_durations.length == 0 || @@lines_durations[-1][0] != text
    # 'later' should be used for batches of messages, where print is
    # invoked multiple times in a row; the last one should be called
    # without setting later
    if @@ready && text && !later
      Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{text}\e[0m\e[K" unless $testing_what == :msgbuf
      @@printed.push([text, min, max, group]) if $testing
    end
    @@printed_at = Time.now.to_f
  end

  # return true, if there is message content left, i.e. if
  # message-line should not be used e.g. for hints
  def update tntf = nil, refresh: false

    tntf ||= Time.now.to_f

    # we keep elements in @@lines_durations until they are expired
    return false if @@lines_durations.length == 0

    # use max duration for check
    if @@printed_at && @@printed_at + @@lines_durations[-1][2] < Time.now.to_f
      # current message is old
      @@lines_durations.pop
      if @@lines_durations.length > 0
        # display new topmost message; special case of text = nil
        # preserves already visible content (e.g. splash)
        if @@ready && @@lines_durations[-1][0]
          Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{@@lines_durations[-1][0]}\e[0m\e[K" unless $testing_what == :msgbuf
          @@printed.push(@@lines_durations[-1]) if $testing
        end
        @@printed_at = Time.now.to_f
        return true
      else
        # no messages
        @@printed_at = nil
        # just became empty, return true one more time
        return true
      end
    else
      # current message is still valid
      if @@ready && @@lines_durations[-1][0] && refresh
        Kernel::print "\e[#{$lines[:hint_or_message]}H\e[2m#{@@lines_durations[-1][0]}\e[0m\e[K" unless $testing_what == :msgbuf
        @@printed.push(@@lines_durations[-1]) if $testing
        @@printed_at = Time.now.to_f
      end
      return true
    end
  end

  def ready state = true
    @@ready = state
  end

  def clear
    @@lines_durations = Array.new
    @@printed_at = nil
    Kernel::print "\e[#{$lines[:hint_or_message]}H\e[K" if @@ready && $testing_what != :msgbuf
  end

  def printed
    @@printed
  end

  def flush_to_term
    return if @@lines_durations.length == 0 || @@lines_durations.none? {|l,_| l}
    puts "\n\e[0m\e[2mFlushing pending messages for completeness:"
    @@lines_durations.each do |l,_|
      next if !l
      puts '  ' + l
    end
    Kernel::print "\e[0m" unless $testing_what == :msgbuf
  end
  
  def empty?
    return @@lines_durations.length > 0
  end

  def get_lines_durations
    @@lines_durations
  end

  def borrowed secs
    # correct for secs where lines have been borrowed something else
    # (e.g. playing the licka)
    @@printed_at += @@printed_at if @@printed_at
  end
end


def create_dir dir
  if File.exist?(dir)
    err "Directory #{dir} does not exist, but there is a file with the same name:\n\n  " + %x(ls -l #{dir} 2>/dev/null) + "\nplease check, correct and retry" unless File.directory?(dir)
  else
    FileUtils.mkdir_p(dir)
    return true
  end
  return false
end


def print_chart_with_notes notes, strip_octave: false
  chart = $charts[:chart_notes]
  chart.each_with_index do |row, ridx|
    print '  '
    row[0 .. -2].each_with_index do |cell, cidx|
      if comment_in_chart?(cell)
        print cell
      elsif strip_octave && notes.include?(cell.strip[0..-2])
        print cell
      elsif !strip_octave && notes.include?(cell.strip)
        print cell
      else
        hcell = ' ' * cell.length
        hcell[hcell.length / 2] = '-'
        print hcell
      end
    end
    puts "\e[0m\e[2m#{row[-1]}\e[0m"
  end
end


def check_needed_viewer_progs needed
  not_found = needed.reject {|x| system("which #{x} >/dev/null 2>&1")}
  err "These programs are needed to view player images with method '$opts[:viewer]', but they cannot be found: #{not_found}" if not_found.length > 0
end


def mostly_avoid_double_invocations

  # Avoid most cases of double invocations; epecially if both instances may use microphone
  # or speaker or fifo.
  #
  # Here we only find out who is running and barf on unwanted others; see mode_jamming.rb
  # for code, that actually requires a second instance
  
  # The files are named 'last' because they still exist after program end. These files will
  # be written or removed at the end of this method
  $pidfile_listen_fifo = "#{$dirs[:data]}/pid_last_listen_fifo"
  pidfile_jamming = "#{$dirs[:data]}/pid_last_jamming"

  # mb = maybe, because we cannot be sure that these processes still exist. Therefore, below
  # we only act if their pid appears in the process list, which confirms their existence
  pid_listen_fifo_mb, pid_jamming_mb = [$pidfile_listen_fifo, pidfile_jamming].map do |f|
    File.exist?(f) && File.read(f).to_i
  end

  # Set initial values according to this processes owns mode and options; check other procs
  # below and maybe set these vars to true then. 'p' stands for 'predicate',
  # 'we_listen_fifo' for 'we would like to listen for fifo'
  #
  $runningp_listen_fifo = we_listen_fifo = ($mode == :listen && $opts[:jamming])
  $runningp_jamming = we_jamming = ($mode == :jamming)

  # Some modes never use microphone or speaker or fifo
  return if [:develop, :print].include?($mode)

  #
  # Go through process-list and bail out via 'next' if we find, that visited process does
  # not collide; but throw error at end of loop if we get there
  #
  
  IO.popen('ps -ef').each_line do |line|
    
    it_pid, it_cmd = line.chomp.split(' ',8).then {|it| [it[1].to_i, it[-1]]}

    # Skip non-harpwise processes
    next unless it_cmd['ruby'] && it_cmd['harpwise']

    # Skip ourself, so that only other processes (and rather not this one) will be
    # considered and checked below
    next if Process.pid == it_pid

    #
    # While we are here: Collect information about instances of harpwise, that are related
    # with jamming
    #
    
    if it_pid == pid_listen_fifo_mb
      # Now we know, that the process for pid_listen_fifo_mb is still running
      err("There is an instance of harpwise (pid #{pid_listen_fifo_mb}) already, that is listening on fifo:  '#{it_cmd}'\nHowever, this (the current) instance of harpwise would like to listen on fifo too;  exiting to avoid double-listen;  please check.") if we_listen_fifo
      $runningp_listen_fifo = true
    end

    if it_pid == pid_jamming_mb
      # Now we know, that the process for pid_jamming_mb is still running
      err("Another instance of 'harpwise jamming' (pid #{pid_jamming_mb}) is already running:  '#{it_cmd}'") if $mode == :jamming
      $runningp_jamming = true
    end

    #
    # Now check for colliding instances of harpwise
    #
    
    # Here we have the two acceptable cases
    if $mode == :jamming
      # If we are jamming, we tolerate anything; the case of another instance of harpwise,
      # that wants to read the fifo too, has already been handled above
      next
    else
      # If we are not jamming, we tolerate a jammer; e.g. user might want to play the
      # lick-progression while jam along is already running
      next if it_pid == pid_jamming_mb
    end

    # None of the resolving conditions above applies, so we probably would collide with the
    # other process
    err "An instance of this program is already running: pid: #{it_pid}, command line: '#{it_cmd}'"

  end
  
  # We can write this only after checking all procs above; otherwise we might overwrite the
  # information of a process, that is still running.
  File.write($pidfile_listen_fifo, "#{Process.pid}\n") if we_listen_fifo
  File.write(pidfile_jamming, "#{Process.pid}\n") if we_jamming

  # Remove stale files (of any origin) here, so that we dont need to do this in the
  # exit-handler
  FileUtils.rm($pidfile_listen_fifo) if File.exist?($pidfile_listen_fifo) && !$runningp_listen_fifo
  FileUtils.rm(pidfile_jamming) if File.exist?(pidfile_jamming) && !$runningp_jamming
end


def initialize_debugging_mb
  # most of the time there is no code to use this debug-log; but we keep it nevertheless for
  # debugging hard problems in the future
  $debug_log_file = "#{$dirs[:data]}/debug.log"
  if $opts && $opts[:debug]
    $debug_log = File.open($debug_log_file, 'w')
  end
  $debug_info = Hash.new  
end


def maybe_write_pers_data
  if $pers_file && $pers_data.keys.length > 0 && $pers_fingerprint != $pers_data.hash
    FileUtils.cp($pers_file, $pers_file_old) if File.exist?($pers_file)
    File.write($pers_file, JSON.pretty_generate($pers_data) + "\n")
    $pers_fingerprint = $pers_data.hash
  end
end


def days_ago_in_words ago
  if ago == 0
    'today'
  elsif ago == 1
    'yesterday'
  elsif ago <= 28
    "#{ago} days ago"
  elsif ago <= 90
    "#{(ago/7.0).round} weeks ago"
  else
    "#{(ago/30.0).round} months ago"
  end
end
