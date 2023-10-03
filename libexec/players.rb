#
# Playing under user control
#

def play_recording_and_handle_kb recording, start, length, key, scroll_allowed = true, octave_shift = 0

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
    cmd = "play --norm=#{$vol.to_i} -q -V1 #{$lick_dir}/recordings/#{recording} #{trim_clause} #{pitch_clause} #{tempo_clause}".strip
    IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
    if $testing_what == :player
      cmd = 'sleep 600 ### ' + cmd
    elsif $testing
      sleep 4
      return false
    end
    pplayer = PausablePlayer.new(cmd)
    (imm_ctrls_again + [:skip, :pause_continue, :show_help]).each {|k| $ctl_rec[k] = false}

    # loop to check repeatedly while the recording is beeing played
    begin
      sleep 0.1
      handle_kb_play_recording
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        if pplayer.paused?
          pplayer.continue
          print "\e[0m\e[32mgo \e[0m"
        else
          pplayer.pause
          printf "\e[0m\e[32m %.1fs SPACE to continue ... \e[0m", pplayer.time_played
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
        pplayer.pause
        display_kb_help 'a recording', scroll_allowed,
                        "  SPACE: pause/continue\n" + 
                        "      +: jump to end           -: jump to start\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        "      <: decrease speed        >: increase speed\n" +
                        "      l: loop over recording   " +
                        ( $ctl_can[:loop_loop]  ?  "L: loop over next recording too\n"  :  "\n" ) +
                        ( $ctl_can[:lick_lick]  ?  "      c: continue with next lick without waiting for key\n"  :  "\n" )
        print "\e[#{$lines[:hint_or_message]}H" unless scroll_allowed
        pplayer.continue
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32m replay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32m jump to end \e[0m"
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
    end while pplayer.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}
    
    $ctl_rec[:loop] = false if $ctl_rec[:skip]
    pplayer.kill
    pplayer.check

  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} || $ctl_rec[:loop]
  $ctl_rec[:skip]

end


def play_recording_and_handle_kb_simple recording, scroll_allowed, timed_comments = nil

  imm_ctrls_again = [:replay, :vol_up, :vol_down]
  loop_message_printed = false

  # loop as long as the recording needs to be played again due to
  # immediate controls triggered while it is playing
  begin

    (imm_ctrls_again + [:skip]).each {|k| $ctl_rec[k] = false}
    cmd = "play --norm=#{$vol.to_i} -q -V1 #{recording}".strip
    IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
    if $testing_what == :player
      cmd = 'sleep 100'
    elsif $testing
      sleep 4
      return false
    end
    pplayer = PausablePlayer.new(cmd)
    
    # loop to check repeatedly while the recording is beeing played
    begin
      sleep 0.1
      handle_kb_play_recording_simple
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        if pplayer.paused?
          pplayer.continue
          print "\e[0m\e[32mgo \e[0m"
        else
          pplayer.pause
          printf "\e[0m\e[32m SPACE to continue ... \e[0m"
        end
      elsif $ctl_rec[:vol_up]
        $vol.inc
        print "\e[0m\e[32m#{$vol} \e[0m"
      elsif $ctl_rec[:vol_down]
        $vol.dec
        print "\e[0m\e[32m#{$vol} \e[0m"
      elsif $ctl_rec[:show_help]
        pplayer.pause
        display_kb_help 'a recording', scroll_allowed,
                        "  SPACE: pause/continue\n" + 
                        "      +: jump to end           -: jump to start\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        "      l: loop over recording"
        print "\e[#{$lines[:hint_or_message]}H" unless scroll_allowed
        pplayer.continue
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32m replay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32m jump to end \e[0m"
      end

      if timed_comments && timed_comments.length > 0
        if pplayer.time_played > timed_comments[0][0]
          print timed_comments[0][1]
          timed_comments.shift
        end
      end

      if $ctl_rec[:loop] && !loop_message_printed
        print "\e[0m\e[32mloop (+ to end)\e[0m"
        loop_message_printed = true
      end

      # need to go leave this loop and play again if any immediate
      # controls have been triggered
    end while pplayer.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}

    pplayer.kill
    pplayer.check
  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} || $ctl_rec[:loop]
end


