#
# Play from the commandline
#

def do_play to_play

  $all_licks, $licks, $all_lick_progs = read_licks(use_opt_lick_prog: false)

  if !$extra
    # We expect lick-names on commandline, so dont narrow to tag-selection
    $licks = $all_licks 
  elsif $opts[:lick_prog]
    err "Options --lick-prog only useful for extra argument licks, not #{$extra}" if $extra != 'licks'
    $licks = $all_licks 
    _ = process_opt_lick_prog
    $all_licks, $licks, $all_lick_progs = read_licks    
  end

  make_term_immediate

  puts "\n\e[2mType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} of #{$all_licks.length} licks.\e[0m"
  puts

  if $extra
    args_for_extra = to_play
  else
    holes_or_notes, semis, lnames, lpnames, snames, _ = partition_for_mode_or_amongs(to_play, extra_allowed: true)
  end

  # common error checking
  err_args_not_allowed(args_for_extra) if $extra == 'user' && args_for_extra.length > 0
  err_args_not_allowed(args_for_extra) if $extra == 'licks' && args_for_extra.length > 0
  err "Option '--start-with' only useful when playing 'licks'" if $opts[:start_with] && !$extra == 'licks'

  
  if !$extra 

    if holes_or_notes.length > 0

      puts "Some holes or notes"
      play_holes_or_notes_and_handle_kb holes_or_notes
      puts
      write_history('holes or notes', 'adhoc-holes', holes_or_notes)
      
    elsif snames.length > 0
      
      snames.each do |sname|
        scale_holes, _, _ = read_and_parse_scale_simple(sname)
        puts "Scale #{sname}"
        play_holes_or_notes_and_handle_kb scale_holes
        puts
        write_history('scale', sname, scale_holes)
      end
      
    elsif lnames.length > 0

      $opts[:iterate] = :cycle
      play_named_licks(lnames, refill: false)

    elsif semis.length > 0

      notes = semis.map {|s| semi2note(s.to_i)}
      puts "Some semitones converted to notes (a4 = 0st)"
      play_holes_or_notes_and_handle_kb notes
      puts
      write_history('semitones converted to notes', 'adhoc-semitones', notes)
      
    elsif lpnames.length > 0

      err "Can only play only one lick progression, not: #{lpnames.join(',')}" if lpnames.length > 1

      print_single_lick_prog($all_lick_progs[lpnames[0]])      
      lnames = $all_lick_progs[lpnames[0]][:licks]
      $opts[:iterate] = :cycle
      play_named_licks(lnames, refill: true)
      
    else

      fail 'Internal error'

    end

  else

    case $extra
    when 'pitch'

      key = if args_for_extra.length == 1
              key_wo_digit = args_for_extra[0].gsub(/\d$/,'')
              err "Unknown key '#{key_wo_digit}'; none of #{$conf[:all_keys]}" unless $conf[:all_keys].include?(key_wo_digit)
              args_for_extra[0]
            elsif args_for_extra.length > 1
              err "harpwise play pitch only accepts zero or one argument, not #{args_for_extra}"
            else
              nil
            end
      play_interactive_pitch(start_key: key)

    when 'interval', 'inter'

      s1, s2 = normalize_interval(args_for_extra)

      play_interactive_interval s1, s2
        
    when 'licks'

      do_play_licks args_for_extra
      
    when 'progression', 'prog'
      
      err "Need at a base hole or note and some semitone diffs or intervals, e.g. 'a4 4st 10st'" unless args_for_extra.length >= 1
      progs = args_for_extra.
                # replace dot by something unlikely, because some day
                # it might also be part of a hole-notation
                map {|a| a == '.'  ?  '###'  :  a}.  
                join(' ').
                split('###').
                map {|p| p.split.map {|hns| hns.strip}}
      play_interactive_progression(
        progs.map {|p| base_and_delta_to_semis(p)},
        progs.map {|p| p.join(' ')} )

    when 'chord'

      puts "A chord"
      err "Need at least two holes or notes or semitone-diffs or intervals, e.g. 'c3 7st'" unless args_for_extra.length >= 1
      _, first = hole_or_note_or_semi(args_for_extra[0], false)
      semis = args_for_extra[1 .. -1].map do |arg|
        tp, sem = hole_or_note_or_semi(arg)
        if tp == :diff
          first + sem
        else
          sem
        end
      end
      semis.unshift(first)
      play_interactive_chord semis, args_for_extra

    when 'user'

      rfile = $ulrec.rec_file
      if File.exist?(rfile)
        duration = '%.1fs' % sox_query(rfile, 'Length')
        puts "Playing \e[32m#{rfile}\e[0m, #{duration} ..."
        puts "\e[2m(h for help)"
        play_recording_and_handle_kb rfile
        puts
      else
        puts "User lick recording #{rfile} not present;\nrecord yourself in mode lick to create it."
        puts
      end

    else

      fail "Internal error: unknown extra '#{extra}'"

    end

  end
  puts
  
