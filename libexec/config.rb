#
# Set some global vars directly and read configuration for others
#

def set_global_vars_early

  $move_down_on_exit = false
  $err_binding = nil
  $word_re ='[[:alnum:]][-_:/\.[:alnum:]]*'
  $lagging_freqs_message_ts = 0
  $lagging_freqs_lost = 0
  $freq_pipeline_cmd = ''
  $max_jitter = -1.0
  $max_jitter_at = 0
  $total_freq_ticks = 0

  # two more entries will be set in find_and_check_dirs
  $early_conf = Hash.new
  $early_conf[:figlet_fonts] = %w(smblock mono12 mono9)
  $early_conf[:modes] = %w(listen quiz licks play print calibrate tools develop)

  # expectations for config-file
  $conf_meta = Hash.new
  $conf_meta[:sections] = [:any_mode, :listen, :quiz, :licks, :print, :calibrate, :general]
  # update config ini if the below is extended
  $conf_meta[:sections_keys] = {
    :any_mode => [:add_scales, :comment, :display, :immediate, :loop, :type, :key, :scale, :fast, :viewer, :viewer_scale_to],
    :licks => [:tags_any, :tags_all, :no_tags_any, :no_tags_all],
    :calibrate => [:auto_synth_db],
    :general => [:time_slice, :pref_sig_def, :pitch_detection, :sample_rate]
  }
  $conf_meta[:deprecated_keys] = [:alsa_aplay_extra, :alsa_arecord_extra, :sox_rec_extra, :sox_play_extra]
  $conf_meta[:keys_for_modes] = Set.new($conf_meta[:sections_keys].values.flatten - $conf_meta[:sections_keys][:general])
  $conf_meta[:conversions] = {:display => :o2sym, :comment => :o2sym, :sharp_or_flat => :to_sym,
                              :pref_sig_def => :to_sym,
                              :immediate => :to_b, :loop => :to_b, :fast => :to_b,
                              :tags_any => :to_str,
                              :add_scales => :empty2nil}
  $conf_meta[:ctrls_play_pitch] = [:semi_up, :semi_down, :octave_up, :octave_down, :fifth_up, :fifth_down, :wave_up, :wave_down, :vol_up, :vol_down, :show_help, :pause_continue, :quit, :accept_or_repeat, :any]
  $conf_meta[:ctrls_play_chord] = [:wave_up, :wave_down, :vol_up, :vol_down, :show_help, :pause_continue, :gap_inc, :gap_dec, :len_inc, :len_dec, :replay, :quit, :any]
  $conf_meta[:ctrls_play_inter] = [:widen, :narrow, :up, :down, :show_help, :pause_continue, :quit, :any, :gap_inc, :gap_dec, :len_inc, :len_dec, :replay, :swap, :vol_up, :vol_down]
  $conf_meta[:ctrls_play_prog] = [:toggle_loop, :show_help, :pause_continue, :prefix, :semi_up, :semi_down, :vol_up, :vol_down, :repeat, :quit]
  
  #
  # These $ctl-Vars transport requests and events initiated by the
  # user; mostly keys pressed but also window changed.
  # But not input from the microphone.
  #
  # Choose Struct instead of Hash to be more typesafe
  #

  # Collect any key pressed and keep it until processed
  $ctl_kb_queue = Queue.new
  $ctl_sig_winch = false
  
  # Variables that may be set by pressing keys when listening to microphone
  ks = [:skip, :redraw, :done, :next, :back, :forget, :quit, :replay, :octave,
        :loop, :start_loop,
        :change_lick, :change_key, :pitch, :debug, :change_scale, :rotate_scale, :change_tags, :show_help, :change_partial,
        :ignore_partial, :ignore_holes, :ignore_recording, :star_lick, :edit_lick_file, :reverse_holes,
        :switch_modes, :toggle_record_user,
        :journal_menu, :journal_current, :journal_play, :journal_delete, :journal_clear, :journal_write, :journal_edit, :journal_recall, :journal_all_toggle, :journal_with_timing, :change_display, :change_comment, :update_comment, :toggle_progress, :warbles_prepare, :warbles_clear,
        :set_ref, :auto_replay, :player_details]
  $ctl_mic = Struct.new(*ks).new
  ks.each {|k| $ctl_mic[k] = false}

  # result of processing keys, while a recording is played
  # this is partially mirrored in sound_driver.rb
  ks = [:skip, :replay, :slower, :faster, :vol_up, :vol_down,
        :loop, :loop_loop, :lick_lick,
        :show_help, :pause_continue]
  $ctl_rec = Struct.new(*ks).new
  ks.each {|k| $ctl_rec[k] = false}

  # result of processing keys, while playing a pitch
  $ctl_pitch = Struct.new(*$conf_meta[:ctrls_play_pitch]).new
  $conf_meta[:ctrls_play_pitch].each {|k| $ctl_pitch[k] = false}

  # result of processing keys, while playing an interval
  $ctl_inter = Struct.new(*$conf_meta[:ctrls_play_inter]).new
  $conf_meta[:ctrls_play_inter].each {|k| $ctl_inter[k] = false}

  # result of processing keys, while playing a chord
  $ctl_chord = Struct.new(*$conf_meta[:ctrls_play_chord]).new
  $conf_meta[:ctrls_play_chord].each {|k| $ctl_chord[k] = false}

  # result of processing keys, while playing a sequence of semitones
  $ctl_prog = Struct.new(*$conf_meta[:ctrls_play_prog]).new
  $conf_meta[:ctrls_play_prog].each {|k| $ctl_prog[k] = false}

  # result of processing keys, while a series of holes is played
  ks = [:skip, :show_help, :vol_up, :vol_down]
  $ctl_hole = Struct.new(*ks).new
  ks.each {|k| $ctl_hole[k] = false}

  # These are related to the ctl_response function, which allows
  # reactions on user actions immediately from within the keyboard handler
  $ctl_reponse_default = ''
  $ctl_response_width = 32
  $ctl_response_non_def_ts = nil

  $all_licks = $licks = nil

  find_and_check_dirs

  # vars for recording user in mode licks
  $ulrec = UserLickRecording.instance

  $version = File.read("#{$dirs[:install]}/resources/version.txt").lines[0].chomp
  fail "Version read from #{$dirs[:install]}/resources/version.txt does not start with a number" unless $version.to_i > 0

  # will be created by test-driver
  $test_wav = "/tmp/#{File.basename($0)}_testing.wav"
  
  # for messages in hande_holes
  $msgbuf = MsgBuf.new

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
  $scale_files_template = "#{$dirs[:install]}/config/%s/scale_%s_with_%s.yaml"
  
  $freqs_queue = Queue.new

  $first_round_ever_get_hole = true

  $display_choices = [:hole, :chart_notes, :chart_scales, :chart_intervals, :chart_inter_semis]
  $display_choices_desc = {hole: 'Hole currently played',
                           chart_notes: 'Chart with notes',
                           chart_scales: 'Chart with abbreviated scales',
                           chart_intervals: 'Chart with intervals to ref as names',
                           chart_inter_semis: 'Chart with intervals to ref as semitones'}
  $comment_choices = Hash.new([:holes_some, :holes_all, :holes_scales, :holes_intervals, :holes_inter_semis, :holes_notes])
  $comment_choices[:listen] = [:hole, :note, :interval, :cents_to_ref, :gauge_to_ref, :warbles, :journal]
  $comment_choices_desc = {holes_some: 'Some of the holes to play; largest letters',
                           holes_all: 'All holes to play; large letters',
                           holes_scales: 'Holes to play with abbreviated scales',
                           holes_intervals: 'Holes to play with named intervals between',
                           holes_inter_semis: 'Holes to play with semitone intervals between',
                           holes_notes: 'Holes to play with notes',
                           hole: 'Hole currently played',
                           note: 'Note currently played',
                           interval: 'Named interval to previous hole',
                           cents_to_ref: 'Cents to ref',
                           gauge_to_ref: 'Instrument for freq diff to ref',
                           warbles: 'Counting warble speed',
                           journal: 'Journal of selected notes you played'}

  # need to define this here, so we may mention it in usage info
  $star_file_template = "#{$dirs[:data]}/licks/%s/starred.yaml"
  
  # will be populated along with $scale and $used_scales
  $scale2short = Hash.new
  $short2scale = Hash.new
  $scale2desc = Hash.new
  $scale2short_count = 0
  $term_kb_handler = nil
  
  $editor = ENV['EDITOR'] || ['editor'].find {|e| system("which #{e} >/dev/null 2>&1")} || 'vi'
  $messages_seen = Hash.new

  $pers_file = "#{$dirs[:data]}/persistent_state.json"
  begin
    $pers_data = JSON.parse(File.read($pers_file))
  rescue Errno::ENOENT, JSON::ParserError
    $pers_data = Hash.new
  end
  $pers_fingerprint = $pers_data.hash

  $splashed = false
  $mode_switches = 0
  $ctl_response_default = 'SPACE to pause; h for help'
  # also sets $warbles and clears $warbles_other_hole
  clear_warbles
  
  # The same volume for recordings and pitch
  $vol = Volume.new(-6)

  # characterize the major scale by semitones
  $maj_sc_st_abs = [0, 2, 4, 5, 7, 9, 11, 12]
  $maj_sc_st_diff = [2, 2, 1, 2, 2, 2, 1]

