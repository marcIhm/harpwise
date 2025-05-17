#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $testing
    FileUtils.cp $test_wav, file
    sleep secs
  else
    pp "rec -q -c 1 -r #{$conf[:sample_rate]} #{file} trim 0 #{secs}"
    cmd = "rec -q -c 1 -r #{$conf[:sample_rate]} #{file} trim 0 #{secs}"
    sys "#{cmd} #{output_clause}", $sox_fail_however
  end
end


def play_wave file, secs = ( $opts[:fast] ? 0.5 : 1 )
  cmd = if $testing
          "sleep #{secs}"
        else
          "play -q --norm=#{$vol.to_i} #{file} trim 0 #{secs}"
        end
  sys(cmd, $sox_fail_however)
end


def run_aubiopitch file, extra = nil
  sys "aubiopitch --pitch #{$conf[:pitch_detection]} #{file} 2>&1"
end


def trim_recorded hole, recorded
  wave2data(recorded)
  duration = sox_query(recorded, 'Length')
  duration_trimmed = 1.2
  do_draw = true
  trimmed_wave = "#{$dirs[:tmp]}/trimmed.wav"
  play_from = find_onset
  trim_wave recorded, play_from, duration_trimmed, trimmed_wave
  loop do
    if do_draw
      draw_data(play_from, play_from + duration_trimmed)
      inspect_recorded(hole, recorded)
      do_draw = false
    else
      puts
    end
    puts "\e[34mTrimming\e[0m #{File.basename(recorded)} for hole  \e[32m-->   \e[92m#{hole}\e[32m   <--  \e[0mplay from %.2f" % play_from
    puts "       \e[0m0-9: \e[2menter start at   \e[0md: \e[2mdraw      \e[0mp,SPACE: \e[2mplay      \e[0mf: \e[2mplay freq"
    puts "  \e[0my,RETURN: \e[2maccept           \e[0mr: \e[2mre-record     \e[0mq,c: \e[2mcancel this hole\e[0m"
    print "Your choice (h for help): "
    choice = one_char

    if ('0' .. '9').to_a.include?(choice) || choice == '.'
      choice = '0.' if choice == '.'
      print "Finish with RETURN: #{choice}"
      choice += gets_with_cursor.downcase
      is_number = true
    else
      puts choice
      is_number = false
    end
    if choice == '?' || choice == 'h'
      puts <<EOHELP

Full Help:

        0-9: set position to start from (marked by vertical bar
             line in plot); just start to type, e.g.:  0.4
          d: draw current recording
    p,SPACE: play from current start position
   y,RETURN: accept current start position, trim file
             and skip to next hole
          f: play a sample frequency for comparison 
        q,c: cancel and go to main menu, where you may
             generate a sample instead
          r: record and trim again for this hole
EOHELP
      
    elsif ['', ' ', 'p'].include?(choice)
      puts "\e[34mPlay\e[0m from %.2f ..." % play_from
      play_wave trimmed_wave, 5
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y' || choice == 'RETURN'
      FileUtils.cp trimmed_wave, recorded
      wave2data(recorded)
      puts "\nEdit\e[0m accepted, trimmed #{File.basename(recorded)}, starting with \e[32mnext hole\e[0m.\n\n"
      return :next
    elsif choice == 'c' || choice == 'q'
      wave2data(recorded)
      puts "\nEdit\e[0m canceled, continue with current hole.\n\n"
      return :cancel
    elsif choice == 'f'
      print "\e[34mSample\e[0m sound ..."
      synth_sound hole, $helper_wave, silent: true
      play_wave $helper_wave
    elsif choice == 'r'
      puts "Redo recording and trim ..."
      return :redo
    elsif is_number
      begin
        val = choice.to_f
        raise ArgumentError.new('must be > 0') if val < 0
        raise ArgumentError.new("must be < duration #{duration}") if val >= duration
        play_from = val
        trim_wave recorded, play_from, duration_trimmed, trimmed_wave
        do_draw = true
      rescue ArgumentError => e
        puts "Invalid Input '#{choice}': #{e.message}"
      end
    else
      puts "Invalid Input '#{choice}'"
    end
  end 
end


