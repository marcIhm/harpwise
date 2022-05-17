# -*- fill-column: 74 -*-

#
# Parse arguments from commandline
#

def parse_arguments

  # get content of all harmonica-types
  types_content = $conf[:all_types].map do |type|
    "scales for #{type}: " +
      scales_for_type(type).join(', ')
  end.join("\n  ")
  
  usage = <<EOU


harp_trainer ('trainer', for short) helps to practice scales
(e.g. blues or mape) for harmonicas of various types (e.g. richter or
chromatic) for various keys (e.g. a or c).  Main modes of operation are
'listen' and 'quiz'.


Usage by examples for the modes listen, quiz, memorize and calibrate: 

------ listen ------

  The trainer listens, while your are playing a richter harmonica of key c
  and it shows the holes, that you played; green if from the scale, red
  otherwise:

    ./harp_trainer listen ri c blues

  Add option '--comment interval' (or '-c i') to show intervals instead
  of notes; other possible values are 'note' and 'hole'.
  See below ('quiz') for some options accepted by both modes.

  Switch on journal to get a simple transcription of the holes played.

------ quiz ------

  The Trainer plays 3 notes from the scale 'mape' for a chromatic
  harmonica of key a and then quizes you to play them back (then repeat):

    ./harp_trainer quiz 3 chrom a mape

  Add option '--loop' (or '-l') to loop over sequence until you type
  'RETURN'. Option '--immediate' shows the full hole-sequence during quiz
  right from the start (rather than after some delay only).

  In the examples above, the type of harmonica (e.g. richter or
  chromatic) and, in addition, the key (e.g. c or a) may be omitted and
  are then taken from the config; so

    ./harp_trainer q 3 ma

  is valid as well.


  Both modes listen and quiz accept the option '--merge' with one or more
  scales (separated by comma) to be merged. E.g. when trying licks for the
  v-chord, you might use the blues scale and add the scale chord-v:

    ./harp_trainer l blues --merge chord-v

  For quiz, the holes from the merged scale (chord-v in the example above)
  will be chosen more frequent than the holes from the main scale (blues);
  the last note of a sequence will likely be a root note (i.e. one with
  the remark root). If you do not want to add new holes during the merge,
  so that you only use remarks, colors and scale-name from the merged
  scale, add option '--no-add'.

  Both modes accept the option '--remove' with one or more scales to be
  removed from the original scale. E.g. you might want to remove bends
  from all notes:

    ./harp_trainer q all --remove blowbends,drawbends

  Both modes listen and quiz allow an option '--display' with possible
  values of 'hole' and 'chart' to change how a recognized hole will be
  displayed.

  Some (display-)settings can also be changed while the program is
  running; type 'h' for details.


------ memo ------

  The mode memo is a variation of quiz, which helps to memorize licks
  from a given set:

    ./harp_trainer memo c

    ./harp_trainer memo c --tags fav,scales

  As shown in the second example, you may restrict the set of licks to
  those with certain tags; tags (e.g. 'scales') may also
  be excluded like '--no-tags scales'.

  Use '--tags print' to see all defined tags in lick-file (or see there).

  To play only shorter licks use e.g. '--max-holes 8'.  '--start-with'
  specifies the first lick to play and accepts the special value 'last' or
  'l' to repeat the last lick ('2l', '3l' for earlier licks); licks
  addressed this way will not be written to the journal.  Use
  '--start-with iter' to iterate through all selected licks one by one;
  use '--start-with foo,iter' to start at lick foo.
  To see a list of recent licks use '--start-with history', for a list of all
  licks '--start-with print'.

  To make the mode more challenging, you may let only parts of the
  recording be played, e.g. '--partial 1/3@b', '1/4@x', '1/2@e' which
  would play the first third of the recording, any randomly chosen quarter
  of it or the last half (but at least one second). '--partial 1s@b',
  '1s@e' or '2s@x' play the given number of seconds at position.

  For memorize to be useful, you need to create a file with your own licks
  for more info see the starter file created initally.  Please note, that
  this mode will set the scale to 'all' implicitly.


------ play ------

  If you just want to play a single lick without beeing challenged to play
  it back:

    ./harp_trainer play c blues

    ./harp_trainer play c 1 -2 c4

  which can play either a complete lick or the holes or notes given on the
  commandline. The special argument 'random' just plays a random lick, 
  'last' repeats the last lick played (even from memorize). 
  If you want to play the holes of the lick (rather than the recording), add
  option '--holes'.
  This mode accepts the same special lick names (e.g. history or print) as 
  '--start-with' for moder 'quit' above.