end


def partition_for_mode_or_amongs to_handle, amongs: nil, extra_allowed: false

  holes_or_notes = []
  semis = []
  lnames = []
  lpnames = []
  snames = []
  spnames = []
  other = []

  amongs ||= $amongs[$mode] || err("Internal error: not for mode #{$mode}")
  err("Internal error: #{amongs} includes :extra_w_wo_s") if amongs.include?(:extra_w_wo_s)

  # allow -1 (oct) +2 to be passed as '-1 (oct) +2'
  to_handle.join(' ').split.each do |th|

    what = recognize_among(th, amongs)

    if what == :note
      holes_or_notes << sf_norm(th)
    elsif what == :hole
      holes_or_notes << th
    elsif what == :event
      holes_or_notes << th
    elsif what == :semi_note
      semis << th
    elsif what == :scale
      snames << th
    elsif what == :scale_prog
      spnames << th
    elsif what == :lick
      lnames << th
    elsif what == :lick_prog
      lpnames << th
    elsif what == :last
      $all_licks, $licks, $all_lick_progs = read_licks
      record = shortcut2history_record(th)
      lnames << record[:name]
    else
      other << th
    end
  end

  #
  # Check results for consistency
  # 

  types_count = [holes_or_notes, semis, lnames, snames].select {|x| x.length > 0}.length

  if other.length > 0 
    puts
    puts "Cannot understand these arguments: #{other.join('  ')}#{not_any_source_of};"
    puts 'they are none of (exact match required):'
    print_amongs(amongs)
    if extra_allowed && $extra == ''
      puts
      puts "Alternatively you may give one of these extra keywords to #{$mode},\nwhich might be able to handle additional arguments:"
      print_amongs(:extra)
    end
    err "Cannot understand these arguments: #{other.join('  ')}\nSee above for full list of choices."
  end
  
  if extra_allowed && $extra == '' && types_count == 0
    puts
    puts "Nothing to handle for #{$mode}; please specify any of:"
    print_amongs([amongs, :extra])
    err 'See above'
  end
  
  if types_count > 1
    puts "The following #{types_count} types of arguments are present,\nbut ONLY ONE OF THEM can be handled at the same time:"
    puts
    puts "     Holes or Notes: #{holes_or_notes.join(' ')}" if holes_or_notes.length > 0
    puts "          semitones: #{semis.join(' ')}" if semis.length > 0
    puts "              Licks: #{lnames.join(' ')}" if lnames.length > 0
    puts "  Lick progressions: #{lpnames.join(' ')}" if lpnames.length > 0
    puts "             Scales: #{snames.join(' ')}" if snames.length > 0
    puts " Scale progressions: #{lpnames.join(' ')}" if spnames.length > 0
    puts
    err 'See above'
  end

  return [holes_or_notes, semis, lnames, lpnames, snames, spnames]

