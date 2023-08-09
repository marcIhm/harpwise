def play_recording_and_handle_kb recording, start, length, key, first_round = true, octave_shift = 0

  trim_clause = if start && length
                  # for positive length this is different than written in the man page of sox ?!
                  "trim #{start} #{length}"
                elsif start
                  "trim #{start}"
                elsif length
                  "trim 0.0 #{length}"
                else
                  ""
                end
  dsemi = diff_semitones($key, key, :g_is_lowest) + octave_shift * 12
  pitch_clause = ( dsemi == 0  ?  ''  :  "pitch #{dsemi * 100}" )
  tempo = 1.0
  $ctl_rec[:loop] = $ctl_rec[:loop_loop]
  imm_ctrls_again = [:replay, :slower, :faster, :vol_up, :vol_down]
  loop_message_printed = false
  lick_lick_was = $ctl_rec[:lick_lick]
  loop_loop_was = $ctl_rec[:loop_loop]

  # loop as long as the recording needs to be played again due to
  # immediate controls triggered while it is playing
  begin
    tempo_clause = ( tempo == 1.0  ?  ''  :  ('tempo -m %.1f' % tempo) )
    cmd = "play --norm=#{$vol.to_i} -q -V1 #{$lick_dir}/recordings/#{recording} #{$conf[:sox_play_extra]} #{trim_clause} #{pitch_clause} #{tempo_clause}".strip
    IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
    return false if $testing
    _, stdout_err, wait_thr  = Open3.popen2e(cmd)
    (imm_ctrls_again + [:skip, :pause_continue, :show_help]).each {|k| $ctl_rec[k] = false}
    started = Time.now.to_f
    duration = 0.0
    paused = false

    # loop to check repeatedly while the recording is beeing played
    begin
      sleep 0.1
      handle_kb_play_recording
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        if paused
          Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
          paused = false
          print "\e[0m\e[32mgo \e[0m"
        else
          Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
          paused = true
          duration += Time.now.to_f - started
          started = Time.now.to_f
          printf "\e[0m\e[32m %.1fs SPACE to continue ... \e[0m", duration
        end
      elsif $ctl_rec[:slower]
        tempo -= 0.1 if tempo > 0.4
        print "\e[0m\e[32mx%.1f \e[0m" % tempo
      elsif $ctl_rec[:faster]
        tempo += 0.1 if tempo < 2.0
        print "\e[0m\e[32mx%.1f \e[0m" % tempo
      elsif $ctl_rec[:vol_up]
        $vol.inc
        print "\e[0m\e[32m#{$vol} \e[0m"
      elsif $ctl_rec[:vol_down]
        $vol.dec
        print "\e[0m\e[32m#{$vol} \e[0m"
      elsif $ctl_rec[:show_help]
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        display_kb_help 'a recording',first_round,
                        "  SPACE: pause/continue\n" + 
                        "      +: jump to end           -: jump to start\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        "      <: decrease speed        >: increase speed\n" +
                        "      l: loop over recording   " +
                        ( $ctl_can[:loop_loop]  ?  "L: loop over next recording too\n"  :  "\n" ) +
                        ( $ctl_can[:lick_lick]  ?  "      c: continue with next lick without waiting for key\n"  :  "\n" )
        print "\e[#{$lines[:hint_or_message]}H" unless first_round
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32mreplay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32mjump to end \e[0m"
      end

      if $ctl_rec[:lick_lick] != lick_lick_was
        print "\n\e[0m\e[32mContinue with next lick at end is: \e[0m" +
              ( $ctl_rec[:lick_lick]  ?  'ON'  :  'OFF' ) + "\n"
        lick_lick_was = $ctl_rec[:lick_lick]
      end

      if $ctl_rec[:loop_loop] != loop_loop_was
        print "\n\e[0m\e[32mLoop over next licks is: \e[0m" +
              ( $ctl_rec[:loop_loop]  ?  'ON'  :  'OFF' ) + "\n"
        loop_loop_was = $ctl_rec[:loop_loop]
      end

      if $ctl_rec[:loop] && !loop_message_printed
        print "\e[0m\e[32mloop (+ to end) " + 
              ( $ctl_rec[:loop_loop]  ?  'and loop after loop (L to end)'  :  '' ) +
              "\e[0m"
        loop_message_printed = true
      end

      # need to go leave this loop and play again if any immediate
      # controls have been triggered
    end while wait_thr.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}
    
    $ctl_rec[:loop] = false if $ctl_rec[:skip]
    if wait_thr.alive?
      Process.kill('KILL',wait_thr.pid)
    end
    wait_thr.join
    if wait_thr && wait_thr.value && wait_thr.value.exitstatus && wait_thr.value.exitstatus != 0
      puts "Command failed with #{wait_thr.value.exitstatus}: #{cmd}\n#{$sox_fail_however}"
      puts stdout_err.read.lines.map {|l| '   >>  ' + l}.join
      err 'See above'
    end
  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} || $ctl_rec[:loop]
  $ctl_rec[:skip]
