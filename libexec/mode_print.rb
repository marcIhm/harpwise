#
# Print from the commandline
#

def do_print to_print

  # We expect lick-names on commandline, so dont narrow to tag-selection
  $licks = $all_licks if !$extra
  
  puts "\n\e[2mType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} of #{$all_licks.length} licks.\e[0m"
  puts

  if $extra
    args_for_extra = to_print
    if $opts[:lick_prog]
      allowed = %w(licks-details licks-list licks-list-all)
      err "Options --lick-prog only useful for these extra arguments: #{allowed.join(',')}, not #{$extra}" unless allowed.include?($extra)
      _ = process_opt_lick_prog
      $all_licks, $licks, $all_lick_progs = read_licks    
    end
  else
    holes_or_notes, lnames, lpnames, snames, spnames = partition_for_mode_or_amongs(to_print, extra_allowed: true)
  end

  # common error checking
  err_args_not_allowed(args_for_extra) if $extra && !%w(player players).include?($extra) && args_for_extra.length > 0

  
  if !$extra

    if holes_or_notes.length > 0
      
      puts_underlined 'Printing Holes or notes given as arguments.', ' ', dim: false
      print_holes_and_more holes_or_notes
      
    elsif snames.length > 0

      puts_underlined 'Printing scales given as arguments.', ' ', dim: false
      snames.each do |sn|
        sname = get_scale_from_sws(sn)
        puts_underlined "#{sname}:", '-', dim: false
        puts
        scale_holes, _ = read_and_parse_scale(sname)
        print_holes_and_more scale_holes
        if $scale2desc[sname] || $scale2short[sname]
          puts
          print "\e[2mShort: #{$scale2short[sname]}\e[0m   " if $scale2short[sname]
          print "\e[2mDesc: #{$scale2desc[sname]}\e[0m" if $scale2desc[sname]
          puts
        end
        puts
        puts if snames.length > 1
      end
      puts "#{snames.length} scales printed." unless $opts[:terse]

    elsif spnames.length > 0

      puts_underlined 'Printing scale progressions given as arguments.', ' ', dim: false
      spnames.each do |spnm|
        print_single_scale_prog(spnm)
      end
      
    elsif lnames.length > 0
      
      puts_underlined 'Printing licks given as arguments.', ' ', dim: false
      lnames.each do |lname|
        puts_underlined "#{lname}:", '-', dim: false
        puts unless $opts[:terse]
        lick = $licks.find {|l| l[:name] == lname}
        print_holes_and_more lick[:holes_wo_events]
        print_lick_meta lick unless $opts[:terse]        
        puts if lnames.length > 1
      end
      puts "#{lnames.length} licks printed." unless $opts[:terse]

    elsif lpnames.length > 0

      puts_underlined 'Printing lick progressions given as arguments.', ' ', dim: false
      lpnames.each do |lpnm|
        lp = $all_lick_progs.values.find {|lp| lp[:name] == lpnm}
        print_single_lick_prog(lp)
      end
      
    else

      fail 'Internal error'

    end

  else
    
    case $extra

    when 'licks-details'

      puts_underlined 'Licks selected by e.g. tags and hole-count, progression:', vspace: !$opts[:terse]
      $licks.each do |lick|
        if $opts[:terse]
          puts "#{lick[:name]}:"
        else
          puts
          puts_underlined "#{lick[:name]}:", '-', dim: false, vspace: false
        end
        print_holes_and_more lick[:holes_wo_events]
        print_lick_meta lick unless $opts[:terse]                
      end
      puts
      puts "\e[2mTotal count of licks printed: #{$licks.length}\e[0m"

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
      puts "\e[2mTotal count of licks printed: #{licks.length}\e[0m"

    when 'licks-with-tags'

      print_licks_by_tags $licks
      
    when 'licks-tags-stats'

      print_lick_and_tag_stats $all_licks

    when 'licks-history'

      print_last_licks_from_history $all_licks

    when 'licks-starred'

      print_starred_licks

    when 'lick-progs', 'lick-progressions'

      print_lick_progs
    
    when 'licks-dump'

      print JSON.pretty_generate($licks)
      
    when 'holes-history'

      print_last_holes_from_history $all_licks

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
      puts "\e[2mTotal count of scales printed: #{$all_scales.length}\e[0m"

    when 'scale-progs', 'scale-progressions'

      puts_underlined 'All scale-progressions:'
      $all_scale_progs.map do |spnm, _|
        print_single_scale_prog spnm
      end
    
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
  puts "\e[2mHoles or notes given:\e[0m" unless $opts[:terse]
  print_in_columns holes_or_notes, pad: :tabs
  return if $opts[:terse]
  puts
  if $used_scales[0] == 'all'
    puts "\e[2mHoles or notes with scales omitted, because no scale specified.\e[0m"
    puts
  else
    scales_text = $used_scales.map {|s| s + ':' + $scale2short[s]}.join(',')
    puts "\e[2mHoles or notes with scales (#{scales_text}):\e[0m"
    print_in_columns(scaleify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
    puts
  end
  puts "\e[2mNotes:\e[0m"
  print_in_columns(holes_or_notes.map {|hon| $harp.dig(hon, :note) || hon})
  puts
  puts "\e[2mWith holes:\e[0m"
  print_in_columns(holeify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith holes and remarks:\e[0m"
  print_in_columns(remarkify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
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
  puts "\e[2mWith intervals to first, positive, maybe minus octaves:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes, prefer_plus: true).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first as semitones:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes, prefer_names: false).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first as positive semitones (maybe minus octaves):\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes, prefer_names: false, prefer_plus: true).map {|ps| ins_dot_mb(ps)})
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


def print_last_licks_from_history licks
  puts "\e[2mList of most recent licks played, modes licks and play:"
  puts "  - abbrev (e.g. '2l') for '--start-with'"
  puts "  - name of lick\e[0m"
  puts
  puts "\e[2mHistory-records in reverse order: Last lick comes first,\n timestamp of start last:\e[0m"
  puts
  cnt = 1
  # must be consistent with selection in shortcut2history_record
  records = get_prior_history_records(:licks, :play).
              select {|r| r[:rec_type] != :entry || r[:play_type] == 'lick'}
  if records.length == 0
    puts "No lick-history found for modes 'lick' or 'play' in file\n  #{$history_file}.\n\n"
    exit 0
  end
  records.each do |rec|
    if rec[:rec_type] == :start
      puts "\e[2m Start with mode #{rec[:mode]} at #{rec[:timestamps][0]}\e[0m"
    elsif rec[:rec_type] == :skipping
      puts "\e[2m  ...\e[0m"
    else
      print '     '
      if cnt == 1
        print ' l: '
      elsif cnt <= 9
        print cnt.to_s + 'l: '
      else
        print '    '
      end
      cnt += 1
      puts rec[:name]
    end
  end
  puts
  puts "\e[2m(from #{$history_file})\e[0m"
  puts
end


def print_last_holes_from_history licks
  puts "\e[2mList of most recent holes played, no matter which mode:"
  puts
  puts "\e[2mHistory-records in reverse order: Last played holes come first,\n timestamp of start last:\e[0m"
  puts
  cnt = 1
  records = get_prior_history_records(:licks, :play, :quiz)
  if records.length == 0
    puts "No history found for any mode.\n\n"
    exit 0
  end
  records.each do |rec|
    if rec[:rec_type] == :start
      puts "\e[2m Start with mode #{rec[:mode]} at #{rec[:timestamps][0]}\e[0m"
    elsif rec[:rec_type] == :skipping
      puts "\e[2m  ...\e[0m"
    else
      puts "  mode #{rec[:mode]}, #{rec[:play_type]} '#{rec[:name]}':   #{rec[:holes].join('  ')}"
    end
  end
  puts
  puts "\e[2m(from #{$history_file})\e[0m"
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
  print "Licks with (un)stars:\n\n"
  maxlen = $starred.keys.map(&:length).max
  if $starred.keys.length > 0
    $starred.keys.sort {|x,y| $starred[x] <=> $starred[y]}.each do |lname|
      puts "  %-#{maxlen}s: %4d" % [lname, $starred[lname]]
    end
  else
    puts "   -- none --"
  end
  puts "\e[2m"
  puts "Total number of   starred licks.." + ("%6d" % $starred.values.select {|x| x > 0}.length).gsub(' ','.')
  puts "             of unstarred licks.." + ("%6d" % $starred.values.select {|x| x < 0}.length).gsub(' ','.')
  puts "                    Sum of both.." + ("%6d" % $starred.values.select {|x| x != 0}.length).gsub(' ','.')
  puts "Total number of selected licks..." + ("%6d" % $licks.length).gsub(' ','.')
  puts "             of      all licks..." + ("%6d" % $all_licks.length).gsub(' ','.')
  puts
  puts "Stars from: #{$star_file}\e[0m\n"
end      


def print_players args
  puts

  # If we have an external viewer (like feh), we get an exception on
  # ctrl-c otherwise
  Thread.report_on_exception = false

  if args.length == 0
    puts_underlined "Players known to harpwise"
    $players.all.each {|p| puts '  ' + $players.dimfor(p) + p + "\e[0m"}
    puts
    puts "\e[2m  r,random: pick one of these at random"
    puts "  l,last: last player (if any) featured in listen"
    puts "  a,all: all players shuffled in a loop\n\n"
    puts "Remarks:"
    puts "- Most information is taken from Wikipedia; sources are provided."
    puts "- You may add your own pictures to already created subdirs of\n    #{$dirs[:players_pictures]}"
    puts "- Players, which do not have all details yet, are dimmed\e[0m"
    puts
    puts "#{$players.all_with_details.length} players with details; specify a single name (or part of) to read details."

  elsif args.length == 1 && 'random'.start_with?(args[0])
    print_player $players.structured[$players.all_with_details.sample]

  elsif args.length == 1 && 'last'.start_with?(args[0])
    if $pers_data['players_last']
      player = $players.structured[$pers_data['players_last']]
      if player
        print_player player
      else
        puts "Name '#{name}' from '#{$pers_file}' is unknown (?)"
      end
    else
      puts "No player recorded in '#{$pers_file}'\ninvoke mode listen first"
    end

  elsif args.length == 1 && 'all'.start_with?(args[0])
    make_term_immediate
    $players.all_with_details.shuffle.each do |name|
      puts
      puts
      print_player $players.structured[name], true
      if $opts[:viewer] != 'feh' || !$players.structured[name]['image']
        puts
        puts "\e[2mPress any key for next Player ...\e[0m"
        $ctl_kb_queue.clear
        $ctl_kb_queue.deq
      end
    end
    puts
    puts "#{$players.all_with_details.length} players with their details."

  else
    selected_by_name, selected_by_content = $players.select(args)
    selected = (selected_by_name + selected_by_content).uniq
    total = selected.length
    if total == 0
      puts "No player matches your input; invoke without arguments to see a complete list of players"
    elsif selected_by_name.length == 1
      print_player $players.structured[selected_by_name[0]]
    elsif selected_by_name.length == 0 && selected_by_content.length == 1
      print_player $players.structured[selected_by_content[0]]
    else
      puts "Multiple players match your input:\n"
      puts
      if total <= 9
        if selected_by_name.length > 0
          puts "\e[2mMatches in name:\e[0m"
          puts
          selected_by_name.each_with_index {|p,i| puts "  #{i+1}: " + $players.dimfor(p) + p + "\e[0m"}
        end
        if selected_by_content.length > 0
          puts "\e[2mMatches in content:\e[0m"
          selected_by_content.each_with_index {|p,i| puts "  #{i+1}: " + $players.dimfor(p) + p + "\e[0m"}
        end
        make_term_immediate
        $ctl_kb_queue.clear
        4.times do
          puts
          sleep 0.04
        end
        print "\e[3A"
        print "Please type one of (1..#{total}) to read details: "
        char = $ctl_kb_queue.deq
        make_term_cooked
        if (1 .. total).map(&:to_s).include?(char)
          puts char
          puts "\n----------------------\n\n"
          print_player $players.structured[selected[char.to_i - 1]]
        else
          print "Invalid input: #{char}"
        end
      else
        puts "\e[2mMatches in name:\e[0m"
        selected_by_name.each {|p,i| puts "  " + p}
        puts "\e[2mMatches in content:\e[0m"
        selected_by_content.each {|p,i| puts "  " + p}
        puts
        puts "Too many matches (#{selected.length}); please be more specific"
      end
    end
    puts
  end
end


def print_player player, in_loop = false
  puts_underlined player['name']
  if $players.has_details?[player['name']]
    $players.all_groups.each do |group|
      next if group == 'name' || player[group].length == 0
      puts "\e[32m#{group.capitalize}:\e[0m"
      player[group].each {|l| puts "  #{l}"}
    end
    $players.view_picture(player['image'], player['name'], in_loop)
  else
    puts "\n\e[2mNot enough details known yet.\e[0m"
  end
end


def print_lick_progs

  if $all_lick_progs.length == 0
    puts "\nNo lick progressions defined."
    puts
  else
    keep_all = Set.new($opts[:tags_all]&.split(','))
    printed = 0
    $all_lick_progs.
      values.
      select {|lp| keep_all.empty? || (keep_all.subset?(Set.new(lp[:tags])))}.
      each do |lp|
      print_single_lick_prog(lp)
      printed += 1
    end
    if $opts[:tags_all] != ''
      puts "#{printed} of #{$all_lick_progs.length} lick progressions, selected by '-t #{$opts[:tags_all]}' from file #{$lick_file}"
    else
      puts "#{$all_lick_progs.length} lick progressions from file #{$lick_file}"
    end
  end
  
end


def print_single_lick_prog lp
  puts "#{lp[:name]}:"
  if $opts[:terse]
    puts("     Desc:  " + lp[:desc]) if lp[:desc]
  else
    puts "     Desc:  " + ( lp[:desc] || 'none' )
  end
  puts " %2d Licks:  #{lp[:licks].join('  ')}" % lp[:licks].length
  unless $opts[:terse]
    puts "     Line:  #{lp[:lno]}"
    puts "     Tags:  #{lp[:tags].join('  ')}" if lp[:tags].length > 0
    puts
  end
end


def print_single_scale_prog spname
  sp = $all_scale_progs[spname]
  puts "#{spname}:"
  puts "      Desc: #{sp[:desc]}"
  puts "  %2d Chords: #{sp[:chords].join(' ')}" % sp[:chords].length
  puts
end


def print_lick_meta lick
  puts
  puts "\e[2m     Desc:\e[0m #{lick[:desc]}"
  puts "\e[2m     Tags:\e[0m #{lick[:tags].join(' ')}"
  puts "\e[2m  rec-Key:\e[0m #{lick[:rec_key]}"
  puts
end

