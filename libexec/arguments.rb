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

  # source of mode, type, scale, key for better diagnostic
  $source_of = {mode: nil, type: nil, key: nil, scale: nil}

  # get mode
  err "Mode 'memorize' is now 'licks'; please change your first argument" if ARGV[0] && 'memorize'.start_with?(ARGV[0])
  $mode = mode = match_or(ARGV[0], $early_conf[:modes]) do |none, choices|
    err "First argument can be one of #{choices}, not #{none}.\n\n    Please invoke without argument for general usage information !\n\n(note, that mode 'develop' is only useful for the maintainer or developer of harpwise.)"
  end.to_sym
  ARGV.shift
  num_args_after_mode = ARGV.length

  # needed for other modes too
  $for_usage = "Invoke 'harpwise #{mode}' for usage information specific for mode '#{mode}' or invoke without any arguments for more general usage"


  #
  # Process options
  #
  
  opts = Hash.new
  # will be enriched with descriptions and arguments below
  modes2opts = 
    [[Set[:calibrate, :listen, :quiz, :licks, :play, :print, :report, :develop, :tools], {
        debug: %w(--debug),
        help: %w(-h --help -? --usage)}],
     [Set[:calibrate, :listen, :quiz, :licks, :play, :print, :report], {
        screenshot: %w(--screenshot)}],
     [Set[:listen, :quiz, :licks, :tools, :print], {
        add_scales: %w(-a --add-scales ),
        ref: %w(-r --reference ),
        remove_scales: %w(--remove-scales),
        no_add_holes: %w(--no-add-holes)}],
     [Set[:listen, :quiz, :licks], {
        display: %w(-d --display),
        comment: %w(-c --comment)}],
     [Set[:listen, :quiz, :licks, :develop], {
        time_slice: %w(--time-slice)}],
     [Set[:quiz, :play, :licks], {
        fast: %w(--fast),
        no_fast: %w(--no-fast)}],
     [Set[:quiz, :licks], {
        immediate: %w(--immediate),
        no_progress: %w(--no-progress),
        :loop => %w(--loop),
        no_loop: %w(--no-loop)}],
     [Set[:listen, :quiz], {
        transpose_scale_to: %w(--transpose-scale-to)}],
     [Set[:calibrate], {
        auto: %w(--auto),
        hole: %w(--hole)}],
     [Set[:print, :report], {
        terse: %w(--terse)}],
     [Set[:licks, :play], {
        holes: %w(--holes),
        iterate: %w(--iterate),
        reverse: %w(--reverse),
        start_with: %w(-s --start-with)}],
     [Set[:licks, :report, :play, :print], {
        tags_any: %w(-t --tags-any),
        tags_all: %w(--tags-all),
        no_tags_any: %w(-nt --no-tags-any),
        no_tags_all: %w(--no-tags-all),
        max_holes: %w(--max-holes),
        min_holes: %w(--min-holes),
      }],
     [Set[:licks], {
        partial: %w(-p --partial)}]]

  double_sets = modes2opts.map {|m2o| m2o[0]}
  double_sets.uniq.each do |del|
    double_sets.delete_at(double_sets.index(del))
  end
  fail "Internal error; at least one set of modes appears twice: #{double_sets}" unless double_sets.length == 0

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

  # now, that we have the mode, we can finish $conf by promoting values
  # from the active mode-section to toplevel
  $conf[:any_mode].each {|k,v| $conf[k] = v}
  mode_for_conf = $conf_meta[:sections_aliases][mode] || mode
  if $conf_meta[:sections].include?(mode_for_conf)
    $conf[mode_for_conf].each {|k,v| $conf[k] = v}
  end
  
  # preset some options from config (maybe overriden later)
  $conf_meta[:keys_for_modes].each do |k|
    if opts_all[k]
      opts[k] ||= $conf[k]
    end
  end
  opts[:time_slice] ||= $conf[:time_slice]

  # match command-line arguments one after the other against available
  # options; use loop index (i) but also remove elements from ARGV
  i = 0
  while i < ARGV.length do
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
      # this is not an option, so process it later
      i += 1
    else
      # exact match, so put into hash of options
      osym = matching.keys[0]
      odet = opts_all[matching.keys[0]]
      ARGV.delete_at(i)
      if odet[1]
        opts[osym] = ARGV[i] || err("Option #{odet[0][-1]} (#{ARGV[i]}) requires an argument, but none is given; #{$for_usage}")
        # convert options as described for configs
        opts[osym] = opts[osym].send($conf_meta[:conversions][osym] || :num_or_str) unless [:ref, :hole, :partial].include?(osym)
        ARGV.delete_at(i)
      else
        opts[osym] = true
      end
    end
  end  ## loop over argv

  # clear options with special value '-'
  opts.each_key {|k| opts[k] = nil if opts[k] == '-'}
  
  #
  # Special handling for some options
  #
  opts[:display] = match_or(opts[:display]&.o2str, $display_choices.map {|c| c.o2str}) do |none, choices|
    err "Option '--display' (or config 'display') needs one of #{choices} as an argument, not #{none}; #{$for_usage}"
  end&.o2sym
  
  opts[:comment] = match_or(opts[:comment]&.o2str, $comment_choices[mode].map {|c| c.o2str}) do |none, choices|
    err "Option '--comment' needs one of #{choices} as an argument, not #{none}; #{$for_usage}"
  end&.o2sym
  
  if opts[:max_holes]
    err "Option '--max-holes' needs an integer argument, not '#{opts[:max_holes]}'; #{$for_usage}" unless opts[:max_holes].to_s.match?(/^\d+$/)
    opts[:max_holes] = opts[:max_holes].to_i
  end
    
  if opts[:min_holes]
    err "Option '--min-holes' needs an integer argument, not '#{opts[:min_holes]}'; #{$for_usage}" unless opts[:min_holes].match?(/^\d+$/)
    opts[:min_holes] = opts[:min_holes].to_i
  end

  opts[:fast] = false if opts[:no_fast]
  opts[:loop] = false if opts[:no_loop]

  if opts[:transpose_scale_to]
    err "Option '--transpose_scale_to' can only be one on #{$conf[:all_keys].join(', ')}, not #{opts[:transpose_scale_to]}; #{$for_usage}" unless $conf[:all_keys].include?(opts[:transpose_scale_to])
    opts[:add_scales] = nil
  end

  opts[:time_slice] = match_or(opts[:time_slice], ['short', 'medium', 'long']) do |none, choices|
    err "Value #{none} of option '--time-slice' or config 'time_slice' is none of #{choices}"
  end.to_sym

  opts[:partial] = '0@b' if opts[:partial] == '0'

  if opts_all[:iterate]
    %w(random cycle).each do |choice|
      opts[:iterate] = choice.to_sym if opts[:iterate] && choice.start_with?(opts[:iterate])
    end
    opts[:iterate] ||= :random
    err "Option '--iterate' only accepts values 'random' or 'cycle', not '#{opts[:iterate]}'" if opts[:iterate].is_a?(String)
  end
  
  if opts[:help] || num_args_after_mode == 0
    print_usage_info(mode, opts_all) 
    exit 1
  end

  # used to issue current state of processing in error messages
  $err_binding = binding

  #
  # Now ARGV does not contain any options; process remaining non-option arguments

  # Mode has already been taken first, so we take type and key, by
  # recognising it among other args by their content; then we process the
  # scale, which is normally the only remaining argument.
  #


  # In any case, mode quiz requires a numeric argument right after the
  # mode-argument; so process it even before type and key

  if mode == :quiz
    $num_quiz = ARGV[0].to_i
    if $num_quiz.to_s != ARGV[0] || $num_quiz < 1
      err "Argument after mode 'quiz' must be an integer starting at 1, not '#{ARGV[0]}'; #{$for_usage}"
    end
    ARGV.shift
  end


  # type and key are taken from front of args only if they match the
  # predefined set of choices; otherwise they come from config

  type = nil
  if ARGV.length > 0 && ARGV[0].length > 1
    type = $conf[:all_types].find {|c| c == ARGV[0]}
    type ||= $conf[:all_types].find {|c| c.start_with?(ARGV[0])}
  end
  if type
    ARGV.shift
  else
    type = $conf[:type]
    $source_of[:type] = 'config'
  end
  $type = type
  
  # prefetch some musical config before they are set regularly (in
  # processing of config)
  
  all_scales = scales_for_type($type)
  # string below duplicates the definition of $holes_file
  all_holes = yaml_parse("#{$dirs[:install]}/config/#{$type}/holes.yaml").keys
  

  # check for unprocessed args, that look like options and are not holes
  
  other_opts = ARGV.select {|arg| arg.start_with?('-') && !all_holes.include?(arg)}
  err("Unknown options: #{other_opts.join(',')}; #{$for_usage}") if other_opts.length > 0 


  # Handle special cases; e.g convert / swap 'harpwise tools transpose c g'
  #                                     into 'harpwise tools c transpose g'
  #  or     'harpwise tools chart c'
  #  into   'harpwise tools c chart'
  #
  # The mode (tools) has already been removed from ARGV
  if mode == :tools && $conf[:all_keys].include?(ARGV[1]) &&
     ( ARGV.length >= 3 && 'transpose'.start_with?(ARGV[0]) && $conf[:all_keys].include?(ARGV[2]) ||
       ARGV.length >= 2 && 'chart'.start_with?(ARGV[0]) && !$conf[:all_keys].include?(ARGV[0]))
    ARGV[0], ARGV[1] = [ARGV[1], ARGV[0]]
  end

  # Handle special case: convert 'harpwise play pitch g'
  #                         into 'harpwise play g pitch'
  # The mode (play) has already been removed from ARGV
  if mode == :play && $conf[:all_keys].include?(ARGV[1]) &&
     ARGV.length >= 2 && 'pitch'.start_with?(ARGV[0])
    ARGV[0], ARGV[1] = [ARGV[1], ARGV[0]]
  end

  # pick key
  key = ARGV.shift if $conf[:all_keys].include?(ARGV[0])
  if !key
    key = $conf[:key]
    $source_of[:key] = 'config'
  end
  check_key_and_set_pref_sig(key)
  

  # For modes play and report, all the remaining arguments (after processing
  # type and key) are things to play or keywords; a scale is not allowed,
  # so we do this before processing the scale

  if [:play, :report, :develop].include?(mode)
    to_handle = []
    to_handle << ARGV.shift while !ARGV.empty?
  end

  
  # Get scale which must be the only remaining argument (if any);
  # modes that do not need a scale get scale 'all'
  case mode
  when :listen, :quiz, :licks
    scales, holes = partition_into_scales_and_holes(ARGV, all_scales, all_holes)
    ARGV.clear
    if scales.length > 0
      scale = get_scale_from_sws(scales[0])
    elsif holes.length > 0
      scale = get_scale_from_sws('adhoc:h')
      $adhoc_holes = holes
    else
      scale = get_scale_from_sws($conf[:scale])
      $source_of[:scale] = 'config'
    end
  when :tools
    # if the first remaining argument looks like a scale, take it as such
    scale = get_scale_from_sws(ARGV[0], true)
    if scale
      ARGV.shift
    else
      scale = get_scale_from_sws('all:a')
      $source_of[:scale] = 'implicit'
    end
  when :print
    # if there are two args and the first remaining argument looks like a
    # scale, take it as such
    scale = get_scale_from_sws(ARGV[0], true) if ARGV.length > 1
    if scale
      ARGV.shift
    else
      scale = get_scale_from_sws('all:a')
      $source_of[:scale] = 'implicit'
    end
  when :play, :print, :report, :develop, :tools
    scale = get_scale_from_sws('all:a')
    $source_of[:scale] = 'implicit'
  when :calibrate
    err("Mode 'calibrate' does not need a scale argument; can not handle: #{ARGV[0]}#{not_any_source_of}; #{$for_usage}") if ARGV.length == 1 && all_scales.include?(ARGV[0])
    scale = get_scale_from_sws('all:a')
    $source_of[:scale] = 'implicit'
  else
    fail "Internal error"
  end
  
  err "Given scale '#{scale}' is none of the known scales for type '#{type}': #{scales_for_type(type)}; #{$for_usage}" unless !$scale || scales_for_type(type).include?(scale)

  # now, as a possible scale argument has been recognized, all the rest is
  # to handle for mode tools or print; others see above
  if [:tools, :print].include?(mode)
    to_handle = []
    to_handle << ARGV.shift while !ARGV.empty?
  end

  
  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}#{not_any_source_of}; #{$for_usage}" if ARGV.length > 0
  $err_binding = nil

  # Commandline processing is complete here
  
  # some of these have already been set as global vars (e.g. for error
  # messages), but return them anyway to make their origin transparent
  [ mode, type, key, scale, opts, to_handle]