def trim_wave file, play_from, duration, trimmed
  fade_out = 0.2
  puts "Taking \e[32m%.2f\e[0m .. %.2f \e[2m(= \e[0m\e[34m#{duration}\e[0m\e[2m + #{fade_out} fade-out)\e[0m" % [play_from, play_from + duration + fade_out]
  cmd = "sox -q #{file} #{trimmed} trim #{play_from.round(2)} #{play_from.round(2) + duration + fade_out} gain -n -3 fade 0 -0 #{fade_out}"
  sys cmd
end


def sox_query file, property
  sys("sox -q #{file} -n stat 2>&1").lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole, file, extra = '', silent: false
  puts "Hole  \e[32m%-8s\e[0m#{extra},   note  \e[32m%-6s\e[0m,   semi \e[32m%4d\e[0m" % [hole, $harp[hole][:note], $harp[hole][:semi]] unless silent
  duration = if $opts[:wave] == 'pluck'
               $opts[:fast] ? 0.5 : 1
             else
               $opts[:fast] ? 2 : 4
             end
  cmd = "sox -q -n #{file} synth #{duration} #{$opts[:wave]} %#{$harp[hole][:semi]} vol #{$conf[:auto_synth_db] || 0}db"
  sys cmd
end


def wave2data file
  sys "sox -q #{file} #{$recorded_data}"
end


def find_onset
  max = 0
  File.foreach($recorded_data) do |line|
    next if line[0] == ';'
    max = [max, line.split[1].to_f].max
  end
  
  max13 = max * 1.0/3
  max23 = max13 * 2
  t13 = t23 = nil
  File.foreach($recorded_data) do |line|
    next if line[0] == ';'
    t, v = line.split.map(&:to_f)
    t13 = t if !t13 && v >= max13
    t23 = t if !t23 && v >= max23
  end
  ts = t13 - 2 * ( t23 - t13 ) - 0.1
  ts = 0 if ts < 0
  ts
end


def this_or_equiv template, note, endings = ['']
  endings.each do |ending|
    notes_equiv(note).each do |eq|
      name = ( template % eq ) + ending
      return name if File.exist?(name)
    end
  end
  return nil
end


def start_collect_freqs
  Thread.new {sox_to_aubiopitch_to_queue}
end


