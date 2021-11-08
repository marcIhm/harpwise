# -*- fill-column: 78 -*-

#
# Parse arguments from commandline
#

def parse_arguments

  # get content of all harmonica-types
  types_content = $conf[:all_types].map do |type|
    "scales for #{type}: " +
      Dir[$scale_files_template % [type, '*', '{holes,notes}']].map {|file| file2scale(file,type)}.sort.join(', ')
  end.join("\n  ")
  
  usage = <<EOU


Help to practice scales (e.g. blues or mape) for harmonicas of various types
(e.g. richter or chromatic) for various keys (e.g. a or c).  Main modes of
operation are 'listen' and 'quiz'.


Usage by examples: 


  Listen to you playing a richter harmonica of key c and show the notes
  played; green if from the scale, red otherwise:

    ./harp_scale_trainer listen ri c blues

  Add option '--comment interval' (or '-c i') to show intervals instead of
  notes; other possible values are 'note' and 'hole'.

  Switch on journal to get a simple transcription of the holes played.


  Play 3 notes from scale mape for a chromatic harmonica of key a and quiz you
  to play them back (then repeat):

    ./harp_scale_trainer quiz 3 chrom a mape

  Add option '--loop' (or '-l') to loop over sequence until you type 'RET'.


  In the examples above, the type of harmonica (e.g. richter or chromatic)
  and, in addition, the key (e.g. c or a) may be omitted and are then taken
  from the config; so

    ./harp_scale_trainer q 3 ma

  is valid as well.


  Both modes listen and quiz allow an option '--display' with possible values
  of 'hole' and 'chart' to change how a recognized will be displayed.


  Once in a lifetime of your c-harp you need to calibrate this program to the
  frequencies of your harp:

    ./harp_scale_trainer calibrate c
    
  this will ask you to play notes on your harp. The samples will be stored in
  the hidden folder .#{File.basename($0)} within your home directory;
  frequencies will be extracted to the file frequencies.yaml.

  This command does not need a scale-argument.

  For quick (and possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -3//'.


Notes:

  The possible scales depend on the chosen type of harmonica:
  #{types_content}

  For modes 'listen' and 'quiz' you may choose to transpose the scale to
  another key: '--transpose_scale_to d'. This would be helpful, if you want to
  practice e.g. the d-major scale on a chromatic harmonica of key c. For a
  diatonic harmonica, however, your milage may vary, as not all notes are
  available.

  Most arguments and options can be abreviated, e.g 'l' for 'listen' or 'cal'
  for 'calibrate'.

  Finally there are some less used options: --debug, --screenshot, --help, --testing


Suggested reading: The section "A word on holes" from the toplevel README.org

Copyright (c) 2021 by Marc Ihm. This program is subject to the MIT License.

EOU

  # extract options from ARGV
  # first process all options commonly
  opts = Hash.new
  opts_with_args = [:hole, :comment, :display, :transpose_scale_to]
  { %w(--debug) => :debug,
     %w(--testing) => :testing,
    %w(-s --screenshot) => :screenshot,
    %w(-h --help) => :help,
    %w(--auto) =>:auto,
    %w(--hole) => :hole,
    %w(--transpose_scale_to) => :transpose_scale_to,
    %w(-d --display) => :display,
    %w(-c --comment) => :comment,
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
    err_h "Option '--#{opt}' needs an argument" if opts.keys.include?(opt) && !opts[opt].is_a?(String)
  end

  # special processing for some options
  opts[:comment] = match_or(opts[:comment], $comment_choices) do |none, choices|
    err_h "Option '--comment' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end

  opts[:display] = match_or(opts[:display], [:chart, :hole]) do |none, choices|
    err_h "Option '--display' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end

  err_b "Option '--transpose_scale_to' can only be one on #{$conf[:all_keys].join(', ')}, not #{opts[:transpose_scale_to]}" unless $conf[:all_keys].include?(opts[:transpose_scale_to]) if opts[:transpose_scale_to]

  # see end of function for final processing of options

  # now ARGV does not contain any more options; process non-option arguments
  ARGV.select {|arg| arg.start_with?('-')}.tap {|left| err_h "Unknown options: #{left.join(',')}" if left.length > 0}

  if ARGV.length == 0 || opts[:help]
    puts usage
    exit 1
  end

  # General idea of argument processing: We take the mode, than other
  # arguments, we now for certain (knowing the mode) then key, by recognicing
  # it among other args by its content and then the rest.
  
  mode = match_or(ARGV[0], %w(listen quiz calibrate)) do |none, choices|
    err_h "First argument can be one of #{choices}, not #{none}"
  end.to_sym
  ARGV.shift

  if mode == :quiz
    $num_quiz = ARGV[0].to_i
    if $num_quiz.to_s != ARGV[0] || $num_quiz < 1
      err_h "Argument after mode 'quiz' must be an integer starting at 1, not '#{ARGV[0]}'"
    end
    ARGV.shift
  end

  if mode == :calibrate
    arg_for_scale = nil
  else
    arg_for_scale = ARGV.pop
    err_h "Need at least one argument for scale" unless arg_for_scale
  end
  if ARGV.length == 2
    arg_for_key = ARGV.pop if $conf[:all_keys].include?(ARGV[-1])
    arg_for_key = ARGV.shift if $conf[:all_keys].include?(ARGV[0])
    arg_for_type = ARGV.shift
  else
    arg_for_key =  ARGV.length > 0 &&  $conf[:all_keys].include?(ARGV[-1])  ?  ARGV.pop : $conf[:key]
    arg_for_type =  ARGV.length > 0  ?  ARGV.shift  :  $conf[:type] 
  end
    
  # process type first
  # set global vars here already for error messages
  $type = type = match_or(arg_for_type, $conf[:all_types]) do |none, choices|
    err_h "Type can be one of #{choices} only, not #{none}"
  end

  # now we have the information to process key and scale
  err_b "Key can only be one on #{$conf[:all_keys].join(', ')}, not #{arg_for_key}" unless $conf[:all_keys].include?(arg_for_key)
  $key = key = arg_for_key.to_sym

  if mode != :calibrate
    err_b "Need value for scale as one more argument" unless arg_for_scale
    glob = $scale_files_template % [type, arg_for_scale, '{holes,notes}']
    globbed = Dir[glob]
    # check for multiple files is in config.rb
    err_b "Unknown scale '#{arg_for_scale}' as there is no file matching #{glob}" unless globbed.length > 0
    $scale = scale = file2scale(globbed[0])
  end

  # do this check late, because we have more specific error messages before
  err_h "Cannot handle these arguments: #{ARGV}" if ARGV.length > 0

  # late option processing depending on mode
  # check for invalid combinations of options and mode
  [[:loop, [:quiz]], [:auto, [:calibrate]], [:comment, [:listen, :quiz]]].each do |o_m|
    err_h "Option '--#{o_m[0]}' is allowed for modes '#{o_m[1]}' only" if opts[o_m[0]] && !o_m[1].include?(mode)
  end

  # carry some options over into $conf
  $conf[:comment_listen] = opts[:comment] if opts[:comment]
  $conf[:display] = $conf["display_#{mode}".to_sym]
  $conf[:display] = opts[:display] if opts[:display]

  # some of these have already been set as global vars, but return them anyway
  # to make their origin transparent
  [ mode, type, key, scale, opts]
end
