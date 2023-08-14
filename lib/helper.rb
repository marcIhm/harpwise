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
  print "\e[0mERROR: #{text}"
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
  print "\e[0m\e[2m"
  print "\n(result of argument processing so far: #{clauses.length > 0  ?  clauses.join(', ')  :  'none'};\n"
  if $early_conf
    puts " config from #{$early_conf[:config_file]} and #{$early_conf[:config_file_user]})"
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
  Dir[$scale_files_template % [type, '*', '{holes,notes}']].map {|file| file2scale(file,type)}.sort
end

def describe_scales_maybe scales, type
  desc = Hash.new
  scales.each do |scale|
    sfile = $scale_files_template % [type, scale, 'holes']
    begin 
      _, holes_rem = YAML.load_file(sfile).partition {|x| x.is_a?(Hash)}
      holes = holes_rem.map {|hr| hr.split[0]}
      desc[scale] = "holes #{holes.join(',')}"
    rescue Errno::ENOENT, Psych::SyntaxError
    end
  end
  desc
end

def display_kb_help what, scroll_allowed, body
  if scroll_allowed
    puts "\n\e[0m"
  else
    clear_area_comment
    puts "\e[#{$lines[:help]}H\e[0m"
  end
  puts "Keys available while playing #{what}:\e[0m\e[32m\n"
  body.lines.each {|l| puts '    ' + l.chomp + "\n"}
  print "\e[0mPress any key to continue ..."
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


def dbg # prepare byebug
  make_term_cooked
  print "\e[0m"
  require 'byebug'
  byebug
end


def write_dump marker
  dumpfile = '/tmp/' + File.basename($0) + "_testing_dumped_#{marker}.json"
  File.delete(dumpfile) if File.exist?(dumpfile)
  structure = {scale: $scale, scale_holes: $scale_holes, licks: $licks, opts: $opts, conf: $conf, conf_system: $conf_system, conf_user: $conf_user, key: $key, }
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
                     map {|nm| ' ' * (-nm.length % 4) + nm}
                 when :space
                   names.map {|nm| '  ' + nm}
                 when :fill
                   names_maxlen = names.max_by(&:length).length
                   names.map {|nm| '  ' + ' ' * (names_maxlen - nm.length) + nm}
                 else
                   err "Internal error: #{pad}"
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

  if $lagging_freqs_lost > 0 && $total_freqs > 0
    afterthought += <<~end_of_content


         Lagging detected !
         ------------------

         harpwise has been lagging behind at least once;
         #{$lagging_freqs_lost} of #{$lagging_freqs_lost + $total_freqs} samples #{'(= %.1f%%)' % (100 * $lagging_freqs_lost / ($lagging_freqs_lost + $total_freqs))} have been lost.

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

         The frequency pipeline

         #{$freq_pipeline_cmd}

         had a maximum jitter of #{$max_jitter}, which means
         that your playing and its display by harpwise were out
         of sync at least once.

         This is out of control of harpwise and might be caused
         by external factors, like system-load or simply by
         hibernation of your computer.


         end_of_content

  end

  if afterthought.length > 0
    puts "\e[#{$lines[:message2]}H\e[0m\n" 
    afterthought.lines.each {|line| puts line.chomp + "\e[K\n"}
  end
end


def animate_splash_line single_line = false
  return if $splashed
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
  $splashed = true
end


def get_files_journal_trace
  trace = if $mode == :licks || $mode == :play || $mode == :report
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
  
  $journal_file, $trace_file  = get_files_journal_trace
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
    puts "Press any key to continue ...\e[K"
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
    return false
  end
end


def print_hom text, line = $lines[:hint_or_message]
  print "\e[#{line}H\e[2m#{text}\e[0m\e[K"
  $message_shown_at = Time.now.to_f
  text
end


def pending_message text
  $pending_message_after_redraw = text
  $message_shown_at = Time.now.to_f
  text
end
