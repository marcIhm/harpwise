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
  special_allowed = %w(ran rand random iterate iter cycle cyc)
  report_allowed = %w(print dump history hist)
  all_lnames = $licks.map {|l| l[:name]}
  
  jtext = nil

  prepare_term
  start_kb_handler
  any_key = "\e[2mPress any key for next lick (or 'c' to go without)\e[0m"
  no_wait_for_key = false

  puts "Type is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} licks."
  
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
      special << ({'iter' => 'iterate',
                   'cyc' => 'cycle',
                   'ran' => 'random',
                   'rand' => 'random'}[tp] || tp).to_sym
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
    puts "The following types of arguments are present,\nbut ONLY ONE OF THEM can be handled at a time:"
    puts "- holes (maybe converted from given notes): #{holes}" if holes.length > 0
    puts "- licks: #{lnames}" if lnames.length > 0
    puts "- special: #{special}" if special.length > 0
    puts "- report: #{report}" if report.length > 0
    err 'See above'
  end
  
  if holes.length > 0 && ( $opts[:tags_all] || $opts[:tags_any] || $opts[:no_tags_any] || $opts[:no_tags_all] )
    err "Cannot use option '--tags_any', '--tags_all', '--no-tags-any' or '--no-tags-all' when playing holes #{holes}"
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

    play_holes holes, true, true

  elsif lnames.length > 0

    lnames.each do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      play_and_print_lick lick
      jtext = sprintf('Lick %s: ', lick[:name]) + lick[:holes].join(' ')
      IO.write($journal_file, "#{jtext}\n\n", mode: 'a')
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
          if lick != $licks[-1] || special.include?(:cycle)
            if no_wait_for_key
              sleep 0.5
            else
              puts any_key
              no_wait_for_key = true if $ctl_kb_queue.deq == 'c'
              puts
            end
          end
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


def play_and_print_lick lick
  if lick[:rec] && !$opts[:holes]
    puts "Lick #{lick[:name]} (h for help)\n" + lick[:holes].join(' ')
    print "\e[0m\e[2m"
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    puts "Desc: #{lick[:desc]}" if lick[:desc]
    print "\e[0m"
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
    puts
  else
    puts "Lick #{lick[:name]} (h for help)"
    play_holes lick[:holes], true, true
    puts
  end
end
