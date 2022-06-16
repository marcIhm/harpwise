# -*- fill-column: 74 -*-

#
# Parse arguments from commandline
#

def parse_arguments

  # get content of all harmonica-types to be inserted in usage
  types_content = $conf[:all_types].map do |type|
    "scales for #{type}: " +
      scales_for_type(type).join(', ')
  end.join("\n  ")
  
  usage = <<EOU


harpwise ('wise', for short) helps to practice scales
(e.g. blues or mape) for harmonicas of various types (e.g. richter or
chromatic) for various keys (e.g. a or c).  Main modes of operation are
'listen', 'quiz' and 'licks'.


Usage by examples for the modes listen, quiz, licks, play and
calibrate:


------ listen ------

  The wise listens, while your are playing a richter harmonica of key c
  and it shows the holes, that you played; green if from the scale, red
  otherwise:

    ./harpwise listen ri c blues

  Add option '--comment interval' (or '-c i') to show intervals instead
  of notes; other possible values are 'note' and 'hole'.
  See below ('quiz') for some options accepted by both modes.

  Switch on journal to get a simple transcription of the holes played.


------ quiz ------

  The Wise plays 3 notes from the scale 'mape' for a chromatic harmonica
  of key a and then quizes you to play them back (then repeat):

    ./harpwise quiz 3 chrom a mape

  Add option '--loop' (or '-l') to loop over sequence until you type
  'RETURN'. Option '--immediate' shows the full hole-sequence during quiz
  right from the start (rather than after some delay only).

  In the examples above, the type of harmonica (e.g. richter or
  chromatic) and, in addition, the key (e.g. c or a) may be omitted and
  are then taken from the config; so

    ./harpwise q 3 ma

  is valid as well.


  Both modes listen and quiz accept the option '--add-scales' with one or
  more extra scales (separated by comma) to be shown. E.g. when trying
  licks for the v-chord, you might use the blues scale and add the scales
  chord-i and chord-v:

    ./harpwise l blues:b --add-scales chord-i:1,chord-v:5

  This example also uses abbreviations, l,1 and 5, for the scales which
  will be used in the chart.
    
  For quiz, the holes from the additional scales will be chosen more
  frequent than the holes from the main scale (blues); the last note of a
  sequence will likely be a root note (i.e. one with the remark root). If
  you do not want to add new holes, so that you only use remarks, colors
  and scale-name from the additional scales, add option '--add-no-holes'.

  Both modes accept the option '--remove' with one or more scales to be
  removed from the original scale. E.g. you might want to remove bends
  from all notes:

    ./harpwise q all --remove blowbends,drawbends

  Both modes listen and quiz allow an option '--display' with possible
  values of 'hole' and 'chart' to change how a recognized hole will be
  displayed.

  Some (display-)settings can also be changed while the program is
  running; type 'h' for details.


------ licks ------

  The mode licks is a variation of quiz, which helps to learn and memorize
  licks from a given set:

    ./harpwise licks c

    ./harpwise licks c --tags fav,scales

  As shown in the second example, you may restrict the set of licks to
  those with certain tags; tags (e.g. 'scales') may also
  be excluded like '--no-tags scales'.

  Use '--tags print' to see all defined tags in lick-file (or see there).

  To play only shorter licks use e.g. '--max-holes 8' or '--min-holes 12'
  for longer.  '--start-with' specifies the first lick to play and accepts
  the special value 'last' or 'l' to repeat the last lick ('2l', '3l' for
  earlier licks); licks addressed this way will not be written to the
  journal.  Use '--start-with iter' to iterate through all selected licks
  one by one; use '--start-with foo,iter' to start at lick foo; 'cycle'
  instead of 'iter' starts all over at the end.  To see a list of recent
  licks use '--start-with history', for a list of all licks from lick-file
  '--start-with print'.

  To make the mode more *challenging* and to improve the learning result,
  you may let only parts of the recording be played. E.g. with '--partial
  1/3@b', '1/4@x' or '1/2@e', which would play the first (1/3) third of
  the recording, any randomly chosen quarter (1/4) of it or the last half
  (1/2) (but at least one second). '--partial 1@b', '1@e' or '2@x' play
  the given number of seconds or holes (1 or 2) at the given position
  (b=begin, x=random, e=end); or, e.g. '1/2@e' plays the second half.

  If you want to play the holes of the lick (rather than the recording), add
  option '--holes', which also honors the option '--partial'.

  For mode licks to be useful, you need to create a file with your own
  licks for more info see the starter file created initally.  Please note,
  that this mode will set the scale to 'all' if no scale argument is
  given.