------ calibrate ------

  Once in the lifetime of your c-harp you need to calibrate the trainer
  for the frequencies of the harp you are using:

    ./harp_trainer calibrate c
    
  this will ask you to play notes on your harp. The samples will be
  stored in the hidden folder .#{File.basename($0)} within your home
  directory; frequencies will be extracted to the file frequencies.yaml.

  This command does not need a scale-argument.

  For quick (but possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -3//'.


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

  # extract options from ARGV
  opts = Hash.new

  # defaults from config
  opts[:fast] = $conf[:play_holes_fast]

  opts_with_args = [:hole, :comment, :display, :transpose_scale_to, :ref, :merge, :remove, :tags, :no_tags, :max_holes, :start_with, :partial]
  { %w(--debug) => :debug,
    %w(--testing) => :testing,
    %w(-s --screenshot) => :screenshot,
    %w(-h --help) => :help,
    %w(--auto) =>:auto,
    %w(--hole) => :hole,
    %w(-m --merge) => :merge,
    %w(-r --remove) => :remove,
    %w(--no-add) => :no_add,
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
    %w(--holes) => :holes,
    %w(--no-progress) => :no_progress,
    %w(--start-with) => :start_with,
    %w(--partial) => :partial,
    %w(-l --loop) => :loop}.each do |txts,opt|
    txts.each do |txt|
      for i in (0 .. ARGV.length - 1) do
        if txt.start_with?(ARGV[i]) && ARGV[i].length >= [4, txt.length].min
          opts[opt] = opts_with_args.include?(opt) ? ARGV.delete_at(i+1) : true
          ARGV.delete_at(i)
          break
        end
      end
    end
  end
  opts_with_args.each do |opt|
    err "Option '--#{opt}' needs an argument" if opts.keys.include?(opt) && !opts[opt].is_a?(String)
  end

  # special processing for some options
  opts[:comment] = match_or(opts[:comment], $comment_choices) do |none, choices|
    err "Option '--comment' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end

  opts[:display] = match_or(opts[:display], $display_choices) do |none, choices|
    err "Option '--display' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end

  if opts[:max_holes]
    err "Option '--max_holes' needs an integer argument, not '#{opts[:max_holes]}'" unless opts[:max_holes].match?(/^\d+$/)
    opts[:max_holes] = opts[:max_holes].to_i
  end
    
  
  opts[:fast] = false if opts[:no_fast]

  err "Option '--transpose_scale_to' can only be one on #{$conf[:all_keys].join(', ')}, not #{opts[:transpose_scale_to]}" unless $conf[:all_keys].include?(opts[:transpose_scale_to]) if opts[:transpose_scale_to]

  # see end of function for final processing of options

  if ARGV.length == 0 || opts[:help]
    puts usage
    exit 1
  end

  # now ARGV does not contain any more options; process non-option arguments

  # General idea of argument processing: We take the mode, then key and
  # type, by recognising it among other args by its content and then the
  # rest.
  
  mode = match_or(ARGV[0], %w(listen quiz memorize play calibrate)) do |none, choices|
    err "First argument can be one of #{choices}, not #{none}"
  end.to_sym
  ARGV.shift

  ARGV.select {|arg| arg.start_with?('-')}.tap {|left| err "Unknown options: #{left.join(',')}" if left.length > 0} unless mode == :play

  if mode == :quiz
    $num_quiz = ARGV[0].to_i
    if $num_quiz.to_s != ARGV[0] || $num_quiz < 1
      err "Argument after mode 'quiz' must be an integer starting at 1, not '#{ARGV[0]}'"
    end
    ARGV.shift
  end

  if [:calibrate, :play, :memorize].include?(mode)
    scale = nil
  else
    scale = ARGV.pop
    err "Need at least one argument for scale" unless scale
  end

  # type and key are taken from front of args only if they match the
  # predefined set of coices; otherwise they come from config
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
   
  (er = check_key_and_set_pref_sig(key)) && err(er)
  $err_binding = binding
  if mode == :calibrate || mode == :memorize
    err("Do not need a scale argument for mode #{mode}: #{ARGV}") if ARGV.length == 1
    scale = 'all' if mode == :memorize
  elsif mode == :play
    err("Need a scale or some holes as arguments") if ARGV.length == 0
    scale = scales_for_type(type).select {|s| s==ARGV[0]}[0] if ARGV.length == 1
  else
    err("Need value for scale as one more argument") unless scale
  end
  err "Need at least one argument for mode play" if ARGV.length == 0 && mode == :play
  
  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}" if ARGV.length > 0 && mode != :play
  $err_binding = nil
  
  # late option processing depending on mode
  # check for invalid combinations of mode and options
  [[[:quiz, :memorize],
    [:loop, :immediate]],
   [[:listen, :quiz, :memorize],
    [:remove, :merge, :no_add, :comment]],
   [[:calibrate],
    [:auto]],
   [[:memorize, :play],
    [:sections, :max_holes]],
   [[:memorize],
    [:start_with, :partial]],
   [[:play],
    [:holes]]].each do |modes_opts|
    modes_opts[1].each do |opt|
      err "Option '--#{opt}' is allowed for modes '#{modes_opts[0]}' only" if opts[opt] && !modes_opts[0].include?(mode)
    end
  end
  
  # carry some options over into $conf
  $conf[:comment_listen] = opts[:comment] if opts[:comment]
  $conf[:display] = $conf["display_#{mode}".to_sym]
  $conf[:display] = opts[:display] if opts[:display]

  # some of these have already been set as global vars, but return them
  # anyway to make their origin transparent
  [ mode, type, key, scale, opts]
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
  if $conf[:all_keys].include?(key)
    nil
  else
    "Key can only be one of #{$conf[:all_keys].join(', ')}, not '#{key}'"
  end
end