def play_interactive_pitch embedded = false
  semi = note2semi($key + '4')
  all_waves = [:pluck, :sawtooth, :square, :sine]
  wave = wave_was = :pluck
  min_semi = -24
  max_semi = 24
  paused = false
  pplayer = nil
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
    # we also loop when paused
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
    else
      # semi+7 because key of song, rather than key of harp is wanted
      cmd = "play --norm=#{$vol.to_i} -q -n synth 3 #{wave} %#{semi+7}"
      if cmd_was != cmd || !pplayer&.alive?
        pplayer.kill if pplayer&.alive?
        pplayer&.check
        if $testing
          IO.write($testing_log, cmd + "\n", mode: 'a')
          cmd = 'sleep 600 ### ' + cmd
        end
        cmd_was = cmd
        pplayer = PausablePlayer.new(cmd)
      end
    end

    # wait until sound has stopped or key pressed
    begin
      break if $ctl_pitch[:any]
      handle_kb_play_pitch
      sleep 0.1
    end while pplayer.alive?

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
      elsif $ctl_pitch[:wave_up]
        wave_was = wave
        wave = rotate_among(wave, :up, all_waves)
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:wave_down]
        wave_was = wave
        wave = rotate_among(wave, :down, all_waves)
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:show_help]
        pplayer.pause
        display_kb_help 'a pitch',true,
                        "  SPACE: pause/continue  ESC,x,q: " + ( embedded ? "discard\n" : "quit\n" ) +
                        "      w: change waveform       W: change waveform back\n" + 
                        "    s,+: one semitone up     S,-: one semitone down\n" +
                        "      o: one octave up         O: one octave down\n" +
                        "      f: one fifth up          F: one fifth down\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        ( embedded  ?  ' RETURN: accept'  :  ' RETURN: play again')
        pplayer.continue
        print_pitch_information(semi)
      elsif $ctl_pitch[:quit] || $ctl_pitch[:accept_or_repeat]
        new_key =  ( $ctl_pitch[:accept_or_repeat]  ?  semi2note(semi)[0..-2]  :  nil)
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        return new_key if $ctl_pitch[:quit] || embedded 
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
  gap = ConfinedValue.new(0.2, 0.2, 0, 2)
  len = ConfinedValue.new(3, 1, 1, 8)
  cmd_template = if $testing
                   "sleep 1"
                 else
                   "play --norm=%s --combine mix #{tfiles[0]} #{tfiles[1]}"
                 end
  cmd = cmd_template % $vol.to_i
  synth_for_inter_or_chord([semi1, semi2], tfiles, wfiles, gap.val, len.val)
  new_sound = true
  paused = false
  pplayer = nil

  # loop forever until ctrl-c; loop on every key
  loop do

    # we also loop when paused
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
    else
      if new_sound || !pplayer&.alive?
        if pplayer
          pplayer.kill
          pplayer.check
        end
        if new_sound
          cmd = cmd_template % $vol.to_i
          synth_for_inter_or_chord([semi1, semi2], tfiles, wfiles, gap.val, len.val)
          puts
          print_interval semi1, semi2
          puts "\e[0m\e[2m\n  Gap: #{gap.val}, length: #{len.val}\e[0m\n\n"
          new_sound = false
        end
        if $testing
          IO.write($testing_log, cmd + "\n", mode: 'a')
          cmd = 'sleep 600 ### ' + cmd
        end
        pplayer = PausablePlayer.new(cmd)
      end
    end

    # wait until sound has stopped or key pressed
    begin
      break if $ctl_inter[:any]
      handle_kb_play_inter
      sleep 0.1
    end while pplayer.alive?

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
      elsif $ctl_inter[:gap_inc]
        gap.inc
        new_sound = true
      elsif $ctl_inter[:gap_dec]
        gap.dec
        new_sound = true
      elsif $ctl_inter[:len_inc]
        len.inc
        new_sound = true
      elsif $ctl_inter[:len_dec]
        len.dec
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
        pplayer.pause
        display_kb_help 'an interval',true,
                        "   SPACE: pause/continue          ESC,x,q: quit\n" +
                        "       +: widen interval by one semi    -: narrow by one semi\n" +
                        "       >: move interval up one semi     <: move down\n" +
                        "       g: decrease time gap             G: increase\n" +
                        "       l: decrease length               L: increase\n" +
                        "       v: decrease volume by 3db        V: increase volume\n" +
                        "       s: swap notes               RETURN: play again"
        pplayer.continue
      elsif $ctl_inter[:quit]
        $ctl_inter[:quit] = false
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        return
      end

      $conf_meta[:ctrls_play_inter].each {|k| $ctl_inter[k] = false}
    end
  end
