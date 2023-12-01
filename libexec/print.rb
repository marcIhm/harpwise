#
# Print from the commandline
#

def do_print to_print

  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false

  $all_licks, $licks = read_licks

  puts "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
  puts

  if $extra
    args_for_extra = to_print
  else
    holes_or_notes, lnames, snames = partition_to_play_or_print(to_print)
  end

  # common error checking
  err "'harpwise print #{$extra}' does not take any arguments, these cannot be handled: #{args_for_extra}" if $extra && !%w(player players).include?($extra) && args_for_extra.length > 0

  
  if !$extra

    if holes_or_notes.length > 0
      
      puts_underlined 'Holes or notes given as arguments:'
      print_holes_and_more holes_or_notes
      
    elsif snames.length > 0

      puts_underlined 'Scales given as arguments:'
      snames.each do |sn|
        sname = get_scale_from_sws(sn)
        puts "\e[2m#{sname}:\e[0m"
        puts
        scale_holes, _ = read_and_parse_scale(sname)
        print_holes_and_more scale_holes
        if $scale2desc[sname] || $scale2short[sname]
          puts
          print "\e[2mShort: #{$scale2short[sname]}\e[0m   " if $scale2short[sname]
          print "\e[2mDesc: #{$scale2desc[sname]}\e[0m" if $scale2desc[sname]
          puts
        end
      end
      
    elsif lnames.length > 0
      
      puts_underlined 'Licks given as arguments:'
      lnames.each do |lname|
        puts_underlined "#{lname}:", '-'
        puts
        lick = $licks.find {|l| l[:name] == lname}
        print_holes_and_more lick[:holes_wo_events]
        unless $opts[:terse]
          puts " Description: #{lick[:desc]}"
          puts "        Tags: #{lick[:tags].join(' ')}"
          puts "Rec harp-key: #{lick[:rec_key]}"
        end
      end

    else

      fail 'Internal error'

    end

  else
    
    case $extra

    when 'licks-details'

      puts_underlined 'Licks selected by tags and hole-count:'
      $licks.each do |lick|
        puts
        puts_underlined "#{lick[:name]}:", '-', dim: false, vspace: false
        print_holes_and_more lick[:holes_wo_events]
      end
      puts "\e[2mTotal count: #{$licks.length}\e[0m"

    when 'licks-list', 'licks-list-all'

      if $extra['all']
        puts_underlined 'All licks as a list:'
        licks = $all_licks
      else
        puts_underlined 'Selected licks as a list:'
        licks = $licks
      end
      puts ' (name : holes)'
      puts
      maxl = licks.map {|l| l[:name].length}.max
      licks.each do |lick|
        puts " #{lick[:name].ljust(maxl)} : #{lick[:holes].length.to_s.rjust(3)}"
      end
      puts
      puts "\e[2mTotal count: #{licks.length}\e[0m"

    when 'licks-with-tags'

      print_licks_by_tags $licks
      
    when 'licks-tags-stats'

      print_lick_and_tag_stats $all_licks

    when 'licks-history'

      print_last_licks_from_journal $all_licks

    when 'licks-starred'

      print_starred_licks

    when 'dump'

      pp $all_licks
      
    when 'scales'

      puts_underlined 'All scales:'
      puts " \e[2m(name : holes)\e[0m"
      puts
      maxs = $all_scales.map {|s| s.length}.max
      $all_scales.each do |sname|
        scale_holes, _ = read_and_parse_scale(sname)
        puts " #{sname.ljust(maxs)} : #{scale_holes.length.to_s.rjust(3)}"
        if $scale2desc[sname] || $scale2short[sname]
          print "   \e[2mShort: #{$scale2short[sname]}\e[0m" if $scale2short[sname]
          print "   \e[2mDesc: #{$scale2desc[sname]}\e[0m" if $scale2desc[sname]
          puts 
        end
      end
      puts
      puts "\e[2mTotal count: #{$all_scales.length}\e[0m"

    when 'intervals'

      puts
      puts "Known intervals: semitones and various names"
      puts
      $intervals.each do |st, names|
        puts " %3dst: #{names.join(', ')}" % st
      end
      puts

    when 'player', 'players'

      $players = FamousPlayers.new
      print_players args_for_extra
      
    else

      fail "Internal error: unknown extra '#{$extra}'"

    end

  end
  puts

end