end


def hole_or_note_or_semi hns, diff_allowed = true

  # check if argument is interval or absolute note or hole or event or
  # many of them

  amongs = if diff_allowed
             [:hole, :note, :inter, :semi_note]
           else
             [:hole, :note]
           end
  what = recognize_among(hns, amongs)
  type, value = case what
                when :hole
                  [:abs, note2semi($hole2note[hns])]
                when :note
                  [:abs, note2semi(hns)]
                when :inter
                  [:diff, $intervals_inv[hns].to_i]
                when :semi_note
                  [:diff, hns.to_i]
                else
                  [nil, nil]
                end

  if !type
    print_amongs(*amongs)
    err "Given argument #{hns} is none of those given above"
  end
  
  return type, value
end


def normalize_interval args

  err "Need two arguments, to #{$mode} an interval (not #{args}):\n" +
      "  - a base-note or base-hole, e.g. 'c4' or '+2'\n" +
      "  - a difference in semitones, either as a number or as a name, e.g. '12st' or 'oct'\n" unless args.length == 2

  args.map!(&:downcase)
      
  tt = Array.new
  vv = Array.new
  args.each do |arg|
    t, v = hole_or_note_or_semi(arg)
    tt << t
    vv << v
  end
  s1 = s2 = 0
  case tt
  when [:abs, :abs]
    s1 = vv[0]
    s2 = vv[1]
  when [:diff, :diff]
    err "You specified two semitone-differences but no base note: #{args}"
  when [:abs, :diff]
    s1 = vv[0]
    s2 = s1 + vv[1]
  when [:diff, :abs]
    s1 = vv[1]
    s2 = s1 + vv[0]
  else
    fail "Internal error: unmatched: #{tt}"
  end

  return s1, s2
end


def base_and_delta_to_semis base_and_delta
  prog = Array.new
  bt, bv = hole_or_note_or_semi(base_and_delta[0], false)
  err "Progression should start with an absolute value (hole or note), but not with a semitone difference like #{base_and_delta[0]}" if bt == :diff
  prog << bv
  base_and_delta[1 .. -1].each do |diff|
    dt, dv = hole_or_note_or_semi(diff)
    err "Up from the second word of progression there are only semitone differences to initial note allowed (e.g. 9st or octave) but not an absolute note or hole like #{diff}; remark: in case of ambiguities between holes and semitones add 'st' to semitones, like in '3st'" if dt == :abs
    prog << prog[0] + dv
  end
  prog
end


def play_and_print_lick lick, extra = ''
  sleep 1 if $ctl_rec[:loop_loop]
  print "Lick #{lick[:name]}\e[2m#{extra}, "
  if lick[:rec] && !$opts[:holes] && !$opts[:reverse]
    puts "rec in #{lick[:rec_key]}" +
         ( $key == lick[:rec_key]  ?  ''  :  ", shifted to #{$key}" ) +
         "    (h for help)\e[0m\e[2m"
    sleep 0.02
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    sleep 0.02
    puts "Desc: #{lick[:desc]}" unless lick[:desc].to_s.empty?
    print "\e[0m"
    puts lick[:holes].join(' ')
    play_lick_recording_and_handle_kb lick, lick[:rec_start], lick[:rec_length], 0, true
  else
    puts ( $opts[:reverse]  ?  ' in reverse'  :  '' ) +
         "    (h for help)\e[0m\e[2m"
    sleep 0.02
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    sleep 0.02
    puts "Desc: #{lick[:desc]}" unless lick[:desc].to_s.empty?
    print "\e[0m"
    play_lick_holes_and_handle_kb ( $opts[:reverse]  ?  lick[:holes].reverse  :  lick[:holes] ),
                                  lick: lick,
                                  scroll_allowed: true,
                                  with_head: false
  end
  sleep 0.02
  puts
end


