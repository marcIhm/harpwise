#
# Play from the commandline
#

def do_play to_play
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false
  
  jtext = nil

  make_term_immediate

  puts "\nType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} licks."
  puts

  holes, lnames, snames, special, extra = partition_to_play_or_print(to_play, ['pitch'])

  if special.include?(:iterate) && special.include?(:cycle)
    err "Cannot use special words 'iterate' and 'cycle' at the same time"
  end

  #
  #  Actually play
  #
  
  if holes.length > 0

    play_holes holes, true, true

  elsif snames.length > 0

    snames.each do |sname|
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      play_holes scale_holes, true, true
      jtext = sprintf('Scale %s: ', sname) + scale_holes.join(' ')
      IO.write($journal_file, "#{jtext}\n\n", mode: 'a')
    end
      
  elsif lnames.length > 0

    lnames.each do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      play_and_print_lick lick
      jtext = sprintf('Lick %s: ', lick[:name]) + lick[:holes].join(' ')
      IO.write($journal_file, "#{jtext}\n\n", mode: 'a')
    end

  elsif extra.length > 0

    play_adjustable_pitch
    
  elsif special.length > 0

    if special.include?(:random)

      if special.include?(:cycle) || special.include?(:iterate)
        lick_idx = nil
        loop do
          # avoid playing the same lick twice in a row
          if lick_idx
            lick_idx = (lick_idx + 1 + rand($licks.length - 1)) % $licks.length
          else
            lick_idx = rand($licks.length)
          end
          play_and_print_lick $licks[lick_idx]
          maybe_wait_for_key
        end
      else
        play_and_print_lick $licks.sample(1)[0]
      end

    else # special is cycle or iterate without random

      begin
        $licks.each do |lick|
          play_and_print_lick lick
          if lick != $licks[-1] || special.include?(:cycle)
            maybe_wait_for_key
          end
        end
      end while special.include?(:cycle)
      puts "Iterated through all #{$licks.length} licks."
      
    end

  else
    fail "Internal error"
  end
end


def partition_to_play_or_print to_p, extra_allowed = []

  holes = []
  lnames = []
  snames = []
  special = []
  extra = []
  other = []

  all_lnames = $licks.map {|l| l[:name]}
  all_snames = scales_for_type($type)
  
  to_p.join(' ').split.each do |tp| # allow -1 (oct) +2 to be passed as '-1 (oct) +2'
    if musical_event?(tp)
      holes << tp
    elsif $harp_holes.include?(tp)
      holes << tp
    elsif $harp_notes.include?(tp)
      holes << $note2hole[tp]
    elsif all_lnames.include?(tp)
      lnames << tp
    elsif all_snames.include?(tp)
      snames << tp
    elsif (md = tp.match(/^(\dlast|\dl)$/)) || tp == 'last' || tp == 'l'
      lnames << $all_licks[get_last_lick_idxs_from_journal($all_licks)[md  ?  md[1].to_i - 1  :  0] || 0][:name]
    elsif $conf[:specials_allowed_play].include?(tp)
      special << ($conf[:specials_allowed_play_2_long][tp] || tp).to_sym
    elsif extra_allowed.include?(tp)
      extra << tp
    else
      other << tp
    end
  end

  #
  # Check results for consistency
  # 

  sources_count = [holes, lnames, snames, special, extra].select {|s| s.length > 0}.length

  if other.length > 0 || sources_count == 0
    puts
    if other.length == 0
      puts 'Nothing to play or print; please specify any of:'
    else
      puts "Cannot understand these arguments: #{other};"
      puts 'they are none of (exact match required):'
    end
    puts "\n- musical events in () or []"
    puts "\n- holes:"
    print_in_columns $harp_holes
    puts "\n- notes:"
    print_in_columns $harp_notes
    puts "\n- scales:"
    print_in_columns all_snames
    puts "\n- licks:"
    print_in_columns all_lnames
    puts "\n- special:"
    print_in_columns $conf[:specials_allowed_play]
    if extra_allowed.length > 0
      puts "\n- extra:"
      print_in_columns extra_allowed
    end
    puts
    err 'See above'
  end
  
  if sources_count > 1
    puts "The following types of arguments are present,\nbut ONLY ONE OF THEM can be handled at a time:"
    puts "- holes (maybe converted from given notes): #{holes}" if holes.length > 0
    puts "- scales: #{snames}" if snames.length > 0
    puts "- licks: #{lnames}" if lnames.length > 0
    puts "- special: #{special}" if special.length > 0
    err 'See above'
  end

  special << $opts[:doiter].to_sym if $opts[:doiter]
  
  [holes, lnames, snames, special, extra]

end


def play_and_print_lick lick
  sleep 1 if $ctl_rec[:loop_loop]
  if lick[:rec] && !$opts[:holes] && !$opts[:reverse]
    puts "Lick #{lick[:name]} (h for help)\n" + lick[:holes].join(' ')
    print "\e[0m\e[2m"
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    puts "Desc: #{lick[:desc]}" unless lick[:desc].to_s.empty?
    print "\e[0m"
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
  else
    if $opts[:reverse]
      puts "Lick #{lick[:name]} in reverse (h for help)"
      play_holes lick[:holes].reverse, true, true
    else
      puts "Lick #{lick[:name]} (h for help)"
      play_holes lick[:holes], true, true
    end
  end
  puts
end

def maybe_wait_for_key
  if $ctl_rec[:lick_lick]
    puts "\e[0m\e[2mContinuing with next lick without waiting for key ('c' to toggle)\e[0m"
    sleep 0.5
  else
    puts "\e[0m\e[2m" +
         "Press any key for next lick, especially:\n" +
         "  c: continue without further questions\n" +
         "  L: loop over next and all licks until pressed again " +
         ( $ctl_rec[:loop_loop]  ?  "(already ON)"  :  "(currently OFF)" ) +
         "\e[0m"
    char = $ctl_kb_queue.deq
    $ctl_rec[:lick_lick] = !$ctl_rec[:lick_lick] if char == 'c'
    $ctl_rec[:loop_loop] = !$ctl_rec[:loop_loop] if char == 'L'
    puts
  end
end
