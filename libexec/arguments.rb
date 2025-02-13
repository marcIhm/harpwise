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
  # arguments, which depend on the mode, but are not only recognized by
  # the position, but by their content too.

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
    err "First argument can be one of\n\n   #{choices}\n\nnot #{none}.\n\n   Please invoke without argument for general usage information.\n\n" +
        if $conf[:all_keys].include?(ARGV[0])
          "However your first argument '#{ARGV[0]}' is a key, which might be placed further right on the commandline, if you wish."
        else
          "\e[2m(note, that mode 'develop' is only useful for the maintainer or developer of harpwise.)\e[0m"
        end
  end.to_sym
  ARGV.shift
  num_args_after_mode = ARGV.length
  
  # needed for error messages
  $for_usage = "invoke 'harpwise #{mode}' for usage information specific for mode '#{mode}' or invoke without any arguments for more general usage."


  #
  # Process options
  #
  
  opts = Hash.new
  # will be enriched with descriptions and arguments below
  modes2opts = 
    [[Set[:samples, :listen, :quiz, :licks, :play, :print, :develop, :tools, :jamming], {
        debug: %w(--debug),
        help: %w(-h --help -? --usage),
        sharps: %w(--sharps),
        flats: %w(--flats),
        options: %w(--show-options -o)}],
     [Set[:samples, :listen, :quiz, :licks, :play, :print], {
        screenshot: %w(--screenshot)}],
     [Set[:listen, :quiz, :licks, :tools, :print], {
        add_scales: %w(-a --add-scales ),
        ref: %w(-r --reference ),
        remove_scales: %w(--remove-scales),
        no_add_holes: %w(--no-add-holes)}],
     [Set[:listen, :quiz, :licks], {
        display: %w(-d --display),
        comment: %w(-c --comment)}],
     [Set[:listen, :licks], {
        scale_prog: %w(--sc-prog --scale-prog --scale-progression),
        keyboard_translate: %w(--kb-tr --keyboard-translate),
        read_fifo: %w(--jamming --read-fifo)}],
     [Set[:listen, :licks, :play, :print], {
        # any mode that handles this option needs to make sure to reread licks
        lick_prog: %w(--li-prog --lick-prog --lick-progression)}],
     [Set[:listen], {
        no_player_info: %w(--no-player-info)}],
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
     [Set[:samples], {
        wave: %w(--wave)}],
     [Set[:print, :samples, :tools, :jamming], {
        terse: %w(-T --terse)}],
     [Set[:listen, :print, :quiz], {
        viewer: %w(--viewer)}],
     [Set[:licks, :play], {
        holes: %w(--holes),
        iterate: %w(-i --iterate),
        reverse: %w(--reverse),
        start_with: %w(-s --start-with)}],
     [Set[:licks, :play, :print, :tools], {
        tags_all: %w(-t --tags-all),
        tags_any: %w(--tags-any),
        drop_tags_all: %w(--drop-tags-all),
        drop_tags_any: %w(-dt --drop-tags-any),
        max_holes: %w(--max-holes),
        min_holes: %w(--min-holes)}],
     [Set[:play], {
        lick_radio: %w(--radio --lick-radio)}],
     [Set[:jamming], {
        paused: %w(--ps --paused),
        print_only: %w(--print-only)}],
     [Set[:licks], {
        fast_lick_switch: %w(--fast-lick-switch),
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
  oabbr2other_modes = Hash.new {|h,k| h[k] = Array.new}
  modes2opts.each do |modes, opts|
    if modes.include?(mode)
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
    else
      opts.each do |osym, oabbrevs|
        oabbrevs.each do |oabbr|
          oabbr2other_modes[oabbr].append(*modes)
        end
      end
    end
  end

  # now, that we have the mode, we can finish $conf by promoting values
  # from the active mode-section to toplevel
  $conf[:any_mode].each {|k,v| $conf[k] = v}
  if $conf_meta[:sections].include?(mode)
    $conf[mode].each {|k,v| $conf[k] = v}
  end
  
  # preset options from config (maybe overriden later)
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
    exact_match = nil
    opts_all.each do |osym, odet|
      odet[0].each do |ostr|
        matching[osym] << ostr if ostr.start_with?(ARGV[i])
        exact_match = osym if ostr == ARGV[i]
      end
    end

    if matching.keys.length > 1 && !exact_match
      err "Argument '#{ARGV[i]}' is the start of multiple options (#{matching.values.flatten.join(', ')}); please be more specific"
    elsif matching.keys.length == 0
      # this is not an option, so process it later
      i += 1
    else
      # single or exact match, so put into hash of options
      osym = exact_match || matching.keys[0]
      odet = opts_all[osym]
      ARGV.delete_at(i)
      if odet[1]
        opts[osym] = ARGV[i] || err("Option #{odet[0][-1]} requires an argument, but none is given; #{$for_usage}")
        # convert options as described for configs
        opts[osym] = opts[osym].send($conf_meta[:conversions][osym]) unless [:ref, :hole, :partial].include?(osym)
        ARGV.delete_at(i)
      else
        opts[osym] = true
      end
    end
  end  ## loop over argv

  # clear options with special value '-'
  opts.each_key {|k| opts[k] = nil if opts[k] == '-'}

  if $testing_what == :opts
    puts JSON.pretty_generate(opts)
    exit
  end

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
    err "Option '--min-holes' needs an integer argument, not '#{opts[:min_holes]}'; #{$for_usage}" unless opts[:min_holes].to_s.match?(/^\d+$/)
    opts[:min_holes] = opts[:min_holes].to_i
  end

  if opts[:viewer]
    if !$image_viewers.map {|vwr| vwr[:syn]}.flatten.include?(opts[:viewer])
      vwrs_desc = get_viewers_desc
      err "Option or config '--viewer' cannot be '#{opts[:viewer]}'; rather use any of:\n#{vwrs_desc}\n"
    else
      opts[:viewer] = $image_viewers.find {|vwr| vwr[:syn].include?(opts[:viewer])}[:syn][-1]
    end
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

  if opts[:difficulty] =~ /^\d+$/
    dicu = opts[:difficulty_numeric] = opts[:difficulty].to_i
    err "Percentage given for difficulty must be between 0 and 100, not #{dicu}" unless (0..100).include?(dicu)
    opts[:difficulty] = ( rand(100) > dicu  ?  'easy'  :  'hard' )
  end
  opts[:difficulty] = match_or(opts[:difficulty], %w(easy hard)) do |none, choices|
    err "Value #{none} of option '--difficulty' or config 'difficulty' is none of #{choices} or a number between 0 and 100"
  end&.to_sym
  opts[:difficulty_numeric] ||= ( opts[:difficulty] == :easy  ?  0  :  100 )
  
  opts[:partial] = '0@b' if opts[:partial] == '0'

  if opts_all[:iterate]
    %w(random cycle).each do |choice|
      opts[:iterate] = choice.to_sym if opts[:iterate] && choice.start_with?(opts[:iterate].to_s)
    end
    opts[:iterate] ||= :random
    err "Option '--iterate' only accepts values 'random' or 'cycle', not '#{opts[:iterate]}'" if opts[:iterate].is_a?(String)
  end

  if opts[:wave]
    opts[:wave] = match_or(opts[:wave], $all_waves) do |none, choices|
      err "Value #{none} of option '--wave' is none of #{choices}"
    end
  end
  opts[:wave] ||= $all_waves[0]

  opts[:no_player_info] = true if opts[:scale_prog]

  # parse mini-language for keyboard translations; guide with good error messages
  $keyboard_translations = parse_keyboard_translate(opts[:keyboard_translate])

  opts[:comment] = :lick_holes if opts[:licks] 

  # save them away, so we may later restore them
  $initial_tag_options = Hash.new
  [:tags_all, :tags_any, :drop_tags_all, :drop_tags_any, :iterate].each do |opt|
    $initial_tag_options[opt] = opts[opt]
  end
  
  # usage info specific for mode
  if opts[:help] || num_args_after_mode == 0
    print_usage_info mode
    exit 0
  end  

  # used to issue current state of processing in error messages
  $err_binding = binding

  # Now ARGV does not contain any options; process remaining non-option
  # arguments

  # Mode has already been taken first, so we take type and key, by
  # recognising them among other args by their content; then we process
  # the scale, which is normally the only remaining argument.

  # type and key (further down below) are taken from front of args only if
  # they match the predefined set of choices; otherwise they come from
  # config

  type = ARGV.shift if $conf[:all_types].include?(ARGV[0])
  if !type
    type = $conf[:type]
    $source_of[:type] = 'config'
  end
  $type = type
  
  # prefetch a very small subset of musical config; this is needed to
  # judge commandline arguments, e.g. scales
  $all_scales, $scale2file, $harp_holes, $all_scale_progs, $sc_prog2file, $holes_file =
  read_and_set_musical_bootstrap_config
  
  # check for unprocessed args, that look like options and are neither holes not semitones  
  looks_like_opts = ARGV.select do |arg|
    arg.start_with?('-') && !$harp_holes.include?(arg) && !arg.match?(/(\+|-)?\d+st/)
  end

  if looks_like_opts.length > 0
    puts
    not_for_any_mode = []
    but_for_mode = []
    looks_like_opts.each do |llo|
      if oabbr2other_modes[llo].length > 0
        but_for_mode << "    #{llo}  , for modes: #{oabbr2other_modes[llo].join(', ')}"
      else
        not_for_any_mode << "    #{llo}"
      end
    end
    if not_for_any_mode.length > 0
      puts "#{not_for_any_mode.length} options for mode #{$mode} that are unknown for any mode:"
      puts not_for_any_mode.join("\n")
      puts
    end
    if but_for_mode.length > 0
      puts "#{but_for_mode.length} options for mode #{$mode} that are unknown for this mode, but are known for other modes:"
      puts but_for_mode.join("\n")
    end
    err("#{looks_like_opts.length} unknown options: #{looks_like_opts.join(', ')}. See above for details; #{$for_usage}")
  end

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
  if mode == :play && ARGV[0] == 'pitch' && ARGV.length >= 2 &&
     $conf[:all_keys].include?(ARGV[1])
    ARGV[0], ARGV[1] = ARGV[1], ARGV[0]
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
  when :quiz
    scale = get_scale_from_sws(ARGV[0], true) if ARGV.length > 0
    if scale
      ARGV.shift
    else
      scale = get_scale_from_sws($conf[:scale] || 'all:a')
      $source_of[:scale] = 'implicit'
    end
  when :listen
    scale = get_scale_from_sws(ARGV[0], true) if ARGV.length > 0
    ARGV.shift if scale
    holes = ARGV.clone
    ARGV.clear
    holes.each do |h|
      next if $harp_holes.include?(h)
      err "Argument '#{h}' from the commandline is:\n  - neither a scale, any of:  #{$all_scales.join('  ')}\n  - nor a hole of a #{$type}-harp  (any of #{$harp_holes.join('  ')})  and can therefore not be part of an adhoc-scale"
    end
    if !scale
      if holes.length == 0
        scale = get_scale_from_sws($conf[:scale])
        $source_of[:scale] = 'config'
      else
        # allow for adhoc-scale
        scale = get_scale_from_sws('adhoc-scale:h')
        $adhoc_scale_holes = holes
        $source_of[:scale] = 'adhoc-commandline'
      end
    end
    scale, opts[:add_scales], $scale_prog = override_scales_mb(scale, opts)
    
  when :play, :print, :tools, :licks
    # modes play and print both accept multiple scales as arguments, tools
    # and licks only one.

    # check if first arg is a scale
    scale = get_scale_from_sws(ARGV[0], true) if ARGV.length > 0
    # See also test id-110 for a some cases of expected behaviour

    if scale
      # ARGV[0] might look like blues:b, this will turn it into blues
      ARGV[0] = scale
      case mode
      when :play, :print
        # If we have only scales on the commandline, we assume that they all
        # should be printed or played; the first scale than servers double
        # duty in also specifying the scale (besides beeing printed or
        # played).
        ARGV.shift unless Set[*ARGV].subset?(Set[*$all_scales])
      when :tools, :licks
        ARGV.shift
      end
    else
      scale = get_scale_from_sws($conf[:scale] || 'all:a')
      $source_of[:scale] = 'implicit'
    end
    scale, opts[:add_scales], $scale_prog = override_scales_mb(scale, opts)

  when :develop, :samples, :jamming
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
  $extra_kws.each {|kw| $name_collisions_mb[kw] << 'extra-keyword'}

  $extra_desc.each do |mode, _|
    $extra_desc[mode].each do |extras,desc|
      $extra_desc[mode][extras] = ERB.new(desc).result(binding)
      $extra_desc[mode][extras].lines.each do |l|
        err "Internal error: line from #{exfile} too long: #{l.length} >= #{$conf[:term_min_width] - 2}: '#{l}'" if l.length >= $conf[:term_min_width] - 2
        extras.split(',').map(&:strip).each {|extra| $extra_kws[mode] << extra}
      end
    end
  end

  # construct variants of keywords (with and without s) for giving hints
  $extra_kws_w_wo_s = Hash.new
  # there might be a more elegant recursive solution, but for now only the
  # result counts
  $extra_kws.each do |mode, extras|
    extras.each do |extra|
      multi_variants = extra.split('-').map do |word|
        [word, ( word.end_with?('s')  ?  word[0..-2]  :  word + 's' )]
      end
      # the if below cannot be made simpler (?), because product for
      # arrays has no neutral element (aka '1'), which we could use for
      # inject
      if multi_variants.length == 1
        multi_variants[0]
      else
        multi_variants[1..-1].inject(multi_variants[0]) do |variants, w_wo_s|
          variants.product(w_wo_s)
        end.map {|variants| variants.join('-')}
      end.each do |variant|
        $extra_kws_w_wo_s[mode] ||= Hash.new
        if mode == :print && %w(player players).include?(variant)
          # handle special case for mode print: both player and players
          # exist and mean different things
          $extra_kws_w_wo_s[mode][extra] = extra
        else
          fail "Internal error: ambigous variant '#{variant}' maps both to '#{extra}' and '#{$extra_kws_w_wo_s[mode][variant]}'" if $extra_kws_w_wo_s[mode][variant]
          $extra_kws_w_wo_s[mode][variant] = extra
        end
      end
    end
  end
end


def parse_arguments_for_mode

  $amongs = Hash.new
  $amongs[:play] = [:hole, :note, :event, :scale, :lick, :last, :lick_prog, :semi_note]
  $amongs[:print] = [$amongs[:play], :lick_prog, :scale_prog].flatten
  $amongs[:licks] = [:hole, :note, :lick]

  $extra = nil
  okay = true
  amongs_clause = ''

  # Only some modes accept an extra argument, listen or licks e.g. do not
  if $extra_desc[$mode]
    if [:play, :print].include?($mode)
      # These mode (play, print) are the only two modes, that allow
      # arguments on the commandline as well as an extra argument, which
      # however is optional (quiz as a counterexample requires its extra
      # argument). Therefore the first argument for play and print can be
      # from any of large set of types
      
      # We want a complete error-message e.g. for a typo in first argument
      # after mode; so this needs to check all possible choices: $amongs
      # as well as $extra. All arguments (with a possible $extra already
      # removed) will later be checked again, but only against
      # $amongs[$mode]
      what = recognize_among(ARGV[0],
                             [$amongs[$mode], :extra, :extra_w_wo_s],
                             licks: $all_licks)
      $extra = ARGV.shift if what == :extra
      if !what
        # this will make print_amongs aware, that we did recognize_among
        # against $all_licks above
        $licks = $all_licks
        any_of = print_amongs($amongs[$mode], :extra)
        err "First argument for mode #{$mode} should belong to one of these #{any_of.length} types:\n\e[2m  #{any_of.map {|a| a.to_s.gsub('_','-')}.join('   ')}\e[0m\nas detailed above, but not '#{ARGV[0]}'"
      end
    else
      # these modes (e.g. quiz, samples or jamming) require their extra argument
      $extra = ARGV.shift if recognize_among(ARGV[0], [:extra,
                                                       ($mode == :jamming  ?  []  :  :extra_w_wo_s)]) == :extra
      if !$extra
        print_amongs(:extra)
        puts get_extra_desc_all(extra_desc: {quiz: {'choose' => 'ask user to choose one'}}).join("\n") if $mode == :quiz
        extra_words = $extra_desc[$mode].keys.map {|x| x.split(',').map(&:strip)}.flatten.sort
        err "First argument for mode #{$mode} should be one of these #{extra_words.length}:\n\e[2m#{wrap_words('  ',extra_words, '  ')} \n\e[0mas described above, but not '#{ARGV[0]}'"     
      end
    end
  end
  
  to_handle = ARGV.clone
  ARGV.clear

  # do this check late, because we have more specific error messages before
  err "Cannot handle these arguments: #{to_handle}#{not_any_source_of}; #{$for_usage}" if to_handle.length > 0 && ![:play, :print, :quiz, :licks, :tools, :develop, :samples, :jamming].include?($mode)

  return to_handle
end


# get_scale_from_scale_with_short
def get_scale_from_sws scale_w_short, graceful = false, added = false   
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
  return scale if scale == 'adhoc-scale'

  if $all_scales.include?(scale)
    scale
  else
    if graceful
      nil
    else
      scale_globs = $scale_files_templates.map {|t| t % [$type, '*', '*']}
      err "Scale (%s) must be one of #{$all_scales.join(',')}, i.e. scales matching:\n#{scale_globs.join('\n')}\nnot '#{scale}'%s" %
          if added
            ["given in option --add-scales or in configuration files",
             ", Hint: use '--add-scales -' to override the value from config"]
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
  types_with_scales = get_types_with_scales_for_usage
  # used for play and print
  no_lick_selecting_options = <<-EOTEXT
  Note, that the above case does not use any of the extra arguments given
  above, but rather expects (maybe among others) lick-names on the
  commandline; in this case the lick-selecting tag-options (e.g. -t) are
  ignored (even those from your config.ini) and the given lick-names
  ('st-louis') are searched among ALL of your licks.
EOTEXT

  if !mode && STDOUT.isatty
    print "\e[?25l"  ## hide cursor      
    animate_splash_line
    puts "\e[2mOverview:\e[0m"
    sleep 0.5
    print "\e[?25h"  ## show cursor
  end
  puts
  lines = ERB.new(IO.read("#{$dirs[:install]}/resources/usage#{mode  ?  '_' + mode.to_s  :  ''}.txt")).result(binding).gsub(/(^\s*\n)+\Z/,'').lines
  lines.each_with_index do |line, idx|
    print line
    sleep 0.01 if STDOUT.isatty && idx < 10
  end

  if $mode
    puts "\nCommandline Options:\n\n"
    puts "  For an extensive, mode-specific list type:\n\n    harpwise #{$mode} -o\n"
  end
  puts
end


def print_options opts
  puts "\nCommandline options for mode #{$mode}:\n\n"
  # check for maximum length; for performance, do this only on usage info (which is among tests)
  pieces = opt_desc_text(opts, false)
  pieces.join.lines.each do |line|
    err "Internal error: line from opt2desc.yml too long: #{line.length} >= #{$conf[:term_min_width]}: '#{line}'" if line.length >= $conf[:term_min_width]
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


def get_types_with_scales_for_usage
  $conf[:all_types].map do |type|
    next if type == 'testing'
    txt = "scales for #{type}: "
    scales_for_type(type,false).each do |scale|
      txt += "\n    " if (txt + scale).lines[-1].length > 80
      txt += scale + ', '
    end
    txt.chomp(', ')
  end.compact.join("\n  ")
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


def override_scales_mb scale, opts

  return scale, opts[:add_scales], nil unless opts[:scale_prog]

  if !opts[:scale_prog][',']
    if !$all_scale_progs.include?(opts[:scale_prog])
      max_nm_len = $all_scale_progs.keys.map(&:length).max
      err "Scale progression given via '--scale-progression #{opts[:scale_prog]}' is none of these:\n\n" +
          $all_scale_progs.map {|nm,sp| "  %#{max_nm_len}s : %s\n  %#{max_nm_len}s   %s\n" % [nm,sp[:desc],'',sp[:scales].join(',')]}.join
    end
    sc_prog = $all_scale_progs[opts[:scale_prog]][:scales]
  else
    sc_prog = opts[:scale_prog].split(',')
  end
  
  $msgbuf.print("Scale prog is #{opts[:scale_prog]}", 5, 5)
  $msgbuf.print("Adjusted scale to match option '--scale-progression'", 5, 5) if scale && scale != sc_prog[0]

  sc_prog.each do |sc|
    err "Scale '#{sc}' given via '--scale-progression #{sc_prog.join(',')}' must be one of #{$all_scales}" unless $all_scales.include?(sc)
  end

  scl = sc_prog[0]
  add_scs = (sc_prog + [scale]).uniq[1..-1].join(',')
  $msgbuf.print("Adjusted option --add-scales to match option --scale-progression", 5, 5) if add_scs != opts[:add_scales]
  return scl, add_scs, sc_prog
end


def parse_keyboard_translate opt_kb_tr
  
  kb_trs = Hash.new
  return kb_trs unless opt_kb_tr
  
  from_slot = ''
  # check for shorthands using slots
  if %w(slot1 slot2 slot3 s1 s2 s3).include?(opt_kb_tr)
    num = opt_kb_tr[-1].to_i
    from_slot = ", shorthand from slot #{num}"
    opt_kb_tr = $conf["keyboard_translate_slot#{num}".to_sym] ||
                                err("'slot#{num}' given in '--keyboard-translate slot#{num}' or '--kb-tr s#{num}' does not have a matching option 'keyboard_translate_slot#{num}' in your config; see there for more explanation")
  elsif opt_kb_tr =~ /^(slot|s)\d+$/
    err "Option --keyboard-translate does not accept a slot other than 1,2,3; see 'harpwise #{$mode} -o' for a full description"
  end
  cite = "'--keyboard-translate #{opt_kb_tr}'#{from_slot}"
  should_form = "In general the argument for option --keyboard-translate should have the form 'key1=key2,key3=key4+key5 ...', which e.g. specifies two separate translations and would translate   key1  into  key2   and   key3  into  key4 plus key5\nIn addition your config may specify three slots of shorthands for convenience, these can be addressed as 'slot1' or 's1' etc.; see the commands in your config for details"
  trs = opt_kb_tr.split(',')
  err "No key translations given in: #{cite}.\n#{should_form}" unless trs.length > 0
  trs.each do |tr|
    from_to = tr.split('=')
    why = if tr == ''
            "empty key translation ''"
          elsif from_to.length != 2
            "not exactly one '='"
          elsif from_to[1] == '+'
            "a '+' without any keys to translate from"
          elsif from_to[1].start_with?('+')
            "translate-to chars '#{from_to[1]}' starts with a '+'"
          elsif from_to[1].end_with?('+')
            "translate-to chars '#{from_to[1]}' ends with a '+'"
          elsif from_to[1]['++']
            "translate-to chars '#{from_to[1]}' contains a double '++' with no char in between"
          else
            nil
          end
    why = ". Reason: #{why}" if why
    err "Cannot parse this keyboard translation: '#{tr}'#{why} (from #{cite}).\n#{should_form}.\nEach of the keys given must be one of: #{$keyboard_translateable.join(',')}   ; note that especially '=','+' and ',' are not available for translation" if why
    from_k = from_to[0]
    to_ks = from_to[1].split('+')
    [from_k,to_ks].flatten.each do |k|
      err "Key '#{k}' (in '#{tr}') (in #{cite})\nis none of the translatable keys #{$keyboard_translateable.join(',')}\n#{should_form}" unless $keyboard_translateable.include?(k)
    end
    err "Key '#{from_k}' already has this translation: '#{kb_trs[from_k]}', cannot translate it again to '#{to_ks.join('+')}'; please use use '#{from_k}=#{[kb_trs[from_k],to_ks].flatten.join('+')}' to have both in a single translation" if kb_trs[from_k]
    to_ks.each do |to_k|
      err "Key '#{to_k}' (in '#{tr}') (in #{cite})\nis none of the translatable keys #{$keyboard_translateable.join(',')}\n#{should_form}" unless $keyboard_translateable.include?(to_k)
      # Remark: Most (all ?) cases of error checking (e.g. circular or
      # translations) are already handled by check for 'in_both' below
      kb_trs[from_k] = if kb_trs[from_k]
                         [kb_trs[from_k], to_k].flatten
                       else
                         to_k
                       end
    end
  end
  in_both = kb_trs.keys & kb_trs.values
  err "Invalid keyboard translation: these keys appear both as from- and to-keys (i.e. on both sides of the '='-sign) (in #{cite}): #{in_both.join(',')}. #{should_form}" if in_both.length > 0

  return kb_trs
end


def get_viewers_desc
  $image_viewers.map do |vwrs|
    '  - ' +
      if vwrs[:syn].length == 1
        vwrs[:syn][0] + ':'
      else
        "#{vwrs[:syn][0]}  or  #{vwrs[:syn][1]}:"
      end + "\n" + wrap_words('      ', vwrs[:desc].split, ' ', width: 70) +
      if vwrs[:choose_desc]
        "\n" + wrap_words('      ', vwrs[:choose_desc].split, ' ', width: 70) 
      else
        ''
      end
  end.join("\n")
end
