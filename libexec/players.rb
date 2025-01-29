#
# Playing under user control
#

def play_lick_recording_and_handle_kb lick, start, length, shift_inter, scroll_allowed

  recording, key = lick[:rec], lick[:rec_key]

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

  dsemi = diff_semitones($key, key, strategy: :minimum_distance) + shift_inter
  pitch_clause = ( dsemi == 0  ?  ''  :  "pitch #{dsemi * 100}" )
  tempo = 1.0
  imm_ctrls_again = [:replay, :slower, :faster, :vol_up, :vol_down]

  cnt_loops = 0
  loop_message_printed = false
  loop_rec = $ctl_lk_hl[:loop_loop]

  # loop over repetitions in radio-playing or as long as the recording needs to be played
  # again due to immediate controls triggered while it is playing
  begin
    cnt_loops += 1
    if loop_rec && cnt_loops > 1 && cnt_loops <= $ctl_lk_hl[:num_loops]
      sleep 2 if cnt_loops <= $ctl_lk_hl[:num_loops]
      print "\e[0m\e[2m(rep #{cnt_loops} of #{$ctl_lk_hl[:num_loops]}) "
    end

    tempo_clause = ( tempo == 1.0  ?  ''  :  ('tempo -m %.1f' % tempo) )
    cmd = "play -q --norm=#{$vol.to_i} -V1 #{$lick_dir}/recordings/#{recording} #{trim_clause} #{pitch_clause} #{tempo_clause}".strip
    IO.write($testing_log, cmd + "\n", mode: 'a') if $testing
    if $testing_what == :player
      cmd = 'sleep 600 ### ' + cmd
    elsif $testing && $testing != 'player'
      sleep 4
      return false
    end
    pplayer = PausablePlayer.new(cmd)
    (imm_ctrls_again + [:skip, :pause_continue, :show_help]).each {|k| $ctl_rec[k] = false}
    
    # loop to check repeatedly while the recording is beeing played
    begin

      sleep 0.1
      handle_kb_play_lick_recording
      
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        pplayer.pause
        print "\e\2m (%.2fs) " % pplayer.time_played
        space_to_cont
        pplayer.continue
        print "\e[0m\e[32mgo \e[0m"
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
        display_kb_help 'the recording of a lick', scroll_allowed,
                        "SPACE: pause/continue            " + 
                        if $ctl_lk_hl[:can_star_unstar]
                          "  *,/: star,unstar lick\n"
                        else
                          "\n"
                        end +
                        "TAB,+: skip to end                  -.: back to start\n" +
                        "  v,V: decrease,increase volume    <,>: decrease,increase speed\n" +
                        "    l: toggle loop over rec " +
                        ( loop_rec  ?  "(now ON)\n"  :  "(now OFF)\n" )
        print "\e[#{$lines[:hint_or_message]}H" unless scroll_allowed
        pplayer.continue
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32mreplay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32mskip to end \e[0m"
      elsif $ctl_lk_hl[:star_lick]
        star_unstar_lick($ctl_lk_hl[:star_lick], lick)
        if $ctl_lk_hl[:star_lick] == :up
          print "\e[0m\e[32mStarred lick \e[0m"
        else
          print "\e[0m\e[32mUnstarred lick \e[0m"
        end
        $ctl_lk_hl[:star_lick] = false
      elsif $ctl_lk_hl[:toggle_loop]
        loop_rec = !loop_rec
        print "\e[0m\e[32mLoop over recording is: " + ( loop_rec  ?  "ON\n"  :  "OFF\n" )
        $ctl_lk_hl[:toggle_loop] = false
      elsif $ctl_rec[:invalid]
        print "\e[0m\e[2m(#{$ctl_rec[:invalid]}) \e[0m"
        $ctl_rec[:invalid] = false
      end

      # should be similar output to playing holes, e.g. holes first, then newline
      if loop_rec && !loop_message_printed
        # let the user know, how to end looping
        print "\e[0m\e[32mloop (TAB,+ to skip, l to end) with #{$ctl_lk_hl[:num_loops]} reps \e[0m"
        loop_message_printed = true
      end
      
      # need to go leave this loop and play again if any immediate
      # controls have been triggered
    end while pplayer.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}
    
    loop_rec = false if $ctl_rec[:skip]
    pplayer.kill
    pplayer.check

  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} ||
            ( loop_rec && cnt_loops < $ctl_lk_hl[:num_loops] )

  puts if scroll_allowed
  $ctl_rec[:skip]