------ play ------

  If you just want the wise to play something, without beeing challenged
  to play it back:

    ./harpwise play c 1 -2 c4

    ./harpwise play c juke

  which can play either the holes or notes given on the commandline or a
  complete lick.

  The special argument 'random' just plays a random lick, 'last' (or 'l',
  '2l', etc) repeats the last lick played (even from mode licks).

  The arguments 'iterate' or 'cycle' play all the licks selected by
  options '--tags' and '--no-tags'. Also, the special lick names
  'history', 'print' and 'dump' are accepted as plain arguments (see
  '--start-with' for mode licks above).

  If you want to play the holes of the lick (rather than the recording),
  add option '--holes'.


------ calibrate ------

  Once in the lifetime of your c-harp you need to calibrate the wise for
  the frequencies of the harp you are using:

    ./harpwise calibrate c
    
  this will ask you to play notes on your harp. The samples will be
  stored in the hidden folder .#{File.basename($0)} within your home
  directory; frequencies will be extracted to the file frequencies.yaml.

  This command does not need a scale-argument.

  For quick (but possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -3//'.


--- Real-World examples ---

  Memorize licks, but only shorter ones and show the scales for each hole:

    harpwise licks c blues:b --loop --max-holes 15 --imm --no-tags scales \
        --disp chart-scales --add-scales chord-i:1,chord-iv:4,chord-v:5,root:r \
        --comment holes-all


  Lick-Radio: Play all my licks in random order:

    harpwise play random cycle


  Show what I am playing, emphasise notes from scales blues and major pentatonic:

    ./harpwise listen blues --add-scales mape
  

--- Some Notes ---

  The possible scales depend on the chosen type of harmonica:

  #{types_content}

  For modes 'listen' and 'quiz' you may choose to transpose the scale to
  another key: '--transpose_scale_to d'. This would be helpful, if you
  want to practice e.g. the d-major scale on a chromatic harmonica of key
  c. For a diatonic harmonica, however, your milage may vary, as not all
  notes are available.

  Modes, that play notes (usually one second) accept the option '--fast'
  to play them for half a second only; use '--no-fast' to override on the
  commandline, if config.yaml sets this to true.

  Most arguments and options can be abreviated, e.g 'l' for 'listen' or
  'cal' for 'calibrate'.

  Finally there are some less used options: --ref, --no-progress, --debug,
  --screenshot, --help, --testing


Suggested reading: The toplevel file README.org

Copyright (c) 2021-2022 by Marc Ihm.
This program is subject to the MIT License.

EOU

  # General idea of processing commandline:
  #
  # We process options first, because there do not have ambiguities; after
  # that, the remaining ags will be processed by their content (see below)

  # Process options
  
  opts = Hash.new

  # defaults from config
  opts[:fast] = $conf[:play_holes_fast]

  opts_with_args = [:hole, :comment, :display, :transpose_scale_to, :ref, :add_scales, :remove, :tags, :no_tags, :max_holes, :min_holes, :start_with, :partial]
  { %w(--debug) => :debug,
    %w(--testing) => :testing,
    %w(-s --screenshot) => :screenshot,
    %w(-h --help) => :help,
    %w(--auto) =>:auto,
    %w(--hole) => :hole,
    %w(--add-scales) => :add_scales,
    %w(-r --remove) => :remove,
    %w(--add-no-holes) => :no_add_holes,
    %w(--immediate) => :immediate,
    %w(--transpose_scale_to) => :transpose_scale_to,
    %w(-r --ref) => :ref,
    %w(-d --display) => :display,
    %w(-c --comment) => :comment,
    %w(-f --fast) => :fast,
    %w(--no-fast) => :no_fast,
    %w(--tags) => :tags,
    %w(--no-tags) => :no_tags,
    %w(--max-holes) =>:max_holes,
    %w(--min-holes) =>:min_holes,
    %w(--holes) => :holes,
    %w(--no-progress) => :no_progress,
    %w(--start-with) => :start_with,
    %w(--partial) => :partial,
    %w(-l --loop) => :loop}.each do |txts,opt|
    begin
      found_one = false
      txts.each do |txt|
        for i in (0 .. ARGV.length - 1) do
          if txt.start_with?(ARGV[i]) && ARGV[i].length >= [4, txt.length].min
            opts[opt] = opts_with_args.include?(opt) ? ARGV.delete_at(i+1) : true
            ARGV.delete_at(i)
            found_one = true
            break
          end
        end
      end
    end while found_one
  end
  opts_with_args.each do |opt|
    err "Option '--#{opt}' needs an argument" if opts.keys.include?(opt) && !opts[opt].is_a?(String)
  end

  # Special handling for some options
  
  opts[:display] = match_or(opts[:display], $display_choices.map {|c| c.to_s.gsub('_','-')}) do |none, choices|
    err "Option '--display' needs one of #{choices} (or abbreviated unambiguously) as an argument, not #{none}"
  end
  opts[:display]&.gsub!('-','_')
  
  if opts[:max_holes]
    err "Option '--max-holes' needs an integer argument, not '#{opts[:max_holes]}'" unless opts[:max_holes].match?(/^\d+$/)
    opts[:max_holes] = opts[:max_holes].to_i
  end
    
  if opts[:min_holes]
    err "Option '--min-holes' needs an integer argument, not '#{opts[:min_holes]}'" unless opts[:min_holes].match?(/^\d+$/)
    opts[:min_holes] = opts[:min_holes].to_i
  end
    
  opts[:fast] = false if opts[:no_fast]

  err "Option '--transpose_scale_to' can only be one on #{$conf[:all_keys].join(', ')}, not #{opts[:transpose_scale_to]}" unless $conf[:all_keys].include?(opts[:transpose_scale_to]) if opts[:transpose_scale_to]

  # usage if no arguments
  if ARGV.length == 0 || opts[:help]
    puts usage
    exit 1
  end

  # used to issue current state of processing in error messages
  $err_binding = binding

  
  # Now ARGV does not contain any more options; process non-option arguments

  # General idea of argument processing:
  #
  # We take the mode, then type and key, by recognising it among other
  # args by their content; then we process the scale, which is normally
  # the only remaining argument.

  # get mode
  err "Mode 'memorize' is now 'licks'; please change your first argument" if 'memorize'.start_with?(ARGV[0])
  mode = match_or(ARGV[0], %w(listen quiz licks play calibrate)) do |none, choices|
    err "First argument can be one of #{choices} (maybe abbreviated), not #{none}"
  end.to_sym
  ARGV.shift


  # As we now have the mode, we may do some final processing on options,
  # which requires the mode

  opts[:comment] = match_or(opts[:comment], $comment_choices[mode].map {|c| c.to_s.gsub('_','-')}) do |none, choices|
    err "Option '--comment' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end
  opts[:comment] = opts[:comment].gsub!('-','_').to_sym if opts[:comment]
  
  # check for unprocessed args, that look like options
  other_opts = ARGV.select {|arg| arg.start_with?('-')}
  err("Unknown options: #{other_opts.join(',')}") if other_opts.length > 0 && mode != :play

  # check for invalid combinations of mode and options
  [[[:quiz, :licks],
    [:loop, :immediate]],
   [[:listen, :quiz, :licks],
    [:remove, :add_scales, :add_no_holes, :comment]],
   [[:calibrate],
    [:auto]],
   [[:licks, :play],
    [:sections, :max_holes, :holes]],
   [[:licks],
    [:start_with, :partial]]].each do |modes_opts|
    modes_opts[1].each do |opt|
      err "Option '--#{opt}' is allowed for modes '#{modes_opts[0]}' only" if opts[opt] && !modes_opts[0].include?(mode)
    end
  end


  # In any case, mode quiz requires a numeric argument right after the
  # mode-argument; so process it even before type and key

  if mode == :quiz
    $num_quiz = ARGV[0].to_i
    if $num_quiz.to_s != ARGV[0] || $num_quiz < 1
      err "Argument after mode 'quiz' must be an integer starting at 1, not '#{ARGV[0]}'"
    end
    ARGV.shift
  end


  # type and key are taken from front of args only if they match the
  # predefined set of choices; otherwise they come from config
  
  if ARGV.length > 0
    type_matches = $conf[:all_types].select {|c| c.start_with?(ARGV[0])}
    if type_matches.length == 1 && ARGV[0].length > 1
      type =  type_matches[0]
      ARGV.shift
    end
  end
  type ||= $conf[:type]     
  $type = type

  key = ARGV.shift if $conf[:all_keys].include?(ARGV[0])
  key ||= $conf[:key]
  check_key_and_set_pref_sig(key)


  # For mode play, all the remaining arguments (after processing type and
  # key) are things to play; a scale is not allowed, so we do this before
  # processing the scale

  if mode == :play
    $to_play = []
    $to_play << ARGV.shift while ARGV.length > 0
    err("Need a lick or some holes as arguments") if $to_play.length == 0
  end

  
  # Get scale which must be the only remaining argument (if any);
  # modes that do not need a scale get scale 'all'

  case mode
  when :listen, :quiz
    err("Mode '#{mode}' needs at least one argument for scale") if ARGV.length == 0
    scale = get_scale(ARGV.shift)
  when :licks
    if ARGV.length > 0
      scale = get_scale(ARGV.shift)
    else
      scale = get_scale('all:a')
    end
  when :play
    scale = get_scale('all:a')
  when :calibrate
    err("Mode 'calibrate' does not need a scale argument; can not handle: #{ARGV[0]}") if ARGV.length > 0
    scale = get_scale('all:a')
  else
    fail "Internal error"
  end
  
  err "Given scale '#{scale}' is none of the known scales for type '#{type}': #{scales_for_type(type)}" unless !$scale || scales_for_type(type).include?(scale)
  
  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}" if ARGV.length > 0 && mode != :play && mode != :licks
  $err_binding = nil

  # Commandline processing is complete here
  
  # carry some options over into $conf
  $conf[:comment] = if mode == :listen
                      $conf[:comment_listen]
                    else
                      $conf[:comment_quiz]
                    end
  $conf[:comment] = opts[:comment] if opts[:comment]
  $conf[:display] = $conf["display_#{mode}".to_sym]
  $conf[:display] = opts[:display] if opts[:display]
  $conf[:display] = $conf[:display]&.to_sym

  # some of these have already been set as global vars (e.g. for error
  # messages), but return them anyway to make their origin transparent
  [ mode, type, key, scale, opts]