end


def play_interactive_pitch embedded = false
  semi = note2semi($key + '4')
  all_waves = [:pluck, :sawtooth, :square, :sine]
  wave = wave_was = :pluck
  min_semi = -24
  max_semi = 24
  paused = false
  wait_thr = stdout_err = nil
  cmd = cmd_was = nil

  sleep 0.1 if embedded
  puts "\e[0m\e[32mPlaying an adjustable pitch, that you may compare\nwith a song, that is playing at the same time."
  puts "\n\e[0m\e[2mPrinted are the key of the song and the key of the harp\nthat matches when played in second position."

  sleep 0.1 if embedded
  puts
  puts "\e[0m\e[2mSuggested procedure: Play the song in the background and"
  puts "step by semitones until you hear a good match; then try a fifth"
  puts "up and down, to check if those may match even better. Step by octaves,"
  puts "if your pitch is far above or below the song."
  sleep 0.1 if embedded
  puts
  puts "\e[0m\e[2m(type 'h' for help)\e[0m"
  puts
  print_pitch_information(semi)

  # loop forever until ctrl-c; loop on every key
  loop do
    duration_clause = ( wave == :pluck  ?  3  :  86400 )

    # we also loop when paused
    if paused
      if wait_thr&.alive?
        Process.kill('KILL',wait_thr.pid)
        join_and_check_thread wait_thr, cmd, stdout_err
      end
    else
      # sending stdout output to /dev/null makes this immune to killing ?
      # +7 because key of song, rather than key of harp is wanted
      cmd = "play --norm=#{$vol.to_i} -q -n #{$conf[:sox_play_extra]} synth #{duration_clause} #{wave} %#{semi+7}"
      if cmd_was != cmd || !wait_thr&.alive?
        if wait_thr&.alive?
          Process.kill('KILL',wait_thr.pid)
        end
        join_and_check_thread wait_thr, cmd, stdout_err
        if $testing
          IO.write($testing_log, cmd + "\n", mode: 'a')
          cmd = 'sleep 86400 ### ' + cmd
        end
        cmd_was = cmd
        _, stdout_err, wait_thr  = Open3.popen2e(cmd)
      end
    end

    # wait until sound has stopped or key pressed
    begin
      break if $ctl_pitch[:any]
      handle_kb_play_pitch
      sleep 0.1
    end while wait_thr.alive?

    if $ctl_pitch[:any]
      knm = $conf_meta[:ctrls_play_pitch].select {|k| $ctl_pitch[k] && k != :any}[0].to_s.gsub('_',' ')
      if $ctl_pitch[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[2mgo\e[0m"
        else
          paused = true
          puts "\e[0m\e[2mSPACE to continue ...\e[0m"
        end
      elsif $ctl_pitch[:vol_up]
        $vol.inc
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_pitch[:vol_down]
        $vol.dec
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_pitch[:semi_up]
        semi += 1 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:semi_down]
        semi -= 1 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:octave_up]
        semi += 12 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:octave_down]
        semi -= 12 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:fifth_up]
        semi += 7 if semi < max_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:fifth_down]
        semi -= 7 if semi > min_semi
        print_pitch_information(semi, knm)
      elsif $ctl_pitch[:wave_up] || $ctl_pitch[:wave_down]
        wave_was = wave
        wave = if $ctl_pitch[:wave_up]
                 all_waves[(all_waves.index(wave) + 1) % all_waves.length]
               else
                 all_waves[(all_waves.index(wave) -1) % all_waves.length]
               end
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:show_help]
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        display_kb_help 'a pitch',true,
                        "  SPACE: pause/continue  ESC,x,q: " + ( embedded ? "discard\n" : "quit\n" ) +
                        "      w: change waveform       W: change waveform back\n" + 
                        "    s,+: one semitone up     S,-: one semitone down\n" +
                        "      o: one octave up         O: one octave down\n" +
                        "      f: one fifth up          F: one fifth down\n" +
                        "      v: decrease volume       V: increase volume by 3dB" +
                        ( embedded  ?  "\n RETURN: accept"  :  '')
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
        print_pitch_information(semi)
      elsif $ctl_pitch[:quit]
        new_key =  ( $ctl_pitch[:quit] == "\n"  ?  semi2note(semi)[0..-2]  :  nil)
        $ctl_pitch[:quit] = false
        if wait_thr&.alive?
          Process.kill('KILL',wait_thr.pid)
          join_and_check_thread wait_thr, cmd, stdout_err
        end
        return new_key
      end

      $conf_meta[:ctrls_play_pitch].each {|k| $ctl_pitch[k] = false}
    end

    if wave == :pluck && wave_was != :pluck
      wave_was = wave
      5.times do
        break if $ctl_pitch[:any]
        handle_kb_play_pitch
        sleep 0.1
      end
    end
  end
