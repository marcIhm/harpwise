# -*- fill-column: 78 -*-

#
# Parse arguments from commandline
#

def parse_arguments
  
  usage = <<EOU


Help to practice scales (e.g. blues or major pentatonic) on a diatonic
harmonica for various keys. Regular modes of operation are 'listen' and
'quiz'.


Usage by examples: 


  Listen to your playing and show the note green from the scale; harp is of
  key c, scale is major pentatonic:

    ./harp_scale_trainer listen c ma

  Add option '--comment interval' (or '-c i') to show intervals instead of
  notes.


  Play 3 notes from the scale and quiz you to play them back (then repeat);
  scale is blues:

    ./harp_scale_trainer quiz 3 a blues

  Add option '--loop' (or '-l') to loop over sequence until you type 'RET'.



  Once in a lifetime of your c-harp you need to calibrate this program to its
  frequencies:

    ./harp_scale_trainer calibrate c
    

  this will ask you to play notes on your harp. The samples will be stored in
  folder samples and frequencies will be extracted to file frequencies.json.
  This command does not need a scale-argument.

  For quick (and possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -2+3'.


Notes:


  The last one or two arguments in all examples above are the key of the harp
  (e.g. c or a) and the scale, e.g. blues or mape (for major pentatonic),
  respectively.

  Most arguments and options can be abreviated, e.g 'l' for 'listen' or 'cal'
  for 'calibrate'.

  Some more less used options: --debug, --screenshot, --help

EOU

  # extract options from ARGV
  # first process all options commonly
  opts = Hash.new
  opts_with_args = [:debug, :hole, :comment]
  { %w(-d --debug) => :debug,
    %w(-s --screenshot) => :screenshot,
    %w(-h --help) => :help,
    %w(--auto) =>:auto,
    %w(--hole) => :hole,
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
  if opts[:debug]
    err_h "Option '--debug' needs an integer argument, not '#{opts[:debug]}" unless opts[:debug].match? /\A\d+\z/
    opts[:debug] = opts[:debug].to_i
  end
  opts[:debug] = 0 unless opts[:debug]
  if opts[:comment]
    %w(note interval).each {|val| opts[:comment] = val.to_sym if val.start_with?(opts[:comment])}
    err_h "Option '--comment' needs either 'note' or 'interval' as an argument not #{opts[:comment]}" unless opts[:comment].is_a?(Symbol)
  end
  # see end of function for final processing of options

  # now ARGV does not contain any more options; process non-option arguments
  ARGV.select {|arg| arg.start_with?('-')}.tap {|left| err_h "Unknown options: #{left.join(',')}" if left.length > 0}

  if ARGV.length == 0 || opts[:help]
    puts usage
    exit 1
  end

  mode = :listen if 'listen'.start_with?(ARGV[0])
  mode = :quiz if 'quiz'.start_with?(ARGV[0])
  mode = :calibrate if 'calibrate'.start_with?(ARGV[0])

  if ![:listen, :quiz, :calibrate].include?(mode)
    err_h "First argument can be either 'listen', 'quiz' or 'calibrate', not '#{ARGV[0]}'"
  end

  # process remaining arguments according to mode
  # first find out, where the remaining arguments are
  if mode == :listen
    if ARGV.length == 3
      arg_for_key = ARGV[1]
      arg_for_scale = ARGV[2]
    else
      err_h "Need exactly two additional arguments (key and scale) for mode listen"
    end
  end
  
  if mode == :quiz
    if ARGV.length == 4
      arg_for_key = ARGV[2]
      arg_for_scale = ARGV[3]
    else
      err_h "Need exactly three additional arguments (count, key and scale) for mode 'quiz'"
    end
    $num_quiz = ARGV[1].to_i
    if $num_quiz.to_s != ARGV[1] || $num_quiz < 1
      err_h "Argument after mode 'q' must be a number starting at 1, not '#{ARGV[1]}'"
    end
  end

  if mode == :calibrate
    if ARGV.length == 2
      arg_for_key = ARGV[1]
      arg_for_scale = nil
    else
      err_h "Need exactly one additional argument (the key) for mode 'calibrate'"
    end
  end

  # process key and scale
  if arg_for_key
    allowed_keys = %w(a c)
    err_b "Key can only be one on #{allowed_keys.inspect}, not '#{arg_for_key}'" if !allowed_keys.include?(arg_for_key)
    key = arg_for_key.to_sym
  end

  if arg_for_scale
    allowed_scales = %w(blues mape)
    scale = allowed_scales.select do |scale|
      scale.start_with?(arg_for_scale)
    end.tap do |matches|
      err_b "Given scale '#{arg_for_scale}' matches none or multiple of #{allowed_scales.inspect}" if matches.length != 1
    end.first.to_sym
  end

  # late option processing depending on mode
  # check for invalid combinations of options and mode
  [[:loop, :quiz], [:auto, :calibrate], [:comment, :listen]].each do |o_m|
    err_h "Option '--#{o_m[0]}' is allowed for mode '#{o_m[1]}' only" if opts[o_m[0]] && mode != o_m[1]
  end

  # set some defaults
  opts[:comment] ||= :note
  
  
  [ mode, key, scale, opts]
end
