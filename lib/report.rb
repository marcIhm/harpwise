#
# Report about licks
#

def do_report to_report

  $all_licks, $licks = read_licks
  err "Can only do 1 report at a time, but not #{to_report.length}; too many arguments: #{to_report}" if to_report.length > 1
  to_report[0] = 'starred' if to_report[0] == 'stars'
  reports_allowed = %w(licks all-licks dump history-of-licks starred)
  to_report[0] = match_or(to_report[0], reports_allowed) do |none, choices|
    err "Argument for mode 'report' must be one of #{choices}, not #{none}; #{$for_usage}"
  end
  report = to_report[0].o2sym

  puts

  case report
  when :licks
    print_licks_by_tags $licks
  when :all_licks
    print_lick_and_tag_info $all_licks
  when :history_of_licks
    print_last_licks_from_journal $all_licks
  when :starred
    print_starred_licks
  when :dump
    pp $all_licks
  else
    err "Internal error: Unknown report '#{report}'"
  end
end


def print_lick_and_tag_info licks

  puts "\n(read from #{$lick_file})\n\n"
  
  puts "\nReporting for all licks\n"
  puts "=======================\n\n"

  # stats for tags
  puts "All tags:\n\n"
  counts = Hash.new {|h,k| h[k] = 0}
  licks.each do |lick|
    lick[:tags].each {|tag| counts[tag] += 1}
  end
  long_text = 'Total number of different tags:'
  maxlen = [long_text.length,counts.keys.max_by(&:length).length].max
  format = "  %-#{maxlen}s %6s\n"
  line = ' ' + '-' * (maxlen + 10)
  printf format,'Tag','Count'
  puts line
  counts.keys.sort.each {|k| printf format,k,counts[k]}
  puts line
  printf format, 'Total number of tags:', counts.values.sum
  printf format, long_text, counts.keys.length
  puts line
  printf format, 'Total number of licks: ',licks.length

  # stats for lick lengths
  puts "\nCounting licks by number of holes:\n"  
  format = "  %2d ... %2d     %3d\n"
  line = "  ----------    ---------------"
  puts "\n  Hole Range    Number of Licks"
  puts line
  by_len = licks.group_by {|l| l[:holes].length}
  cnt = 0
  lens = []
  by_len.keys.sort.each_with_index do |len,idx|
    cnt += by_len[len].length
    lens << len
    if cnt > licks.length / 10 || ( idx == by_len.keys.length && cnt > 0)
      printf format % [lens[0],lens[-1],cnt]
      cnt = 0
      lens = []
    end
  end
  printf format % [lens[0],lens[-1],cnt] if lens.length > 0
  puts line
  puts format % [by_len.keys.minmax, licks.length].flatten
  puts
end


def get_last_lick_idxs_from_journal licks
  lnames = []
  err "Expected journal file #{$journal_file} could not be found" unless File.exist?($journal_file)
  File.readlines($journal_file).each do |line|
    md = line.match(/^Lick +([^, :\/]+):/)
    lnames << md[1] if md
    lnames.shift if lnames.length > 100
  end
  err "Did not find any licks in #{$journal_file}" unless lnames.length > 0
  idxs = lnames.map do |ln|
    licks.index {|l| l[:name] == ln }
  end.select(&:itself)
  err "Could not find any of the lick names #{lnames} from #{$journal_file} among current set of licks #{licks.map {|l| l[:name]}}" if idxs.length == 0
  idxs.reverse.uniq[0..16]
end


def print_last_licks_from_journal licks
  puts "\nList of most recent licks played:"
  puts "  - abbrev (e.g. '2l') for '--start-with'"
  puts "  - name of lick"
  puts
  puts "Last lick comes first:"
  puts
  cnt = 1
  get_last_lick_idxs_from_journal(licks).each do |idx|
    print '  '
    if cnt == 1
      print ' l: '
    elsif cnt <= 9
      print cnt.to_s + 'l: '
    else
      print '    '
    end
    cnt += 1
    puts licks[idx][:name]
    
  end
  puts
  puts "(from #{$journal_file})"
  puts
end


def print_licks_by_tags licks

  puts "\n(read from #{$lick_file})\n\n"

  puts "\nReporting for licks selected by tags and hole-count only\n"
  puts "========================================================\n\n"
  
  ltags = tags = nil
  puts "Licks with their tags:"
  puts
  print '  '
  licks.each do |lick|
    tags = lick[:tags].join(',')
    if ltags && ltags != tags
      print " ..... #{ltags}\n  "
    else
      print ',' if ltags
    end
    print lick[:name]
    ltags = tags
  end
  puts " ..... #{ltags}"
  puts "\n  Total number of licks:   #{licks.length}"
  puts
end


def print_starred_licks
  print "Licks with stars:\n\n"
  maxlen = $starred.keys.map(&:length).max
  $starred.keys.sort {|x,y| $starred[x] <=> $starred[y]}.each do |lname|
    print "  %-#{maxlen}s: %4d\n" % [lname, $starred[lname]]
  end
  print "\nTotal number of starred licks: %4d\n" % $starred.keys.length
  print "Total number of stars:       %6d\n" % $starred.values.sum
  print "Stars from: #{$star_file}\n\n"
end      
