#
# Play from the commandline
#

def do_print to_print
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false
  
  $all_licks, $licks = read_licks
  holes, lnames, snames, _, _ = partition_to_play_or_print(to_print)

  puts "\nType is #{$type}, key of #{$key}."
  puts
  
  if holes.length > 0

    puts 'Holes given as arguments:'
    puts '========================='
    puts
    print_holes_and_more holes

  elsif snames.length > 0

    puts 'Scales given as arguments:'
    puts '=========================='
    puts
    snames.each do |sname|
      puts " #{sname}:"
      puts
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      print_holes_and_more scale_holes
    end
      
  elsif lnames.length > 0

    puts 'Licks given as arguments:'
    puts '========================='
    puts
    lnames.each do |lname|
      puts "#{lname}:"
      puts '-' * (lname.length + 1)
      puts
      lick = $licks.find {|l| l[:name] == lname}
      print_holes_and_more lick[:holes]
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
  