def play_licks_controller licks, refill, sleep_between: false
  stock = licks.clone
  prev_licks = Array.new
  lick = stock.shift

  print "\e[2m"
  if refill
    print "Set of licks will be played without end, "
  else 
    print "Set of licks will be played once, "
  end
  if $opts[:iterate] == :random
    puts "shuffled and in random order."
  else
    puts "in given order."
  end
  puts "\e[0m"
  
  loop do  ## one lick after the other

    write_history('lick', lick[:name], lick[:holes])
    
    loop do  ## repeats of the same lick
      play_and_print_lick lick, "    #{licks.length - stock.length}/#{licks.length}"
      
      if sleep_between && $ctl_rec[:lick_lick]
        $ctl_kb_queue.clear
        plen = $ctl_rec[:skip]  ?  3  :  5 
        print "\e[0m\e[2m#{plen} secs pause (any key for menu) "
        (0..10*plen).each do |i|
          sleep 0.1
          print '.' if i % 10 == 5
          break if !$ctl_kb_queue.empty?
        end
        puts "\e[0m"
      else
        sleep ( $opts[:fast] ? 0.25 : 0.5 )
      end
      if stock.length == 0 && !refill
        # last lick has been played, no need to ask
        lick = nil
        break
      end
      case maybe_wait_for_key_and_decide_replay
      when :next
        prev_licks << lick if lick && lick != prev_licks[-1]
        lick = stock.shift
        break
      when :redo
        redo
      when :edit
        puts
        edit_file($lick_file, lick[:lno])
        puts
        $all_licks, $licks, $all_lick_progs = read_licks
        redo
      when :named
        choose_prepare_for skip_term: true
        puts
        lnames = $all_licks.map {|l| l[:name]}
        input = choose_interactive("Please choose lick (current is #{lick[:name]}): ", lnames) do |lname|
          lk = $all_licks.find {|l| l[:name] == lname}
          "[#{lk[:tags].join(',')}] #{lk[:holes].length} holes, #{lk[:desc]}"
        end
        choose_clean_up skip_term: true
        if input
          lick = $all_licks.find {|l| l[:name] == input}
          puts "New lick."
        else
          puts "Canceled."
        end
      when :star_up
        star_unstar_lick(:up, lick)
        puts "Starred most recent lick"
        puts
      when :star_down
        star_unstar_lick(:down, lick)
        puts "Unstarred most recent lick"
        puts
      when :prev
        if prev_licks.length > 0
          lick = prev_licks.pop
        else
          puts "No previous lick available."
          puts
          redo
        end
        break
      end
    end  ## repeats of the same lick

    if !lick && stock.length == 0
      print "\e[2m"
      if refill
        print "Every licks played once, "
        if $opts[:iterate] == :random
          stock = refill.shuffle
          print "shuffled in random sequence."
        else
          stock = refill.clone
          print "in order of lickfile."
        end
        puts "   Starting over ..."
        puts
        lick = stock.shift
      else
        puts "Done with playing #{licks.length} licks."
        puts "\e[0m"
        return
      end
    end
  end  ## one lick after the other
end


