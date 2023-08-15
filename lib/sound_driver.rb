#
# Recording and manipulation of sound-files
#

def record_sound secs, file, **opts
  output_clause = ( opts[:silent] ? '>/dev/null 2>&1' : '' )
  if $testing
    FileUtils.cp $test_wav, file
    sleep secs
  else
    cmd = "rec -q -r #{$conf[:sample_rate]} #{file} trim 0 #{secs}"
    sys "#{cmd} #{output_clause}", $sox_fail_however
  end
end


def play_wave file, secs = ( $opts[:fast] ? 0.5 : 1 )
  cmd = if $testing
          "sleep #{secs}"
        else    
          "play --norm=#{$vol.to_i} #{file} trim 0 #{secs}"
        end
  sys(cmd, $sox_fail_however) unless $testing
end


def run_aubiopitch file, extra = nil
  sys "aubiopitch --pitch #{$conf[:pitch_detection]} #{file} 2>&1"
end


def trim_recorded hole, recorded
  wave2data(recorded)
  duration = sox_query(recorded, 'Length')
  duration_trimmed = 2.0
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
    puts "\e[93mTrimming\e[0m #{File.basename(recorded)} for hole   \e[33m#{hole}\e[0m   play from %.2f" % play_from
    puts 'Choices: <secs-start> | d:raw | p:play (SPC) | y:es (RET)'
    puts '                        f:req | r:ecord      | c:ancel'
    print "Your choice (h for help): "
    choice = one_char

    if ('0' .. '9').to_a.include?(choice) || choice == '.'
      choice = '0.' if choice == '.'
      print "Finish with RETURN: #{choice}"
      choice += STDIN.gets.chomp.downcase.strip
      number = true
    else
      puts choice
      number = false
    end
    if choice == '?' || choice == 'h'
      puts <<EOHELP

Full Help:

   <secs-start>: set position to start from (marked by vertical bar
                 line in plot); just start to type, e.g.:  0.4
              d: draw current wave form
       p, SPACE: play from current position
      y, RETURN: accept current play position, trim file
                 and skip to next hole
              f: play a sample frequency for comparison 
            q,c: cancel and go to main menu, where you may generate
              r: record and trim again
EOHELP
      
    elsif ['', ' ', 'p'].include?(choice)
      puts "\e[33mPlay\e[0m from %.2f ..." % play_from
      play_wave trimmed_wave, 5
    elsif choice == 'd'
      do_draw = true
    elsif choice == 'y' || choice == "\n"
      FileUtils.cp trimmed_wave, recorded
      wave2data(recorded)
      puts "\nEdit\e[0m accepted, trimmed #{File.basename(recorded)}, starting with next hole.\n\n"
      return :next
    elsif choice == 'c' || choice == 'q'
      wave2data(recorded)
      puts "\nEdit\e[0m canceled, continue with current hole.\n\n"
      return :cancel
    elsif choice == 'f'
      print "\e[33mSample\e[0m sound ..."
      synth_sound hole, $helper_wave
      play_wave $helper_wave
    elsif choice == 'r'
      puts "Redo recording and trim ..."
      return :redo
    elsif number
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
  puts "Taking #{duration} seconds of original sound plus 0.2 fade out, starting at %.2f" % play_from
  cmd = "sox #{file} #{trimmed} trim #{play_from.round(2)} #{play_from.round(2) + duration + 0.2} gain -n -3 fade 0 -0 0.2"
  sys cmd
end


def sox_query file, property
  sys("sox #{file} -n stat 2>&1").lines.select {|line| line[property]}[0].split.last.to_f
end


def synth_sound hole, file, extra = ''
  puts "Hole \e[32m#{hole}\e[0m#{extra},   note \e[32m#{$harp[hole][:note]}\e[0m,   semi \e[32m#{$harp[hole][:semi]}\e[0m"
  cmd = "sox -n #{file} synth 4 sawtooth %#{$harp[hole][:semi]} vol #{$conf[:auto_synth_db] || 0}db"
  sys cmd
