#
# Report about licks
#

def do_report to_report

  $all_licks, $licks = read_licks
  reports_allowed = %w(licks dump journal jour starred star stars)

  err "Can only do 1 report at a time, but not #{to_report.length}; too many arguments: #{to_report}" if to_report.length > 1
  err "Unknown report '#{to_report[0]}', only these are allowed: #{reports_allowed}" unless reports_allowed.include?(to_report[0])
  report = to_report[0].to_sym
  report = :journal if report == :jour
  report = :starred if report == :star || report == :stars

  puts

  case report
  when :licks
    print_lick_and_tag_info
  when :journal
    print_last_licks_from_journal $all_licks
  when :starred
    print_starred_licks
  when :dump
    pp $all_licks
  end
end


def print_lick_and_tag_info all_licks = $all_licks, licks = $licks

  puts "\n(read from #{$lick_file})\n\n"

  iaal = "\nReporting for all licks\n=======================\n\n"
  if [:tags_any, :tags_all, :no_tags_any, :no_tags_all, :max_holes, :min_holes].any? {|o| $opts[o]}
    puts "\nReporting for licks selected by tags and hole-count only\n"
    puts "========================================================\n\n"
  else
    print iaal
    iaal = ''
  end

  print_licks_by_tags licks

  print iaal
  # stats for tags
  puts "All tags:\n\n"
  counts = Hash.new {|h,k| h[k] = 0}
  all_licks.each do |lick|
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
  printf format, 'Total number of licks: ',all_licks.length

  # stats for lick lengths
  puts "\nCounting licks by number of holes:\n"  
  format = "  %2d ... %2d     %3d\n"
  line = "  ----------    ---------------"
  puts "\n  Hole Range    Number of Licks"
  puts line
  by_len = all_licks.group_by {|l| l[:holes].length}
  cnt = 0
  lens = []
  by_len.keys.sort.each_with_index do |len,idx|
    cnt += by_len[len].length
    lens << len
    if cnt > all_licks.length / 10 || ( idx == by_len.keys.length && cnt > 0)
      printf format % [lens[0],lens[-1],cnt]
      cnt = 0
      lens = []
    end
  end
  printf format % [lens[0],lens[-1],cnt] if lens.length > 0
  puts line
  puts format % [by_len.keys.minmax, all_licks.length].flatten
  puts
end


def get_last_lick_idxs_from_journal licks = $licks
  lnames = []
  File.readlines($journal_file).each do |line|
    md = line.match(/^Lick +([^, :\/]+)/)
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


def print_last_licks_from_journal licks = $licks
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