end


$scale_abbrev_count = 1
$abbrev2scale = Hash.new

def get_scale scale_abbrev
  err_text = "Abbreviation '%s' has already been used for scale '%s'; cannot reuse it for scale '%s'"
  scale = nil
  if md = scale_abbrev.match(/^(.*?):(.*)$/)
    scale = md[1]
    $scale2abbrev[md[1]] = md[2]
    err(err_text % [md[2], abbrev2scale[md[2]], md[1]]) if $abbrev2scale[md[1]]
    $abbrev2scale[md[2]] = md[1]
  else
    scale = scale_abbrev
    $scale2abbrev[scale_abbrev] = $scale_abbrev_count.to_s
    err(err_text % [$scale_abbrev_count.to_s, $abbrev2scale[$scale_abbrev_count.to_s], scale_abbrev]) if $abbrev2scale[$scale_abbrev_count.to_s]
    $abbrev2scale[$scale_abbrev_count.to_s] = scale_abbrev
    $scale_abbrev_count += 1
  end
  scale
end


def get_all_scales scales_abbrevs
  scales = [$scale]
  if scales_abbrevs
    scales_abbrevs.split(',').each do |scale_abbrev|
      scales << get_scale(scale_abbrev)
    end
  end
  scales
end


def check_key_and_set_pref_sig key
  $conf[:pref_sig] = if key.length == 2
                       if key[-1] == 'f'
                         :flat
                       else
                         :sharp
                       end
                     else
                       $conf[:pref_sig_def]
                     end

    nil
    err("Key can only be one of #{$conf[:all_keys].join(', ')}, not '#{key}'") unless $conf[:all_keys].include?(key)
end
