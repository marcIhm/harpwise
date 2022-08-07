# -*- fill-column: 74 -*-

#
# Parse arguments from commandline
#

def parse_arguments

  # General idea of processing commandline:
  #
  # We get the mode first, because set of available options depends on it.
  #  
  # Then we process all options.  Last come the remaining positional
  # arguments, which depend on the mode too, but are not only recognized
  # by the position, but by their content too.

  # produce general usage, if appropriate
  if ARGV.length == 0 || %w(-h --help -? ? help usage --usage).any? {|w| w.start_with?(ARGV[0])}
    print_usage_info
    exit
  end
  # get mode
  err "Mode 'memorize' is now 'licks'; please change your first argument" if ARGV[0] && 'memorize'.start_with?(ARGV[0])
  $mode = mode = match_or(ARGV[0], %w(listen quiz licks play report calibrate)) do |none, choices|
    err "First argument can be one of #{choices}, not #{none}; invoke without argument for general usage information"
  end.to_sym
  ARGV.shift
  for_usage = "Invoke with single argument '#{mode}' for usage information specific for this mode or invoke without any arguments for more general usage"


  #
  # Process options
  #
  
  opts = Hash.new
  # defaults from config
  opts[:fast] = $conf[:play_holes_fast]

  # will be enriched with descriptions and arguments below
  modes2opts = 
    [[Set[:calibrate, :listen, :quiz, :licks, :play, :report], {
        debug: %w(--debug),
        testing: %w(--testing),
        screenshot: %w(--screenshot),
        help: %w(-h --help -? --usage)}],
     [Set[:listen, :quiz, :licks], {
        add_scales: %w(-a --add-scales ),
        remove_scales: %w(--remove-scales),
        no_add_holes: %w(--no-add-holes),
        ref: %w(-r --ref ),
        display: %w(-d --display),
        comment: %w(-c --comment)}],
     [Set[:quiz, :play], {
        fast: %w(--fast),
        no_fast: %w(--no-fast)}],
     [Set[:quiz, :licks], {
        immediate: %w(--immediate),
        no_progress: %w(--no-progress),
        loop: %w(--loop)}],
     [Set[:listen, :quiz], {
        transpose_scale_to: %w(--transpose_scale_to)}],
     [Set[:calibrate], {
        auto: %w(--auto),
        hole: %w(--hole)}],
     [Set[:licks, :play], {
        holes: %w(--holes)}],
     [Set[:licks, :play, :report], {
        tags_any: %w(-t --tags-any),
        tags_all: %w(--tags-all),
        no_tags_any: %w(-nt --no-tags-any),
        no_tags_all: %w(--no-tags-all),
        max_holes: %w(--max-holes),
        min_holes: %w(--min-holes),
      }],
     [Set[:licks], {
        start_with: %w(-s --start-with),
        partial: %w(-p --partial)}]]

  all_sets = modes2opts.map {|m2o| m2o[0]}
  fail 'Internal error; at least one set of modes appears twice' unless all_sets.uniq.length == all_sets.length

  # construct hash opts_all with options specific for mode; take
  # descriptions from file with embedded ruby
  opt2desc = yaml_parse("#{$dirs[:install]}/resources/opt2desc.yaml").transform_keys!(&:to_sym)
  opts_all = Hash.new
  oabbr2osym = Hash.new {|h,k| h[k] = Array.new}
  modes2opts.each do |modes, opts|
    next unless modes.include?(mode)
    opts.each do |osym, oabbrevs|
      oabbrevs.each do |oabbr|
        oabbr2osym[oabbr] << osym
        fail "Internal error: option '#{oabbr}' belongs to multiple options: #{oabbr2osym[oabbr]}" if oabbr2osym[oabbr].length > 1
      end
      fail "Internal error #{osym} cannot be added twice to options" if opts_all[osym]
      opts_all[osym] = [oabbrevs]
      opts_all[osym] << opt2desc[osym][1]
      opts_all[osym] << ( opt2desc[osym][0] && ERB.new(opt2desc[osym][0]).result(binding) )
    end
  end

  # match command-line arguments one after the other against available
  # options; use loop index (i) but also remove elements from ARGV
  i = 0
  while i<ARGV.length do
    unless ARGV[i].start_with?('-')
      i += 1
      next
    end
    matching = Hash.new {|h,k| h[k] = Array.new}
    opts_all.each do |osym, odet|
      odet[0].each do |ostr|
        matching[osym] << ostr if ostr.start_with?(ARGV[i])
      end
    end

    if matching.keys.length > 1
      err "Argument '#{ARGV[i]}' matches multiple options (#{matching.values.flatten.join(', ')}); please be more specific"
    elsif matching.keys.length == 0
      if mode != :play && mode != :report
         err "Argument '#{ARGV[i]}' matches none of the available options (#{opts_all.values.map {|od| od[0]}.flatten.join(', ')}); #{for_usage}"
       else
         i += 1
       end
    else
      # put into central hash of options
      osym = matching.keys[0]
      odet = opts_all[matching.keys[0]]
      ARGV.delete_at(i)
      if odet[1]
        opts[osym] = ARGV[i] || err("Option #{odet[0][-1]} (#{ARGV[i]}) requires an argument, but none is given; #{for_usage}")
        ARGV.delete_at(i)
      else
        opts[osym] = true
      end
    end
  end

  
  #
  # Special handling for some options
  #
  
  opts[:display] = match_or(opts[:display], $display_choices.map {|c| c.to_s.gsub('_','-')}) do |none, choices|
    err "Option '--display' needs one of #{choices} as an argument, not #{none}; #{for_usage}"
  end
  opts[:display]&.gsub!('-','_')
  
  if opts[:max_holes]
    err "Option '--max-holes' needs an integer argument, not '#{opts[:max_holes]}'; #{for_usage}" unless opts[:max_holes].to_s.match?(/^\d+$/)
    opts[:max_holes] = opts[:max_holes].to_i
  end
    
  if opts[:min_holes]
    err "Option '--min-holes' needs an integer argument, not '#{opts[:min_holes]}'; #{for_usage}" unless opts[:min_holes].match?(/^\d+$/)
    opts[:min_holes] = opts[:min_holes].to_i
  end
    
  opts[:fast] = false if opts[:no_fast]

  err "Option '--transpose_scale_to' can only be one on #{$conf[:all_keys].join(', ')}, not #{opts[:transpose_scale_to]}; #{for_usage}" unless $conf[:all_keys].include?(opts[:transpose_scale_to]) if opts[:transpose_scale_to]

  opts[:partial] = '0@b' if opts[:partial] == '0'

  if opts[:help] || ARGV.length == 0
    print_usage_info(mode, opts_all) 
    exit 1
  end

  # used to issue current state of processing in error messages
  $err_binding = binding

  #
  # Now ARGV does not contain any options; process remaining non-option arguments

  # Mode has already been takne first, so we take type and key, by
  # recognising it among other args by their content; then we process the
  # scale, which is normally the only remaining argument.
  #

  opts[:comment] = match_or(opts[:comment], $comment_choices[mode].map {|c| c.to_s.gsub('_','-')}) do |none, choices|
    err "Option '--comment' needs one of #{choices} as an argument, not #{none}; #{for_usage}"
  end
  opts[:comment] = opts[:comment].gsub!('-','_').to_sym if opts[:comment]
  
  # check for unprocessed args, that look like options
  other_opts = ARGV.select {|arg| arg.start_with?('-')}
  err("Unknown options: #{other_opts.join(',')}; #{for_usage}") if other_opts.length > 0 && mode != :play && mode != :report


  # In any case, mode quiz requires a numeric argument right after the
  # mode-argument; so process it even before type and key

  if mode == :quiz
    $num_quiz = ARGV[0].to_i
    if $num_quiz.to_s != ARGV[0] || $num_quiz < 1
      err "Argument after mode 'quiz' must be an integer starting at 1, not '#{ARGV[0]}'; #{for_usage}"
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


  # For modes play and report, all the remaining arguments (after processing
  # type and key) are things to play or keywords; a scale is not allowed,
  # so we do this before processing the scale

  if mode == :play || mode == :report
    to_handle = []
    to_handle << ARGV.shift while !ARGV.empty?
  end

  
  # Get scale which must be the only remaining argument (if any);
  # modes that do not need a scale get scale 'all'

  case mode
  when :listen, :quiz
    err("Mode '#{mode}' needs at least one argument for scale; #{for_usage}") if ARGV.length == 0
    scale = get_scale_from_sws(ARGV.shift)
  when :licks
    if ARGV.length > 0
      scale = get_scale_from_sws(ARGV.shift)
    else
      scale = get_scale_from_sws('all:A')
    end
  when :play, :report
    scale = get_scale_from_sws('all:A')
  when :calibrate
    err("Mode 'calibrate' does not need a scale argument; can not handle: #{ARGV[0]}; #{for_usage}") if ARGV.length > 0
    scale = get_scale_from_sws('all:A')
  else
    fail "Internal error"
  end
  
  err "Given scale '#{scale}' is none of the known scales for type '#{type}': #{scales_for_type(type)}; #{for_usage}" unless !$scale || scales_for_type(type).include?(scale)
  
  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}; #{for_usage}" if ARGV.length > 0 && mode != :play && mode != :licks
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
  [ mode, type, key, scale, opts, to_handle]
