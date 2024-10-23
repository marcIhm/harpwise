# -*- fill-column: 74 -*-

#
# Record or generate needed samples
#

def do_samples to_handle

  print "\e[?25l"  ## hide cursor
  
  case $extra
  when 'record'
    samples_record to_handle
  when 'generate'
    samples_generate to_handle
  when 'check'
    samples_check to_handle
  when 'delete'
    samples_delete to_handle
  else
    fail "Internal error: unknown extra '#{$extra}'"
  end
end


def samples_generate to_handle

  do_all_keys, these_keys = sample_args_helper(to_handle)
  
  your_own = <<EOYOUROWN
Letting harpwise generate your samples is the preferred way to get
started.  The frequencies will be in "equal temperament" tuning.

But please note, that the generated samples and their frequencies
cannot match those of your own harp or style very well. So, later,
you may want to redo the samples by playing yourself
EOYOUROWN
  
  if do_all_keys
    puts <<EOINTRO

\e[2m(type #{$type})\e[0m


This will \e[32mautomatically\e[0m generate all needed samples
for \e[32mall holes\e[0m of \e[32mall keys\e[0m:

  \e[32m#{these_keys.each_slice(12).to_a.map{|s| s.join('  ')}.join("\n  ")}\e[0m

harmonica type is #{$type}. Other types still require their
own samples beeing created.

Any samples that you have recorded before will be kept; use extra-command
'delete' to delete them.

#{your_own.chomp}
e.g. for a specific key via 'harpwise record c'
EOINTRO

    puts "\nNow, type   'y'   to let harpwise generate all samples for all keys."
    char = one_char
    puts
    
    if char != 'y'
      puts "Generation of samples aborted on user request ('#{char}')."
      puts
      exit 0
    end

  end
  
  these_keys.each_with_index do |key, idx|

    $key = key
    
    if do_all_keys
      puts "Generating for key of   \e[92m#{$key}\e[0m   [#{idx+1}/#{these_keys.length}]\n"
    else
      puts <<EOINTRO

\e[2m(type #{$type}, key of #{$key})\e[0m


This will generate all needed samples for holes:

  \e[32m#{$harp_holes.each_slice(12).to_a.map{|s| s.join('  ')}.join("\n  ")}\e[0m

Harmonica type   #{$type},   key of   #{$key};   other keys or types will require
their own samples beeing created, but only once.

#{your_own.chomp}
e.g. 'harpwise record #{$key}'
EOINTRO

      puts "\nNow, type   'y'   to let harpwise generate all samples for the \e[32mkey of #{$key}\e[0m."
      unless $opts[:terse]
        puts
        puts "\e[2mThese samples will also be played in the process.\e[0m"
      end
      char = one_char
      puts
      
      if char != 'y'
        puts "Generation of samples aborted on user request ('#{char}')."
        puts
        exit 0
      end
    end

    set_global_vars_late
    set_global_musical_vars
    FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)    
    
    hole2freq = Hash.new
    num_wavs_uniq = $harp_holes.map {|h| $harp[h][:semi]}.uniq.length
    terse = do_all_keys || $opts[:terse]
    $harp_holes.each_with_index do |hole, idx|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.mp3"
      synth_sound hole, file, " (%2d of #{$harp_holes.length})" % (idx + 1), silent: terse
      print "\e[2m#{hole}\e[0m  " if terse
      play_wave file, 0.5 unless terse
      hole2freq[hole] = analyze_with_aubio(file)
    end
    write_freq_file hole2freq
    puts unless do_all_keys
    puts "\nFrequencies in: #{$freq_file}"
    if terse
      puts 
    else
      print_summary hole2freq, 'generated'
    end
  end
  puts
  puts "Sample generation \e[32mdone.\e[0m\n\n\n"    
end


def samples_record to_handle

  err "Can only handle zero or one argument, but not #{to_handle.length}:  #{to_handle.join(' ')}" if to_handle.length > 1
  hole = to_handle[0]
  err "Argument '#{hole}' is none of  #{$harp_holes.join(' ')}" if hole && !$harp_holes.include?(hole)

  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)

  holes = if hole
            $harp_holes[$harp_holes.find_index(hole) .. -1]
          else
            $harp_holes
          end

  ERB.new(IO.read("#{$dirs[:install]}/resources/samples_intro.txt")).result(binding).lines.each do |line|
    print line
    sleep 0.01
  end
  puts
  puts "Press:   \e[32many key\e[0m   to start with the first hole (#{holes[0]}), key of #{$key}"
  puts "or       \e[32ms\e[0m         and skip to summary for existing samples."
  puts
  char = one_char

  if File.exist?($freq_file)
    hole2freq = yaml_parse($freq_file)
  else
    hole2freq = Hash.new
  end

  do_animation 'first hole', 5
  unless char == 's'
    i = 0
    # loop over all holes
    begin
      hole = holes[i]
      what, freq = record_and_review_hole(hole)
      if freq
        hole2freq[hole] = freq
        write_freq_file hole2freq
      end
      
      if what == :back
        if i == 0
          puts "\nCannot go back, already at first hole."
          sleep 0.5
          do_animation 'first hole', 5
        else
          i -= 1
          do_animation 'previous hole', 5
        end
      elsif what == :cancel
        # keep current value of i
      else
        i += 1
        do_animation 'next hole', 5
      end
      break if what == :quit
    end while what != :quit && i < holes.length
  end
  print_summary hole2freq, 'recorded'
  puts "\n\nAll recordings \e[32mdone.\e[0m\n\n\n"
end


def record_and_review_hole hole

  sample_file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
  backup = "#{$dirs[:tmp]}/backup.wav"
  if File.exist?(sample_file)
    puts "There is already a generated or recorded sound present for hole  \e[32m#{hole}\e[0m"
    puts "\e[2m#{sample_file}\e[0m"
    wave2data(sample_file)
    FileUtils.cp(sample_file, backup)
  else
    puts "\nFile  #{sample_file}  for hole  \e[32m#{hole}\e[0m\nis not present so it needs to be recorded or generated."
  end
  issue_before_trim = false

  # This loop contains all the operations record, trim and draw as well as some checks and user input
  # the sequence of these actions is fixed; if they are executed at all is determined by do_xxx
  # For the first loop iteration this is set below, for later iterations according to user input
  do_record, do_draw, do_trim = [false, true, false]
  freq = nil
  
  begin  ## while answer != :okay

    # false on first iteration
    if do_record 
      rec_dura = 2.4
      puts "\nRecording #{rec_dura} secs for hole  \e[32m#{hole}\e[0m  when '\e[0;101mRECORDING\e[0m' appears."
      [2, 1].each do |c|
        puts c
        sleep 1
      end

      # Discard stale samples (which we recognize, because they are delivered too fast)
      begin
        tstart_record = Time.now.to_f
        record_sound 0.2, $helper_wave, silent: true
      end while Time.now.to_f - tstart_record < 0.1

      puts "\e[0;101mRECORDING\e[0m to #{sample_file} ..."
      record_sound rec_dura, sample_file
      wave2data(sample_file)
      
      puts "\e[32mdone\e[0m"
    end

    # normally true, can only be false on first iteration
    if File.exist?(sample_file)  
   
      # true on first iteration
      wave2data(sample_file)
      draw_data(0, 0) if do_draw && !do_trim  

      # false on first iteration
      if do_trim  
        puts issue_before_trim if issue_before_trim
        issue_before_trim = false
        result = trim_recorded(hole, sample_file)
        if result == :redo
          do_record, do_draw, do_trim = [true, false, true]
          redo                         
        elsif result == :next || result == :cancel
          FileUtils.mv(backup, sample_file) if result == :cancel && File.exist?(backup)
          FileUtils.rm(backup) if File.exist?(backup)
          return result, analyze_with_aubio(sample_file)
        end
      end
      
      freq = inspect_recorded(hole, sample_file)
      
    end

    # get user input
    # ruler for 75 chars:
    #            ---------------------------------------------------------------------------
    puts "\e[34mReview and/or Record\e[0m hole  \e[32m-->   \e[92m#{hole}\e[32m   <--  \e[0m(key of #{$key})"

    sleep 0.1
    choices = {:play =>
               [['p', 'SPACE'],
                'play current recording',
                'play current recording'],
               :draw =>
               [['d'],
                'draw sound',
                'draw sound data (again)'],
               :frequency =>
               [['f'],
                'play frequency sample',
                'show and play the ET frequency of the hole by generating and',
                'analysing a sample sound; does not overwrite current recording'],
               :record =>
               [['r'],
                'record and trim',
                'record RIGHT AWAY (after countdown); then trim recording',
                'and remove initial silence and surplus length'],
               :generate =>
               [['g'],
                'generate sound',
                'generate a sound (instead of recording it) for the',
                'ET frequency of the hole'],
               :back =>
               [['b', 'BACKSPACE'],
                'back to prev hole',
                'jump back to previous hole and discard work on current']}
    choices[:okay] = [['y', 'RETURN'], 'accept and continue', 'continue to next hole'] if File.exist?(sample_file)
    choices[:quit] = [['q'],
                      'quit recording',
                      'exit from recording of samples, but keep all samples,',
                      'that have been recorded up to this point']
    
    answer = read_answer(choices)

    # operations will be in this sequence if set below according to user input
    do_record, do_draw, do_trim = [false, false, false]
    case answer
    when :play
      if File.exist?(sample_file)
        print "\e[34mPlay\e[0m ... "
        play_wave sample_file, 5
        puts 'done'
      else
        print "\e[91mFile #{sample_file} does not exist !\e[0m\n"
      end
    when :draw
      do_draw = true
    when :back
      return :back, freq
    when :quit
      return :quit, freq
    when :frequency
      print "\e[0m\e[34mGenerate\e[0m and analyse a sample sound:"
      synth_sound hole, $helper_wave
      play_wave $helper_wave, 0.25
      puts "Frequency: #{analyze_with_aubio($helper_wave)}"
    when :generate
      synth_sound hole, sample_file
      wave2data(sample_file)
      do_draw = true
    when :record
      do_record, do_draw, do_trim = [true, false, true]
      issue_before_trim = "\e[0m\e[34mTrimming\e[0m recorded sound right away ...\n"
    end
    
  end while answer != :okay

  return :next, freq
end


def write_freq_file hole2freq
  # Recreate the hash in order of $harp_holes
  hole2freq_sorted = Hash.new
  [$harp_holes + hole2freq.keys].flatten.each do |hole|
    hole2freq_sorted[hole] = hole2freq[hole]
  end
  File.write($freq_file, YAML.dump(hole2freq_sorted))
end


def print_summary hole2freq, rec_or_gen
  template = '    %8s | %8s | %8s | %6s | %6s | %s '
  puts "Recordings in #{$sample_dir}"
  puts "\nSummary of #{rec_or_gen} frequencies:\n\n"
  puts template % %w(Hole Freq ET Diff Cents Gauge)
  puts '  ------------' + '-' * (template % ['','','','','','']).length
  maxhl = $harp_holes.map(&:length).max
  $harp_holes.each do |hole|
    semi = note2semi($harp[hole][:note])
    freq = hole2freq[hole]
    unless freq
      puts template % [hole.ljust(maxhl), '', '', '', 'not yet #{rec_or_gen}']
      next
    end
    freq_et = semi2freq_et(semi)
    freq_et_p1 = semi2freq_et(semi + 1)
    freq_et_m1 = semi2freq_et(semi - 1)
    gauge = if (freq_et_m1 - freq).abs < (freq_et - freq).abs
              ' too low' 
            elsif (freq_et_p1 - freq).abs < (freq_et - freq).abs
              'too high' 
            else
              get_dots('........:........', 2, freq, freq_et_m1, freq_et, freq_et_p1) {|hit, idx| idx}[0]
            end
    puts template % [hole.ljust(maxhl), freq.round(0), freq_et.round(0), (freq - freq_et).round(0), cents_diff(freq, freq_et).round(0), gauge]
  end
  puts "\nYou may compare #{rec_or_gen} frequencies with those calculated from equal"
  puts "temperament tuning. The gauge shows the difference in frequency between"
  puts "#{rec_or_gen} and target frequency (:); left and right border are the"
  puts "neighbouring semitones."
end


def samples_check to_handle
  
  do_all_keys, these_keys = sample_args_helper(to_handle)

  if do_all_keys
    puts
    puts "Checking counts of recorded and generated sound-samples\nfor all #{these_keys.length} keys,\nin subdirectories of #{$dirs[:data]}/samples:"
    puts
    template = '| %-3s | %11s | %12s | %s    '
    ins = '  '
    head = template % ['key', '# recorded', '# generated', 'remark'] 
    puts ins + head
    hline = '-' * head.length
    (0 ... head.length).each {|i| hline[i] = '+' if head[i] == '|'}
    puts ins + hline

    prev_remark = nil
    these_keys.each do |key|
      sample_dir = get_sample_dir(key)
      counts = ['wav', 'mp3'].map do |suff|
        [suff,
         File.directory?(sample_dir)  ?  Dir["#{sample_dir}/*.#{suff}"].length  :  0]
      end.to_h
      nosa = false
      num_wavs_uniq = $harp_holes.map {|h| $harp[h][:semi]}.uniq.length
      remark = if counts.values.sum == 0
                 nosa = true
                 'no samples yet'
               elsif counts['wav'] == 0
                 'generated only'
               elsif counts['wav'] == num_wavs_uniq
                 'recorded for all holes'
               else
                 'recorded for some holes'
               end
      line = ( template % [ key,
                            nosa  ?  '-'  :  counts['wav'].to_s,
                            nosa  ?  '-'  :  counts['mp3'].to_s,
                            remark == prev_remark  ?  "\e[2m#{remark}\e[0m"  :  remark ] )
      prev_remark = remark
      puts ins + line.gsub(/^\s*\|(.*?)\|/, "|\e[32m\\1\e[0m|")
    end
    puts
  else
    # check single key only
    puts
    if File.directory?($sample_dir)
      puts "Checking for recorded and/or generated samples for each hole"
      puts "in  #{$sample_dir}:"
      puts
      maxlen = $harp_holes.map(&:length).max
      found_prev = nil
      counts = Hash.new {|h,k| h[k] = 0}
      $harp_holes.each do |hole|
        endings = %w(wav mp3).map do |ending|
          this_or_equiv("#{$sample_dir}/%s.#{ending}", $harp[hole][:note]) && ending
        end.compact

        print "  #{hole.ljust(maxlen)} : "
        found = case endings.length
                when 0
                  'no samples'
                when 1
                  {'wav' => 'recorded', 'mp3' => 'generated'}[endings[0]] + ' sample'
                when 2
                  'recorded + generated sample'
                else
                  fail "Internal error: #{endings}"
                end
        puts ( found == found_prev  ?  "\e[2m#{found}\e[0m"  :  found )
        counts[found] += 1
        found_prev = found
      end
      puts
      puts 'Summary:'
      maxlen = counts.keys.map(&:length).max
      counts.keys.sort.each {|w| puts "#{head}  #{w.rjust(maxlen)}:  #{counts[w]}"}
      puts
    else
      puts "No samples for key #{$key} yet; maybe record or create some ?\n\e[2m#{for_sample_generation}\e[0m"
    end
    puts
  end
end


def samples_delete to_handle

  do_all_keys, these_keys = sample_args_helper(to_handle)  

  mindful = "Please be mindful, because the recordings have probably\nbeen done by you with some effort ..."
  
  puts
  if do_all_keys
    puts "About to   \e[91mdelete\e[0m   recorded samples for   \e[91mall #{these_keys.length} keys !\e[0m"
    puts
    puts mindful
    puts
    puts "Press   'Y'   (uppercase) to \e[0;101m DELETE \e[0m them; anything else to cancel."
    char = one_char
    puts
    if char != 'Y'
      puts 'Operation canceled; no files deleted'
      puts
      exit
    end
  end

  these_keys.each do |key|
    sample_dir = get_sample_dir(key)
    to_delete = []
    $harp_holes.each do |hole|
      file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
      to_delete << File.basename(file) if file && File.exist?(file)
    end
    
    if to_delete.length == 0
      puts "No recorded sound samples for key   #{key}"
    else
      if do_all_keys
        print "\e[91mDeleting\e[0m "
      else
        print "About to   \e[91mdelete\e[0m  "
      end
      puts "these recorded sound samples for key of   \e[91m#{key}\e[0m   in\n#{$sample_dir}:"
      puts
      puts wrap_words('    ', to_delete, sep = '  ')
      puts
      if do_all_keys
        char = 'Y'
      else
        puts mindful
        puts
        puts
        puts
        print "\e[A"
        puts "Press   'Y'   (uppercase) to \e[0;101m DELETE \e[0m them; anything else to cancel."
        char = one_char
      end
      if char == 'Y'
        print 'deleting .'
        to_delete.each do |f|
          ff = "#{$sample_dir}/#{f}"
          FileUtils.rm(ff) if File.exist?(ff)
          print '.'
          sleep 0.2
        end
        puts '. done.'
        if do_all_keys
          sleep 0.5
          puts
        end
      else
        puts
        puts 'Operation canceled; no files deleted'
      end
    end
  end
  puts
end


def sample_args_helper to_handle
  
  err "Can only handle zero or one argument, but not #{to_handle.length}:  #{to_handle.join(' ')}" if to_handle.length > 1
  
  do_all_keys, these_keys = if to_handle.length == 1
                              err "Can only handle 'all' as an optional argument, not:  #{to_handle[0]}" if to_handle[0] != 'all'
                              [true, $all_harp_keys]
                            else
                              [false, [$key]]
                end
  return [do_all_keys, these_keys]
end


