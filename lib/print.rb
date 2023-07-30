#
# Play from the commandline
#

def do_print to_print
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false

  $all_licks, $licks = read_licks
  extra_allowed = {'licks' => 'selected licks (e.g. by option -t) with their content',
                   'list-licks' => 'list of selected licks with hole count',
                   'list-all-licks' => 'list of all licks',
                   'list-all-scales' => 'list of all scales with hole count',
                   'interval' => 'interactive, adjustable interval',
                   'inter' => nil,
                   'progression' => 'take a base and semitone diffs, then spell it out',
                   'prog' => nil}
  
  holes_or_notes, lnames, snames, extra, args_for_extra = partition_to_play_or_print(to_print, extra_allowed, %w(progression prog interval inter))

  puts "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
  puts
  
  if holes_or_notes.length > 0

    puts_underlined 'Holes or notes given as arguments:'
    print_holes_and_more holes_or_notes

  elsif snames.length > 0

    puts_underlined 'Scales given as arguments:'
    snames.each do |sname|
      puts " \e[2m#{sname}:\e[0m"
      puts
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      print_holes_and_more scale_holes
    end
      
  elsif lnames.length > 0

    puts_underlined 'Licks given as arguments:'
    lnames.each do |lname|
      puts_underlined "#{lname}:", '-'
      puts
      lick = $licks.find {|l| l[:name] == lname}
      print_holes_and_more lick[:holes_wo_events]
      unless $opts[:terse]
        puts "Description: #{lick[:desc]}"
        puts "       Tags: #{lick[:tags].join(' ')}"
      end
    end

  elsif extra.length > 0

    err "only one of #{extra_allowed.keys} is allowed" if extra.length > 1

    if extra[0] == 'licks'
      puts_underlined 'Licks selected by tags and hole-count:'
      $licks.each do |lick|
        puts_underlined "#{lick[:name]}:", '-', dim: false, vspace: false
        print_holes_and_more lick[:holes_wo_events]
      end
      puts "\e[2mTotal count: #{$licks.length}\e[0m"
    elsif extra[0] == 'list-all-licks' || extra[0] == 'list-licks'
      if extra[0]['all']
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

    elsif extra[0] == 'list-all-scales'
      puts_underlined 'All scales:'
      puts " \e[2m(name : holes)\e[0m"
      puts
      maxs = $all_scales.map {|s| s.length}.max
      $all_scales.each do |sname|
        scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
        puts " #{sname.ljust(maxs)} : #{scale_holes.length.to_s.rjust(3)}"
      end
      puts
      puts "\e[2mTotal count: #{$all_scales.length}\e[0m"

    elsif extra[0] == 'interval' || extra[0] == 'inter'
      s1, s2 = normalize_interval(args_for_extra)
      print_interval s1, s2
      
    elsif extra[0] == 'progression' || extra[0] == 'prog'
      err "Need at a base note and some distances, e.g. 'a4 4st 10st'" unless args_for_extra.length >= 1
      puts_underlined 'Progression:'
      prog = base_and_delta_to_semis(args_for_extra)
      holes, notes, abs_semis, rel_semis = get_progression_views(prog)
      
      puts_underlined 'Holes:', '-'
      print_progression_view holes

      puts_underlined 'Notes:', '-'
      print_progression_view notes

      puts_underlined 'Absolute Semitones (a4 = 0):', '-'
      print_progression_view abs_semis

      puts_underlined 'Relative Semitones to first:', '-'
      print_progression_view rel_semis

    else
      fail "Internal error"
    end
  end

  puts
end


def print_holes_and_more holes_or_notes
  puts "\e[2mHoles or notes:\e[0m"
  print_in_columns holes_or_notes, pad: :tabs
  puts
  return if $opts[:terse]
  if $used_scales[0] != 'all'
    scales_text = $used_scales.map {|s| s + ':' + $scale2short[s]}.join(',')
    puts "\e[2mHoles with scales (#{scales_text}):\e[0m"
    print_in_columns(scaleify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
    puts
  end
  puts "\e[2mWith notes:\e[0m"
  print_in_columns(noteify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith holes:\e[0m"
  print_in_columns(holeify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals between:\e[0m"
  print_in_columns(intervalify(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mWith intervals to first as semitones:\e[0m"
  print_in_columns(intervalify_to_first(holes_or_notes, prefer_names: false).map {|ps| ins_dot_mb(ps)})
  puts
  puts "\e[2mAs absolute semitones:\e[0m"
  print_in_columns(holes_or_notes.map do |hon|
                     note2semi(
                       if $harp_holes.include?(hon)
                         $hole2note[hon]
                       else
                         hon
                       end
                     ).to_s
                   end,
                   pad: :tabs)
  puts 
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