end


def play_recording_and_handle_kb recording, timed_comments = nil, scroll_allowed = true

  imm_ctrls_again = [:replay, :vol_up, :vol_down]

  loop_message_printed = false
  loop_rec = $ctl_lk_hl[:loop_loop]  

  # loop as long as the recording needs to be played again due to
  # immediate controls triggered while it is playing
  begin

    (imm_ctrls_again + [:skip]).each {|k| $ctl_rec[k] = false}
    if recording.is_a?(Array)
      cmd = "play --norm=#{$vol.to_i} -q -V1 --combine mix #{recording.join(' ')}".strip
    else
      cmd = "play --norm=#{$vol.to_i} -q -V1 #{recording}".strip
    end
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
      handle_kb_play_recording
      if $ctl_rec[:pause_continue]
        $ctl_rec[:pause_continue] = false
        pplayer.pause
        space_to_cont
        pplayer.continue
        print "\e[0m\e[32mgo \e[0m"
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
                        "  TAB,+: skip to end           -: back to start\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        "      l: loop over recording"
        print "\e[#{$lines[:hint_or_message]}H" unless scroll_allowed
        pplayer.continue
        $ctl_rec[:show_help] = false
      elsif $ctl_rec[:replay]
        print "\e[0m\e[32m replay \e[0m"
      elsif $ctl_rec[:skip]
        print "\e[0m\e[32m skip to end \e[0m"
      elsif $ctl_lk_hl[:toggle_loop]
        loop_rec = !loop_rec
        print "\e[0m\e[32mLoop over recording is: " + ( loop_rec  ?  "ON\n"  :  "OFF\n" )
        $ctl_lk_hl[:toggle_loop] = false
      elsif $ctl_rec[:invalid]
        print "\e[0m\e[2m(#{$ctl_rec[:invalid]}) \e[0m"
        $ctl_rec[:invalid] = false        
      end

      if timed_comments && timed_comments.length > 0
        if pplayer.time_played > timed_comments[0][0]
          print timed_comments[0][1]
          timed_comments.shift
        end
      end

      if loop_rec && !loop_message_printed
        print "\e[0m\e[32mloop (TAB,+ to skip, l to end)\e[0m "
        puts if scroll_allowed
        loop_message_printed = true
      end

      # need to go leave this loop and play again if any immediate
      # controls have been triggered
    end while pplayer.alive? && !(imm_ctrls_again + [:skip]).any? {|k| $ctl_rec[k]}

    pplayer.kill
    pplayer.check
  end while imm_ctrls_again.any? {|k| $ctl_rec[k]} || loop_rec
end