end


def find_and_check_dirs
  $dirs = Hash.new
  $dirs_data_created = false
  $dirs[:install] = File.dirname(File.realpath(File.expand_path(__FILE__) + '/..'))
  $dirs[:install_devel] = if $testing || !File.directory?(File.expand_path('~') + '/harpwise')
                            '/TESTING_SO_DIR_HARPWISE_DEVEL_SHOULD_NOT_EXIST'
                          else
                            File.realpath(File.expand_path('~') + '/harpwise')
                          end
  $dirs[:tmp] = Dir.mktmpdir(File.basename($0) + '_tmp_')
  $dirs[:data] = if $testing
                   "#{Dir.home}/dot_#{File.basename($0)}"
                 else
                   "#{Dir.home}/.#{File.basename($0)}"
                 end
  $dirs[:players_pictures] = "#{$dirs[:data]}/players_pictures"

  [:data, :players_pictures].each do |dirsym|
    if File.exist?($dirs[dirsym])
      err "Directory #{$dirs[dirsym]} does not exist, but there is a file with the same name:\n\n  " + %x(ls -l #{$dirs[dirsym]} 2>/dev/null) + "\nplease check, correct and retry" unless File.directory?($dirs[dirsym])
    else
      FileUtils.mkdir_p($dirs[dirsym])
      $dirs_data_created = true if dirsym == :data
    end
  end
    
  $early_conf[:config_file] = "#{$dirs[:install]}/config/config.ini"
  $early_conf[:config_file_user] = "#{$dirs[:data]}/config.ini"
  $sox_fail_however = <<~end_of_however

  sox (or play or rec) did not start correctly; see above.
  --------------------------------------------------------

  However, you may try to make the command, that failed above, work on
  the commandline. How this can be done, depends on the exact type of
  error and cannot be described here. This applies to the commands
  'sox' as well as its aliases 'play' and 'rec'.

  To give a real-world example:

  sox-Errors which mention "no default audio device" can often be
  solved by setting (and exporting) the environment variable
  AUDIODRIVER to a suitable value. sox shows possible values for this
  when invoked without arguments; search for the line 'AUDIO DEVICE
  DRIVERS'. Possible values might be 'alsa oss ossdsp pulseaudio'
  (linux) or 'coreaudio' (macOS); so e.g. on linux setting and
  exporting AUDIODRIVER=alsa might help.

  If this is not enough to solve the (example) problem, you may also
  set AUDIODEV to a suitable value, which however must be understood
  by your audio driver (as specified by AUDIODRIVER); as a linux
  example and for AUDIODRIVER=alsa, the setting AUDIODEV=hw:0 might
  work. Note, that for macOS most surely different values will be
  needed.

  Other options necessary for sox might be passed through the
  environmant variable SOX_OPTS. See the man-page of sox for details;
  also see the documentation of your respective audio driver,
  e.g. alsa (for linux) or coreaudio (for macOS).

  end_of_however

  unless File.exist?($early_conf[:config_file_user])
    File.open($early_conf[:config_file_user], 'w') do |cfu|
      cfu.write(<<~end_of_content)
      #
      # Custom configuration
      #
      # This is a verbatim copy of the global config file
      #
      #   #{$early_conf[:config_file]}
      #
      # with every entry commented out (at least initially).
      #
      # The global config defines the defaults, which you may 
      # override here.
      #
      end_of_content
      past_head = false
      File.readlines($early_conf[:config_file]).each do |line|
        past_head = true if line[0] != '#'
        next unless past_head
        cfu.write(
          if line[0] == '#' || line.strip == '' 
            line
          else
            '#' + line
          end
        )
      end
    end
  end

  $dirs.each do |k,v|
    next if k == :install_devel
    err "Directory #{v} for #{k} does not exist; installation looks bogus" unless File.directory?(v)
  end
end


def calculate_screen_layout
  squeeze = stretch = 0
  stretch += 1 if $term_height > 30
  stretch += 1 if $term_height > 36
  squeeze = 1 if $term_height < 27
  lines_extra = $term_height - $conf[:term_min_height]
  need_message2 = ( $mode == :quiz || $mode == :licks )
  lines = Struct.new(:mission, :key, :display, :hole, :frequency, :interval, :comment, :hint_or_message, :help, :message2, :message_bottom, :comment_tall).new
  lines = Hash.new
  lines[:mission] = 1
  lines[:key] = 2
  lines[:display] = 4 + stretch - squeeze
  lines[:hole] = 15 + 2 * stretch - 2 * squeeze
  lines[:frequency] = lines[:hole] + 1
  lines[:interval] = lines[:hole] + 2
  lines[:comment] = 18 + 3 * stretch - 2 * squeeze
  lines[:hint_or_message] = [26 + 5 * stretch - ( need_message2 ? 3 : 2 ) * squeeze,
                             $term_height - ( need_message2 ? 1 : 0 )].min
  2.times do
    lines[:hint_or_message] += 1 if $term_height - lines[:hint_or_message] > ( need_message2 ? 1 : 0 )
  end
  lines[:comment_tall] = lines[:comment_low] = lines[:comment]
  if need_message2
    lines[:comment_low] += 1
    if lines_extra > 0
      # font for quiz is fairly small, so we may leave some space
      lines[:comment_low] += 1
      lines[:comment] += 1
    end
    # only needed for quiz and licks
    lines[:message2] = lines[:hint_or_message] + 1
  else
    # we do not need a second line for mode :listen
    lines[:message2] = -1
  end
  lines[:message_bottom] = [lines[:hint_or_message], lines[:message2]].max
  lines[:help] = lines[:comment_tall]

  lines
end


def set_global_vars_late
  $sample_dir = this_or_equiv("#{$dirs[:data]}/samples/#{$type}/key_of_%s", $key.to_s) ||
                "#{$dirs[:data]}/samples/#{$type}/key_of_#{$key}"
  $lick_dir = "#{$dirs[:data]}/licks/#{$type}"
  $derived_dir = "#{$dirs[:data]}/derived/#{$type}"
  FileUtils.mkdir_p($derived_dir) unless File.directory?($derived_dir)
  $lick_file_template = "#{$lick_dir}/licks_with_%s.txt"
  $freq_file = "#{$sample_dir}/frequencies.yaml"
  $helper_wave = "#{$dirs[:tmp]}/helper.wav"
  $recorded_data = "#{$dirs[:tmp]}/recorded.dat"
  $recorded_data_ts = nil
  $recorded_processed = Struct.new(:start, :end, :vals_norm, :term_width, :term_height, :plot_width, :plot_height).new
  # these need (?) to be global vars, as the should persist over invocations
  $hole_held_inter = $hole_held_inter_was = nil

  # Concepts: 'journaling' is writing holes, that are played by user,
  # 'tracing' (nothing to do with 'debugging') is writing holes, that
  # are played by program.
  
  $journal = Array.new
  # is journaling of all holes played ongoing ?
  $journal_all = false
  # filenames; $journal_file contains both 'all' and 'some'
  $journal_file, $trace_file, $players_file = get_files_journal_trace_players

  $testing_log = "/tmp/#{File.basename($0)}_testing.log"
  $debug_log = "/tmp/#{File.basename($0)}_debug.log"
  File.delete($debug_log) if $opts && $opts[:debug] && File.exist?($debug_log)

  $star_file = $star_file_template % $type

  # Remark: The bufsizes below are powers of 2; if not (e.g. bufsize = 5120),
  # this may lead to aubio aborting with this error-message:
  #
  #   AUBIO ERROR: fft: can only create with sizes power of two, requested 5120, try recompiling aubio with --enable-fftw3
  #
  # so having a bufsize as a power of two makes harpwise more robust.
  #
  
  # Format: [bufsize, hopsize]
  $aubiopitch_sizes = { short: [2048, 512],
                        medium: [4096, 1024],
                        long: [8192, 2048] }
  $time_slice_secs = $aubiopitch_sizes[$opts[:time_slice]][1] / $conf[:sample_rate].to_f

end


def check_installation verbose: false
  # check for some required programs
  needed_progs = %w( figlet toilet aubiopitch sox rec play stdbuf )
  not_found = needed_progs.reject {|x| system("which #{x} >/dev/null 2>&1")}
  err "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0
  puts "Found needed programs: #{needed_progs}" if verbose

  # check, that sox understands mp3
  %x(sox -h).match(/AUDIO FILE FORMATS: (.*)/)[1]['mp3'] ||
    err("Your installation of sox does not support mp3 (check with: sox -h); please install the appropriate package")
  puts "Sox is able to handle mp3." if verbose

  # Check some sample dirs and files
  some_needed_files = %w(resources/usage.txt config/intervals.yaml recordings/wade.mp3 recordings/st-louis.mp3)
  some_needed_files.each do |file|
    if !File.exist?($dirs[:install] + '/' + file)
      err "Installation is incomplete: The file #{file} does not exist in #{$dirs[:install]}"
    end
  end
  puts "Some needed files are verified to exist:\n#{some_needed_files}" if verbose

  # check fonts and map fonts to figlet/toilet directory
  $font2dir = Hash.new
  font_dirs = %w(figlet toilet).map {|prog| %x(#{prog} -I2).chomp}
  $early_conf[:figlet_fonts].each do |font|
    font_dirs.each do |fdir|
      %w(flf tlf).each do |ending|
        if File.exist?("#{fdir}/#{font}.#{ending}")
          $font2dir[font] = fdir
          break 2
        end
      end
    end
  end
  missing_fonts = $early_conf[:figlet_fonts] - $font2dir.keys
  err "Could not find this fonts (neither in installation of figlet nor toilet): #{missing_fonts}" if missing_fonts.length > 0
  puts "All needed figlet fonts are verified to exist: #{$early_conf[:figlet_fonts]}" if verbose
end


def read_technical_config
  # read and merge
  conf = read_config_ini($early_conf[:config_file], strict: true)
  $conf_system = conf.clone
  $conf_system.each {|k,v| $conf_system[k] = v.clone}

  if File.exist?($early_conf[:config_file_user])
    uconf = read_config_ini($early_conf[:config_file_user], strict: false)
    $conf_user = uconf.clone
    $conf_user.each {|k,v| $conf_user[k] = v.clone}
    # deep merge
    uconf.each do |k,v|
      if v.is_a?(Hash)
        conf[k] ||= Hash.new
        v.each do |kk,vv|
          conf[k][kk] = vv
        end
      else
        conf[k] = v
      end
    end
  end

  # carry over from early config
  $early_conf.each {|k,v| conf[k] = v}
  # Set some things we do not take from file
  conf[:all_keys] = Set.new($notes_with_sharps + $notes_with_flats).to_a
  conf[:all_types] = Dir["#{$dirs[:install]}/config/*"].
                       select {|f| File.directory?(f)}.
                       map {|f| File.basename(f)}.
                       reject {|f| f.start_with?('.')}
  conf[:term_min_width] = 75
  conf[:term_min_height] = 24

  conf
end


def read_config_ini file, strict: true

  lnum = 0
  section = nil
  conf = Hash.new
  $conf_meta[:sections].each {|s| conf[s] = Hash.new}

  File.readlines(file).each do |line|
    lnum += 1
    err_head = "Error in #{file}, line #{lnum}: "
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''

    if md = line.match(/^\[(#{$word_re})\]$/)
      # new section
      section = md[1].o2sym
      err err_head + "Section #{section.o2str} is none of allowed #{$conf_meta[:sections].map(&:o2str)}" unless $conf_meta[:sections].include?(section)
    elsif md = line.match(/^(#{$word_re})\s*=\s*(.*?)$/)
      key = md[1].to_sym
      value = md[2].send($conf_meta[:conversions][key] || :num_or_str)
      err err_head + "Key '#{key.to_sym}' is deprecated; please edit the file and remove the key" if $conf_meta[:deprecated_keys].include?(key)
      if section
        allowed = Set.new($conf_meta[:sections_keys][section])
        allowed += Set.new($conf_meta[:sections_keys][:any_mode]) if ! [:any_mode, :general].include?(section)
        err err_head + "Key '#{key.to_sym}' is not among allowed keys in section '#{section}'; none of '#{allowed}'" unless allowed.include?(key)
        conf[section][key] = value
      elsif section.nil?
        err err_head + "Not in a section, key '#{key}' can only be assigned to in a section" 
      end
    else
      err err_head + "Cannot understand this line:\n\n#{line}\n\n,should be either a [section] or 'key = value'"
    end
  end

  # overall checking of key-sets
  err_head = "Error in #{file}: "
  $conf_meta[:sections].each do |section|
    found = Set.new(conf[section].keys.sort)
    required = Set.new($conf_meta[:sections_keys][section])
    allowed = required.clone
    allowed += Set.new($conf_meta[:sections_keys][:any_mode]) unless [:any_mode, :general].include?(section)

    err err_head + "Section #{section.o2str} has these keys:\n\n#{found}\n\nwhich is not a subset of all keys allowed:\n\n#{allowed}" unless found.subset?(allowed)

    if strict && [:any_mode, :general].include?(section)
      err err_head + "Section #{section.o2str} has these keys:\n\n#{found}\n\nwhich is different from all keys required:\n\n#{required}" unless required == found
    end
  end

  # transfer keys from general
  conf[:general].each {|k,v| conf[k] = v}

  conf
end


def read_and_set_musical_bootstrap_config
  $holes_file = "#{$dirs[:install]}/config/#{$type}/holes.yaml"
  return [scales_for_type($type), yaml_parse($holes_file).keys]
end


def read_and_set_musical_config

  $hole2note_read = yaml_parse($holes_file)
  $dsemi_harp = diff_semitones($key, 'c')
  harp = Hash.new
  hole2rem = Hash.new
  hole2flags = Hash.new {|h,k| h[k] = Set.new}
  semi2holes = Hash.new {|h,k| h[k] = Array.new}
  hole_root = nil
  $hole2note_read.each do |hole, note|
    semi = note2semi(note) + $dsemi_harp
    harp[hole] = [[:note, semi2note(semi)],
                  [:semi, semi]].to_h
    semi2holes[semi] << hole
    hole_root ||= hole if semi % 12 == 0
  end
  $hole2note_read.each do |hole, _|
    all_holes = harp[hole][:equiv] = semi2holes[harp[hole][:semi]].reject {|h| h == hole}
  end
  semis = harp.map {|hole, hash| hash[:semi]}
  $min_semi = semis.min
  $max_semi = semis.max
  harp_holes = harp.keys

  # for convenience
  # 'reverse', because we want to get the first of two holes having the same freq
  $hole2note = harp.map {|hole, hash| [hole, hash[:note]]}.reverse.to_h
  $note2hole = $hole2note.invert
  harp_notes = harp.keys.map {|h| $hole2note[h]}

  # process scales
  if $scale
    
    # get all holes to remove
    holes_remove = []
    if $opts[:remove_scales]
      $opts[:remove_scales].split(',').each do |sn|
        sc_ho, _ = read_and_parse_scale(sn)
        holes_remove.concat(sc_ho)
      end
    end

    scale = []
    h2s_shorts = Hash.new('')
    $used_scales.each_with_index do |sname, idx|
      # read scale
      sc_ho, h2rem = read_and_parse_scale(sname, harp)
      holes_remove.each {|h| sc_ho.delete(h)}
      # build final scale as sum of multiple single scales
      scale.concat(sc_ho) unless idx > 0 && $opts[:add_no_holes]
      # construct remarks to be shown amd flags to be used while
      # handling holes
      h2rem.each_key do |h|
        next if holes_remove.include?(h)
        if idx == 0
          hole2flags[h] << :main
        else
          next if $opts[:add_no_holes] && !hole2flags[h]
          hole2flags[h] << :added
        end
        hole2flags[h] << :root if h2rem[h] && h2rem[h].match(/\broot\b/)
        h2s_shorts[h] += $scale2short[sname]
        harp[h][:equiv].each {|h| h2s_shorts[h] += $scale2short[sname]}
        hole2rem[h] ||= [[],[]]
        hole2rem[h][0] << ( $scale2short[sname] || sname ) if sname != 'all' && $used_scales.length > 1
        if h2rem[h]
          h2rem[h].split(/, /).each do |r|
            if %w( root rt ).include?(r) && $used_scales.length > 0
              hole2rem[h][1] << "rt(#{( $scale2short[sname] || sname )})"
            else
              hole2rem[h][1] << r
            end
          end
        end
      end
    end
    # omit equivalent holes
    scale_holes = scale.sort_by {|h| harp[h][:semi]}.uniq

    scale_notes = scale_holes.map {|h| $hole2note[h]}
    semi2hole = scale_holes.map {|hole| [harp[hole][:semi], hole]}.to_h
  else            
    semi2hole = scale_holes = scale_notes = nil
  end

  hole2rem.each_key do |h|
    hole2rem[h] = [hole2rem[h][0].uniq, hole2rem[h][1].uniq].flatten.select(&:itself).uniq.join(',')
  end
  # read from first available intervals file
  ifile = ["#{$dirs[:install]}/config/#{$type}/intervals.yaml", "#{$dirs[:install]}/config/intervals.yaml"].find {|f| File.exist?(f)}
  intervals = yaml_parse(ifile).transform_keys!(&:to_i)
  intervals.keys.to_a.each do |st|
    next if st == 0 || st - 12 < -12 || st - 12 >= 0
    intervals[st-12] = intervals[st].clone
    # dont use prepend here
    intervals[st - 12].map! {|inter| inter = inter + '-O'}
  end

  # inverted
  intervals_inv = Hash.new
  intervals.each do |k,vv|
    vv.each do |v|
      next if v[' ']
      intervals_inv[v.downcase] = k
    end
  end

  [ harp,
    harp_holes,
    harp_notes,
    scale_holes,
    scale_notes,
    hole2rem.values.all?(&:nil?)  ?  nil  :  hole2rem,
    hole2flags.values.all?(&:nil?)  ?  nil  :  hole2flags,
    h2s_shorts,
    semi2hole,
    intervals,
    intervals_inv,
    hole_root]

end


def read_and_parse_scale sname, harp = nil
  
  scale_holes, hole2rem, all_props, sfile = read_and_parse_scale_simple(sname, harp)

  # get properties of scale; currently only :short
  props = Hash.new
  all_props.inject(&:merge)&.map {|k,v| props[k.to_sym] = v}
  err "Partially unknown properties in #{sfile}: #{props.keys}, only 'short' and 'desc' are supported" unless Set.new(props.keys).subset?(Set[:short, :desc])
  props[:short] = props[:short].to_s if props[:short]
  $scale2desc[sname] = props[:desc].to_s if props[:desc]
  
  unless $scale2short[sname]
    # No short name given on commandline: use from scale properties or make one up
    if props[:short]
      short = props[:short]
    else
      short = ('Q'.ord + $scale2short_count).chr
      $scale2short_count += 1
    end
    warn_if_double_short(short, sname)
    $short2scale[short] = sname
    $scale2short[sname] = short
  end

  scale_holes_with_rem = scale_holes.map {|h| "#{h} #{hole2rem[h]}".strip}
  scale_notes_with_rem = scale_holes.map {|h| "#{$hole2note[h]} #{hole2rem[h]}".strip}
  
  # write derived scale file
  dfile = $derived_dir + '/derived_' + File.basename(sfile).sub(/holes|notes/, sfile['holes'] ? 'notes' : 'holes')
  comment = "#\n# derived scale file with %s before any transposing has been applied,\n# created from #{sfile}\n#\n" 
  File.write(dfile, (comment % [ dfile['holes'] ? 'holes' : 'notes' ]) + YAML.dump([{short: $scale2short[sname]}] + (dfile['holes'] ? scale_holes_with_rem : scale_notes_with_rem)))

  [scale_holes, hole2rem]
end


def read_and_parse_scale_simple sname, harp = nil

  hole2rem = Hash.new

  # shortcut for scale given on commandline
  if sname == 'adhoc'
    $adhoc_holes.map! {|h| $note2hole[harp[h][:note]]}
    $adhoc_holes.each {|h| hole2rem[h] = nil}
    return [$adhoc_holes, hole2rem, [{'short' => 'h'}], 'commandline']
  end
  
  err "Scale '#{sname}' should not contain chars '?' or '*'" if sname['?'] || sname['*']
  glob = $scale_files_template % [$type, sname, '{holes,notes}']
  sfiles = Dir[glob]
  if sfiles.length != 1
    snames = scales_for_type($type)
    err "Unknown scale '#{sname}' (none of #{snames.join(', ')}) as there is no file matching #{glob}" if sfiles.length == 0
    err "Invalid scale '#{sname}' (none of #{snames.join(', ')}) as there are multiple files matching #{glob}"
  end
  sfile = sfiles[0]

  # Actually read the file
  all_props, scale_read = yaml_parse(sfile).partition {|x| x.is_a?(Hash)}

  scale_holes = Array.new

  # For convenience we have both $hole2note and $hole2note_read; they only differ,
  # if key does not equal c; the following relation always holds true:
  # note2semi($hole2note[h]) - note2semi($hole2note_read[h]) == note2semi($key) - note2semi('c') =: $dsemi_harp
  # Note, that below we transpose the scale, regardless if it is written as notes or as holes.
  dsemi_scale = if $opts[:transpose_scale].is_a?(Integer)
                  $opts[:transpose_scale]
                else
                  note2semi(($opts[:transpose_scale] || 'c') + '0') - note2semi('c0')
                end
  scale_read.each do |fields|
    hon_read, rem = fields.split(nil,2)
    if sfile['holes']
      err "Internal error: hole or note #{hon_read}\nas read from #{sfile}\ndoes not appear in:\n#{$hole2note_read}\nas read from #{$holes_file}" unless $hole2note_read[hon_read]
    else
      err "Internal error: hole or note #{hon_read}\nas read from #{sfile}\ndoes not appear in:\n#{$hole2note_read}\nas read from #{$holes_file}" unless $hole2note_read.values.include?(hon_read)
    end
    semi_read = if sfile['holes']
                  note2semi($hole2note_read[hon_read])
                else
                  note2semi(hon_read)
                end
    note_read = semi2note(semi_read)
    semi = $dsemi_harp + dsemi_scale + semi_read
    if semi >= $min_semi && semi <= $max_semi
      note = semi2note(semi)
      hole = $note2hole[note]
      hole2rem[hole] = rem&.strip
      if !hole
        tr_desc = if $opts[:transpose_scale].is_a?(Integer)
                    "by #{$opts[:transpose_scale]}st"
                  else
                    "to #{$opts[:transpose_scale]}"
                  end
        hon_read_desc = if sfile['holes']
                          "hole #{hon_read} (note #{note_read}, semi #{semi_read})"
                        else
                          "note #{hon_read} (semi #{semi_read})"
                        end
        if $opts[:transpose_scale]
          err("Transposing scale #{sname} from key of c #{tr_desc} fails for #{hon_read_desc}: it results in #{note} (semi = #{semi}), which is not present in #{$holes_file} (but still in range of harp #{$min_semi} .. #{$max_semi}). Maybe choose another value for --transpose-scale")
        else
          err("#{sfile} has #{hon_read_desc}, which is not present in #{$holes_file} (but still in range of harp #{$min_semi} .. #{$max_semi}). Please correct these files")
        end
      end
      scale_holes << hole
    end
  end

  [scale_holes, hole2rem, all_props, sfile]
end


$chart_with_holes_raw = nil
$chart_cell_len = nil

def read_chart
  $chart_file = "#{$dirs[:install]}/config/#{$type}/chart.yaml"
  chart_with_holes_raw = yaml_parse($chart_file)
  len = chart_with_holes_raw.shift
  chart_with_holes_raw.map! {|r| r.split('|')}
  hole2chart = Hash.new {|h,k| h[k] = Array.new}
  # first two elements will be set when checking for terminal size
  $conf[:chart_offset_xyl] = [0, 0, len] unless $conf[:chart_offset_xyl]
  begin
    # check for completeness
    chart_holes = Set.new(chart_with_holes_raw.map {|r| r[0 .. -2]}.flatten.map(&:strip).reject {|x| comment_in_chart?(x)})
    # Beware of false friends: $harp.keys has nothing to do with the
    # musical key of the harp
    harp_holes = Set.new($harp.keys)
    raise ArgumentError.new("holes from chart is not the same set as holes from harp; missing in chart: #{harp_holes - chart_holes}, extra in chart: #{chart_holes - harp_holes}") if chart_holes != harp_holes
    
    chart_with_notes = []
    chart_with_scales = []
    # will be used in get chart with intervals
    $chart_with_holes_raw = chart_with_holes_raw
    $chart_cell_len = len
    # for given key: map from holes to notes or scales
    (0 ... chart_with_holes_raw.length).each do |row|
      chart_with_notes << []
      chart_with_scales << []
      (0 ... chart_with_holes_raw[row].length - 1).each do |col|
        hole_padded = chart_with_holes_raw[row][col]
        hole = hole_padded.strip
        chart_with_notes[row][col] =
          if comment_in_chart?(hole_padded)
            hole_padded[0,len]
          else
            note = $harp[hole][:note]
            raise ArgumentError.new("hole '#{hole}' maps to note '#{note}' which is longer than given length '#{len}'") if note.length > len
            hole2chart[hole] << [col, row]
            $harp[hole][:equiv].each {|h| hole2chart[h] << [col, row]}
            note.center(len)
          end
        chart_with_scales[row][col] =
          if comment_in_chart?(hole_padded)
            hole_padded[0,len]
          else
            shorts = $hole2scale_shorts[hole]
            shorts = '-' if shorts == ''
            raise ArgumentError.new("hole '#{hole}' maps to scale shorts '#{shorts}' which are longer than given length '#{len}'; maybe you need to provide some shorter srhornames for scales on the commandline like 'scale:x'") if shorts.length > len
            shorts.center(len)
          end
      end
      chart_with_notes[row] << chart_with_holes_raw[row][-1]
      chart_with_scales[row] << chart_with_holes_raw[row][-1]
    end

  rescue ArgumentError => e
    fail "Internal error with #{$chart_file}: #{e}"
  end

  [ {chart_notes: chart_with_notes,
     chart_scales: chart_with_scales,
     chart_intervals: nil,
     chart_inter_semis: nil},
    hole2chart ]

end


def get_chart_with_intervals prefer_names: true
  fail "Internal error: reference hole is not set" unless $hole_ref
  len = $chart_cell_len
  chart_with_holes_raw = $chart_with_holes_raw
  chart_with_intervals = []
  (0 ... chart_with_holes_raw.length).each do |row|
    chart_with_intervals << []
    (0 ... chart_with_holes_raw[row].length - 1).each do |col|
      hole_padded = chart_with_holes_raw[row][col]
      hole = hole_padded.strip
      chart_with_intervals[row][col] =
        if comment_in_chart?(hole_padded)
          hole_padded[0,len]
        else
          isemi ,_ ,itext, dsemi = describe_inter(hole, $hole_ref)
          idesc = if prefer_names
                    itext || isemi
                  else
                    isemi || itext
                  end
          idesc.gsub!(' ','')
          idesc = 'REF' if dsemi == 0
          raise ArgumentError.new("hole '#{hole}' maps to interval description '#{idesc}' which is longer than given length '#{len}'") if idesc.length > len
          idesc.center(len)
        end
    end
    chart_with_intervals[row] << chart_with_holes_raw[row][-1]
  end
  chart_with_intervals
end


def read_calibration
  unless File.exist?($freq_file)
    puts "\nFrequency file #{$freq_file}\ndoes not exist; you need to calibrate for key of #{$key} first !\n\n#{for_automatic_calibration}\n\n(this needs to be done only once for this key)\n\n"
    exit 1
  end
  hole2freq = yaml_parse($freq_file)
  unless Set.new($harp_holes).subset?(Set.new(hole2freq.keys))
    err "There are more holes in #{$holes_file} #{$harp_holes} than in #{$freq_file} #{hole2freq.keys}. Missing in #{$freq_file} are holes #{(Set.new($harp_holes) - Set.new(hole2freq.keys)).to_a}. Probably you need to redo the calibration and play the missing holes. Or you may redo the whole calibration !\n\n#{for_automatic_calibration}"
  end
  unless Set.new(hole2freq.keys).subset?(Set.new($harp_holes))
    err "There are more holes in #{$freq_file} #{hole2freq.keys} than in #{$holes_file} #{$harp_holes}. Extra in #{$freq_file} are holes #{(Set.new(hole2freq.keys) - Set.new($harp_holes)).to_a.join(' ')}. Probably you need to remove the frequency file #{$freq_file} and redo the calibration to rebuild the file properly !\n\n#{for_automatic_calibration}"
  end
  unless $harp_holes.each_cons(2).all? do |ha, hb|
      fa, fb = [ha,hb].map {|h| hole2freq[h]}
      fb_plus = semi2freq_et($harp[hb][:semi] + 0.25)
      fa < fb_plus
    end
    err "Frequencies in #{$freq_file} are not even in roughly ascending (by 0.25 semitones margin) order of #{$harp_holes.inspect}: #{hole2freq.pretty_inspect}"
  end

  hole2freq.map {|k,v| $harp[k][:freq] = v}

  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    err "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)
  end

  # 'reverse', because we want to get the first of two holes having the same freq
  freq2hole = $harp_holes.map {|h| [$harp[h][:freq], h]}.reverse.to_h

  freq2hole
end


def set_global_musical_vars
  $used_scales = get_used_scales($opts[:add_scales])
  $opts[:add_scales] = nil if $used_scales.length == 1
  $all_scales = scales_for_type($type)
  $scale_desc_maybe = describe_scales_maybe($all_scales, $type)
  $harp, $harp_holes, $harp_notes, $scale_holes, $scale_notes, $hole2rem, $hole2flags, $hole2scale_shorts, $semi2hole, $intervals, $intervals_inv, $hole_root = read_and_set_musical_config
  $charts, $hole2chart = read_chart
  if $hole_ref
    $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
    $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
  end
  $all_licks, $licks = read_licks if $mode == :play || $mode == :licks || $mode == :print
  $freq2hole = read_calibration unless [:calibrate, :print, :tools, :develop].include?($mode)
  if $opts[:ref] 
    err "Option '--ref' needs a valid hole as an argument, not '#{$opts[:ref]}'" unless $harp_holes.include?($opts[:ref])
    $hole_ref = $opts[:ref]
  end
end


def for_automatic_calibration
  "For automatic calibration use:\n\n  #{$0} calibrate #{$type} #{$key} --auto"
end


$warned_for_double_short = Hash.new
def warn_if_double_short short, long
  if $short2scale[short] && long != $short2scale[short] && !$warned_for_double_short[short]
    $warned_for_double_short[short] = true
    txt = ["Shortname '#{short}' is used for two scales '#{$short2scale[short]}' and '#{long}'",
           "consider explicit shortname with ':' (see usage)"]
    if [:listen, :quiz, :licks].include?($mode)
      $msgbuf.print "... #{txt[1]}", 5, 5, later: true
      $msgbuf.print "#{txt[0]} ...", 5, 5
    else
      return if $initialized
      print "\n\e[0mWARNING: #{txt[0]} #{txt[1]}\n\n"
    end
  end
end