def sox_to_aubiopitch_to_queue

  cmd = if $testing
          get_pipeline_cmd(:pv, $test_wav)
        else
          get_pipeline_cmd(:sox, '-d')
        end
  
  _, ppl_out, ppl_err, wait_thr = Open3.popen3(cmd)

  # cmd may need some time to terminate in the case of startup problems
  sleep 0.5
  if !IO.select([ppl_out], nil, nil, 4) || !wait_thr.alive?
    err(
      if IO.select([ppl_err], nil, nil, 2)
        "Command terminated unexpectedly: #{cmd}\n" +
          # we use sysread, because read would block (?)
          ppl_err.sysread(65536).lines.map {|l| " >> #{l}"}.join
      else
        "Command produced no output and no error message: #{cmd}"
      end
    ) 
  end
  line = nil
  no_gets = 0
  iters = 0
  last_queue_time_now = last_queue_time = last_queue_line = nil
  #
  # Remark: The code below checks for several conditions, we have encountered while porting
  # to homebrew/macos  or  switching to the one-piece pipeline  or  building a snap.
  # So please read the comments twice, before streamlining.
  #
  # The jitter checks tests for jitter, i.e. varying delays in samples beeing delivered by
  # aubiopitch (which seems to happen under wsl2 now and then).
  #
  pipeline_started = Time.now.to_f
  $freqs_queue.clear  
  # loop forever one batch of frequencies after the other
  loop do
    # gets (below) might block, so guard it by timeout
    begin
      Timeout.timeout(10) do
        # inner loop to reduce (suspected) overhead of setting up timeout
        20.times do
          line = nil
          # gets might return nil for unknown reasons (e.g. in an unpatched homebrew-setup)
          while !(line = ppl_out.gets)
            sleep 0.5
            no_gets += 1
            err_out = if IO.select([ppl_err], nil, nil, 2)
                        "Output from stderr is:\n" +
                          # we use sysread, because read would block (?)
                          ppl_err.sysread(65536).lines.map {|l| " >> #{l}"}.join
                      else
                        "No output from stderr either.\n"
                      end

            err "10 times no output from:\n#{cmd}\n#{err_out}\nMaybe try:   harpwise tools diag2   to investigate in detail" if no_gets > 10
          end
          line.chomp!
          $freqs_queue.enq Float(line.split(' ',2)[1])

          # Check for jitter now and then. This will not find every case
          # of jitter, but if jitter repeats, it will be found
          # eventually.
          #
          # At the same time (now and then), we check more throughly for
          # output of pipeline.
          iters += 1
          if iters == $jitter_check_after_iters
            begin
              iters = 0
              # get the timestamp, that is generated by aubiopitch; it is relative to the
              # start of the sound
              queue_time = Float(line.split(' ',2)[0])
              now = Time.now.to_f
              if last_queue_time
                # diff in timestamps transmitted over pipeline vs. diff in timestamps of
                # picking these values from pipeline
                jitter = ((queue_time - last_queue_time) - (now - last_queue_time_now)).abs
                $jitter_checks_total += 1
                # ignore jitter within first two secs
                if now > pipeline_started + 2 && jitter > $jitter_threshold 
                  $jitter_checks_bad += 1
                  if jitter > $max_jitter
                    $max_jitter = jitter.abs
                    $max_jitter_at = now
                    $max_jitter_info = [[last_queue_time_now, last_queue_line.split], [now, line.split]]
                  end
                end
              end
              last_queue_line = line
              last_queue_time = queue_time
              last_queue_time_now = now
              last_queue_time_now -= 2 if $testing_what == :jitter
            rescue ArgumentError
              err "Cannot understand below output of this command: #{ppl_cmd}\n" +
                  line.lines.map {|l| " >> #{l}"}.join
            end  # check for invalid output
          end  # check for jitter (now and then)
        end
      end
    rescue Timeout::Error
      err "No output from: #{cmd}"
    end  # check for timeout in gets    
    
  end  # one batch of frequencies after the other
end


def get_pipeline_cmd(what, wav_from)

  err "Internal error: #{what}" unless [:pv, :sox].include?(what)
  #
  # Regarding "pv" below: 192000 = 48000 * 4 (sample rate, 32 Bit, 1
  # Chanel) is the rate of our sox-generated testing-files
  #
  # Regarding "sox" below: We tried "rec" instead of "sox -d" but this
  # did not work within a pipeline for unknown reasons
  #
  templates = [{pv: "pv -qL 192000 %s",
                sox: "stdbuf -o0 sox -q %s -r #{$conf[:sample_rate]} -t wav -"},
               "stdbuf -i0 -oL aubiopitch --bufsize %s --hopsize %s --pitch %s -i -"]

  args = [wav_from]
  args << $aubiopitch_sizes[$opts[:time_slice]]
  args.flatten!
  args << $conf[:pitch_detection]
  template = templates[0][what] + ' | ' + templates[1]
  $freq_pipeline_cmd = template % args
end
  

def pipeline_catch_up
  $freqs_queue.clear
end


def play_hole_or_note_and_collect_kb hon, duration

  note = $harp[hon]&.dig(:note) || hon
  wfile = this_or_equiv("#{$sample_dir}/%s", note, %w(.wav .mp3))
  wait_thr = Thread.new do
    if $testing
      sys "sleep #{duration}"
    else
      if wfile
        sys "play -q --norm=#{$vol.to_i} #{wfile} trim 0 #{duration}", $sox_fail_however
      else
        sys "play -q -n --norm=#{$vol.to_i} synth #{duration} sawtooth %#{note2semi(note)}", $sox_fail_however
      end
    end
  end  
  begin
    sleep 0.1
    # this sets $ctl_hole, which will be used by caller one level up
    handle_kb_play_holes_or_notes
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def synth_for_inter_or_chord semis, files, gap, len, wave = 'pluck'
  fail 'Internal error: unequal param len' unless semis.length == files.length
  im_files = [1, 2].map {|i| "#{$dirs[:tmp]}/intermediate_#{i}.wav"}
  times = (0 ... semis.length).map {|i| 0.3 + i*gap}
  files.zip(semis, times).each do |f, s, t|
    # create file with silence of given length
    sys("sox -q -n #{im_files[0]} trim 0.0 #{t}")
    # create actual file with requested frequency
    sys("sox -q -n #{im_files[1]} synth #{len} #{wave} %#{s}")
    # append those two
    sys("sox -q #{im_files[0]} #{im_files[1]} #{f}") 
  end
