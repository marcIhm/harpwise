#
# Play from the commandline
#

def do_print to_print
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false
  
  $all_licks, $licks = read_licks
  holes, lnames, snames, extra = partition_to_play_or_print(to_print, %w(all-licks all-scales))

  puts "\nType is #{$type}, key of #{$key}."
  puts
  
  if holes.length > 0

    puts_underlined 'Holes given as arguments:'
    print_holes_and_more holes

  elsif snames.length > 0

    puts_underlined 'Scales given as arguments:'
    snames.each do |sname|
      puts " #{sname}:"
      puts
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      print_holes_and_more scale_holes
    end
      
  elsif lnames.length > 0

    puts_underlined 'Licks given as arguments:'
    lnames.each do |lname|
      puts "#{lname}:"
      puts '-' * (lname.length + 1)
      puts
      lick = $licks.find {|l| l[:name] == lname}
      print_holes_and_more lick[:holes]
    end

  elsif extra.length > 0

    err "only one of 'all-licks', 'all-scales' is allowed, not both" if extra.length > 1
    if extra[0] == 'all-licks'
      puts_underlined 'All licks:'
      puts ' (name : holes)'
      puts
      maxl = $all_licks.map {|l| l[:name].length}.max
      $licks.each do |lick|
        puts " #{lick[:name].ljust(maxl)} : #{lick[:holes].length.to_s.rjust(3)}"
      end
      puts
      puts "Total count: #{$all_licks.length}"
    else
      puts_underlined 'All scales:'
      puts ' (name : holes)'
      puts
      maxs = $all_scales.map {|s| s.length}.max
      $all_scales.each do |sname|
        scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
        puts " #{sname.ljust(maxs)} : #{scale_holes.length.to_s.rjust(3)}"
      end
      puts
      puts "Total count: #{$all_scales.length}"
    end
  end

  puts
end


def print_holes_and_more holes
  puts "Holes:"
  print_in_columns holes
  puts
  if $used_scales[0] != 'all'
    scales_text = $used_scales.map {|s| s + ':' + $scale2short[s]}.join(',')
    puts "Holes with scales (#{scales_text}):"
    print_in_columns(scaleify(holes).map {|ps| ins_dot_mb(ps)})
    puts
  end
  puts "Holes with notes:"
  print_in_columns(noteify(holes).map {|ps| ins_dot_mb(ps)})
  puts
  puts "Holes with intervals:"
  print_in_columns(intervalify(holes).map {|ps| ins_dot_mb(ps)})
  puts
end


def ins_dot_mb parts
  parts[0] + parts[1] +
    ( parts[2].strip.length > 0  ?  '.' + parts[2]  :  parts[2] )
end
  