def print_holes_and_more holes_or_notes
  puts "\e[2mHoles or notes:\e[0m"
  print_in_columns holes_or_notes, pad: :tabs
  puts
  return if $opts[:terse]
  if $used_scales[0] == 'all'
    puts "\e[2mHoles with scales omitted, because no scale specified.\e[0m"
    puts
  else
    scales_text = $used_scales.map {|s| s + ':' + $scale2short[s]}.join(',')
    puts "\e[2mHoles with scales (#{scales_text}):\e[0m"
    print_in_columns(scaleify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
    puts
  end
  puts "\e[2mNotes:\e[0m"
  print_in_columns(holes_or_notes.map {|hon| $harp.dig(hon, :note) || hon})
  puts
  puts "\e[2mWith holes:\e[0m"
  print_in_columns(holeify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals between:\e[0m"
  print_in_columns(intervalify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals between as semitones:\e[0m"
  print_in_columns(intervalify(holes_or_notes, prefer_names: false).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first as semitones:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes, prefer_names: false).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mAs absolute semitones (a4 = 0):\e[0m"
  print_in_columns(holes_or_notes.map {|x| hon2semi(x)}, pad: :tabs)
  puts 
  puts "\e[2mAs absolute frequencies in Hz (equal temperament):\e[0m"
  print_in_columns(holes_or_notes.map {|x| '%.2f' % semi2freq_et(hon2semi(x).to_i)}, pad: :tabs)
end


def hon2semi hon
  note2semi(
    if $harp_holes.include?(hon)
      $hole2note[hon]
    else
      hon
    end
  ).to_s
end


def ins_dot_mb parts
  parts[0] + parts[1] +
    ( parts[2].strip.length > 0  ?  '.' + parts[2]  :  parts[2] )
end
  

def print_interval s1, s2
  iname = $intervals[s2 - s1]
  puts '  Interval ' +
       if iname
          iname[0] + " (#{s2 - s1}st)"
        else
          "#{s2 - s1}st"
       end + ':'
  puts
  print_semis_as_abs("    from: ", s1, "      to: ", s2)
end


def print_progression_view prog
  print '  '
  prog.each {|p| print p.to_s.rjust(8)}
  puts "\n\n"
end


def get_progression_views prog
  [prog.map {|s| $semi2hole[s] || '--'},
   prog.map {|s| semi2note(s) || '--'},
   prog,
   prog.map.with_index {|s,idx| idx == 0  ?  0  :  (s - prog[0])}]
end


def print_lick_and_tag_stats licks

  puts "\n(read from #{$lick_file})\n\n"
  
  puts_underlined "\nStatistics for all licks and tags"

  # stats for tags
  puts "All tags and the count of licks they appear in:\n\n"
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


def get_last_lick_idxs_from_trace licks, graceful = false
  lnames = []
  if !File.exist?($trace_file)
    return [] if graceful
    err "Expected trace-file #{$trace_file} could not be found"
  end
  File.readlines($trace_file).each do |line|
    md = line.match(/^Lick +([^, :\/]+):/)
    lnames << md[1] if md
    lnames.shift if lnames.length > 100
  end
  if lnames.length == 0
    return [] if graceful
    err "Did not find any licks in #{$trace_file}"
  end
  idxs = lnames.map do |ln|
    licks.index {|l| l[:name] == ln }
  end.select(&:itself)
  if idxs.length == 0
    return [] if graceful
    err "Could not find any of the lick names #{lnames} from trace-fie #{$trace_file} among current set of licks #{licks.map {|l| l[:name]}}"
  end
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
  get_last_lick_idxs_from_trace(licks).each do |idx|
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
  puts "(from #{$trace_file})"
  puts
end


def print_licks_by_tags licks

  puts "\n(read from #{$lick_file})\n\n"

  puts_underlined "\nReporting for licks selected by tags and hole-count only"
  
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


def print_players args
  puts
  if args.length == 0
    puts_underlined "All players known to harpwise"
    $players.all.each {|p| puts '  ' + $players.dimfor(p) + p + "\e[0m"}
    puts
    puts "\e[2m  r,random: pick one of these at random"
    puts "  l,last: last player (if any) featured in listen"
    puts "  a,all: all players in a loop\n\n"
    puts "Remark: you may add your own pictures of players to subdirs of\n#{$dirs[:players_pictures]}\n\n"
    puts "players, which have no details yet, are dimmed\e[0m"
    puts
    puts "#{$players.all_with_details.length} players with details. Specify a single name (or part of) to read details."
  elsif args.length == 1 && 'random'.start_with?(args[0])
    print_player $players.structured[$players.all_with_details.sample]
  elsif args.length == 1 && 'last'.start_with?(args[0])
    if File.exist?($players_file)
      name = IO.read($players_file).lines[0].chomp
      player = $players.structured[name]
      if player
        print_player player
      else
        puts "Name '#{name}' from '#{$players_file}' is unknown (?)"
      end
    else
      puts "Players file '#{$players_file}' does not exist (yet);\ninvoke mode listen first"
    end
  elsif args.length == 1 && 'all'.start_with?(args[0])
    $players.all_with_details.each do |name|
      puts
      puts
      print_player $players.structured[name]
    end
    puts
    puts "#{$players.all_with_details.length} players with their details."
  else
    selected = $players.select(args)
    if selected.length == 0
      puts "No player matches your input; invoke without arguments to see a complete list"
    elsif selected.length == 1
      print_player $players.structured[selected[0]]
    else
      puts "Multiple players match your input:\n"
      puts
      if selected.length <= 9
        selected.each_with_index {|p,i| puts "  #{i+1}: " + $players.dimfor(p) + p + "\e[0m"}
        make_term_immediate
        $ctl_kb_queue.clear
        puts
        print "Please type one of (1..#{selected.length}) to read details: "
        char = $ctl_kb_queue.deq
        make_term_cooked
        if (1 .. selected.length).map {|i| i.to_s}.include?(char)
          puts char
          puts "\n----------------------\n\n"
          print_player $players.structured[selected[char.to_i - 1]]
        else
          print "Invalid input: #{char}"
        end
      else
        selected.each {|p,i| puts "  " + p}
        puts
        puts "Too many matches (#{selected.length}); please be more specific"
      end
    end
    puts
  end
end


def print_player player
  puts_underlined player['name']
  if $players.has_details?[player['name']]
    $players.all_groups.each do |group|
      next if group == 'name' || player[group].length == 0
      puts "\e[32m#{group.capitalize}:\e[0m"
      player[group].each {|l| puts "  #{l}"}
    end
    $players.view_picture(player['image'][0]) if player['image'][0]
  else
    puts "\n\e[2mNo details known yet.\e[0m"
  end
end