end


def get_scale_from_sws scale_w_short, graceful = false, added = false   # get_scale_from_scale_with_short
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
  return scale if scale == 'adhoc'
  
  match_or(scale, scales_for_type($type)) do |none, choices|
    if graceful
      nil
    else
      scale_glob = $scale_files_template % [$type, '*', '*']
      err "Scale (%s) must be one of #{choices}, i.e. scales matching #{scale_glob}; not #{none}%s" %
          if added
            ["given in option --add-scales or in configuration files",
             ", Hint: use '--add-scaless -' to ignore the value from the config-files"]
          else
            ['main scale', '']
          end
    end
  end
end


def get_used_scales scales_w_shorts
  scales = [$scale]
  if scales_w_shorts
    scales_w_shorts.split(',').each do |sws|
      sc = get_scale_from_sws(sws, false, true)
      scales << sc unless scales.include?(sc)
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
  types_with_scales = get_types_with_scales

  puts
  puts ERB.new(IO.read("#{$dirs[:install]}/resources/usage#{mode  ?  '_' + mode.to_s  :  ''}.txt")).result(binding).gsub(/\n+\Z/,'')
  
  if opts
    puts "\nAVAILABLE OPTIONS\n\n"
    nprinted = 0
    opts.values.each do |odet|
      next unless odet[2]
      nprinted += 1
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
    if nprinted == 0
      puts '  none'
    else
      puts "\n  Please note, that options, that you use on every invocation, may\n  also be put permanently into #{$early_conf[:config_file_user]}\n  And for selected invocations you may clear them again by using\n  the special value '-', e.g. '--add-scales -'"
    end
  end
  puts
