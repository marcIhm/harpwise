# -*- fill-column: 78 -*-

#
# General helper functions
#


def match_or cand, choices
  return unless cand
  matches = choices.select {|c| c.start_with?(cand)}
  yield "'#{cand}'", choices.join(', ') unless matches.length == 1
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
    clear_area_help
    puts "\e[#{$line_help}H\e[0m"
  end
  puts "Keys available when playing a #{what}:\e[0m\e[32m\n"
  body.lines.each {|l| puts '      ' + l.chomp + "\n"}
  print "\e[0mType any key to continue ..."
  $ctl_kb_queue.clear
  $ctl_kb_queue.deq
  unless first_lap
    clear_area_help 
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
             "Notes played by trainer only.\n\n"
           end, mode: 'a')
end


def get_last_lick_idxs_from_journal
  lnames = []
  File.readlines($journal_file).each do |line|
    md = line.match(/^Lick +([^, ]+)/)
    lnames << md[1] if md
    lnames.shift if lnames.length > 20
  end
  err "Did not find any licks in #{$journal_file}" unless lnames.length > 0
  idxs = lnames.map do |ln|
    $licks.index {|l| l[:name] == ln }
  end.select(&:itself)
  err "Could not find any lick names #{lnames} from #{$journal_file} among current set of licks #{$licks.map {|l| l[:name]}}" if idxs.length == 0
  idxs.reverse
end


def print_last_licks_from_journal
  puts "\nList of most recent licks played:"
  puts "  - abbrev (e.g. '2l') for '--start-with'"
  puts "  - name,tag1,tag2, ... of lick"
  puts
  puts "Last lick comes first:"
  puts
  cnt = 1
  get_last_lick_idxs_from_journal.each do |idx|
    print '  '
    if cnt == 1
      print ' l: '
    elsif cnt <= 9
      print cnt.to_s + 'l: '
    else
      print '    '
    end
    cnt += 1
    puts $licks[idx][:desc]
    
  end
  puts
  puts "(from #{$journal_file})"
  puts
end


def print_all_licks
  puts "\nList of all known licks (after applying selections):"
  puts
  lname = $licks.max_by {|l| l[:name].length}
  $licks.each do |lick|
    puts "  %#{lname[:name].length}s : %s" % [lick[:name], lick[:tags].join(',')]
  end
  puts
  puts "#{$licks.length} licks"
  puts "from #{$lick_file}"
end