end


def play_interactive_interval semi1, semi2

  puts "\e[0m\e[2mPlaying in loop.\n"
  puts "(type 'h' for help)\e[0m\n\n"

  delta_semi = semi2 - semi1
  tfiles = [1, 2].map {|i| "#{$dirs[:tmp]}/interval_semi#{i}.wav"}
  wfiles = [1, 2].map {|i| "#{$dirs[:tmp]}/interval_work#{i}.wav"}
  gap = 0.2
  len = 3
  cmd_template = if $testing
                   "sleep 1"
                 else
                   "play --norm=%s --combine mix #{tfiles[0]} #{tfiles[1]}"
                 end
  cmd = cmd_template % $vol.to_i
  synth_for_inter([semi1, semi2], tfiles, wfiles, gap, len)
  new_sound = true
  paused = false
  wait_thr = stdout_err = nil

  # loop forever until ctrl-c; loop on every key
  loop do

    # we also loop when paused
    if paused
      if wait_thr&.alive?
        Process.kill('KILL',wait_thr.pid)
        join_and_check_thread wait_thr, cmd, stdout_err
      end
    else
      if new_sound || !wait_thr&.alive?
        Process.kill('KILL',wait_thr.pid) if wait_thr&.alive?
        join_and_check_thread wait_thr, cmd, stdout_err
        if new_sound
          cmd = cmd_template % $vol.to_i
          synth_for_inter([semi1, semi2], tfiles, wfiles, gap, len)
          puts
          print_interval semi1, semi2
          puts "\e[0m\e[2m\n  Gap: #{gap}, length: #{len}\e[0m\n\n"
          new_sound = false
        end
        IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
        _, stdout_err, wait_thr  = Open3.popen2e($testing  ?  'sleep 86400'  :  cmd)
      end
    end

    # wait until sound has stopped or key pressed
    begin
      break if $ctl_inter[:any]
      handle_kb_play_inter
      sleep 0.1
    end while wait_thr.alive?

    # handle kb
    if $ctl_inter[:any]
      new_sound = false
      if $ctl_inter[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[2mgo\e[0m"
        else
          paused = true
          puts "\e[0m\e[2mSPACE to continue ...\e[0m"
        end
      elsif $ctl_inter[:up] || $ctl_inter[:down]
        step =  $ctl_inter[:up]  ?  +1  :  -1
        semi1 += step
        semi2 += step
        new_sound = true
      elsif $ctl_inter[:narrow] || $ctl_inter[:widen]
        delta_semi +=  $ctl_inter[:narrow]  ?  -1  :  +1
        semi2 = semi1 + delta_semi
        new_sound = true
      elsif $ctl_inter[:gap_inc] || $ctl_inter[:gap_dec]
        gap +=  $ctl_inter[:gap_dec]  ?  -0.2  :  +0.2
        gap = 0 if gap < 0
        gap = 2 if gap > 2
        gap = gap.round(1)
        new_sound = true
      elsif $ctl_inter[:len_inc] || $ctl_inter[:len_dec]
        len +=  $ctl_inter[:len_inc]  ?  +1 : -1
        len = 1 if len < 1
        len = 8 if len > 8
        len = len.round(1)
        new_sound = true
      elsif $ctl_inter[:swap]
        semi1, semi2 = semi2, semi1
        delta_semi = -delta_semi
        new_sound = true        
      elsif $ctl_inter[:replay]
        puts "\e[0m\e[2mReplay\e[0m\n\n"
        new_sound = true        
      elsif $ctl_inter[:vol_up]
        $vol.inc
        puts "\e[0m\e[2m#{$vol}\e[0m"
        new_sound = true        
      elsif $ctl_inter[:vol_down]
        $vol.dec
        puts "\e[0m\e[2m#{$vol}\e[0m"
        new_sound = true        
      elsif $ctl_inter[:show_help]
        Process.kill('TSTP',wait_thr.pid) if wait_thr.alive?
        display_kb_help 'an interval',true,
                        "   SPACE: pause/continue             ESC,x,q: quit\n" +
                        "       +: widen interval by one semi       -: narrow by one semi\n" +
                        "       >: move interval up one semi        <: move down\n" +
                        "       G: increase time gap                g: decrease\n" +
                        "       L: increase length                  l: decrease\n" +
                        "       v: decrease volume by 3db           V: increase volume\n" +
                        "       s: swap notes                  RETURN: play again"
        Process.kill('CONT',wait_thr.pid) if wait_thr.alive?
      elsif $ctl_inter[:quit]
        $ctl_inter[:quit] = false
        if wait_thr&.alive?
          Process.kill('KILL',wait_thr.pid)
          join_and_check_thread wait_thr, cmd, stdout_err
        end
        return
      end

      $conf_meta[:ctrls_play_inter].each {|k| $ctl_inter[k] = false}
    end
  end
end


def play_interactive_progression prog
  fmt = ' ' + '|%8s ' * 4 + '|'
  print "\e[0m\e[2m(type 'h' for help)\e[0m\n\n"
  loop = quit = change_semis = false
  iteration = 1
  begin
    if change_semis
      prog.map! {|s| s += change_semis}
      change_semis = false
    end
    holes, notes, abs_semis, rel_semis = get_progression_views(prog)
      
    puts fmt % ['Holes', 'Notes', 'abs st', 'rel st']
    puts ' ' + '|---------' * 4 + '|'
    holes.zip(notes, abs_semis, rel_semis).each do |ho, no, as, rs|
      line = fmt % [ho, no, as, rs]

      print "\n\n\n\e[3A"
      print "\e[0m\e[32m#{line}\e[0m"
      play_semi_and_handle_kb as
      print "\r\e[0m#{line}\n"

      if $ctl_semi[:show_help]
        display_kb_help 'a semitone progression', true,
                        "  SPACE: pause/continue\n" +
                        "    0-9: add to prefix for semitone step\n" +
                        "    ESC: clear semitone prefix\n" +
                        "    s,+: shift whole prog by one (or prefix) semitones up\n" +
                        "    S,-: shift whole progression down\n" +
                        "      v: decrease volume by 3db           V: increase volume\n" +
                        "      l: toggle looping of progression    q: quit after iteration"
        $ctl_semi[:show_help] = false
      elsif $ctl_semi[:pause_continue]
        print "\n\e[0m\e[32mSPACE to continue ..."
        begin
          char = $ctl_kb_queue.deq
        end until char == ' '
        print " go\e[0m\n"
        puts
        sleep 0.5
        $ctl_semi[:pause_continue] = false
      elsif $ctl_semi[:semi_up] || $ctl_semi[:semi_down]
        # things happen at start if outside loop
        change_semis = ( $ctl_semi[:prefix] || '1').to_i * ( $ctl_semi[:semi_up]  ?  +1  :  -1 )
        $ctl_semi[:prefix] = nil
        print "\e[0m\e[2mnext iteration: #{change_semis.abs} semitones #{$ctl_semi[:semi_up] ? 'UP' : 'DOWN'}\e[0m\n"
        $ctl_semi[:semi_up] = $ctl_semi[:semi_down] = false
      elsif $ctl_semi[:vol_up]
        $ctl_semi[:vol_up] = false
        $vol.inc
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_semi[:vol_down]
        $ctl_semi[:vol_down] = false
        $vol.dec
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_semi[:toggle_loop]
        $ctl_semi[:toggle_loop] = false
        loop = !loop
        print "\e[0m\e[2mloop: #{loop ? 'ON' : 'OFF'}\e[0m\n"
      elsif $ctl_semi[:quit]
        $ctl_semi[:quit] = false
        quit = true
        print "\e[0m\e[2mQuit after this iteration\e[0m\n"
      end
    end
    print "\e[0m\e[2mIteration #{iteration} done ...\e[0m\n\n" if loop || change_semis
    break if quit
    iteration += 1
  end while loop || change_semis
  puts
end


def join_and_check_thread wait_thr, cmd, stdout_err
  if wait_thr && wait_thr.value && wait_thr.value.exitstatus && wait_thr.value.exitstatus != 0
    wait_thr.join
    puts "Command failed with #{wait_thr.value.exitstatus}: #{cmd}\n#{$sox_fail_however}"
    puts stdout_err.read.lines.map {|l| '   >>  ' + l}.join
    err 'See above'
  end
end


def play_holes_or_notes_simple holes_or_notes

  puts "\e[2m(SPACE to pause, 'h' for help)\e[0m"
  puts
  $ctl_hole[:skip] = false
  holes_or_notes.each do |hon|
    print hon + ' '
    if musical_event?(hon)
      sleep $opts[:fast]  ?  0.125  :  0.25
    else
      duration = ( $opts[:fast] ? 0.5 : 1 )
      note = $harp.dig(hon, :note) || hon
      play_hole_or_note_simple_and_handle_kb note, duration
    end
    if $ctl_hole[:show_help]
      display_kb_help 'series of holes or notes', true,  <<~end_of_content
        SPACE: pause/continue
        TAB,+: skip to end
            v: decrease volume     V: increase volume by 3dB
      end_of_content
      # continue below help (first round only)
      print "\n"
      $ctl_hole[:show_help] = false
    elsif $ctl_hole[:vol_up]
      $vol.inc
      print "\e[0m\e[2m#{$vol}\e[0m "
    elsif $ctl_hole[:vol_down]
      $vol.dec
      print "\e[0m\e[2m#{$vol}\e[0m "
    elsif $ctl_hole[:skip]
      print "\e[0m\e[32m skip to end\e[0m"
      sleep 0.3
      break
    end
  end
  puts
end


def play_holes all_holes, at_line: nil, verbose: false, lick: nil

  if $opts[:partial] && !$ctl_mic[:ignore_partial]
    holes, _, _ = select_and_calc_partial(all_holes, nil, nil)
  else
    holes = all_holes
  end
  
  IO.write($testing_log, all_holes.inspect + "\n", mode: 'a') if $testing
  
  $ctl_hole[:skip] = false
  ltext = if lick
            "\e[2mLick \e[0m#{lick[:name]}\e[2m (h for help) ... "
          else
            "\e[2m(h for help) ... "
          end
  [holes, '(0.5)'].flatten.each_cons(2).each_with_index do |(hole, hole_next), idx|
    if ! verbose
      print hole + ' '
    else
      if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
        ltext = "\e[2m(h for help)  "
        if at_line
          print "\e[#{at_line}H\e[K"
          print "\e[#{at_line-1}H\e[K"
        else
          print "\e[#{$lines[:hint_or_message]}H\e[K"
          print "\e[#{$lines[:message2]}H\e[K"
        end
      end
      if idx > 0
        if !musical_event?(hole) && !musical_event?(holes[idx - 1])
          isemi, itext, _, _ = describe_inter(hole, holes[idx - 1])
          ltext += ' ' + ( itext || isemi ).tr(' ','') + ' '
        else
          ltext += ' '
        end
      end
      ltext += if musical_event?(hole)
                 "\e[0m#{hole}\e[2m"
               elsif $opts[:immediate]
                 "\e[0m#{hole},#{$harp[hole][:note]}\e[2m"
               else
                 "\e[0m#{$harp[hole][:note]}\e[2m"
               end
      if $used_scales.length > 1
        part = '(' +
               $hole2flags[hole].map {|f| {added: 'a', root: 'r'}[f]}.compact.join(',') +
               ')'
        ltext += part unless part == '()'
      end

      if at_line
        print "\e[#{at_line}H\e[K"
        print "\e[#{at_line-1}H#{ltext.strip}\e[K"
      else
        print "\e[#{$lines[:message2]}H\e[K"
        print "\e[#{$lines[:hint_or_message]}H#{ltext.strip}\e[K"
      end
    end
    
    if musical_event?(hole)
      sleep $opts[:fast]  ?  0.125  :  0.25
    else
      # this also handles kb input and sets $ctl_hole
      play_hole_and_handle_kb(hole, get_musical_duration(hole_next))
    end

    if $ctl_hole[:show_help]
      display_kb_help 'series of holes', verbose,  <<~end_of_content
        SPACE: pause/continue
        TAB,+: skip to end
            v: decrease volume     V: increase volume by 3dB
      end_of_content
      # continue below help (first round only)
      print "\n\n"
      at_line = [at_line + 10, $term_height].min if at_line
      $ctl_hole[:show_help] = false
    elsif $ctl_hole[:vol_up]
      $vol.inc
      ltext += "\e[0m\e[32m #{$vol}\e[0m "
      $ctl_hole[:vol_up] = false
    elsif $ctl_hole[:vol_down]
      $vol.dec
      ltext += "\e[0m\e[32m #{$vol}\e[0m "
      $ctl_hole[:vol_down] = false
    elsif $ctl_hole[:skip]
      print "\e[0m\e[32m skip to end\e[0m"
      sleep 0.3
      break
    end
  end
  puts unless verbose
end