end


def print_pitch_information semi, name = nil
  puts "\e[0m\e[2m#{name}\e[0m" if name
  puts "\e[0m\e[2mSemi = #{semi}, Note = #{semi2note(semi+7)}, Freq = #{'%.2f' % semi2freq_et(semi)}\e[0m"
  print "\e[0mkey of song: \e[0m\e[32m%-3s,  " % semi2note(semi+7)[0..-2]
  print "\e[0m\e[2mmatches \e[0mkey of harp: \e[0m\e[32m%-3s\e[0m" % semi2note(semi)[0..-2]
  puts
end


class UserLickRecording

  attr_accessor :first_hole_good_at, :duration
  
  def initialize
    @active = false
    @file_raw1 = "#{$dirs[:tmp]}/usr_lick_rec_raw1.wav"
    @file_raw2 = "#{$dirs[:tmp]}/usr_lick_rec_raw2.wav"
    @file_trimmed = "#{$dirs[:data]}/usr_lick_rec.wav"
    @file_prev = "#{$dirs[:data]}/usr_lick_rec_prev.wav"
    @sign_text = '-REC-'

    # see reset_rec, which does the same and a bit more
    @first_hole_good_at = nil
    @rec_started_at = nil
    @has_rec = false
    @rec_pid = nil
  end

  def print_rec_sign_mb
    sign_column = $term_width - @sign_text.length
    print "\e[#{$lines[:key]};#{sign_column}H" +
          if active?
            "\e[0;101m" +
            if first_hole_good_at && @rec_pid
              @sign_text
            else
              @sign_text.downcase
            end + "\e[0m"
          else
            ' ' * @sign_text.length
          end
  end
  
  def active?
    @active
  end
  
  def has_rec?
    @has_rec
  end
  
  def toggle_active
    @active = !@active
    reset_rec
  end

  def ensure_end_rec
    if @rec_pid
      stop_rec
      process_rec if @first_hole_good_at
    end
  end
  
  def start_rec
    stop_rec if @rec_pid
    FileUtils.cp($test_wav, @file_raw1) if $testing
    @rec_pid = Process.spawn("rec -q -r #{$conf[:sample_rate]} %s" %
                             ($testing  ?  '/dev/null'  :  @file_raw1 ))
    @first_hole_good_at = nil
    @rec_started_at = Time.now.to_f
    @has_rec = false
    $perfctr[:start_rec] += 1
  end

  def stop_rec
    return unless @rec_pid
    Process.kill('HUP', @rec_pid)
    Process.wait(@rec_pid)
    @rec_pid = nil
    $perfctr[:stop_rec] += 1
  end

  def recording?
    @rec_pid
  end
  
  def process_rec
    trim_secs = @first_hole_good_at - @rec_started_at - 2
    if trim_secs > 0
      sys "sox -q #{@file_raw1} #{@file_raw2} trim #{'%.1f' % trim_secs}"
    else
      FileUtils.mv @file_raw1, @file_raw2
    end
    FileUtils.mv @file_trimmed, @file_prev if File.exist?(@file_trimmed)
    sys "sox -q #{@file_raw2} #{@file_trimmed} silence 1 0.1 2%"
    @first_hole_good_at = nil
    @has_rec = true
    @duration = sox_query(@file_trimmed, 'Length')
  end

  def reset_rec
    stop_rec
    @first_hole_good_at = nil
    @rec_started_at = nil
    @has_rec = false
    @rec_pid = nil
  end
  
  def play_rec
    fail 'Internal error: no rec' unless @has_rec
    play_recording_and_handle_kb @file_trimmed
  end

  def rec_file
    @file_trimmed
  end
  
end
