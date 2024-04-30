#
# Play from the commandline
#

def do_play to_play

  $all_licks, $licks = read_licks

  trace_text = nil

  make_term_immediate

  puts "\n\e[2mType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} licks.\e[0m"
  puts

  if $extra
    args_for_extra = to_play
  else
    holes_or_notes, lnames, snames = partition_to_play_or_print(to_play)
  end

  # common error checking
  err "'harpwise play #{$extra}' does not take any arguments, these cannot be handled: #{args_for_extra}" if %w(pitch licks user).include?($extra) && args_for_extra.length > 0
  err "Option '--start-with' only useful when playing 'licks'" if $opts[:start_with] && !$extra == 'licks'


  if !$extra 

    if holes_or_notes.length > 0

      puts "Some holes or notes"
      play_holes_or_notes_simple holes_or_notes
      puts
      
    elsif snames.length > 0
      
      snames.each do |sname|
        scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
        puts "Scale #{sname}"
        play_holes_or_notes_simple scale_holes
        puts
        trace_text = sprintf('Scale %s: ', sname) + scale_holes.join(' ')
        IO.write($trace_file, "#{trace_text}\n\n", mode: 'a')
      end
      
    elsif lnames.length > 0
      
      $ctl_rec[:lick_lick] = false
      $ctl_rec[:loop_loop] = false
      
      lnames.each do |lname|
        lick = $licks.find {|l| l[:name] == lname}
        trace_lick(lick)
        sleep ( $opts[:fast] ? 0.25 : 0.5 )
        loop do
          play_and_print_lick lick
          break if lnames.length == 1
          maybe_wait_for_key_and_decide_replay  ?  redo  :  break
        end
      end

    else

      fail 'Internal error'

    end

  else

    case $extra
    when 'pitch'

      play_interactive_pitch

    when 'interval', 'inter'

      s1, s2 = normalize_interval(args_for_extra)

      play_interactive_interval s1, s2
        
    when 'licks'

      do_play_licks
      
    when 'progression', 'prog'
      
      err "Need at a base note and some distances, e.g. 'a4 4st 10st'" unless args_for_extra.length >= 1
      prog = base_and_delta_to_semis(args_for_extra)
      play_interactive_progression prog

    when 'chord'

      puts "A chord"
      semis = args_for_extra.map do |hon|
        if $harp_holes.include?(hon)
          $harp[hon][:semi]
        elsif semi = note2semi(hon, 2..8, true)
          semi
        else
          err "Can only play holes or notes, but not this: #{hon}"
        end
      end
      err "Need at least two holes or notes to play a chord" unless semis.length >= 1
      play_interactive_chord semis, args_for_extra

    when 'user'

      rfile = $ulrec.rec_file
      if File.exist?(rfile)
        duration = '%.1fs' % sox_query(rfile, 'Length')
        puts "Playing \e[32m#{rfile}\e[0m, #{duration} ..."
        puts "\e[2m(h for help)"
        play_recording_and_handle_kb_simple rfile, true
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


def partition_to_play_or_print to_handle

  holes_or_notes = []
  lnames = []
  snames = []
  other = []

  to_handle.join(' ').split.each do |th| # allow -1 (oct) +2 to be passed as '-1 (oct) +2'

    what = recognize_among(th, $amongs_play_or_print)
    if what == :note
      holes_or_notes << sf_norm(th)
    elsif [:semi_note, :hole].include?(what)
      holes_or_notes << th
    elsif what == :lick && !$opts[:scale_over_lick]
      lnames << th
    elsif what == :scale
      snames << th
    elsif what == :lick
      lnames << th
    elsif what == :last
      md = th.match(/^(\dlast|\dl)$/)
      lnames << $all_licks[get_last_lick_idxs_from_trace($all_licks)[md  ?  md[1].to_i - 1  :  0] || 0][:name]
    else
      other << th
    end
  end

  #
  # Check results for consistency
  # 

  types_count = [holes_or_notes, lnames, snames].select {|x| x.length > 0}.length

  if other.length > 0  ## other is only filled, if $extra == ''
    puts
    puts "Cannot understand these arguments: #{other}#{not_any_source_of};"
    puts 'they are none of (exact match required):'
    print_amongs($amongs_play_or_print)
    puts
    puts "Alternatively you may give one of these extra keywords to #{$mode},\nwhich might be able to handle additional arguments:"
    print_amongs(:extra)
    err 'See above'
  end
  
  if $extra == '' && types_count == 0
    puts
    puts "Nothing to #{$mode}; please specify any of:"
    print_amongs([$amongs_play_or_print, :extra])
    err 'See above'
  end
  
  if types_count > 1
    puts "The following #{types_count} types of arguments are present,\nbut ONLY ONE OF THEM can be handled at the same time:"
    puts
    puts " Holes or Notes: #{holes_or_notes.join(' ')}" if holes_or_notes.length > 0
    puts "          Licks: #{lnames.join(' ')}" if lnames.length > 0
    puts "         Scales: #{snames.join(' ')}" if snames.length > 0
    puts
    err 'See above'
  end

  return [holes_or_notes, lnames, snames]

end


