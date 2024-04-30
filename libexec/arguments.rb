# -*- fill-column: 74 -*-

#
# Parse arguments from commandline
#

def parse_arguments_early
  
  # General idea of processing commandline:
  #
  # We get the mode first, because set of available options depends on it.
  #  
  # Then we process all options.  Last come the remaining positional
  # arguments, which depend on the mode too, but are not only recognized
  # by the position, but by their content too.

  # produce general usage, if appropriate
  if ARGV.length == 0 || %w(-h --help -? ? help usage --usage).any? {|w| w.start_with?(ARGV[0])}
    initialize_extra_vars
    print_usage_info
    exit 0
  end
  
  # source of mode, type, scale, key for better diagnostic
  $source_of = {mode: nil, type: nil, key: nil, scale: nil, extra: nil}

  # get mode
  $mode = mode = match_or(ARGV[0], $early_conf[:modes]) do |none, choices|
    err "First argument can be one of #{choices}, not #{none}.\n\n    Please invoke without argument for general usage information !\n\n(note, that mode 'develop' is only useful for the maintainer or developer of harpwise.)"
  end.to_sym
  ARGV.shift
  num_args_after_mode = ARGV.length
  
  # needed for error messages
  $for_usage = "Invoke 'harpwise #{mode}' for usage information specific for mode '#{mode}' or invoke without any arguments for more general usage"


  #
  # Process options
  #
  
  opts = Hash.new
  # will be enriched with descriptions and arguments below
  modes2opts = 
    [[Set[:calibrate, :listen, :quiz, :licks, :play, :print, :develop, :tools], {
        debug: %w(--debug),
        help: %w(-h --help -? --usage),
        sharps: %w(--sharps),
        flats: %w(--flats),
        options: %w(--show-options -o)}],
     [Set[:calibrate, :listen, :quiz, :licks, :play, :print], {
        screenshot: %w(--screenshot)}],
     [Set[:listen, :quiz, :licks, :tools, :print], {
        add_scales: %w(-a --add-scales ),
        ref: %w(-r --reference ),
        remove_scales: %w(--remove-scales),
        no_add_holes: %w(--no-add-holes)}],
     [Set[:listen, :quiz, :licks], {
        display: %w(-d --display),
        comment: %w(-c --comment),
        read_fifo: %w(--read-fifo)}],
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
     [Set[:quiz], {
        difficulty: %w(--difficulty)}],
     [Set[:listen, :quiz, :play, :print], {
        transpose_scale: %w(--transpose-scale)}],
     [Set[:calibrate], {
        auto: %w(--auto),
        hole: %w(--hole)}],
     [Set[:print], {
        terse: %w(--terse)}],
     [Set[:listen, :print], {
        viewer: %w(--viewer)}],
     [Set[:licks, :play], {
        holes: %w(--holes),
        iterate: %w(--iterate),
        reverse: %w(--reverse),
        start_with: %w(-s --start-with)}],
     [Set[:licks, :play, :print, :tools], {
        tags_any: %w(--tags-any),
        tags_all: %w(-t --tags-all),
        no_tags_any: %w(-nt --no-tags-any),
        no_tags_all: %w(--no-tags-all),
        max_holes: %w(--max-holes),
        min_holes: %w(--min-holes)}],
     [Set[:play, :print], {
        scale_over_lick: %w(--scale-over-lick)}],
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
      fail "Internal error, not defined: opt2desc[#{osym}]" unless opt2desc[osym]
      opts_all[osym] << opt2desc[osym][1]
      opts_all[osym] << ( opt2desc[osym][0] && ERB.new(opt2desc[osym][0]).result(binding) )
    end
  end

  # now, that we have the mode, we can finish $conf by promoting values
  # from the active mode-section to toplevel
  $conf[:any_mode].each {|k,v| $conf[k] = v}
  if $conf_meta[:sections].include?(mode)
    $conf[mode].each {|k,v| $conf[k] = v}
  end
  
  # preset some options e.g. from config (maybe overriden later)
  $conf_meta[:keys_for_modes].each do |k|
    if opts_all[k]
      opts[k] ||= $conf[k]
    end
  end
  opts[:time_slice] ||= $conf[:time_slice]
  opts[:difficulty] ||= $conf[:difficulty]
  opts[:viewer] ||= $conf[:viewer]
  opts[:sharps_or_flats] ||= $conf[:sharps_or_flats]

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

  if opts && opts[:options]
    print_options opts_all
    exit 0
  end

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

  if opts[:viewer]
    vchoices = %w(none feh chafa)
    err "Option '--viewer' can be any of #{vchoices}, not '#{opts[:viewer]}'" unless vchoices.include?(opts[:viewer])
  else
    opts[:viewer] = 'none'
  end

  err "Options '--sharps' and '--flats' may not be given at the same time" if opts[:sharps] && opts[:flats]
  opts[:sharps_or_flats] = :flats if opts[:flats]
  opts[:sharps_or_flats] = :sharps if opts[:sharps]
  
  opts[:fast] = false if opts[:no_fast]
  opts[:loop] = false if opts[:no_loop]

  if opts[:transpose_scale]
    if opts[:transpose_scale].to_s.match?(/(\+|-)?\d+st/)
      opts[:transpose_scale] = opts[:transpose_scale].to_i
    elsif $conf[:all_keys].include?(opts[:transpose_scale])
      # do nothing
    else
      err "Option '--transpose_scale' can only be one on #{$conf[:all_keys].join(', ')} or a semitone value (e.g. 5st, -3st), not #{opts[:transpose_scale]}; #{$for_usage}"
    end
    opts[:add_scales] = nil
  end

  opts[:time_slice] = match_or(opts[:time_slice], %w(short medium long)) do |none, choices|
    err "Value #{none} of option '--time-slice' or config 'time_slice' is none of #{choices}"
  end.to_sym

  if opts[:difficulty].is_a?(Numeric)
    dicu = opts[:difficulty].to_i
    err "Percentage given for difficulty must be between 0 and 100, not #{dicu}" unless (0..100).include?(dicu)
    opts[:difficulty_numeric] = opts[:difficulty]
    opts[:difficulty] = (rand(100) > dicu ? 'easy' : 'hard')
  end
  opts[:difficulty] = match_or(opts[:difficulty], %w(easy hard)) do |none, choices|
    err "Value #{none} of option '--difficulty' or config 'difficulty' is none of #{choices} or a number between 0 and 100"
  end&.to_sym
  opts[:difficulty_numeric] ||= ( opts[:difficulty] == :easy ? 0 : 100 )
  
  opts[:partial] = '0@b' if opts[:partial] == '0'

  if opts_all[:iterate]
    %w(random cycle).each do |choice|
      opts[:iterate] = choice.to_sym if opts[:iterate] && choice.start_with?(opts[:iterate])
    end
    opts[:iterate] ||= :random
    err "Option '--iterate' only accepts values 'random' or 'cycle', not '#{opts[:iterate]}'" if opts[:iterate].is_a?(String)
  end

  # usage info specific for mode
  if opts[:help] || num_args_after_mode == 0
    print_usage_info mode
    exit 0
  end  

  # used to issue current state of processing in error messages
  $err_binding = binding

  #
  # Now ARGV does not contain any options; process remaining non-option arguments

  # Mode has already been taken first, so we take type and key, by
  # recognising it among other args by their content; then we process the
  # scale, which is normally the only remaining argument.
  #


  # type and key (further down below) are taken from front of args only if
  # they match the predefined set of choices; otherwise they come from
  # config

  type = ARGV.shift if $conf[:all_types].include?(ARGV[0])
  if !type
    type = $conf[:type]
    $source_of[:type] = 'config'
  end
  $type = type
  
  # prefetch a very small subset of musical config
  $all_scales, $harp_holes = read_and_set_musical_bootstrap_config
  
  # check for unprocessed args, that look like options and are neither holes not semitones  
  other_opts = ARGV.select do |arg|
    arg.start_with?('-') && !$harp_holes.include?(arg) && !arg.match?(/(\+|-)?\d+st/)
  end
  err("Unknown options: #{other_opts.join(',')}; #{$for_usage}") if other_opts.length > 0 


  # Handle special cases; e.g:
  #  convert / swap 'harpwise tools transpose c g'
  #            into 'harpwise tools c transpose g'
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

  # Get key
  key = ARGV.shift if $conf[:all_keys].include?(ARGV[0])
  if !key
    key = $conf[:key]
    $source_of[:key] = 'config'
  end
  err("Key can only be one of #{$conf[:all_keys].join(', ')}, not '#{key}'") unless $conf[:all_keys].include?(key)
  
  # Get scale
  case mode
  when :listen, :licks
    # these modes dont take an extra arg
    scales, holes = partition_into_scales_and_holes(ARGV, $all_scales, $harp_holes)
    ARGV.clear
    if scales.length > 0
      scale = get_scale_from_sws(scales[0])
    elsif holes.length > 0
      scale = get_scale_from_sws('adhoc:h')
      $adhoc_holes = holes
      $source_of[:scale] = 'adhoc'
    else
      scale = get_scale_from_sws($conf[:scale])
      $source_of[:scale] = 'config'
    end
  when :play, :print, :tools, :quiz
    # if the first remaining argument looks like a scale, take it as such
    scale = get_scale_from_sws(ARGV[0], true) if ARGV.length > 0
    if scale
      # for modes play and print: if the scale is our only argument, keep it for later
      # for mode tools: remove the recognized scale in any case
      #
      # These cases should all be treated as described:
      #   Take chord-i as scale-argument and print chord-iv and chord-v:
      #     harpwise print chord-i chord-iv chord-v
      #   Take chord-i as scale-argument and print it:
      #     harpwise print chord-i
      #   Take chord-i as scale-argument and show table of keys:
      #     harpwise tools chord-i keys
      ARGV.shift if ARGV.length > 1 || $mode == :tools
    else
      scale = get_scale_from_sws($conf[:scale] || 'all:a')
      $source_of[:scale] = 'implicit'
    end
  when :develop, :calibrate
    # no explicit scale, ever
    scale = get_scale_from_sws($conf[:scale] || 'all:a')
    $source_of[:scale] = 'implicit'
  else
    fail "Internal error"
  end
  
  $err_binding = nil

  # some of these have already been set as global vars (e.g. for error
  # messages), but return them anyway to make their origin transparent
  return [ mode, type, key, scale, opts]
end


def initialize_extra_vars 
  exfile = "#{$dirs[:install]}/resources/extra2desc.yaml"
  $extra_desc = yaml_parse(exfile).transform_keys!(&:to_sym)
  $extra_kws = Hash.new {|h,k| h[k] = Set.new}
  $extra_desc.each do |key, val|
    $extra_desc[key].each do |kk,vv|
      $extra_desc[key][kk] = ERB.new(vv).result(binding)
      $extra_desc[key][kk].lines.each do |l|
        err "Internal error: line from #{exfile} too long: #{l.length} >= #{$conf[:term_min_width] - 2}: '#{l}'" if l.length >= $conf[:term_min_width] - 2
        kk.split(',').map(&:strip).each {|k| $extra_kws[key] << k}
      end
    end
  end
  
  # check, that the names of those extra args do not collide with scales
  scales = scales_for_type($type)
  $extra_kws.each do |mode, extra|
    double = extra & scales
    err "Internal error: some scales for type #{$type} can also be extra arguments for mode #{mode}: #{double}\n\nScales:\n#{scales}\n\nExtra for #{mode}:\n#{extra}" if double.length > 0
  end

  $quiz_flavour2class = [QuizFlavour.subclasses - [QuizFlavourScales], QuizFlavourScales.subclasses].flatten.map do |subclass|
    [subclass.to_s.underscore.tr('_', '-'), subclass]
  end.to_h
  $quiz_flavours_meta = $extra_kws[:quiz].to_a - $quiz_flavour2class.keys
  $quiz_flavours_scales = QuizFlavourScales.subclasses.map {|c| c.to_s.underscore.tr('_', '-')}

end


def parse_arguments_late

  $amongs_play_or_print = if $opts[:scale_over_lick]
                            [:semi_note, :hole, :note, :scale, :lick, :last]
                          else
                            [:semi_note, :hole, :note, :lick, :scale, :last]
                          end

  $extra = nil
  okay = true
  if $extra_desc[$mode]
    if [:play, :print].include?($mode)
      what = recognize_among(ARGV[0], [$amongs_play_or_print, :extra])
      $extra = ARGV.shift if what == :extra
      if !what
        print_amongs($amongs_play_or_print, :extra)
        okay = false
      end
    else
      $extra = ARGV.shift if recognize_among(ARGV[0], :extra) == :extra
      if !$extra
        print_amongs(:extra)
        okay = false
      end
    end
  end
  if !okay
    err "Mode #{$mode} needs an argument from the list above" if ARGV.length == 0
    rem = ( $mode == :quiz  ?  "; you may also give 'choose'"  :  '' )
    err "First argument for mode #{$mode} should be one of those listed above, not '#{ARGV[0]}'#{rem}"
  end
  
  if [:play, :print, :quiz, :tools, :develop].include?($mode)
    to_handle = ARGV.clone
    ARGV.clear
  end

  # do these checks late, because we have more specific error messages before
  err "Cannot handle these arguments: #{ARGV}#{not_any_source_of}; #{$for_usage}" if ARGV.length > 0
  return to_handle
end


def get_scale_from_sws scale_w_short, graceful = false, added = false   # get_scale_from_scale_with_short
  scale = nil

  if md = scale_w_short.match(/^(.*?):(.*)$/)
    warn_if_double_short md[2], md[1]
    scale = md[1]
    $scale2short[md[1]] = md[2]
    $short2scale[md[2]] = md[1]
  else
    # $scale2short will be set when actually reading scale
    scale = scale_w_short
  end
  return scale if scale == 'adhoc'

  scales = scales_for_type($type)
  if scales.include?(scale)
    scale
  else
    if graceful
      nil
    else
      scale_glob = $scale_files_template % [$type, '*', '*']
      err "Scale (%s) must be one of #{scales}, i.e. scales matching #{scale_glob}; not #{scale}%s" %
          if added
            ["given in option --add-scales or in configuration files",
             ", Hint: use '--add-scales -' to ignore the value from the config-files"]
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


def print_usage_info mode = nil

  # get content of all harmonica-types to be inserted
  types_with_scales = get_types_with_scales

  puts
  puts ERB.new(IO.read("#{$dirs[:install]}/resources/usage#{mode  ?  '_' + mode.to_s  :  ''}.txt")).result(binding).gsub(/\n+\Z/,'')

  if $mode
    puts "\nCOMMANDLINE OPTIONS\n\n"
    puts "  For an extensive, mode-specific list type:\n\n    harpwise #{$mode} -o\n"
  end
  puts
end


def print_options opts
  puts "\nCommandline options for mode #{$mode}:\n\n"
  # check for maximum length; for performance, do this only on usage info (which is among tests)
  pieces = opt_desc_text(opts, false)
  pieces.join.lines.each do |line|
    err "Internal error: line from opt2desc.yml too long: #{line.length} >= #{$conf[:term_min_width]}: '#{line}'" if line.length >= $conf[:term_min_width] - 2
  end
  
  # now produce again (with color) and print
  pieces = opt_desc_text(opts)
  if pieces.length == 0
    puts '  none'
  else
    pieces.each {|p| print p}
    puts "\n  Please note, that options, that you use on every invocation, may\n  also be put permanently into #{$early_conf[:config_file_user]}\n  And for selected invocations you may clear them again by using\n  the special value '-', e.g. '--add-scales -'"
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


def opt_desc_text opts, with_color = true
  pieces = []
  opts.values.each do |odet|
    next unless odet[2]
    pieces << "\e[0m\e[32m" if with_color
    pieces << '  ' + odet[0].join(', ')
    pieces << ' ' + odet[1] if odet[1]
    pieces << "\e[0m" if with_color
    pieces << ' : '
    lines = odet[2].chomp.lines
    pieces << lines[0]
    lines[1..-1].each {|l| pieces << '    ' + l}
    pieces << "\n"
  end
  return pieces
end