def play_interactive_pitch embedded: false, explain: true,
                           start_key: nil, return_accepts: false

  semi = note2semi((start_key || $key).then {|k| ('1' .. '9').include?(k[-1])  ?  k  :  k + '4'})
  wave = wave_was = 'pluck'
  min_semi = -24
  max_semi = 24
  paused = false
  pplayer = nil
  cmd = cmd_was = nil
  sleep 0.1 if embedded
  if explain
    puts "\e[0m\e[32mPlaying an adjustable pitch, that you may compare\nwith a song, that is playing at the same time."
    puts "\n\e[0m\e[2mPrinted are the key of the song and the key of the harp\nthat matches when played in second position."
  end

  sleep 0.1 if embedded
  if explain
    puts
    puts "\e[0m\e[2mSuggested procedure: Play the song in the background and"
    puts "step by semitones until you hear a good match; then try a fifth"
    puts "up and down, to check if those may match even better. Step by octaves,"
    puts "if your pitch is far above or below the song."
  end
  sleep 0.1 if embedded
  puts
  puts "\e[0m\e[2m(type 'h' for help)\e[0m"
  puts
  print_pitch_information(semi)

  # loop forever until ctrl-c
  loop do
    # we also loop when paused, so that user can change other settings during pause
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
      sleep 0.1
    else
      # semi+7 because key of song, rather than key of harp is wanted
      cmd = if $testing then 
              "sleep 1"
            else
              "play --norm=#{$vol.to_i} -q -n synth 3 #{wave} %#{semi+7}"
            end
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
      break if $ctl_pitch[:any] || $ctl_pitch[:invalid]
      handle_kb_play_pitch
      sleep 0.1
    end while pplayer.alive?

    if $ctl_pitch[:any] || $ctl_pitch[:invalid]
      knm = $conf_meta[:ctrls_play_pitch].select {|k| $ctl_pitch[k] && k != :any}[0].to_s.gsub('_',' ')
      if $ctl_pitch[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[32m#{$resources[:playing_on]}\e[0m"
        else
          paused = true
          print "\e[0m\e[32m#{$resources[:playing_is_paused]}\e[0m"
        end
        $ctl_rec[:pause_continue] = false        
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
        wave = rotate_among(wave, :up, $all_waves)
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:wave_down]
        wave_was = wave
        wave = rotate_among(wave, :down, $all_waves)
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_pitch[:show_help]
        pplayer.pause
        display_kb_help 'a pitch',true,
                        "  SPACE: pause/continue  ESC,x,q: " + ( embedded ? "discard\n" : "quit\n" ) +
                        "      w: change waveform       W: change waveform back\n" + 
                        " s,+,up: one semi up    S,-,down: one semitone down\n" +
                        "      o: one octave up         O: one octave down\n" +
                        "      f: one fifth up          F: one fifth down\n" +
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        ( embedded  ?  ' RETURN: accept'  :  ' RETURN: play again'),
                        wait_for_key: !paused
        pplayer.continue
        print_pitch_information(semi)
      elsif $ctl_pitch[:invalid]
        puts "\e[0m\e[2m(#{$ctl_pitch[:invalid]})\e[0m"
        $ctl_pitch[:invalid] = false
      elsif $ctl_pitch[:quit] || $ctl_pitch[:accept_or_repeat]
        new_key =  if $ctl_pitch[:accept_or_repeat] || return_accepts
                     semi2note(semi)[0..-2]
                   else
                     nil
                   end
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        if $ctl_pitch[:quit] || ($ctl_pitch[:accept_or_repeat] && return_accepts) || embedded
          $ctl_pitch[:quit] = $ctl_pitch[:accept_or_repeat] = false
          return new_key
        end
      end

      $conf_meta[:ctrls_play_pitch].each {|k| $ctl_pitch[k] = false}
    end

    if wave == 'pluck' && wave_was != 'pluck'
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
  tfiles = [1, 2].map {|i| "#{$dirs[:tmp]}/semi#{i}.wav"}
  gap = ConfinedValue.new(0.2, 0.2, 0, 2)
  len = ConfinedValue.new(3, 1, 1, 8)
  cmd_template = if $testing
                   "sleep 1"
                 else
                   "play --norm=%s -q --combine mix #{tfiles[0]} #{tfiles[1]}"
                 end
  cmd = cmd_template % $vol.to_i
  synth_for_inter_or_chord([semi1, semi2], tfiles, gap.val, len.val)
  new_sound = true
  paused = false
  pplayer = nil

  # loop forever until ctrl-c; loop on every key
  loop do
    # we also loop when paused, so that user can change other settings during pause
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
      sleep 0.1
    else
      if new_sound || !pplayer&.alive?
        if pplayer
          pplayer.kill
          pplayer.check
        end
        if new_sound
          cmd = cmd_template % $vol.to_i
          synth_for_inter_or_chord([semi1, semi2], tfiles, gap.val, len.val)
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
      break if $ctl_inter[:any] || $ctl_inter[:invalid]
      handle_kb_play_inter
      sleep 0.1
    end while pplayer.alive?

    # handle kb
    if $ctl_inter[:any] || $ctl_inter[:invalid] 
      new_sound = false
      if $ctl_inter[:pause_continue]
        if paused
          paused = false
          puts "\e[0m\e[32m#{$resources[:playing_on]}\e[0m"
        else
          paused = true
          print "\e[0m\e[32m#{$resources[:playing_is_paused]}\e[0m"          
        end
        $ctl_rec[:pause_continue] = false        
      elsif $ctl_inter[:up] || $ctl_inter[:down]
        step =  $ctl_inter[:up]  ?  +1  :  -1
        semi1 += step
        semi2 += step
        print_interval(semi1, semi2) if paused
        new_sound = true
      elsif $ctl_inter[:narrow] || $ctl_inter[:widen]
        delta_semi +=  $ctl_inter[:narrow]  ?  -1  :  +1
        semi2 = semi1 + delta_semi
        print_interval(semi1, semi2) if paused
        new_sound = true
      elsif $ctl_inter[:gap_inc]
        gap.inc
        puts "\e[0m\e[2m  Gap: #{gap.val}\n\n" if paused
        new_sound = true
      elsif $ctl_inter[:gap_dec]
        gap.dec
        puts "\e[0m\e[2m  Gap: #{gap.val}\n\n" if paused
        new_sound = true
      elsif $ctl_inter[:len_inc]
        len.inc
        puts "\e[0m\e[2m  length: #{len.val}\e[0m\n\n" if paused
        new_sound = true
      elsif $ctl_inter[:len_dec]
        len.dec
        puts "\e[0m\e[2m  length: #{len.val}\e[0m\n\n" if paused
        new_sound = true
      elsif $ctl_inter[:swap]
        semi1, semi2 = semi2, semi1
        delta_semi = -delta_semi
        print_interval(semi1, semi2) if paused
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
        pplayer.pause unless paused
        display_kb_help 'an interval',true,
                        "   SPACE: pause/continue          ESC,x,q: quit\n" +
                        "       +: widen interval by one semi    -: narrow by one semi\n" +
                        "       >: move interval up one semi     <: move down\n" +
                        "       g: decrease time gap             G: increase\n" +
                        "       l: decrease length               L: increase\n" +
                        "       v: decrease volume by 3db        V: increase volume\n" +
                        "       s: swap notes               RETURN: play again",
                        wait_for_key: !paused
        pplayer.continue unless paused
      elsif $ctl_inter[:quit]
        $ctl_inter[:quit] = false
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        return
      elsif $ctl_inter[:invalid]
        puts "\e[0m\e[2m#{$ctl_inter[:invalid]}\e[0m"
        $ctl_inter[:invalid] = false
      end

      $conf_meta[:ctrls_play_inter].each {|k| $ctl_inter[k] = false}
    end
  end
end


def play_interactive_chord semis, args_orig

  puts "\e[0m\e[2mPlaying in loop.\n"
  puts "(type 'h' for help)\e[0m\n\n"

  tfiles = (1 .. semis.length).map {|i| "#{$dirs[:tmp]}/semi#{i}.wav"}
  wave = 'sawtooth'
  gap = ConfinedValue.new(0.2, 0.1, 0, 2)
  len = ConfinedValue.new(6, 1, 1, 16)
  # chord dscription and sound description
  cdesc = semis.zip(args_orig).map {|s,o| "#{o} (#{s}st)"}.join('  ')
  sdesc = get_sound_description(wave, gap.val, len.val)
  cmd_template = if $testing
                   "sleep 1"
                 else
                   "play --norm=%s -q --combine mix #{tfiles.join(' ')}"
                 end
  cmd = cmd_template % $vol.to_i
  synth_for_inter_or_chord(semis, tfiles, gap.val, len.val, wave)
  new_sound = false
  paused = false
  pplayer = nil
  puts "\e[0m#{cdesc}\e[2m\n^^^ given notes or holes with st diff to a4\e[0m\n#{sdesc}"
  puts

  # loop forever until ctrl-c; loop on every key
  loop do
    # we also loop when paused, so that user can change other settings during pause    
    if paused
      if pplayer&.alive?
        pplayer.kill
        pplayer.check
      end
      sleep 0.1
    else
      if new_sound || !pplayer&.alive?
        if pplayer
          pplayer.kill
          pplayer.check
        end
        if new_sound
          cmd = cmd_template % $vol.to_i
          synth_for_inter_or_chord(semis, tfiles, gap.val, len.val, wave)
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
          puts "\e[0m\e[32m#{$resources[:playing_on]}\e[0m"
          puts "#{cdesc}"
        else
          paused = true
          print "\e[0m\e[32m#{$resources[:playing_is_paused]}\e[0m"
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
        wave = rotate_among(wave, :up, $all_waves)
        new_sound = true
        puts "\e[0m\e[2m#{wave}\e[0m"
      elsif $ctl_chord[:wave_down]
        wave = rotate_among(wave, :down, $all_waves)
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
                        "      v: decrease volume       V: increase volume by 3dB\n" +
                        " RETURN: play again",
                        wait_for_key: !paused
        pplayer.continue
        puts "\e[0m#{cdesc}"
      elsif $ctl_chord[:quit]
        if pplayer&.alive?
          pplayer.kill
          pplayer.check
        end
        return
      elsif $ctl_chord[:invalid]
        puts "\e[0m\e[2m#{$ctl_chord[:invalid]}\e[0m"
        $ctl_chord[:invalid] = false
      end
      $conf_meta[:ctrls_play_chord].each {|k| $ctl_chord[k] = false}
    end
  end
end


def play_interactive_progression progs, progs_disp

  fmt = ' ' + '|%8s ' * 4 + '|'
  puts "\nProgressions are: "
  progs_disp.each_with_index {|pr, ix| puts "   (#{ix+1})  #{pr}"}
  print "\n\n"
  
  puts "\e[0m\e[2mWhile a progression play, you may shift its next iteration\nby pressing appropriate keys"
  if progs.length == 1
    puts "You specified one progression only, but multiple are accepted too, separated by ' . '"
  else
    puts "You may also switch between progressions for each next iteration"
  end
  print "\nSPACE to pause, h for help;   looping is  ON\e[0m\n\n"
  quit = change_semis = false
  total_semis = total_semis_was = 0
  progs_idx = 0
  progs_idx_was = -1
  loop = true
  pplayer = nil

  # loop repeating the progression
  begin
    prog = progs[progs_idx]
    if change_semis
      prog.map! {|s| s += change_semis}
      total_semis += change_semis
      change_semis = false
    end
    holes, notes, abs_semis, rel_semis = get_progression_views(prog)

    if progs_idx != progs_idx_was
      print "\e[2mProgression is (#{progs_idx + 1}): #{progs_disp[progs_idx]}\e[0m\n\n"
      progs_idx_was = progs_idx
    end
    
    if total_semis != total_semis_was
      print "\e[2mTotal shift is #{total_semis} semitones"
      print ", #{$intervals[total_semis][0]}" if $intervals[total_semis]
      print "\e[0m\n\n"
      total_semis_was = total_semis
    end

    
    puts fmt % ['Holes', 'Notes', 'abs st', 'rel st']
    sleep 0.05
    puts ' ' + '|---------' * 4 + '|'
    sleep 0.05
    $ctl_prog[:prefix] = nil    

    # loop over holes of progression
    [holes, :delay].flatten.zip(notes, abs_semis, rel_semis).each do |ho, no, as, rs|

      if ho != :delay
        line = fmt % [ho, no, as, rs]
        3.times { puts ; sleep 0.05 }
        print "\e[3A\e[G"
        print "\e[G\e[0m#{line}\e[0m\n"
      end
      
      if pplayer
        pplayer.kill
        pplayer.check
      end
      cmd = if ho == :delay
              "sleep 0.1"
            elsif $testing
              "sleep 1"
            else
              "play --norm=#{$vol.to_i} -q -n synth #{( $opts[:fast] ? 1 : 0.5 )} pluck %#{as}"
            end
      pplayer = PausablePlayer.new(cmd)
      paused = false
      
      # we also loop when paused, so that user can change other settings during pause
      # loop while playing or paused
      begin

        handle_kb_play_semis

        if $ctl_prog[:pause_continue]
          if paused
            paused = false
            pplayer.continue
            puts "\e[0m\e[32m#{$resources[:playing_on]}\e[0m"
          else
            paused = true
            pplayer.pause
            print "\e[0m\e[32m#{$resources[:playing_is_paused]}\e[0m"
          end
          $ctl_prog[:pause_continue] = false        
        elsif $ctl_prog[:show_help]
          display_kb_help 'a semitone progression', true,
                          "    SPACE: pause/continue\n" +
                          "      0-9: add to prefix for semitone step\n" +
                          "      ESC: clear semitone prefix\n" +
                          "    u,s,+: shift next iteration of progression UP by one (or prefix) semitones\n" +
                          "    d,S,-: shift next iteration of progression DOWN\n" +
                          "  <,>,p,n: switch to previous or next progression (if more than one)\n" +
                          "        v: decrease volume by 3db           V: increase volume\n" +
                          "        l: toggle looping of progression    q: quit after iteration",
                          wait_for_key: !paused
          $ctl_prog[:show_help] = false
        elsif $ctl_prog[:semi_up] || $ctl_prog[:semi_down]
          # things happen at start if outside loop
          change_semis_was = change_semis
          change_semis = ( $ctl_prog[:prefix] || '1').to_i * ( $ctl_prog[:semi_up]  ?  +1  :  -1 )
          ctxt = ( change_semis == change_semis_was  ?  '; unchanged; does not add up, rather use prefix'  :  '' )
          itxt = ( $intervals[change_semis.abs]  ?  " (#{$intervals[change_semis.abs][0]})"  :  '' )
          puts "\e[0m\e[2mnext iteration: #{change_semis.abs} semitones#{itxt} #{$ctl_prog[:semi_up] ? 'UP' : 'DOWN'}#{ctxt}\e[0m"
          $ctl_prog[:semi_up] = $ctl_prog[:semi_down] = false
          $ctl_prog[:prefix] = nil
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
          puts "\e[0m\e[2mloop: #{loop ? 'ON' : 'OFF'}\e[0m"
        elsif $ctl_prog[:prev_prog]
          $ctl_prog[:prev_prog] = false
          progs_idx = (progs_idx + 1) % progs.length
          if progs.length == 1
            puts "\e[0m\e[2mjust one progression given, cannot change it\e[0m"
          else
            puts "\e[0m\e[2mprevious progression\e[0m"
          end
        elsif $ctl_prog[:next_prog]
          $ctl_prog[:next_prog] = false
          progs_idx = (progs_idx - 1) % progs.length
          if progs.length == 1
            puts "\e[0m\e[2mjust one progression given, cannot change it\e[0m"
          else
            puts "\e[0m\e[2mnext progression\e[0m"
          end
        elsif $ctl_prog[:quit]
          $ctl_prog[:quit] = false
          quit = true
          puts "\e[0m\e[2mQuit after this iteration\e[0m"
        elsif $ctl_prog[:invalid]
          puts "\e[0m\e[2m#{$ctl_prog[:invalid]}\e[0m"
          $ctl_prog[:invalid] = false
        end
      end while paused  || pplayer&.alive?  ## loop while playing or paused
    end  ## loop over holes of progression

    print "\n\n" if loop || change_semis
    break if quit
  end while loop || change_semis  ## loop repeating the progression
  puts
end


def play_holes_or_notes_and_handle_kb holes_or_notes, hide: nil

  # allow hide to be a single value, a hash or an array (maybe with hashes)
  hide = [hide].flatten
  hide.compact!
  hides, simples = hide.partition {_1.is_a?(Hash)}
  hide = Hash.new
  hides.each {hide.merge!(_1)}
  simples.each {hide[_1] = '?'}
  
  unless hide[:help]
    puts "\e[2m(SPACE to pause, 'h' for help)\e[0m"
    puts
  end
  $ctl_hole[:skip] = false
  holes_or_notes.each do |hon|
    print((hide[hon] || hide[:all] || hon) + ' ')
    if musical_event?(hon)
      sleep $opts[:fast]  ?  0.125  :  0.25
    else
      duration = ( $opts[:fast] ? 0.5 : 1 )
      non = $harp.dig(hon, :note) || hon
      play_hole_or_note_and_collect_kb hon, duration
    end
    if $ctl_hole[:show_help]
      display_kb_help 'a series of holes or notes', true,  <<~end_of_content
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
    elsif $ctl_hole[:invalid]
      print "(#{$ctl_hole[:invalid]}) "
      $ctl_hole[:invalid] = false
    end
  end
  puts
end


def play_lick_holes_and_handle_kb all_holes, at_line: nil, scroll_allowed: false, lick: nil, with_head: false, hide_holes: false

  if $opts[:partial] && !$ctl_mic[:replay_flags].include?(:ignore_partial)
    holes, _, _ = select_and_calc_partial(all_holes, nil, nil)
  else
    holes = all_holes
  end
  
  IO.write($testing_log, holes.inspect + "\n", mode: 'a') if $testing
  
  $ctl_hole[:skip] = false

  if !scroll_allowed
    if at_line
      print "\e[#{at_line}H\e[K"
      print "\e[#{at_line - 1}H\e[K"
    else
      print "\e[#{$lines[:message2]}H\e[K"
      print "\e[#{$lines[:hint_or_message]}H\e[K"
    end
  end
  
  print( lick  ?  "\e[2mLick \e[0m#{lick[:name]}\e[2m (h for help) ... "  :  "\e[2mHoles (h for help) ... ") if with_head

  cnt_loops = 0
  loop_message_printed = false
  loop_holes = $ctl_lk_hl[:loop_loop]

  # loop over repetitions in radio-playing
  begin
    cnt_loops += 1
    if loop_holes && cnt_loops > 1 && cnt_loops <= $ctl_lk_hl[:num_loops]
      sleep 2 if cnt_loops <= $ctl_lk_hl[:num_loops]
      print "\e[0m\e[2m(rep #{cnt_loops} of #{$ctl_lk_hl[:num_loops]}) "
    end

    [holes, '(0.5)'].flatten.each_cons(2).each_with_index do |(hole, hole_next), idx|

      hole_disp = ( hide_holes  ?  '?'  :  hole )
      print( musical_event?(hole)  ?  "\e[2m#{hole_disp}\e[2m "  :  "\e[0m#{hole_disp}\e[2m " )
      
      if musical_event?(hole)
        sleep $opts[:fast]  ?  0.125  :  0.25
      else
        # this also handles kb input and sets $ctl_hole
        play_hole_or_note_and_collect_kb hole, get_musical_duration(hole_next)
      end

      # react on keyboard input
      if $ctl_hole[:show_help]
        display_kb_help 'the holes of a lick', scroll_allowed,
        "SPACE: pause/continue" +
        if $ctl_lk_hl[:can_star_unstar]
          "          *,/: star,unstar lick\n"
        else
          "\n"
        end +
        "TAB,+: skip to end\n" +
        "  v,V: decrease,increase volume\n" +
        "    l: toggle loop over holes " +
        ( loop_holes  ?  "(now ON)\n"  :  "(now OFF)\n" )
        # continue below help (first round only)
        print "\n"
        at_line = [at_line + 10, $term_height].min if at_line
        $ctl_hole[:show_help] = false
      elsif $ctl_hole[:vol_up]
        $vol.inc
        print "\e[0m\e[32m #{$vol}\e[0m "
        $ctl_hole[:vol_up] = false
      elsif $ctl_hole[:vol_down]
        $vol.dec
        print "\e[0m\e[32m #{$vol}\e[0m "
        $ctl_hole[:vol_down] = false
      elsif $ctl_hole[:skip]
        print "\e[0m\e[32mskip to end \e[0m"
        sleep 0.3
        break
      elsif $ctl_lk_hl[:star_lick]
        star_unstar_lick($ctl_lk_hl[:star_lick], lick)
        if $ctl_lk_hl[:star_lick] == :up
          print "\e[0m\e[32mStarred lick \e[0m"
        else
          print "\e[0m\e[32mUnstarred lick \e[0m"
        end
        $ctl_lk_hl[:star_lick] = false
      elsif $ctl_lk_hl[:toggle_loop]
        loop_holes = !loop_holes
        print "\e[0m\e[32mLoop over holes is: " + ( loop_holes  ?  "ON\n"  :  "OFF\n" )
        $ctl_lk_hl[:toggle_loop] = false
      elsif $ctl_hole[:invalid]
        print "\e[0m(#{$ctl_hole[:invalid]}\e[0m) "
        $ctl_hole[:invalid] = false
      end
    end

    # should be similar output to playing recording, e.g. holes first, then newline
    if loop_holes && !loop_message_printed
      puts if scroll_allowed
      print "\e[0m\e[32mloop (TAB,+ to skip, l to end) with #{$ctl_lk_hl[:num_loops]} reps \e[0m"
      loop_message_printed = true
    end

  end while !$ctl_hole[:skip] && loop_holes && cnt_loops < $ctl_lk_hl[:num_loops]
  
  puts if scroll_allowed
end


class PausablePlayer

  attr_accessor :sum_pauses
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

  def wait
    Process.wait(@wait_thr.pid) if @wait_thr.alive?  
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