end


def get_types_with_scales
  $conf[:all_types].map do |type|
    next if type == 'testing'
    txt = "scales for #{type}: "
    scales_for_type(type).each do |scale|
      txt += "\n    " if (txt + scale).lines[-1].length > 80
      txt += scale + ', '
    end
    txt.chomp(', ')
  end.compact.join("\n  ")
end


def partition_into_scales_and_holes args, all_scales, all_holes
  scales = Array.new
  holes = Array.new
  other = Array.new
  
  hint = "\n\n\e[2mHint: The commandline for modes listen, quiz and licks might contain a single scale or alternatively a set of holes, which then make up an adhoc-scale.\nScales are: #{all_scales}\nHoles are: #{all_holes}\e[0m"
  
  args.each do |arg|
    arg_woc = arg.gsub(/:.*/,'')
    err "Scale 'adhoc' is only the temporary name for the holes given on commandline; there is no such permanent scale however" if arg.downcase == 'adhoc'
    found = match_or(arg_woc, all_scales) do |none, choices, matches|
      err "Argument from commandline #{none} should be unique among the known scales, but it matches more than one: #{matches}#{hint}" if matches.length > 1
    end
    if found
      scales << found
    else
      found = all_holes.find {|x| x == arg}
      if found
        holes << found
      else
        other << arg
      end
    end
  end
  if other.length > 0
    err "Some arguments from commandline are neither scales nor holes: #{other}" +
        not_any_source_of + hint
  end
  err "Commandline specified scales (#{scales}) as well as holes (#{holes}); this cannot be handled#{hint}" if scales.length > 0 && holes.length > 0
  err "commandline contains more than one scale (#{scales}), but only one can be handled#{hint}" if scales.length > 1
  return scales, holes
end


def not_any_source_of
  not_any = $source_of.to_a.select {|x,y| y}.map {|x,y| x}.map(&:to_s)
  if not_any.length > 0
      " (and could not process it as #{not_any.join(', ')} either)"
  else
    ''
  end
end