end


def get_scale_from_sws scale_w_short   # get_scale_from_scale_with_short
  scale = nil

  if md = scale_w_short.match(/^(.*?):(.*)$/)
    scale = md[1]
    $scale2short[md[1]] = md[2]
    err($scale2short_err_text % [md[2], $short2scale[md[2]], md[1]]) if $short2scale[md[2]]
    $short2scale[md[2]] = md[1]
  else
    # $scale2short will be set when actually reading scale
    scale = scale_w_short
  end

  match_or(scale, scales_for_type($type)) do |none, choices|
    err "Scale must be one of #{choices}, not #{none}"
  end
end


def get_all_scales scales_w_shorts
  scales = [$scale]
  if scales_w_shorts
    scales_w_shorts.split(',').each do |sws|
      scales << get_scale_from_sws(sws)
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


def print_usage_info mode = nil, opts = nil
  # get content of all harmonica-types to be inserted
  types_content = $conf[:all_types].map do |type|
    txt = "scales for #{type}: "
    scales_for_type(type).each do |scale|
      txt += "\n    " if (txt + scale).lines[-1].length > 80
      txt += scale + ', '
    end
    txt.chomp(', ')
  end.join("\n  ")

  puts
  puts ERB.new(IO.read("#{$dirs[:install]}/resources/usage#{mode  ?  '_' + mode.to_s  :  ''}.txt")).result(binding).chomp
  
  if opts
    puts "\nAVAILABLE OPTIONS\n\n"  
    opts.values.each do |odet|
      next unless odet[2]
      print "\e[0m\e[32m"
      print '  ' + odet[0].join(', ')
      print(' ' + odet[1]) if odet[1]
      print "\e[0m"
      print ' : '
      lines = odet[2].chomp.lines
      print lines[0]
      lines[1..-1].each {|l| print '    ' + l}
      puts
    end
  end
  puts
end