def maybe_wait_for_key_and_decide_replay
  show_help = false
  if $ctl_rec[:lick_lick] && $ctl_kb_queue.empty?
    puts "\e[0m\e[2mContinuing with next lick without waiting for key ('c' to toggle)\e[0m"
    $ctl_kb_queue.clear
    return :next
  else
    loop do
      # lines are devided in segments, which are highlighted if they change
      lines_long = [["\e[0mPress:\e[2m      h: this help        .r: replay this lick    e: edit lickfile"],
                    ['    BACKSPACE: previous lick    */: star,unstar most recent lick'],
                    ['            n: choose lick by name'],
                    ["Keys here and while playing:   (help there for more keys)"],
                    ['      c: toggle continue without this menu (now ',
                     ( $ctl_rec[:lick_lick]  ?  ' ON'  :  'OFF' ), ')'],
                    ['    L,l: toggle loop for all licks (now ',
                     ( $ctl_rec[:loop_loop]  ?  ' ON'  :  'OFF' ), ')'],
                    ['  2-9,0: set num, if looping (l,L) enabled (now ',
                     get_num_loops_desc(true).to_s, ')'],
                    ["SPACE or RETURN for next lick ...\n"]]
       lines = if show_help
                 lines_long
              else
                [['Press:      h: show help with more keys (available now already)'],
                 ["SPACE or RETURN for next lick ...\n"]]
              end
       oldlines ||= lines
       oldlines_long ||= lines_long
      $ctl_kb_queue.clear
      # highlight diffs to initial state
      lines.zip(oldlines).each do |line, oldline|
        print "\e[0m\e[2m"
        # not strings but rather arrays of segments
        line.zip(oldline).each do |seg, oldseg|
          if seg != oldseg
            print "\e[0m\e[32m"
            # modify, so that highlight persists
            oldseg[0] = '#'
          end
          print seg
          print "\e[0m\e[2m"
        end
        puts
        sleep 0.02
      end
      print "\e[0m"
      char = $ctl_kb_queue.deq
      case char
      when 'BACKSPACE'
        $ctl_rec[:lick_lick] = false
        return :prev
      when 'n'
        return :named
      when 'r','.'
        return :redo
      when 'e'
        return :edit
      when 'h'
        oldlines = nil
        show_help = true
        redo
      when 'c'
        $ctl_rec[:lick_lick] = !$ctl_rec[:lick_lick]
        show_help = true
        oldlines = oldlines_long        
        redo
      when 'L', 'l'
        $ctl_rec[:loop_loop] = !$ctl_rec[:loop_loop]
        show_help = true
        oldlines = oldlines_long        
        redo
      when '0'
        $ctl_rec[:num_loops] = false
        show_help = true
        oldlines = oldlines_long
        redo
      when '1'
        puts "\e[0m\e[2m#{$resources[:nloops_not_one]}"
        puts
        redo
      when '2','3','4','5','6','7','8','9'
        $ctl_rec[:num_loops] = char.to_i
        show_help = true
        oldlines = oldlines_long
        redo
      when ' ', 'RETURN'
        return :next
      when '*'
        return :star_up
      when '/'
        return :star_down        
      else
        puts "\e[0mUnknown key: '#{char}'    \e[2m(but more keys available during play)"
        puts
        oldlines = nil
        show_help = true
        redo
      end
    end
  end
end


def do_play_licks args

  if $opts[:lick_radio]
    $ctl_rec[:lick_lick] = $ctl_rec[:loop_loop] = true
    $ctl_rec[:num_loops] = 4
  end

  $ctl_rec[:can_star_unstar] = true
  sw = $opts[:start_with]
  licks = if $opts[:iterate] == :random
            licks = $licks.shuffle
          else
            licks = $licks.clone
          end  
  idx = if sw 
          if record = shortcut2history_record(sw)
            # we canno use record[:lick_idx], because that is against unshuffled licks
            licks.each_with_index.find {|l,i| l[:name] == record[:name]}&.at(1) || 0
          else
            (0 ... licks.length).find {|i| licks[i][:name] == sw} or fail "Unknown lick #{sw} given for option '--start-with'" 
          end
        else
          0
        end
  licks.rotate!(idx)
  if $opts[:iterate] == :random
    puts "\e[2mA random walk through licks.\e[0m"
  else
    puts "\e[2mOne lick after the other.\e[0m"
  end  
  puts
  play_licks_controller licks, licks, sleep_between: true
end


def play_named_licks lnames, refill: true
  $ctl_rec[:lick_lick] = false
  $ctl_rec[:loop_loop] = false
  $ctl_rec[:can_star_unstar] = true
  licks = lnames.map {|lnm| $licks.find {|l| l[:name] == lnm}}
  play_licks_controller licks, ( refill  ?  licks  :  nil )
end
