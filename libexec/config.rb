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
  $max_jitter_info = []
  $jitter_check_after_iters = 40
  $jitter_checks_total = 0
  $jitter_checks_bad = 0
  $jitter_threshold = 0.2
  $total_freq_ticks = 0
  $name_collisions_mb = Hash.new {|h,k| h[k] = Set.new}

  # two more entries will be set in find_and_check_dirs_early
  $early_conf = Hash.new
  $early_conf[:figlet_fonts] = %w(smblock mono12 mono9)
  $early_conf[:modes] = %w(listen quiz licks play print samples tools develop jamming)

  # expectations for config-file
  $conf_meta = Hash.new
  # Read config.ini for the background  semantics of :any_mode and its relations
  # to others; basically the first defines defaults for the rest
  $conf_meta[:sections] = [:any_mode, :listen, :quiz, :licks, :play, :print, :samples, :general]
  # Below we only need to list those modes (e.g. :quiz) which allow
  # more keys, than :any_mode.  Remark: update config.ini if the below
  # is extended
  $conf_meta[:sections_keys] = {
    :any_mode => [:add_scales, :comment, :display, :immediate, :loop, :type, :key, :scale, :fast, :viewer, :tags_all, :tags_any, :drop_tags_all, :drop_tags_any],
    :samples => [:auto_synth_db],
    :quiz => [:difficulty],
    :listen => [:keyboard_translate, :keyboard_translate_slot1,  :keyboard_translate_slot2,  :keyboard_translate_slot3],
    :licks => [:keyboard_translate, :keyboard_translate_slot1,  :keyboard_translate_slot2,  :keyboard_translate_slot3],
    :general => [:time_slice, :sharps_or_flats, :pitch_detection, :sample_rate]
  }
  $conf_meta[:deprecated_keys] = [:alsa_aplay_extra, :alsa_arecord_extra, :sox_rec_extra, :sox_play_extra, :pref_sig_def]
  $conf_meta[:keys_for_modes] = Set.new($conf_meta[:sections_keys].values.flatten - $conf_meta[:sections_keys][:general])
  $conf_meta[:conversions] = Hash.new {|h,k| :to_str}
  $conf_meta[:conversions].merge!({:display => :o2sym, :comment => :o2sym,
                                   :sharps_or_flats => :to_sym,
                                   :immediate => :to_b, :loop => :to_b, :fast => :to_b,
                                   :add_scales => :empty2nil})
  $conf_meta[:ctrls_play_pitch] = [:semi_up, :semi_down, :octave_up, :octave_down, :fifth_up, :fifth_down, :wave_up, :wave_down, :vol_up, :vol_down, :show_help, :pause_continue, :quit, :accept_or_repeat, :any, :invalid]
  $conf_meta[:ctrls_play_chord] = [:wave_up, :wave_down, :vol_up, :vol_down, :show_help, :pause_continue, :gap_inc, :gap_dec, :len_inc, :len_dec, :replay, :quit, :any, :invalid]
  $conf_meta[:ctrls_play_inter] = [:widen, :narrow, :up, :down, :show_help, :pause_continue, :quit, :any, :gap_inc, :gap_dec, :len_inc, :len_dec, :replay, :swap, :vol_up, :vol_down, :invalid]
  $conf_meta[:ctrls_play_prog] = [:toggle_loop, :show_help, :pause_continue, :prefix, :semi_up, :semi_down, :vol_up, :vol_down, :prev_prog, :next_prog, :quit, :invalid]
  
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
  ks = [:skip, :redraw, :hole_given, :next, :back, :forget, :first_lick, :quit, :replay, :octave,
        :loop,
        :change_lick, :change_key, :pitch, :debug, :change_scale, :rotate_scale, :rotate_scale_reset, :change_tags, :show_help, :change_partial, :change_num_quiz_replay, :quiz_hint,
        :replay_menu, :replay_flags, :star_lick, :edit_lick_file, :reverse_holes, :shuffle_holes, :lick_info, :options_info, :shift_inter, :comment_lick_play, :comment_lick_next, :comment_lick_prev, :comment_lick_first,
        :switch_modes, :toggle_record_user, :remote_message,
        :journal_menu, :journal_current, :journal_play, :journal_delete, :journal_clear, :journal_write, :journal_edit, :journal_recall, :journal_short, :journal_all_toggle, :journal_with_timing, :change_display, :change_comment, :update_comment, :toggle_progress, :warbles_prepare, :warbles_clear,
        :set_ref, :auto_replay, :player_details]
  $ctl_mic = Struct.new(*ks).new
  ks.each {|k| $ctl_mic[k] = false}
  $ctl_mic[:replay_flags] = Set.new

  # result of processing keys, while a recording is played
  # this is partially mirrored in sound_driver.rb
  ks = [:skip, :replay, :slower, :faster, :vol_up, :vol_down,
        :loop, :loop_loop, :lick_lick, :num_loops, :num_loops_to_one,
        :show_help, :pause_continue, :star_lick, :can_star_unstar, :invalid]
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
  ks = [:skip, :show_help, :vol_up, :vol_down, :invalid]
  $ctl_hole = Struct.new(*ks).new
  ks.each {|k| $ctl_hole[k] = false}

  # These are related to the ctl_response function, which allows
  # reactions on user actions immediately from within the keyboard handler
  $ctl_reponse_default = ''
  $ctl_response_width = 32
  $ctl_response_non_def_ts = nil

  $all_licks = $licks = nil

  find_and_check_dirs_early

  # vars for recording user in mode licks
  $ulrec = UserLickRecording.new

  $version = File.read("#{$dirs[:install]}/resources/version.txt").lines[0].chomp
  fail "Version read from #{$dirs[:install]}/resources/version.txt does not start with a number" unless $version.to_i > 0

  # will be created by test-driver
  $test_wav = "/tmp/#{File.basename($0)}_testing.wav"
  # tool diag
  $diag_wav = "/tmp/#{File.basename($0)}_diag.wav"
  
  # for messages in hande_holes
  $msgbuf = MsgBuf.new

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
  $scale_files_templates = ["#{$dirs[:install]}/scales/%s/scale_%s_with_%s.yaml",
                            "#{$dirs[:user_scales]}/%s/scale_%s_with_%s.yaml"]
  # $type will be inserted later
  $scale_prog_file_templates = ["#{$dirs[:install]}/scales/%s/scale_progressions.yaml",
                                "#{$dirs[:user_scales]}/%s/scale_progressions.yaml"]

  
  $freqs_queue = Queue.new

  $first_round_ever_get_hole = true

  $display_choices = [:hole, :chart_notes, :chart_scales, :chart_intervals, :chart_inter_semis]
  $display_choices_desc = {hole: 'Hole currently played',
                           chart_notes: 'Chart with notes',
                           chart_scales: 'Chart with abbreviated scales',
                           chart_intervals: 'Chart with intervals to ref as names',
                           chart_inter_semis: 'Chart with intervals to ref as semitones'}
  $comment_choices = Hash.new([:holes_some, :holes_all, :holes_scales, :holes_intervals, :holes_inter_semis, :holes_notes])
  $comment_choices[:listen] = [:hole, :note, :interval, :cents_to_ref, :gauge_to_ref, :warbles, :journal, :lick_holes, :lick_holes_large]
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
                           journal: 'Journal of selected notes you played',
                           lick_holes: "Show holes of a lick given via '--lick-prog'",
                           lick_holes_large: "The same as lick_holes but with large letters"}

  $image_viewers = [{syn: %w(none), desc: 'Do not view images at all.'},
                    {syn: %w(pixel-in-terminal pixel), desc: 'View images as pixel-grafic inside your terminal, scrolling along with the text; this requires kitty or img2sixel to be installed.', choose_desc: 'With this option kitty will be tried, if TERM is some form of kitty. In any other case will img2sixel will betrd, which however requires your terminal to support sixel (your mileage may vary).'},
                    {syn: %w(new-window window), desc: 'Open a new grafical window to show the image; this requires feh to be installed.'},
                    {syn: %w(char-in-terminal char), desc: 'Render the image with unicode characters; ths requires chafa to be installed.'}]
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

  $remote_fifo = "#{$dirs[:data]}/remote_fifo"
  $remote_message = "#{$dirs[:data]}/remote_message"
  FileUtils.rm($remote_message) if File.exist?($remote_message)

  # strings that are used identically at different locations;
  # collected here to help consistency
  $resources = {
    nloops_not_one: 'Number of loops cannot be set to 1; rather switch looping off ...',
    quiz_hints: 'Available hints for quiz-flavour %s',
    any_key: 'Press any key to continue ...',
    space_to_cont: 'SPACE to continue ... ',
    just_type_one: ";or just type '1' to get one hole",
    hl_wheel: [32,92,0,92],
    hl_long_wheel: [32,92,0,92,32,92,0,92,32,92,0],
    playing_is_paused: "Playing paused, but keys are still available;\npress h to see their list or SPACE to resume playing ...\n",
    playing_on: "playing on"
  }

  $keyboard_translateable = %w(SPACE TAB RETURN BACKSPACE LEFT RIGHT UP DOWN ALT-s ALT-l) + ('a' .. 'z').to_a + ('A' .. 'Z').to_a + ('0' .. '9').to_a + %w(! " § $ % & ? - * # . / : ; _) + ['(', ')']

  # default is (sometimes) $all_waves[0]
  $all_waves = %w(pluck sawtooth square sine)
  
end


def find_and_check_dirs_early

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
  $dirs[:user_scales] = "#{$dirs[:data]}/scales"

  [:data, :players_pictures, :user_scales].each do |dirsym|
    created = create_dir($dirs[dirsym])
    $dirs_data_created = true if created && dirsym == :data
  end
  
  readme = "#{$dirs[:data]}/README.org"
  unless File.exist?(readme)
    File.write readme, <<~EOREADME

      The directory contains your personal data for harpwise,
      e.g. your configuration file config.ini or your licks.

      Many of these files contain comments, others are explained in
      the documentation of harpwise.

      Consider backing up this directory now and then.

EOREADME
  end
    
  $early_conf[:config_file] = "#{$dirs[:install]}/config/config.ini"
  $early_conf[:config_file_user] = "#{$dirs[:data]}/config.ini"
  $sox_fail_however = <<~end_of_however

  sox (or play or rec) did work start correctly; see error-message above.
  -----------------------------------------------------------------------

  Please try:

    harpwise tools diag

  which will execute a simple test, that can be diagnosed more easily.

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
  # they start of the same, but may diverge below
  lines[:comment_tall] = lines[:comment_flat] = lines[:comment]
  lines[:comment_flat] += 1
  if lines_extra > 0
    lines[:comment_flat] += 1
    lines[:comment] += 1
  end
  if need_message2
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
  $sample_dir = get_sample_dir($key)
  $lick_dir = "#{$dirs[:data]}/licks/#{$type}"
  $derived_dir = "#{$dirs[:data]}/derived/#{$type}"
  FileUtils.mkdir_p($derived_dir) unless File.directory?($derived_dir)

  # check and do this before read_samples is called in set_global_musical_vars
  if $type == 'richter' and $key == 'c'
    created = create_dir($sample_dir)
    if created
      from_dir = "#{$dirs[:install]}/resources/starter_samples_richter_c"
      Dir["#{from_dir}/*.mp3"].each do |mp3|
        FileUtils.cp mp3, $sample_dir
      end
      FileUtils.cp "#{from_dir}/frequencies.yaml", $sample_dir
      $msgbuf.print "Copied an initial set of samples for type 'richter' and key of 'c' to get you started. However, for a more natural sound, you may replace them with your own recordings later; see mode 'samples' for that.", 2, 5, wrap: true, truncate: false
    end
  end
  
  $invocations_dir = "#{$dirs[:data]}/invocations"
  if !File.directory?($invocations_dir)
    FileUtils.mkdir_p($invocations_dir)
    File.write "#{$invocations_dir}/README.org", <<~EOREADME

      The files in this directory contain the most recent
      commandlines, that have been used to invoke harpwise. These are
      grouped by mode and extra keyword, so each type may have its own
      history.

      The files can be used as a basis for an easy lookup of harpwise
      commands; a sample script using fzf can be found in the
      install-dir of harpwise, subdirectory util.

EOREADME
  end
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
  $journal_minimum_duration = 0.2
  # filenames for user-readable persistant data
  $journal_file = "#{$dirs[:data]}/journal_#{$type}.txt"
  $history_file = "#{$dirs[:data]}/history_#{$type}.json"

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
  #
  # The values below (first two pairs only) stem from a restriction of aubiopitch on macos
  # for fft
  $aubiopitch_sizes = { short: [2048, 512],
                        medium: [4096, 1024],
                        long: [8192, 2048] }
  $time_slice_secs = $aubiopitch_sizes[$opts[:time_slice]][1] / $conf[:sample_rate].to_f

  # prepare meta information about flavours and their tags
  $quiz_flavour2class = QuizFlavour.subclasses.map do |subclass|
    [subclass.to_s.underscore.tr('_', '-'), subclass]
  end.to_h
  $quiz_coll2flavs = Hash.new
  # $q_cl2ts comes from the individual flavour classes
  $q_class2colls.each do |clasz, colls|
    flav = clasz.to_s.underscore.tr('_', '-')
    colls.each do |co|
      $quiz_coll2flavs[co] ||= Array.new
      $quiz_coll2flavs[co] << flav
    end
  end
  $quiz_coll2flavs['all'] = $quiz_flavour2class.keys

  # does not fit into find_and_check_dirs_early, because we need
  # all_types
  $conf[:all_types].each do |type|
    create_dir "#{$dirs[:user_scales]}/#{type}"
  end
end


def check_installation verbose: false
  # check for some required programs
  needed_progs = %w( figlet toilet aubiopitch sox stdbuf )
  not_found = needed_progs.reject {|x| system("which #{x} >/dev/null 2>&1")}
  err "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0
  puts "Found needed programs: #{needed_progs}" if verbose

  # check, that sox understands mp3
  %x(sox -h).match(/AUDIO FILE FORMATS: (.*)/)[1]['mp3'] ||
    err("Your installation of sox does not support mp3 (check with: sox -h); please install the appropriate package (e.g. libsox-fmt-all)")
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

  # Handle some special cases
  # gracefully handle common plural/singular-mingling
  conf[:sharps_or_flats] = :sharps if conf[:sharps_or_flats] == :sharp
  conf[:sharps_or_flats] = :flats if conf[:sharps_or_flats] == :flat
  err err_head + "Config 'sharps_or_flats' can only be 'flats' or 'sharps' not '#{conf[:sharps_or_flats]}'" unless [:sharps, :flats].include?(conf[:sharps_or_flats])
  
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
      value = md[2].send($conf_meta[:conversions][key])
      err err_head + "Key '#{key.to_sym}' is deprecated; please edit the file and remove or rename it" if $conf_meta[:deprecated_keys].include?(key)
      if section
        allowed = Set.new($conf_meta[:sections_keys][section])
        allowed += Set.new($conf_meta[:sections_keys][:any_mode]) if ! [:any_mode, :general].include?(section)
        err err_head + "Key '#{key.to_sym}' is not among allowed keys in section '#{section}'; none of '#{allowed}'. If not a typo, it might be allowed in one of the other sections however #{$conf_meta[:sections].map(&:o2str)}" unless allowed.include?(key)
        conf[section][key] = value
      elsif section.nil?
        err err_head + "Not in a section, key '#{key}' can only be assigned to in a section" 
      end
    else
      err err_head + "\nCannot understand this line:\n\n#{line}\n\na line should be one of:\n  - a comment starting with '#'\n  - a section like [name]\n  - an assignment  like 'key = something'"
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

    # For the two sections below, we require all keys to be present,
    # but only for installation-config, not for user-config. This
    # requirement is relaxed for other sections, e.g. :licks
    if strict && [:any_mode, :general].include?(section)
      err err_head + "Section #{section.o2str} has these keys:\n\n#{found}\n\nwhich is different from all keys required:\n\n#{required}" unless required == found
    end
  end

  # transfer keys from general
  conf[:general].each {|k,v| conf[k] = v}

  conf
end


def read_and_set_musical_bootstrap_config
  $samples_needed = ![:samples, :print, :tools, :develop].include?($mode)
  all_scales, scale2file = scales_for_type($type,true)  
  all_scales.each {|sc| $name_collisions_mb[sc] << 'scale'}
  all_sc_progs = Hash.new
  sc_prog2file = Hash.new
  $scale_prog_file_templates.each do |sc_pr_fl_tpl|
    sc_pr_fl = sc_pr_fl_tpl % $type
    next unless File.exist?(sc_pr_fl)
    sc_progs = yaml_parse(sc_pr_fl)
    sc_progs.is_a?(Hash) || err("Not an array but a #{sc_progs.class}   (in #{sc_pr_fl})")
    sc_progs.each do |name, prog|
      err "Scale progression #{name} has already been defined in #{sc_prog2file[name]} cannot redefine it in #{sc_pr_file}" if sc_prog2file[name]
      sc_prog2file[name] = sc_pr_fl
      prog.is_a?(Hash) || err("Not a hash #{prog}   (in #{sc_pr_fl})")
      prog.transform_keys!(&:to_sym)
      sc_pr_ks = [:desc, :scales]
      prog.keys == sc_pr_ks || err("Wrong keys #{prog.keys}, not #{sc_pr_ks}   (in #{sc_pr_fl})")
      prog[:scales].each do |sc|
        err("Unknown scale #{sc} specified in scale progression #{name}, none of #{all_scales}   (in #{sc_pr_fl})") unless all_scales.include?(sc)
      end
      all_sc_progs[name] = prog
    end
  end
  holes_file = "#{$dirs[:install]}/config/#{$type}/holes.yaml"
  return [all_scales, scale2file, yaml_parse(holes_file).keys, all_sc_progs, sc_prog2file, holes_file]
end


def read_and_set_musical_config
  $hole2note_for_c = yaml_parse($holes_file)
  $dsemi_key_minus_c = diff_semitones($key, 'c', strategy: :minimum_distance)
  harp = Hash.new
  hole2flags = Hash.new {|h,k| h[k] = Set.new}
  semi2hole_sc = Hash.new {|h,k| h[k] = Array.new}
  bare_note2holes = Hash.new {|h,k| h[k] = Set.new}
  hole_root = nil
  $hole2note_for_c.each do |hole, note|
    semi = note2semi(note) + $dsemi_key_minus_c
    harp[hole] = [[:note, semi2note(semi)],
                  [:semi, semi]].to_h
    semi2hole_sc[semi] << hole
    hole_root ||= hole if semi % 12 == 0
  end
  # :equiv and :canonical are useful when doing set operations with
  # holes; eg for scales and licks
  $hole2note_for_c.each do |hole, _|
    harp[hole][:equiv] = semi2hole_sc[harp[hole][:semi]].reject {|h| h == hole}
    equiv = harp[harp[hole][:equiv][0]] 
    harp[hole][:canonical] = ( equiv && equiv[:canonical]  ?  equiv[:canonical]  :  hole)
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

  harp_holes.each do |hole|
   bare_note2holes[harp[hole][:note][0..-2]] << hole 
  end

  # process scales
  if $scale
    
    # get all holes to remove
    holes_remove = []
    if $opts[:remove_scales]
      $opts[:remove_scales].split(',').each do |sn|
        sc_ho = read_and_parse_scale(sn)
        holes_remove.concat(sc_ho)
      end
    end

    scale = []
    h2s_shorts = Hash.new('')
    $used_scales.each_with_index do |sname, idx|
      # read scale
      scale_holes = read_and_parse_scale(sname, harp)
      holes_remove.each {|h| scale_holes.delete(h)}
      # build final scale as sum of multiple single scales
      scale.concat(scale_holes) unless idx > 0 && $opts[:add_no_holes]
      # construct remarks to be shown amd flags to be used while
      # handling holes
      scale_holes.each do |h|
        next if holes_remove.include?(h)
        if idx == 0
          hole2flags[h] << :main
        else
          next if $opts[:add_no_holes] && !hole2flags[h]
          hole2flags[h] << :added
        end
        h2s_shorts[h] += $scale2short[sname]
        harp[h][:equiv].each {|h| h2s_shorts[h] += $scale2short[sname]}
      end
    end
    # omit equivalent holes
    scale_holes = scale.sort_by {|h| harp[h][:semi]}.uniq

    scale_notes = scale_holes.map {|h| $hole2note[h]}
  else            
    scale_holes = scale_notes = nil
  end

  # semi2hole is independent of scale
  # "reverse" below to make the first hole (e.g. -2) prevail
  semi2hole = harp_holes.map {|hole| [harp[hole][:semi], hole]}.reverse.to_h

  # read e.g. typical and named holes
  sets_file = "#{$dirs[:install]}/config/#{$type}/hole_sets.yaml"
  hole_sets = yaml_parse(sets_file).transform_keys!(&:to_sym)
  required = Set[:typical_hole, :named_sets]
  found = Set.new(hole_sets.keys)
  err "Internal error: Set of keys #{found} from #{sets_file} is different from required set #{required}" unless required == found
  typical_hole = hole_sets[:typical_hole]
  named_hole_sets = hole_sets[:named_sets].transform_keys!(&:to_sym)
  required = Set[:draw, :blow]
  found = Set.new(named_hole_sets.keys)
  err "Internal error: Characteristic sets #{found} from #{sets_file} is different from required set #{required}" unless required == found

  # read from first available intervals file
  ifile = ["#{$dirs[:install]}/config/#{$type}/intervals.yaml", "#{$dirs[:install]}/config/intervals.yaml"].find {|f| File.exist?(f)}
  $intervals_quiz = {easy: [], hard: []}
  intervals = yaml_parse(ifile).transform_keys!(&:to_i)
  intervals.keys.each do |st|
    $intervals_quiz[:easy] << st if intervals[st].include?('quiz_easy')
    $intervals_quiz[:hard] << st
    intervals[st].delete('quiz_easy')
    intervals[st].delete('quiz_hard')
    next if st == 0
    err "Intervals < 0 (here: #{st}) are not supported; they are created by inverting those > 0: #{intervals[st]}, as read from #{ifile}" if st < 0
    # dont use prepend here
    intervals[-st] = intervals[st].map {|i| '-' + i}
  end
  
  # intervals inverted
  intervals_inv = Hash.new
  intervals.each do |k,vv|
    vv.each do |v|
      intervals_inv[v.downcase] = k
      $name_collisions_mb[v] << 'interval'
      # add some common variations
      intervals_inv[v.downcase+ ' up'] = k
      intervals_inv[v.downcase+ ' down'] = -k
    end
  end

  # precalculate some hole shifting
  harp.each_key do |hole|
    harp[hole][:shifted_by] = $std_semi_shifts.flatten.map do |shift|
      [shift, semi2hole[harp[hole][:semi] + shift]]
    end.to_h.compact
    # do not mix up equivalent holes
    harp[hole][:shifted_by][0] = hole
  end
  
  [ harp,
    harp_holes,
    harp_notes,
    scale_holes,
    scale_notes,
    hole2flags.values.all?(&:nil?)  ?  nil  :  hole2flags,
    h2s_shorts,
    semi2hole,
    intervals,
    intervals_inv,
    hole_root,
    typical_hole,
    named_hole_sets,
    bare_note2holes ]

end


def read_and_parse_scale sname, harp = nil
  
  scale_holes, props, sfile = read_and_parse_scale_simple(sname, harp)
  
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

  # write derived scale file
  dfile = $derived_dir + '/derived_' +
          File.basename(sfile).sub(/holes|notes/, sfile['holes'] ? 'notes' : 'holes')
  dcont = {'short' => $scale2short[sname],
           'desc' => $scale2desc[sname]}
  if dfile['holes']
    dcont['holes'] = scale_holes
  else
    # map notes back to c
    dcont['notes'] = scale_holes.map {|h| $hole2note_for_c[h]}
  end
  what = ( dfile['holes']  ?  'holes'  :  'notes' )
  File.write( dfile,
              "#\n" +
              "# Derived scale file with #{what}\n" +
              "# created from   #{sfile}\n" +
              "# and moved to the key of c.\n" +
              "#\n" +
              YAML.dump(dcont) )
  scale_holes
end


def read_and_parse_scale_simple sname, harp = nil, desc_only: false, override_file: nil

  # shortcut for scale given on commandline
  if sname == 'adhoc-scale'
    $adhoc_scale_holes.map! {|h| $note2hole[harp[h][:note]]}
    return [$adhoc_scale_holes, [{'short' => 'h'}], 'commandline']
  end

  err "Scale '#{sname}' should not contain chars '?' or '*'" if sname['?'] || sname['*']
  sfile = if override_file
            override_file
          else
            globs = $scale_files_templates.map {|t| t % [$type, sname, '{holes,notes}']}
            sfiles = globs.map {|g| Dir[g]}.flatten
            if sfiles.length != 1
              err "Unknown scale '#{sname}' (none of #{$all_scales.join(', ')}) as there is no file matching #{glob}" if sfiles.length == 0
              err "Invalid scale '#{sname}' (none of #{$all_scales.join(', ')}) as there are multiple files matching #{glob}"
            end
            sfiles[0]
          end

  # Actually read the file and check the yaml-keys
  raw_read = yaml_parse(sfile)
  what = ( sfile['holes']  ?  'holes'  :  'notes' )
  err "Content of scale file #{sfile} is not a hash, but rather: #{raw_read.class}" unless raw_read.class == Hash
  if sfile['holes']
    err "Content of scale file #{sfile} does not have required key 'holes', but rather these: #{raw_read.keys.join(', ')}" unless raw_read.keys.include?('holes')
  else
    err "Content of scale file #{sfile} does not have required key 'notes', but rather these: #{raw_read.keys.join(', ')}" unless raw_read.keys.include?('notes')
  end
  err "Content of scale file   #{sfile}   has both keys 'holes' and 'notes', but judging from the filename, only '#{what}' is allowed." if (%w(holes notes) - raw_read.keys).length == 0
  unknown = raw_read.keys - %w(desc short holes notes)
  err "These keys from scale file #{sfile} are unknown: #{unknown.join(', ')}" if unknown.length > 0
  hons_read = raw_read[what]
  err "Value of key '#{what}' from scale file #{sfile} is not an Array, but rather this: #{hons_read.class}" unless hons_read.class == Array
  
  # get properties of scale
  props = Hash.new
  %w(desc short).each do |key|
    next unless raw_read[key]
    props[key.to_sym] = raw_read[key] 
    err "Value of key '#{key}' from scale file #{sfile} is not a String, but rather this: #{props[key.to_sym].class}" unless props[key.to_sym].class == String
  end
  $scale2desc[sname] = props[:desc] if props[:desc]

  return if desc_only

  # move the scale to the right key and maybe transpose
  dsemi_transpose = if !$opts[:transpose_scale]
                      0
                    elsif $opts[:transpose_scale].is_a?(Integer)
                      $opts[:transpose_scale]
                    else
                      note2semi(($opts[:transpose_scale] || $key) + '0') - note2semi($key + '0')
                    end
  scale_holes = Array.new

  if sfile['holes']

    holes_lost = []
    hons_read.each do |hole|
      err "Hole   '#{hole}'   as read from   #{sfile}   is none of the available holes:   #{$hole2note_for_c.keys.join(', ')}" unless $hole2note_for_c[hole]
      semi_for_c = note2semi($hole2note_for_c[hole])
      semi_moved = semi_for_c + $dsemi_key_minus_c + dsemi_transpose
      if semi_moved >= $min_semi && semi_moved <= $max_semi
        note_moved = semi2note(semi_moved)
        hole_moved = $note2hole[note_moved]
        if hole_moved
          scale_holes << hole_moved
        else
          holes_lost << hole
        end
      else
        holes_lost << hole
      end
    end
    if $used_scales.include?(sname) && holes_lost.length > 0
      $msgbuf.print "These holes from scale #{sname} have been lost during transpose: #{holes_lost.join(' ')}", 5, 5
    end

  else

    notes_lost = []
    all_notes_norm = $hole2note_for_c.values.map {|n| sf_norm(n)}
    hons_read.each do |note_for_c|
      err "Note   '#{note_for_c}'   as read from   #{sfile}   is none of the available notes:   #{$hole2note_for_c.values.join(', ')}" unless all_notes_norm.include?(sf_norm(note_for_c))
      semi_for_c = note2semi(note_for_c)
      semi_moved = semi_for_c + $dsemi_key_minus_c + dsemi_transpose
      if semi_moved >= $min_semi && semi_moved <= $max_semi
        note_moved = semi2note(semi_moved)
        hole_moved = $note2hole[note_moved]
        if hole_moved
          scale_holes << hole_moved
        else
          notes_lost << note_for_c
        end
      else
        notes_lost << note_for_c
      end
    end
    if $used_scales.include?(sname) && notes_lost.length > 0
      $msgbuf.print "These notes from scale #{sname} have been lost during transpose: #{notes_lost.join(' ')}", 5, 5
    end

  end
  
  [scale_holes, props, sfile]
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


def get_chart_with_intervals prefer_names: true, ref: nil
  ref ||= $hole_ref || $typical_hole
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
          isemi ,_ ,itext, dsemi = describe_inter(hole, ref)
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


def read_samples
  err "Frequency file #{$freq_file}\ndoes not exist; you need to create, samples for the key of   #{$key}   first !\n\nYou may either record samples or let harpwise generate them.\n#{for_sample_generation}this needs to be done only once.\n\n" unless File.exist?($freq_file)
  hole2freq = yaml_parse($freq_file)
  unless Set.new($harp_holes) == Set.new(hole2freq.keys)
    err "The sets of holes from #{$holes_file}\n#{$harp_holes.join(' ')}\nand #{$freq_file}\n#{hole2freq.keys.join(' ')}\ndiffer. The symmetrical difference is\n#{(Set.new($harp_holes) ^ Set.new(hole2freq.keys)).to_a.join(' ')}\nProbably you should redo the whole recording or generation of samples !\n\n#{for_sample_generation}"
  end
  hole2freq.each do |hole, freq|
    err "The frequency for hole   #{hole}   in #{$freq_file} is zero. Probably you need to re-record this sample or delete it !" if freq == 0
  end
  $harp_holes.each_cons(2).all? do |ha, hb|
    fa = hole2freq[ha]
    fa_plus = semi2freq_et($harp[ha][:semi] + 0.5)
    fa_minus = semi2freq_et($harp[ha][:semi] - 0.5)
    fb_plus = semi2freq_et($harp[hb][:semi] + 0.5)
    maybe = "Maybe re-record hole #{ha} or simply generate all holes for this key."
    if fa >= fb_plus
      err "Frequencies are not in ascending order, rather #{ha} has higher frequency than #{hb}:\n  #{fa} (for #{ha}, measured)  >=  #{fb_plus.round(2)} (for #{hb}, calculated + 0.5 st)\n#{maybe}"
    end
    if fa <= fa_minus || fa >= fa_plus
      err "Frequency    #{fa}   for hole   #{ha}   is not in expected range   #{fa_minus.round(2)} ... #{fa_plus.round(2)}\n#{maybe}"
    end
  end

  hole2freq.map {|k,v| $harp[k][:freq] = v}

  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s", $harp[hole][:note], %w(.wav .mp3))
    err "Sample file #{file} does not exist; you need to create samples" unless File.exist?(file)
  end

  # 'reverse', because we want to get the first of two holes having the same freq
  freq2hole = $harp_holes.map {|h| [$harp[h][:freq], h]}.reverse.to_h

  freq2hole
end


def set_global_musical_vars rotated: false

  $used_scales = get_used_scales($opts[:add_scales])
  $scale_prog ||= $used_scales
  $opts[:add_scales] = nil if $used_scales.length == 1
  $all_quiz_scales = yaml_parse("#{$dirs[:install]}/config/#{$type}/quiz_scales.yaml").transform_keys!(&:to_sym)
  fail "Internal error: #{$all_quiz_scales}" unless $all_quiz_scales.is_a?(Hash) && $all_quiz_scales.keys == [:easy, :hard]
  [:easy, :hard].each do |dicu|
    fail "Internal error: #{$all_scales}, #{$all_quiz_scales[dicu]}" unless $all_quiz_scales[dicu] - $all_scales == []
  end
  $all_quiz_scales[:hard].append(*$all_quiz_scales[:easy]).uniq!

  $std_semi_shifts = [-12, -10, -7, -5, -4, 4, 5, 7, 10, 12]

  $harp, $harp_holes, $harp_notes, $scale_holes, $scale_notes, $hole2flags, $hole2scale_shorts, $semi2hole, $intervals, $intervals_inv, $hole_root, $typical_hole, $named_hole_sets, $bare_note2holes = read_and_set_musical_config

  $scale_desc_maybe = Hash.new
  $scale2count = Hash.new
  $all_scales.each do |scale|
    scale_holes, props, sfile = read_and_parse_scale_simple(scale)
    $scale2count[scale] = scale_holes.length
    $scale_desc_maybe = $scale2desc[scale] || "holes #{scale_holes.join(',')}"
  end
  
  # semitone shifts that will be tagged and can be traversed
  $licks_semi_shifts = {0 => nil, 5 => 'shifts_four',
                        7 => 'shifts_five', 12 => 'shifts_eight'}

  $charts, $hole2chart = read_chart
  if $hole_ref
    $charts[:chart_intervals] = get_chart_with_intervals(prefer_names: true)
    $charts[:chart_inter_semis] = get_chart_with_intervals(prefer_names: false)
  end

  if [:play, :print, :licks, :listen].include?($mode)
    # might be reread later. Pass use_opt_lick_prog = false on very
    # first invocation, where $all_licks has not yet been set
    $all_licks, $licks, $all_lick_progs = read_licks(use_opt_lick_prog: !!$all_licks)
  end
  
  $freq2hole = read_samples if $samples_needed
  if $opts[:ref] 
    err "Option '--ref' needs a valid hole as an argument, not '#{$opts[:ref]}'" unless $harp_holes.include?($opts[:ref])
    $hole_ref = $opts[:ref]
  end

  $common_harp_keys = %w(g a c d)
  $all_harp_keys = if $opts[:sharps_or_flats] == :flats
                     %w(g af a bf b c df d ef e f gf)
                   else
                     %w(g gs a as b c cs d ds e f fs)
                   end

  # check, that the names of those extra args do not collide with scales
  $extra_kws.each do |mode, extra|
    double = extra & $all_scales - ['all']
    err "Some scales for type #{$type} can also be extra arguments for mode #{mode}: #{double.to_a.join(',')}\n\nScales:\n#{$all_scales}\n\nExtra arguments for #{mode}:\n#{extra.to_a}\n\nPlease rename your scale" if double.length > 0
  end
end


def for_sample_generation
  "For automatic generation of samples for key #{$key} use:\n\n  #{$0} samples #{$type} #{$key} generate\n\nor to generate for all keys:\n\n  #{$0} samples #{$type} generate all\n\n"
end


$warned_for_double_short = Hash.new
def warn_if_double_short short, long
  if $short2scale[short] && long != $short2scale[short] && !$warned_for_double_short[short]
    $warned_for_double_short[short] = true
    $msgbuf.print("Shortname '#{short}' is used for two scales '#{$short2scale[short]}' and '#{long}' consider explicit shortname with ':' (see usage)", 5, 5, wrap: true, truncate: false) if [:listen, :quiz, :licks].include?($mode)
  end
end


def get_sample_dir key
  this_or_equiv("#{$dirs[:data]}/samples/#{$type}/key_of_%s", key.to_s) ||
    "#{$dirs[:data]}/samples/#{$type}/key_of_#{key}"    
end