end


def wave2data file
  sys "sox #{file} #{$recorded_data}"
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


def this_or_equiv template, note
  notes_equiv(note).each do |eq|
    name = template % eq
    return name if File.exist?(name)
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
  if !IO.select([ppl_out], nil, nil, 4) || !wait_thr.alive?
    err(
      if IO.select([ppl_err], nil, nil, 2)
        # we use sysread, because read block (?)
        "Command terminated unexpectedly: #{cmd}\n" +
          ppl_err.sysread(65536).lines.map {|l| " >> #{l}"}.join
      else
        "Command produced no output and no error message: #{cmd}"
      end
    ) 
  end
  line = nil
  no_gets = 0
  iters = 0
  last_delta_time_at = last_delta_time = nil
  next_check_after_iters = 100
  #
  # Remark: The code below checks for several conditions, we have
  # encountered when porting to homebrew / macos; or when switching to
  # the one-piece pipeline. Read the comments twice, before
  # streamlining.
  #
  # loop forever one frequency after the other
  loop do
    # gets (below) might block, so guard it by timeout
    Timeout.timeout(10) do
      # loop to reduce (suspected) overhead of setting up timeout
      20.times do
        line = nil
        # gets might return nil for unknown reasons (e.g. in an
        # unpatched homebrew-setup)
        while !(line = ppl_out.gets)
          sleep 0.5
          no_gets += 1
          err "No output (10 times within more than 5 secs) from: #{cmd}" if no_gets > 10
        end
        $freqs_queue.enq Float(line.split(' ',2)[1])

        # Check for jitter now and then. This will not find every case
        # of jitter, but if jitter repeats, it will be found
        # eventually.
        #
        # At the same time (now and then), we check more throughly for
        # output of pipeline.
        iters += 1
        if iters == next_check_after_iters
          begin
            iters = 0
            # next check at random interval
            next_check_after_iters = 20 + rand(20)
            delta_time = Float(line.split(' ',2)[0])
            now = Time.now.to_f
            if last_delta_time
              jitter = (delta_time - last_delta_time) - (now - last_delta_time_at)
              $max_jitter = [jitter.abs, $max_jitter].max
            end
            last_delta_time = delta_time
            last_delta_time_at = now
            last_delta_time_at -= 2 if $testing_what == :jitter
          rescue ArgumentError
            err "Cannot understand below output of this command: #{ppl_cmd}\n" +
                line.lines.map {|l| " >> #{l}"}.join
          end  # check for invalid output
        end  # check for jitter (now and then)
      end
    rescue Timeout::Error
      err "No output from: #{cmd}"
    end  # check for timeout in gets    
    
  end  # one frequency after the other
end


def get_pipeline_cmd(what, wav_from)

  err "Internal error: #{what}" unless [:pv, :sox].include?(what)
  #
  # Regarding "pv" below: 19200 = 48000 * 4 (sample rate, 32 Bit, 1
  # Chanel) is the rate of our sox-generated testing-files
  #
  # Regarding "sox" below: We tried "rec" instead of "sox -d" but this
  # did not work within a pipeline for unknown reasons
  #
  templates = [{pv: "pv -qL 192000 %s",
                sox: "stdbuf -o0 sox %s -q -r #{$conf[:sample_rate]} -t wav -"},
               "stdbuf -i0 -o0 aubiopitch --bufsize %s --hopsize %s --pitch %s -i -"]

  # The values below (first two pairs only) are dictated by a restriction
  # of aubiopitch on macos for fft
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