end


def play_interactive_chord semis, args_orig

  puts "\e[0m\e[2mPlaying in loop.\n"
  puts "(type 'h' for help)\e[0m\n\n"

  tfiles = (1 .. semis.length).map {|i| "#{$dirs[:tmp]}/chord_semi#{i}.wav"}
  wfiles = [1, 2].map {|i| "#{$dirs[:tmp]}/interval_work#{i}.wav"}
  all_waves = [:pluck, :sawtooth, :square, :sine]
  wave = :sawtooth
  gap = ConfinedValue.new(0.2, 0.1, 0, 2)
  len = ConfinedValue.new(6, 1, 1, 16)
  # chord dscription and sound description
  cdesc = semis.zip(args_orig).map {|s,o| "#{o} (#{s}st)"}.join('  ')
  sdesc = get_sound_description(wave, gap.val, len.val)
  cmd_template = if $testing
                   "sleep 1"
                 else
                   "play --norm=%s --combine mix #{tfiles.join(' ')}"
                 end
  cmd = cmd_template % $vol.to_i
  synth_for_inter_or_chord(semis, tfiles, wfiles, gap.val, len.val, wave)
  new_sound = false
  paused = false
  pplayer = nil
  puts "\e[0m#{cdesc}\e[2m\n^^^ given notes or holes with st diff to a4\e[0m\n#{sdesc}"
  puts

  # loop forever until ctrl-c; loop on every key
  loop do
    # we also loop when paused
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
    else
      if new_sound || !pplayer&.alive?
        if pplayer
          pplayer.kill
          pplayer.check
        end
        if new_sound
          cmd = cmd_template % $vol.to_i
          synth_for_inter_or_chord(semis, tfiles, wfiles, gap.val, len.val, wave)
          sdesc = get_sound_description(wave, gap.val, len.val)
          new_sound = false
        end
        if $testing
          IO.write($testing_log, cmd + "\n", mode: 'a')
          cmd = 'sleep 600 ### ' + cmd
        end
        pplayer = PausablePlayer.new(cmd)
      end
    end

    # wait until sound has stopped or key pressed
    begin
      break if $ctl_chord[:any]
      handle_kb_play_chord
      sleep 0.1
    end while pplayer.alive?

    # handle_kb
    if $ctl_chord[:any]
      new_sound = false
      if $ctl_chord[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[2mgo\e[0m"
          puts "#{cdesc}"
        else
          paused = true
          puts "\e[0m\e[2mSPACE to continue ...\e[0m"
        end
      elsif $ctl_chord[:vol_up]
        $vol.inc
        puts "\e[0m\e[2m#{$vol}\e[0m"
        new_sound = true
      elsif $ctl_chord[:vol_down]
        $vol.dec
        puts "\e[0m\e[2m#{$vol}\e[0m"
        new_sound = true
      elsif $ctl_chord[:wave_up]
        wave = rotate_among(wave, :up, all_waves)
        new_sound = true
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_chord[:wave_down]
        wave = rotate_among(wave, :down, all_waves)
        new_sound = true
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_chord[:gap_inc]
        gap.inc
        puts "\e[0m\e[2mGap: #{gap.val}\e[0m"
        new_sound = true
      elsif $ctl_chord[:gap_dec]
        gap.dec
        puts "\e[0m\e[2mGap: #{gap.val}\e[0m"
        new_sound = true
      elsif $ctl_chord[:len_inc]
        len.inc
        puts "\e[0m\e[2mLen: #{len.val}\e[0m"
        new_sound = true
      elsif $ctl_chord[:len_dec]
        len.dec
        puts "\e[0m\e[2mLen: #{len.val}\e[0m"
        new_sound = true
      elsif $ctl_chord[:replay]
        puts "\e[0m\e[2mReplay\e[0m"
        new_sound = true        
      elsif $ctl_chord[:show_help]
        pplayer.pause
        display_kb_help 'a chord',true,
                        "  SPACE: pause/continue  ESC,x,q: quit\n" +
                        "      w: change waveform       W: change waveform back\n" +
                        "      g: decrease time gap     G: increase\n" +
                        "      l: decrease length       L: increase\n" +
                        "      v: decrease volume       V: increase volume by 3dB" +
                        " RETURN: play again"
        pplayer.continue
        puts "\e[0m#{cdesc}"
      elsif $ctl_chord[:quit]
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        exit
      end
      $conf_meta[:ctrls_play_chord].each {|k| $ctl_chord[k] = false}
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

      if $ctl_prog[:show_help]
        display_kb_help 'a semitone progression', true,
                        "  SPACE: pause/continue\n" +
                        "    0-9: add to prefix for semitone step\n" +
                        "    ESC: clear semitone prefix\n" +
                        "    s,+: shift whole prog by one (or prefix) semitones up\n" +
                        "    S,-: shift whole progression down\n" +
                        "      v: decrease volume by 3db           V: increase volume\n" +
                        "      l: toggle looping of progression    q: quit after iteration"
        $ctl_prog[:show_help] = false
      elsif $ctl_prog[:pause_continue]
        print "\n\e[0m\e[32mSPACE to continue ..."
        begin
          char = $ctl_kb_queue.deq
        end until char == ' '
        print " go\e[0m\n"
        puts
        sleep 0.5
        $ctl_prog[:pause_continue] = false
      elsif $ctl_prog[:semi_up] || $ctl_prog[:semi_down]
        # things happen at start if outside loop
        change_semis = ( $ctl_prog[:prefix] || '1').to_i * ( $ctl_prog[:semi_up]  ?  +1  :  -1 )
        $ctl_prog[:prefix] = nil
        print "\e[0m\e[2mnext iteration: #{change_semis.abs} semitones #{$ctl_prog[:semi_up] ? 'UP' : 'DOWN'}\e[0m\n"
        $ctl_prog[:semi_up] = $ctl_prog[:semi_down] = false
      elsif $ctl_prog[:vol_up]
        $ctl_prog[:vol_up] = false
        $vol.inc
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_prog[:vol_down]
        $ctl_prog[:vol_down] = false
        $vol.dec
        puts "\e[0m\e[2m#{$vol}\e[0m"
      elsif $ctl_prog[:toggle_loop]
        $ctl_prog[:toggle_loop] = false
        loop = !loop
        print "\e[0m\e[2mloop: #{loop ? 'ON' : 'OFF'}\e[0m\n"
      elsif $ctl_prog[:quit]
        $ctl_prog[:quit] = false
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
      # continue below help
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
      print "\n"
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


class PausablePlayer

  def initialize cmd
    @cmd = cmd
    _, @stdout_err, @wait_thr  = Open3.popen2e(cmd)
    @started_at = Time.now.to_f
    @sum_pauses = 0.0
    @paused_at = nil
  end
  
  def pause
    Process.kill('TSTP', @wait_thr.pid) if @wait_thr.alive?
    @paused_at ||= Time.now.to_f
    return true
  end

  def continue
    Process.kill('CONT', @wait_thr.pid) if @wait_thr.alive?
    if @paused_at
      @sum_pauses += Time.now.to_f - @paused_at
      @paused_at = nil
    end
    return false
  end

  def time_played
    Time.now.to_f - @started_at - @sum_pauses
  end
  
  def kill
    Process.kill('KILL',@wait_thr.pid) if alive?
    @wait_thr.join
  end

  def paused?
    !!@paused_at
  end
  
  def alive?
    @wait_thr.alive?
  end

  def check
    exst = @wait_thr&.value&.exitstatus
    if exst && exst != 0
      @wait_thr.join
      puts "Command:\n  #{@cmd}\nfailed with rc #{exst} and output:\n"
      out = @stdout_err.read.lines.map {|l| '   >>  ' + l}.join
      puts ( out.length > 0  ?  out  :  '<no output>' )
      puts $sox_fail_however
      err 'See above'
    end
  end
  
end


class ConfinedValue

  def initialize value, step, lowest, highest
    @value = value
    @step = step
    @lowest = lowest
    @highest = highest
  end

  def val
    @value
  end

  def confine
    @value = @lowest if @value < @lowest
    @value = @highest if @value > @highest
    @value = @value.round(1)
    @value
  end

  def inc
    @value += @step
    confine
  end

  def dec
    @value -= @step
    confine
  end
end


def get_sound_description wave, gap, len
  "Wave: #{wave}, Gap: #{gap}, Len: #{len}"
end
