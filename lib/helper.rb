# -*- fill-column: 78 -*-

#
# General helper functions
#


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
  sane_term
  puts
  puts "ERROR: #{text} !"
  puts_err_context
  puts
  fail if $opts[:debug]
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


def display_kb_help what, first_lap, body
  if first_lap
    puts "\n\n\e[0m"
  else
    clear_area_comment
    puts "\e[#{$lines[:help]}H\e[0m"
  end
  puts "Keys available while playing a #{what}:\e[0m\e[32m\n"
  body.lines.each {|l| puts '      ' + l.chomp + "\n"}
  print "\e[0mType any key to continue ..."
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
  unless first_lap
    clear_area_comment
  end
  if first_lap
    puts "\ncontinue"
  else
    ctl_issue 'continue'
  end
end


def write_to_journal hole, since
  IO.write($journal_file,
           "%8.2f %8.2f %12s %6s\n" % [ Time.now.to_f - $program_start,
                                        Time.now.to_f - since,
                                        hole,
                                        $harp[hole][:note]],
           mode: 'a')
  $journal_listen << hole
end


def journal_start
  IO.write($journal_file,
           "\nStart writing journal at #{Time.now}, mode #{$mode}\n" +
           if $mode == :listen
             "Columns: Secs since prog start, duration, hole, note\n" +
               "Notes played by you only.\n\n"
           else
             "Notes played by harpwise only.\n\n"
           end, mode: 'a')
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
      err "Internal error: Unknown escape"
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


def bbg # prepare byebug
  sane_term
  stop_kb_handler
  print "\e[0m"
  require 'byebug'
  byebug
end