def play_hole_and_handle_kb hole, duration
  wait_thr = Thread.new do
    play_wave(this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]),
              duration)
  end  
  begin
    sleep 0.1
    # this sets $ctl_hole, which will be used by caller one level up
    handle_kb_play_holes
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_hole_or_note_simple_and_handle_kb note, duration
  
  wfile = this_or_equiv("#{$sample_dir}/%s.wav", note)
  wait_thr = Thread.new do
    if $testing
      sys "sleep #{duration}"
    else
      if wfile
        sys "play --norm=#{$vol.to_i} #{wfile} trim 0 #{duration}", $sox_fail_however
      else
        sys "play -n --norm=#{$vol.to_i} synth #{duration} sawtooth %#{note2semi(note)}", $sox_fail_however
      end
    end
  end  
  begin
    sleep 0.1
    # this sets $ctl_hole, which will be used by caller one level up
    handle_kb_play_holes_or_notes_simple
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def play_semi_and_handle_kb semi
  cmd = if $testing
          "sleep 1"
        else
          "play --norm=#{$vol.to_i} -q -n synth #{( $opts[:fast] ? 1 : 0.5 )} sawtooth %#{semi}"
        end
  
  _, stdout_err, wait_thr  = Open3.popen2e(cmd)

  # loop to check repeatedly while the semitone is beeing played
  begin
    sleep 0.1
    # this sets $ctl_semi, which will be used by caller one level up
    handle_kb_play_semis
  end while wait_thr.alive?
  wait_thr.join   # raises any errors from thread
end


def synth_for_inter semis, files, wfiles, gap, len
  times = [0.3, 0.3 + gap]
  files.zip(semis, times).each do |f, s, t|
    sys("sox -q -n #{wfiles[0]} trim 0.0 #{t}")
    sys("sox -q -n #{wfiles[1]} synth #{len} pluck %#{s}") 
    sys("sox -q #{wfiles[0]} #{wfiles[1]} #{f}") 
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

  include Singleton

  attr_accessor :first_hole_good_at, :duration
  
  def initialize
    @active = false
    @file_raw1 = "#{$dirs[:tmp]}/usr_lick_rec_raw1.wav"
    @file_raw2 = "#{$dirs[:tmp]}/usr_lick_rec_raw2.wav"
    @file_trimmed = "#{$dirs[:data]}/usr_lick_rec.wav"
    @file_prev = "#{$dirs[:data]}/usr_lick_rec_prev.wav"
    @sign_text = '-REC-'

    @first_hole_good_at = nil
    @rec_started_at = nil
    @rec_pid = nil
    @has_rec = false
  end

  def sign_column
    ( $term_width - @sign_text.length ) / 2
  end
  
  def print_rec_sign_mb
    print "\e[#{$lines[:mission]};#{sign_column}H" +
          if active?
            "\e[0;101m" + @sign_text + "\e[0m"
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
    reset_rec if !@active
  end

  def ensure_end_rec
    if @rec_pid
      stop_rec
      process_rec if @first_hole_good_at
    end
  end
  
  def start_rec
    stop_rec if @rec_pid
    cmd = "sox %s -q -r #{$conf[:sample_rate]} #{@file_raw1}" %
          ( $testing  ?  $test_wav  :  '-d' )
    @rec_pid = Process.spawn "rec -q -r #{$conf[:sample_rate]} #{@file_raw1}"
    @first_hole_good_at = nil
    @rec_started_at = Time.now.to_f
    @has_rec = false
  end

  def stop_rec
    return unless @rec_pid
    Process.kill('HUP', @rec_pid)
    Process.wait(@rec_pid)
    @rec_pid = nil
  end
  
  def process_rec
    trim_secs = @first_hole_good_at - @rec_started_at - 2
    if trim_secs > 0
      sys "sox #{@file_raw1} #{@file_raw2} trim #{'%.1f' % trim_secs}"
    else
      FileUtils.mv @file_raw1, @file_raw2
    end
    FileUtils.mv @file_trimmed, @file_prev if File.exist?(@file_trimmed)
    sys "sox #{@file_raw2} #{@file_trimmed} silence 1 0.1 2%"
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
    play_recording_and_handle_kb_simple @file_trimmed, false
  end

  def rec_file
    @file_trimmed
  end
  
end