def hole_or_note_or_semi hns, diff_allowed = true

  types = Array.new
  values = Array.new

  # check if argument is interval or absolute note or hole or event or
  # many of them

  what = recognize_among(hns, [:hole, :note, :inter, :semi_note])
  case what
  when :hole
    types << :abs
    values << note2semi($hole2note[hns])
  when :note
    values << note2semi(hns)
    types << :abs
  when :inter
    types << :diff
    values << $intervals_inv[hns].to_i
  when :semi_note
    types << :diff
    values << hns.to_i
  end

  fail "Internal error: #{types}" if types.length >= 3
  
  if types.length == 0
    amongs = [:hole, :note]
    amongs.append(:semi_inter, :inter) if diff_allowed
    print_amongs(*amongs)
    inters_desc = $intervals_inv.keys.join(', ')
    err "Given argument #{hns} is none those given above"
  end

  return types, values
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
  when [[:abs, :diff], [:abs, :diff]]
    s1 = vv[0][0]
    s2 = vv[1][0]
  when [[:diff], [:diff]]
    err "You specified two semitone-differences but no base note: #{args}"
  when [[:abs, :diff], [:diff]], [[:abs], [:diff]]
    s1 = vv[0][0]
    s2 = s1 + vv[1][0]
  when [[:diff], [:abs, :diff]], [[:diff], [:abs]]
    s1 = vv[1][0]
    s2 = s1 + vv[0][0]
  when [[:abs], [:abs]], [[:abs, :diff], [:abs]], [[:abs], [:abs, :diff]]
    s1 = vv[0][0]
    s2 = vv[1][0]
  else
    fail "Internal error: unmatched: #{tt}"
  end

  return s1, s2
end


def base_and_delta_to_semis base_and_delta
  prog = Array.new
  bt, bv = hole_or_note_or_semi(base_and_delta[0], false)
  err "Progression should start with an absolute value (hole or note), but not with a semitone difference like #{base_and_delta[0]}" if bt == [:diff]
  prog << bv[0]
  base_and_delta[1 .. -1].each do |diff|
    dt, dv = hole_or_note_or_semi(diff)
    err "Up from the second word of progression there are only semitone differences to initial note allowed (e.g. 9st or octave) but not an absolute note or hole like #{diff}; remark: in case of ambiguities between holes and semitones add 'st' to semitones, like in '3st'" if dt.include?(:abs)
    prog << prog[0] + dv[-1]
  end
  prog
end


def play_and_print_lick lick
  sleep 1 if $ctl_rec[:loop_loop]
  if lick[:rec] && !$opts[:holes] && !$opts[:reverse]
    puts "Lick #{lick[:name]}\e[2m" +
         if lick[:rec_key] == $key
           ", recorded and played on a #{$key}-harp"
         else
           ", recorded with a #{lick[:rec_key]}-harp, shifted for #{$key}"
         end +
         " (h for help)\e[0m\n" +
         lick[:holes].join(' ')
    print "\e[0m\e[2m"
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    puts "Desc: #{lick[:desc]}" unless lick[:desc].to_s.empty?
    print "\e[0m"
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
  else
    if $opts[:reverse]
      puts "Lick #{lick[:name]} in reverse \e[2m(h for help)\e[0m"
      play_holes lick[:holes].reverse, lick: lick
    else
      puts "Lick #{lick[:name]} \e[2m(h for help)\e[0m"
      play_holes lick[:holes], lick: lick
    end
  end
  puts
end

def maybe_wait_for_key_and_decide_replay
  if $ctl_rec[:lick_lick]
    puts "\e[0m\e[2mContinuing with next lick without waiting for key ('c' to toggle)\e[0m"
    sleep 0.5
    return false
  else
    puts "\e[0m\e[2m" +
         "Press:    r: to replay this lick\n" +
         "any other key for next, especially:\n" +
         "          c: continue without further questions\n" +
         "          L: loop over next licks until pressed again " +
         ( $ctl_rec[:loop_loop]  ?  "(already ON)"  :  "(currently OFF)" ) +
         "\e[0m"
    char = $ctl_kb_queue.deq
    $ctl_rec[:lick_lick] = !$ctl_rec[:lick_lick] if char == 'c'
    $ctl_rec[:loop_loop] = !$ctl_rec[:loop_loop] if char == 'L'
    puts
    return char == 'r'
  end
end


def trace_lick lick
  trace_text = sprintf('Lick %s: ', lick[:name]) + lick[:holes].join(' ')
  IO.write($trace_file, "#{trace_text}\n\n", mode: 'a')
end    
  

def do_play_licks

  if $opts[:iterate] == :random
    lick_idx = nil
    loop do
      # avoid playing the same lick twice in a row
      if lick_idx
        lick_idx = (lick_idx + 1 + rand($licks.length - 1)) % $licks.length
          else
            lick_idx = rand($licks.length)
      end
      trace_lick($licks[lick_idx])
      loop do
        play_and_print_lick $licks[lick_idx]
        maybe_wait_for_key_and_decide_replay  ?  redo  :  break
      end
    end
  else
    sw = $opts[:start_with]
    idx = if sw 
            if (md = sw.match(/^(\dlast|\dl)$/)) || sw == 'last' || sw == 'l'
              # start with lick from history
              get_last_lick_idxs_from_trace($licks)[md  ?  md[1].to_i - 1  :  0]
            else
              (0 ... $licks.length).find {|i| $licks[i][:name] == sw} or fail "Unknown lick #{sw} given for option '--start-with'" 
            end
          else
            0
          end
    
    loop do
      $licks.rotate(idx).each do |lick|
        trace_lick(lick)
        loop do
          play_and_print_lick lick
          maybe_wait_for_key_and_decide_replay  ?  redo  :  break
        end
      end
    end
  end
  
end
