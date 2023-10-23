#
# Play from the commandline
#

def do_play to_play
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false
  
  trace_text = nil

  make_term_immediate

  puts "\n\e[2mType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} licks.\e[0m"
  puts

  extra_allowed = {'licks' => 'licks selected',
                   'pitch' => 'interactive, adjustable pitch',
                   'interval' => 'interactive, adjustable interval',
                   'inter' => nil,
                   'progression' => 'take a base and semitone diffs, then play it',
                   'prog' => nil,
                   'chord' => 'play the given holes or notes as a chord',
                   'user' => 'play last recording of you playing a lick (if any)'}
  
  holes_or_notes, lnames, snames, extra, args_for_extra = partition_to_play_or_print(to_play, extra_allowed, %w(pitch interval inter progression prog chord))
  extra = Set.new(extra).to_a
  err "Option '--start-with' only useful when playing 'licks'" if $opts[:start_with] && !extra.include?('licks')

  #
  #  Actually play
  #

  if holes_or_notes.length > 0

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

    lnames.each do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      trace_lick(lick)
      sleep ( $opts[:fast] ? 0.25 : 0.5 )
      play_and_print_lick lick
    end

  elsif extra.length > 0

    err "only one of #{extra_allowed.keys} is allowed" if extra.length > 1

    if extra[0] == 'pitch'
      play_interactive_pitch

    elsif extra[0] == 'interval' || extra[0] == 'inter'

      s1, s2 = normalize_interval(args_for_extra)

      play_interactive_interval s1, s2
        
    elsif extra[0] == 'licks'
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
          play_and_print_lick $licks[lick_idx]
          maybe_wait_for_key
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
            play_and_print_lick lick
            maybe_wait_for_key
          end
        end
      end

    elsif extra[0] == 'progression' || extra[0] == 'prog'
      err "Need at a base note and some distances, e.g. 'a4 4st 10st'" unless args_for_extra.length >= 1
      prog = base_and_delta_to_semis(args_for_extra)
      play_interactive_progression prog

    elsif extra[0] == 'chord'
      semis = args_for_extra.map do |hon|
        if $harp_holes.include?(hon)
          $harp[hon][:semi]
        elsif semi = begin
                       note2semi(hon, 2..8)
                     rescue ArgumentError
                       nil
                     end
          semi
        else
          err "Can only play holes or notes, but not this: #{hon}"
        end
      end
      err "Need at least two holes or notes to play a chord" unless semis.length >= 1
      play_interactive_chord semis, args_for_extra

    elsif extra[0] == 'user-lick-recording' || extra[0] == 'user'

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
      fail "Internal error: #{extra}"
    end

  else
    fail "Internal error"
  end
end


def partition_to_play_or_print to_p, extra_allowed = [], extra_takes_args = []

  holes_or_notes = []
  lnames = []
  snames = []
  extra = []
  args_for_extra = []
  other = []
  all_lnames = $licks.map {|l| l[:name]}
  all_snames = scales_for_type($type)
  extra_seen = false
  to_p.join(' ').split.each do |tp| # allow -1 (oct) +2 to be passed as '-1 (oct) +2'

    is_note = false
    begin
      note2semi(tp, 2..8)
      is_note = true
    rescue ArgumentError
    end

    if extra_allowed.keys.include?(tp)
      extra << tp
      extra_seen = true
    elsif extra_seen && (extra_takes_args & extra).length > 0
      args_for_extra << tp
    elsif musical_event?(tp)
      holes_or_notes << tp
    elsif $harp_holes.include?(tp) && !extra_seen
      holes_or_notes << tp
    elsif is_note
      holes_or_notes << tp
    elsif all_lnames.include?(tp) && !$opts[:scale_over_lick]
      lnames << tp
    elsif all_snames.include?(tp)
      snames << tp
    elsif all_lnames.include?(tp)
      lnames << tp
    elsif (md = tp.match(/^(\dlast|\dl)$/)) || tp == 'last' || tp == 'l'
      lnames << $all_licks[get_last_lick_idxs_from_trace($all_licks)[md  ?  md[1].to_i - 1  :  0] || 0][:name]
    else
      other << tp
    end
  end

  #
  # Check results for consistency
  # 

  sources_count = [holes_or_notes, lnames, snames, extra].select {|s| s.length > 0}.length

  if other.length > 0 || sources_count == 0
    puts
    if other.length == 0
      txt = 'Nothing to play or print'
      puts txt + '; please specify any of:'
    else
      txt = "Cannot understand these arguments: #{other}#{not_any_source_of}"
      puts txt + ";"
      puts 'they are none of (exact match required):'
    end
    puts "\n- musical events in () or []"
    puts "\n- holes:"
    print_in_columns $harp_holes, indent: 4, pad: :tabs
    puts "\n- notes:"
    puts '    all notes from octaves 2 to 8, e.g. e2, fs3, g5, cf7'
    puts "\n- scales:"
    print_in_columns all_snames, indent: 4, pad: :tabs
    puts "\n- licks:"
    print_in_columns all_lnames, indent: 4, pad: :tabs
    if extra_allowed.keys.length > 0
      puts "\n- extra:"
      mklen = extra_allowed.keys.map(&:length).max
      extra_allowed.each do |k,v|
        puts "    #{k.rjust(mklen)} : #{v || 'the same'}"
      end
    end
    puts
    err "#{txt}, see above"
  end
  
  if sources_count > 1
    puts "The following #{sources_count} types of arguments are present,\nbut ONLY ONE OF THEM can be handled at a time:"
    puts "- holes (maybe converted from given notes): #{holes_or_notes}" if holes_or_notes.length > 0
    puts "- scales: #{snames}" if snames.length > 0
    puts "- licks: #{lnames}" if lnames.length > 0
    err 'See above'
  end

  [holes_or_notes, lnames, snames, extra, args_for_extra]

end


def hole_or_note_or_semi hns, diff_allowed = true

  types = Array.new
  values = Array.new

  # check if argument is interval or absolute note or hole or event or
  # many of them

  # hole ?
  if $harp_holes.include?(hns)
    types << :abs
    values << note2semi($hole2note[hns])
  end

  # note ?
  begin
    values << note2semi(hns)
    types << :abs
  rescue ArgumentError
  end

  # named interval ?
  if $intervals_inv[hns]
    types << :diff
    values << $intervals_inv[hns].to_i
  end

  # interval in semitones ?
  if hns.match(/^[+-]?\d+(st)?$/)
    types << :diff
    values << hns.to_i
  end

  fail "Internal error: #{types}" if types.length >= 3
  
  if types.length == 0
    inters_desc = $intervals_inv.keys.join(', ')
    err "Given argument #{hns} is none of these:\n" +
        if diff_allowed
          "  - numeric interval\e[2m, e.g. 12st or -3\n\e[0m" +
            "  - named interval\e[2m, i.e. one of: " + inters_desc + "\n"
        else
          ''
        end +
        "\e[0m  - hole\e[2m, i.e. one of: " + $harp_holes.join(', ') + "\n" +
        "\e[0m  - note\e[2m, e.g. c4, df5, as3\e[0m"
  end

  return types, values
end


def normalize_interval args

  err "Need two arguments, to play or print an interval:\n" +
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


def trace_lick lick
  trace_text = sprintf('Lick %s: ', lick[:name]) + lick[:holes].join(' ')
  IO.write($trace_file, "#{trace_text}\n\n", mode: 'a')
end    
  
