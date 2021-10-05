# -*- fill-column: 78 -*-

#
# Parse arguments from commandline
#

def parse_arguments

  # get content of all harmonica-types
  types_content = $conf[:all_types].map do |type|
    "#{type}:   " + %w(keys.json scales.json).map do |file_base|
      file_full = "config/#{type}/#{file_base}"
      begin
        "#{file_base[0..-6]} = " + JSON.parse(File.read(file_full)).keys.join(', ')
      rescue JSON::ParserError => e
        err_b "Cannot parse #{file_full}: #{e}"
      end
    end.join(';  ')
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
  notes.


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
  folder samples and frequencies will be extracted to file frequencies.json.
  This command does not need a scale-argument.

  For quick (and possibly inaccurate) calibration you may use the option
  '--auto' to generate and analyze all needed samples automatically.

  To calibrate only a single whole, add e.g. '--hole -3//'.


Notes:

  The possible value for the arguments for key and scale depend on the chosen
  type of harmonica:
  #{types_content}

  Most arguments and options can be abreviated, e.g 'l' for 'listen' or 'cal'
  for 'calibrate'.

  Finally there are some less used options: --debug, --screenshot, --help


Suggested reading: The section "A word on holes" from the toplevel README.org

EOU

  # extract options from ARGV
  # first process all options commonly
  opts = Hash.new
  opts_with_args = [:debug, :hole, :comment, :display]
  { %w(--debug) => :debug,
    %w(-s --screenshot) => :screenshot,
    %w(-h --help) => :help,
    %w(--auto) =>:auto,
    %w(--hole) => :hole,
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
  if opts[:debug]
    err_h "Option '--debug' needs an integer argument, not '#{opts[:debug]}" unless opts[:debug].match? /\A\d+\z/
    opts[:debug] = opts[:debug].to_i
  end
  opts[:debug] = 0 unless opts[:debug]

  opts[:comment] = match_or(opts[:comment], [:note, :interval, :hole]) do |none, choices|
    err_h "Option '--comment' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end

  opts[:display] = match_or(opts[:display], [:chart, :hole]) do |none, choices|
    err_h "Option '--display' needs one of #{choices} (maybe abbreviated) as an argument, not #{none}"
  end
  # see end of function for final processing of options

  # now ARGV does not contain any more options; process non-option arguments
  ARGV.select {|arg| arg.start_with?('-')}.tap {|left| err_h "Unknown options: #{left.join(',')}" if left.length > 0}

  if ARGV.length == 0 || opts[:help]
    puts usage
    exit 1
  end

  mode = match_or(ARGV[0], %w(listen quiz calibrate)) do |none, choices|
    err_h "First argument can be one of #{choices}, not #{none}"
  end.to_sym
  ARGV.shift

  # process remaining arguments according to mode
  # first find out, where the remaining arguments are
  if mode == :listen
    arg_for_type = ( ARGV.length >= 3 ) ? ARGV.shift : $conf[:type]
    arg_for_key = ( ARGV.length >= 2 ) ? ARGV.shift : $conf[:key]
    arg_for_scale = ARGV.shift
    err_h "Need arguments type, key and scale for mode 'listen'; type and in addition key can be omitted" unless ARGV.length == 0
  end
  
  if mode == :quiz
    arg_for_count = ARGV.shift
    arg_for_type = ( ARGV.length >= 3 ) ? ARGV.shift : $conf[:type]
    arg_for_key = ( ARGV.length >= 2 ) ? ARGV.shift : $conf[:key]
    arg_for_scale = ARGV.shift if ARGV.length >= 1
    err_h "Need arguments count, type, key and scale for mode 'quiz'; type and in addition key can be omitted" unless ARGV.length == 0
    $num_quiz = arg_for_count.to_i
    if $num_quiz.to_s != arg_for_count || $num_quiz < 1
      err_h "Argument after mode 'quiz' must be an integer starting at 1, not '#{arg_for_count}'"
    end
  end

  if mode == :calibrate
    arg_for_type = ( ARGV.length >= 2 ) ? ARGV.shift : $conf[:type]
    arg_for_key = ( ARGV.length >= 1 ) ? ARGV.shift : $conf[:key]
    arg_for_scale = nil
    err_h "Need arguments type and key for mode 'calibrate'; type and in addition key can be omitted" unless ARGV.length == 0
  end

  # process type first
  type = match_or(arg_for_type, $conf[:all_types]) do |none, choices|
    err_h "Type can be one of #{choices} only, not #{none}"
  end

  # extract possible keys and scales from respective files
  {'keys.json' => :all_keys, 'scales.json' => :all_scales}.each do |file_base, cfg_key|
    file_full = "config/#{type}/#{file_base}"
    begin
      $conf[cfg_key] = JSON.parse(File.read(file_full)).keys
    rescue JSON::ParserError => e
      err_b "Cannot parse #{file_full}: #{e}"
    end
  end

  # now we have the information to process key and scale
  key = match_or(arg_for_key, $conf[:all_keys]) do |none, choices|
    err_b "Key can only be one on #{choices}, not '#{none}'"
  end.to_sym

  if mode != :calibrate
    err_b "Need value for scale as one more argument" unless arg_for_scale
    scale = match_or(arg_for_scale, $conf[:all_scales]) do |none, choices|
      err_b "Given scale '#{none}' matches none or multiple of #{choices}"
    end.to_sym
  end


  # late option processing depending on mode
  # check for invalid combinations of options and mode
  [[:loop, [:quiz]], [:auto, [:calibrate]], [:comment, [:listen, :quiz]]].each do |o_m|
    err_h "Option '--#{o_m[0]}' is allowed for modes '#{o_m[1]}' only" if opts[o_m[0]] && !o_m[1].include?(mode)
  end

  # carry some options over into $conf
  $conf[:comment_listen] = opts[:comment] if opts[:comment]
  $conf[:display] = $conf["display_#{mode}".to_sym]
  $conf[:display] = opts[:display] if opts[:display]
  
  [ mode, type, key, scale, opts]
end


def match_or cand, choices
  return unless cand
  matches = choices.select {|c| c.start_with?(cand)}
  yield "'#{cand}'", choices.join(', ') unless matches.length == 1
  matches[0]
end
          
