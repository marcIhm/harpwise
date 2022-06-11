#
# Play from the commandline
#

def do_play
  $all_licks, $licks = read_licks
  holes = []
  lnames = []
  special = []
  report = []
  other = []
  special_allowed = %w(ran rand random iterate iter cycle)
  report_allowed = %w(print dump history hist)
  all_lnames = $licks.map {|l| l[:name]}
  
  jtext = nil
  do_write_journal = true

  prepare_term
  start_kb_handler
  any_key = "\e[2mPress any key for next lick (or 'c' to go without)\e[0m"
  no_wait_for_key = false

  #
  # Partition arguments
  #
  
  $to_play.join(' ').split.each do |tp| # allow -1 (oct) +2 to be passed as '-1 (oct) +2'
    if musical_event?(tp)
      holes << tp
    elsif $harp_holes.include?(tp)
      holes << tp
    elsif $harp_notes.include?(tp)
      holes << $note2hole[tp]
    elsif all_lnames.include?(tp)
      lnames << tp
    elsif special_allowed.include?(tp)
      special <<
        if tp == 'iter'
          'iterate'
        elsif tp == 'ran' || tp == 'rand'
          'random'
        else
          tp
        end.to_sym
    elsif report_allowed.include?(tp)
      report <<
        if tp == 'hist'
          'history'
        else
          tp
        end.to_sym
    else
      other << tp
    end
  end

  #
  # Check results for consistency
  # 

  if other.length > 0
    puts "Cannot understand these arguments: #{other};"
    puts "they are none of:"
    puts "- musical events in ()"
    puts "- holes: #{$harp_holes}"
    puts "- notes: #{$harp_notes}"
    puts "- licks: #{all_lnames}"
    puts "- special: #{special_allowed}"
    puts "- report: #{report_allowed}"
    err 'See above'
  end
  
  sources_count = [holes, lnames, special, report].select {|s| s.length > 0}.length
  if sources_count == 0
    puts 'Nothing to play'
    exit
  end
  
  if sources_count > 1
    puts "The following types of arguments are present, but only one of them can be handled at a time:"
    puts "- holes (maybe converted from given notes): #{holes}" if holes.length > 0
    puts "- licks: #{lnames}" if lnames.length > 0
    puts "- special: #{special}" if special.length > 0
    puts "- report: #{report}" if report.length > 0
    err 'See above'
  end
  
  if holes.length > 0 && ( $opts[:tags] || $opts[:no_tags] )
    err "Cannot use option '--tags' or '--no-tags' when playing holes #{holes}"
  end
  
  if special.include?(:iterate) && special.include?(:cycle)
    err "Cannot use special words 'iterate' and 'cycle' at the same time"
  end

  if report.length > 1
    err "Only one of these allowed at the same time: #{report_allowed}, but given is: #{report}"
  end
  
  puts

  #
  #  Actually play
  #
  
  if holes.length > 0

    play_and_print_holes holes

  elsif lnames.length > 0

    lnames.each do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      play_and_print_lick lick
    end
      
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
          if no_wait_for_key
            sleep 0.5
          else
            puts any_key
            no_wait_for_key = true if $ctl_kb_queue.deq == 'c'
            puts
          end
        end
      else
        play_and_print_lick $licks.sample(1)[0]
      end

    else # special is cycle or iterate without random

      begin
        $licks.each do |lick|
          play_and_print_lick lick
          puts any_key
          $ctl_kb_queue.deq
          puts
        end
      end while special.include?(:cycle)
      puts "Iterated through all #{$licks.length} licks."
      
    end

  elsif report.length > 0

    case report[0]
    when :print
           print_lick_and_tag_info
    when :history
           print_last_licks_from_journal $all_licks
    when :dump
           pp $all_licks
    end
    exit
    
  else
    err "Internal error"
  end
end


def play_and_print_holes holes
  holes.each_with_index do |hole, i|
    print ' ' if i > 0
    print hole
    if musical_event?(hole)
      sleep $opts[:fast]  ?  0.25  :  0.5
    else
      play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    end
  end
  puts
end


def play_and_print_lick lick
  if lick[:rec] && !$opts[:holes]
    puts "Lick #{lick[:desc]} (h for help)\n" + lick[:holes].join(' ')
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
    puts
  else
    puts "Lick #{lick[:desc]}"
    play_and_print_holes lick[:holes]
    puts
  end
end
