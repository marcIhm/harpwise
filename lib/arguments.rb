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


harp_scale_trainer ('trainer', for short) helps to practice scales
(e.g. blues or mape) for harmonicas of various types (e.g. richter or
chromatic) for various keys (e.g. a or c).  Main modes of operation are
'listen' and 'quiz'.


Usage by examples: 


  The trainer listens, while your are playing a richter harmonica of key c
  and it shows the holes, that you played; green if from the scale, red
  otherwise:

    ./harp_scale_trainer listen ri c blues

  Add option '--comment interval' (or '-c i') to show intervals instead
  of notes; other possible values are 'note' and 'hole'.

  Switch on journal to get a simple transcription of the holes played.


  Trainer plays 3 notes from the scale 'mape' for a chromatic harmonica of
  key a and then quizes you to play them back (then repeat):

    ./harp_scale_trainer quiz 3 chrom a mape

  Add option '--loop' (or '-l') to loop over sequence until you type
  'RETURN'. Option '--immediate' shows the full hole-sequence during quiz
  right from the start (rather than after some delay only).

  In the examples above, the type of harmonica (e.g. richter or
  chromatic) and, in addition, the key (e.g. c or a) may be omitted and
  are then taken from the config; so

    ./harp_scale_trainer q 3 ma

  is valid as well.


  Both modes listen and quiz accept the option '--merge' with one or more
  scales (separated by comma) to be merged. E.g. when trying licks for the
  v-chord, you might use the blues scale and add the scale chord-v:

    ./harp_scale_trainer l blues --merge chord-v

  For quiz, the holes from the merged scale (chord-v in the example above)
  will be chosen more frequent than the holes from the main scale (blues);
  the last note of a sequence will likely be a root note (i.e. one with
  the remark root). If you do not want to add new holes during the merge,
  so that you only use remarks, colors and scale-name from the merged
  scale, add option '--no-add'.

  Both modes accept the option '--remove' with one or more scales to be
  removed from the original scale. E.g. you might want to remove bends
  from all notes:

    ./harp_scale_trainer q all --remove blowbends,drawbends

  Both modes listen and quiz allow an option '--display' with possible
  values of 'hole' and 'chart' to change how a recognized hole will be
  displayed.

  Some (display-)settings can also be changed while the program is
  running; type 'h' for details.


  The mode memo is a variation of quiz, which helps to memorize licks
  from a given set:

    ./harp_scale_trainer memo c

  for this to be useful, you need to create a file with your own licks;
  for more info see the initial error message.  (This mode will set the
  scale to all unconditionally.)


  Mostly for testing new scales, there is also a mode play:

    ./harp_scale_trainer play c blues

    ./harp_scale_trainer play c 1 -2 c4

  which can play either a complete scale or the holes or notes given on
  the commandline.


  Once in the lifetime of your c-harp you need to calibrate the trainer
  for the frequencies of the harp you are using:

    ./harp_scale_trainer calibrate c
    
  this will ask you to play notes on your harp. The samples will be
  stored in the hidden folder .#{File.basename($0)} within your home
  directory; frequencies will be extracted to the file frequencies.yaml.

  This command does not need a scale-argument.

  For quick (but possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -3//'.


Notes:

  The possible scales depend on the chosen type of harmonica:
  #{types_content}

  For modes 'listen' and 'quiz' you may choose to transpose the scale to
  another key: '--transpose_scale_to d'. This would be helpful, if you
  want to practice e.g. the d-major scale on a chromatic harmonica of key
  c. For a diatonic harmonica, however, your milage may vary, as not all
  notes are available.

  Modes, that play notes (usually one second) accept the option '--fast'
  to play them for half a second only.

  Most arguments and options can be abreviated, e.g 'l' for 'listen' or
  'cal' for 'calibrate'.

  Finally there are some less used options: --ref, --debug,
  --screenshot, --help, --testing


Suggested reading: The toplevel file README.org

Copyright (c) 2021-2022 by Marc Ihm.
This program is subject to the MIT License.

EOU

  # extract options from ARGV
  # first process all options commonly
  opts = Hash.new
  opts_with_args = [:hole, :comment, :display, :transpose_scale_to, :ref, :merge, :remove]
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

  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}" if ARGV.length > 0 && mode != :play
  $err_binding = nil
  
  # late option processing depending on mode
  # check for invalid combinations of mode and options
  [[:loop, [:quiz, :memorize]], [:immediate, [:quiz, :memorize]], [:remove, [:listen, :quiz, :memorize]], [:merge, [:listen, :quiz, :memorize]], [:no_add, [:listen, :quiz, :memorize]], [:auto, [:calibrate]], [:comment, [:listen, :quiz, :memorize]], [:comment, [:play, :quiz, :memorize]]].each do |o_m|
    err "Option '--#{o_m[0]}' is allowed for modes '#{o_m[1]}' only" if opts[o_m[0]] && !o_m[1].include?(mode)
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
