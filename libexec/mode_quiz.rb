#
# Mode quiz with its different flavours
#

def do_quiz to_handle

  unless $other_mode_saved[:conf]
    print "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
    puts "\e[?25l"  ## hide cursor
  end

  flavour = nil
  
  #
  # Handle Signals
  #
  Signal.trap('TSTP') do
    # do some actions of at_exit-handler here
    sane_term
    puts "\e[#{$lines[:message_bottom]}H\e[0m\e[K"
    puts "\e[2m\e[34m ... quiz start over ... \e[0m\e[K"
    puts "\e[K"    
    if $pers_file && $pers_data.keys.length > 0 && $pers_fingerprint != $pers_data.hash
      File.write($pers_file, JSON.pretty_generate($pers_data))
    end
    exec($full_commandline)
  end

  if ENV['HARPWISE_RESTARTED_AFTER_SIGNAL']
    do_restart_animation
    puts "\e[0m\e[2mStarting over with a different flavour ...\e[0m\n\n"    
  else
    animate_splash_line
    puts "\e[2mPlease note, that when playing holes, the normal play-controls\n(e.g. space or 'h') are available but not advertised.\e[0m"
  end
  
  #
  # process any arguments passed in as to_handle
  #
  $num_quiz_replay_explicit = false
  if $extra == 'replay'
    if to_handle.length == 1
      err "'harpwise quiz replay' requires an integer argument, not: #{to_handle[0]}" unless to_handle[0].match(/^\d+$/)
      $num_quiz_replay = to_handle[0].to_i
      $num_quiz_replay_explicit = true
    elsif to_handle.length > 1
      err "'harpwise quiz replay' allows only one argument, not: #{to_handle}"
    end
  else
    err_args_not_allowed(to_handle) if to_handle.length > 0
  end
  $num_quiz_replay ||= {easy: 4, hard: 8}[$opts[:difficulty]]


  #
  # Get Flavour
  #
  $quiz_flavour = get_accepted_flavour_from_extra unless $other_mode_saved[:conf]

  
  # for listen-perspective, dont show solution immediately
  $opts[:comment] = :holes_some
  $opts[:immediate] = false
  

  #
  # Actually start different quiz cases; all contain their own
  # infinite loop
  #
  # First some special flavours
  #
  if $quiz_flavour == 'replay'

    back_to_comment_after_mode_switch
    puts
    puts "\e[34mNumber of holes to replay is: #{$num_quiz_replay}\e[0m"
    puts "\n\n\n"
    prepare_listen_perspective_for_quiz
    do_licks_or_quiz(lambda_quiz_hint: -> (holes, _, _, _) do
                       solve_text = "\e[0mHoles  \e[34mto replay\e[0m  are:\n\n\n" +
                                    "\e[32m       #{holes.join('  ')}"
                       quiz_hint_in_handle_holes_simple(solve_text, 'sequence', holes, :all)
                     end)

    
  elsif $quiz_flavour == 'play-scale'

    scale_name = $all_quiz_scales[$opts[:difficulty]].sample
    back_to_comment_after_mode_switch
    puts
    puts "\e[34mScale to play is:\n-----------------"
    puts
    do_figlet_unwrapped scale_name, 'smblock'
    puts "\e[0m"
    puts
    sleep 2
    prepare_listen_perspective_for_quiz
    do_licks_or_quiz(quiz_scale_name: scale_name,
                     lambda_quiz_hint: -> (holes, _, scale_name, _) do
                       solve_text = "\e[0mScale  \e[34m#{scale_name}\e[0m  is:\n\n\n" +
                                    "\e[32m       #{holes.join('  ')}"
                       quiz_hint_in_handle_holes_simple(solve_text, 'scale', holes, :all)
                     end)

    
  elsif $quiz_flavour == 'play-inter'

    holes_inter = get_random_interval
    back_to_comment_after_mode_switch
    puts "\e[34mInterval to play is:\e[0m\e[2m"
    puts
    puts
    do_figlet_unwrapped holes_inter[4], 'smblock'
    puts
    puts
    sleep 2
    prepare_listen_perspective_for_quiz
    do_licks_or_quiz(quiz_holes_inter: holes_inter,
                     lambda_quiz_hint: -> (holes, holes_inter, _, _) do
                       solve_text = "\e[0mInterval  \e[34m#{holes_inter[4]}\e[0m  is:\n\n\n" +
                                    "\e[32m                #{holes_inter[0]}  to  #{holes_inter[1]}"
                       quiz_hint_in_handle_holes_simple(solve_text, 'interval', holes, holes[-1])
                     end)

    
  elsif $quiz_flavour == 'play-shifted'

    back_to_comment_after_mode_switch
    holes_shifts = get_holes_shifts
    puts
    puts "\e[0m\e[2mInterval to shift is: \e[0m\e[34m#{holes_shifts[2]}\e[0m"
    puts
    puts
    prepare_listen_perspective_for_quiz
    do_licks_or_quiz(quiz_holes_shifts: holes_shifts,
                     lambda_quiz_hint: -> (holes, holes_inter, _, holes_shifts) do
                       quiz_hint_in_handle_holes_shifts holes_shifts
                     end)

    
  elsif $quiz_flavour == 'keep-tempo'

    loop do
      catch :NEW_PARAMS do
        keep = KeepTempo.new
        keep.set_params
        loop do
          keep.issue_question
          unless keep.play_and_record
            puts
            puts get_dim_hline
            puts "\nChoosing new parameters."
            throw :NEW_PARAMS
          end
          keep.extract_beats
          keep.judge_result
          puts
          puts get_dim_hline
          puts
          puts "\e[0mWhat's next ?"
          puts 
          puts "\e[0m\e[32mPress any key for a new set of parameters or\n      BACKSPACE to redo with the current set ... \e[0m"
          drain_chars
          char = one_char
          puts
          if char == 'BACKSPACE'
            puts "Same parameters \e[2magain.\e[0m"
          else
            puts "New parameters."
            $opts[:difficulty] = (rand(100) > $opts[:difficulty_numeric] ? :easy : :hard)
            keep.set_params
            keep.clear_history
          end
          puts
          sleep 0.2
        end
      end
    end

    
  elsif $quiz_flavour2class[$quiz_flavour]
    # Generic flavour
    
    first_round = true
    loop do  ## every new question
      
      re_calculate_quiz_difficulty unless first_round

      catch :next do
        sleep 0.1
        puts
        if !first_round
          puts "Next question."
          puts
          sleep 0.2
        end
        first_round = false
        flavour = $quiz_flavour2class[$quiz_flavour].new
        loop do  ## repeats of question
          catch :reissue do
            flavour.issue_question
            sleep 0.1
            loop do  ## repeats of asking for answer
              catch :reask do
                throw flavour.get_and_check_answer
              end
            end
          end
        end
      end
    end

  else

    err "Internal error: #{$quiz_flavour}, #{$quiz_flavour2class}"

  end
end

# will be populated by class-definitions (with flavours and tags) and
# reworked in config.rb into $quiz_flav2tag and $quiz_tag2flav
$q_f2t = Hash.new

class QuizFlavour

  @@prevs = Array.new

  def initialize
    @state = Hash.new
    @state_orig = @state.clone
  end

  def get_and_check_answer
    choose_prepare_for
    all_helps = ['.HELP-NARROW', 'NOT_DEFINED', 'NOT_DEFINED']
    all_choices = ['.AGAIN', @choices, '.SOLVE', '.SKIP', all_helps[0]].flatten
    choices_desc = {'.AGAIN' => 'Ask same question again',
                    '.SOLVE' => 'Give solution and go to next question',
                    '.SKIP' => 'Show solution and Skip to next question without extra info',
                    all_helps[0] => 'Remove some solutions, leaving less choices'}
    
    [help2_desc, help3_desc, help4_desc, help5_desc].each_with_index do |desc, idx|
      next unless desc
      all_choices << desc[0]
      choices_desc[desc[0]] = desc[1]
      all_helps[idx + 1] = desc[0]
    end
    answer = choose_interactive(@prompt, all_choices) do |tag|
      choices_desc[tag] ||
        ( tag_desc(tag) && "#{@help_head} #{tag_desc(tag)}" ) ||
        "#{@help_head} #{tag}"
    end
    choose_clean_up
    # @solution might be string or array
    if [@solution].flatten.include?(answer)
      if self.respond_to?(:after_solve)
        stand_out "Yes, '#{answer}' is RIGHT !\n\nSome extra info below.", all_green: true
        puts
        after_solve
      else
        stand_out "Yes, '#{answer}' is RIGHT !", all_green: true
      end
      puts
      return next_or_reissue
    end
    case answer
    when nil
      stand_out "No input or invalid key ?\nPlease try again or\nterminate with ctrl-c ..."
      return :reask
    when '.AGAIN'
      stand_out 'Asking question again.'
      puts
      return :reissue
    when '.SOLVE', '.SKIP'
      sol_text = if @solution.is_a?(Array) && @solution.length > 1
                   "  any of  #{@solution.join(',')}"
                 else
                   "        #{[@solution].flatten[0]}"
                 end
      if answer != '.SKIP' && self.respond_to?(:after_solve)
        stand_out "The correct answer is:\n\n#{sol_text}\n\nSome extra info below."
        after_solve
      else
        stand_out "The correct answer is:\n\n#{sol_text}\n"
      end
      puts
      return next_or_reissue
    when all_helps[0]
      if @choices.length > 1
        stand_out 'Removing some choices.'
        orig_len = @choices.length 
        while @choices.length > orig_len / 2
          idx = rand(@choices.length)
          next if @choices[idx] == @solution
          @choices.delete_at(idx)
        end
      else
        stand_out "There is only one choice left;\nit should be pretty easy by now.\nYou may also choose 'SOLVE' ..."
      end
      return :reask
    when all_helps[1]
      help2
      return :reask
    when all_helps[2]
      help3
      return :reask
    when all_helps[3]
      help4
      return :reask
    when all_helps[4]
      help5
      return :reask
    else
      stand_out "Sorry, your answer '#{answer}' is wrong\nplease try again ...", turn_red: 'wrong'
      @choices.delete(answer)
      return :reask
    end
  end

  def self.difficulty_head
    "difficulty is '#{$opts[:difficulty].upcase}'"
  end

  def play_hons hide: nil, reverse: false, hons: nil, newline: true
    hons ||= @holes
    make_term_immediate
    $ctl_kb_queue.clear
    puts if newline
    play_holes_or_notes_simple(reverse ? hons.rotate : hons, hide: [hide, :help])
    make_term_cooked
  end

  def recharge
    @choices = @choices_orig.clone
    @state = @state_orig.clone
  end
  
  def help2_desc
    nil
  end

  def help3_desc
    nil
  end

  def help4_desc
    nil
  end

  def help5_desc
    nil
  end

  def tag_desc tag
    nil
  end

  def after_solve_interval
    puts
    print "\e[2mHoles as notes:   "
    print @holes.map {|h| "#{h} = #{$hole2note[h]}"}.join(',   ')
    puts "\e[0m"
    puts
    printf "Playing interval of %+dst:\n", @dsemi
    play_hons
  end

  def next_or_reissue
    puts
    puts get_dim_hline
    puts
    puts "\e[0mWhat's next ?"
    puts
    puts "\e[32mPress any key for next \e[92m#{$quiz_flavour}\e[0m\e[32m or BACKSPACE to re-ask this one ... \e[0m"
    char = one_char
    puts
    if char == 'BACKSPACE'
      puts "Same question again."
      puts
      sleep 0.2
      recharge
      return :reissue
    end
    return :next  
  end

end



# The three classes below are mostly done within do_licks, so the
# classes here are not complete

class Replay < QuizFlavour

  $q_f2t[self] = %w(mic)

  def self.describe_difficulty
    if $num_quiz_replay_explicit
      "number of holes to replay is #{$num_quiz_replay} (explicitly set)"
    else
      QuizFlavour.difficulty_head + ", number of holes to replay is #{$num_quiz_replay}"
    end
  end
end


class PlayScale < QuizFlavour

  $q_f2t[self] = %w(mic scales)

  def self.describe_difficulty
    HearScale.describe_difficulty
  end
end


class PlayInter < QuizFlavour

  $q_f2t[self] = %w(mic inters)

  def self.describe_difficulty
    AddInter.describe_difficulty
  end
end


class PlayShifted < QuizFlavour

  $q_f2t[self] = %w(mic)

  def self.describe_difficulty
    $num_quiz_replay = {easy: 3, hard: 6}[$opts[:difficulty]]
    QuizFlavour.difficulty_head +
      ", #{$num_quiz_replay} holes to be shifted by one of #{$std_semi_shifts.length} intervals"
  end
end


class HearScale < QuizFlavour

  $q_f2t[self] = %w(scales no-mic)
  
  def initialize
    super
    @choices = $all_quiz_scales[$opts[:difficulty]].clone
    @choices_orig = @choices.clone
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @sorted, _, _, _ = read_and_parse_scale(@solution, $harp)
    @holes = @sorted.clone.shuffle
    @holes_orig = @holes.clone
    @prompt = 'Choose the scale you have heard:'
    @help_head = 'Scale'
    @scale2holes = @choices.map do |scale|
      holes, _, _, _ = read_and_parse_scale(scale, $harp)
      [scale, holes]
    end.to_h

  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$all_quiz_scales[$opts[:difficulty]].length} scales out of #{$all_scales.length}"
  end
  
  def after_solve
    puts
    puts "Playing scale #{@solution} ..."
    sleep 0.1
    puts
    play_hons hons: @sorted
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying a scale\e[0m\e[2m; one scale out of #{@choices.length}; with \e[0m\e[34m#{@holes.length}\e[0m\e[2m holes ...\e[0m"
    puts "\e[2mThe " + self.class.describe_difficulty + "\e[0m"
    puts
    play_hons hide: :all
  end

  def tag_desc tag
    $scale2desc[tag] || tag
  end

  def recharge
    super
    @holes = @holes_orig.clone
  end
  
  def help2
    puts "Playing sorted holes for scale:"
    play_hons(hons: @sorted, hide: :all)
  end

  def help2_desc
    ['.HELP-PLAY-ASCENDING', 'Play holes in ascending order']
  end

  def help3
    choose_and_play_answer_scale
  end

  def help3_desc
    ['.HELP-PLAY-COMPARE', 'Select a scale and play it for comparison']
  end

  
end


class MatchScale < QuizFlavour

  $q_f2t[self] = %w(scales no-mic)

  def initialize
    super
    scales = $all_quiz_scales[$opts[:difficulty]]
    @choices = scales.clone 
    @choices_orig = @choices.clone
    @state = Hash.new
    @state[:hide_holes] = :all
    @state_orig = @state.clone
    @scale2holes = scales.map do |scale|
      holes, _, _, _ = read_and_parse_scale(scale, $harp)
      [scale, holes]
    end.to_h
    # General goal: for every scale try to find a sequence of holes,
    # that has this scale as its shortest superset. Later we pick one
    # of the scales with equal probability
    pool = Hash.new
    others = Hash.new
    unique = Hash.new
    # having duplicates in all_holes emperically has a higher chance
    # for finding examples even for exotic scales. In addition, this
    # algorithm gives nicer, up-and-down sequences
    all_holes = @scale2holes.values.flatten
    rounds = 0
    # loop until: we have a sequence for every scale and
    until ( pool.keys.length == scales.length &&
            # all scales are the only superset of their sequences or
            pool.values.map {|v| v[1]}.uniq == ['single'] ) ||
          # we have tried often enough
          rounds > 1000
      rounds += 1
      # random length of sequence
      holes = all_holes.sample(6 + rand(5).to_i)
      superset_scales = scales.
                          # must be superset, i.e. contain all holes;
                          # subtracting arrays does work, even if
                          # holes has duplicates (which it has)
                          select {|sc| (holes - @scale2holes[sc]).length == 0}.
                          # group by length, so that we know, if two
                          # or more scales with the same length are
                          # superset; we do not want this, because it
                          # would be ambigous. The result of group_by.to_a
                          # has this form (e.g.):
                          # [[len1,[sc1,sc2]],[len2,[sc3]]]
                          group_by {|sc| @scale2holes[sc].length}.to_a.
                          # sort by length, so that the shortest scale
                          # comes first
                          sort {|g1, g2| g1[0] <=> g2[0]}
      # if there are any matching scales, take shortest but only if it
      # is not ambigous
      if superset_scales.length > 0 && superset_scales[0][1].length == 1
        scale = superset_scales[0][1][0]
        # do not overwrite a single match
        if !pool[scale] || others[scale] 
          pool[scale] = holes
          os = superset_scales.map {|ssc| ssc[1]}.flatten.uniq - [scale]
          others[scale] = ( os.length > 0  ?  os  :  nil )
          unique[scale] = holes -
                          @scale2holes.keys.select {|s| s != scale}.
                            map {|s| @scale2holes[s]}.flatten
          unique[scale] = nil if unique[scale].length == 0
          ( ierr = if unique[scale] && (unique[scale] - @scale2holes[scale]).length > 0
                     "unique holes #{unique[scale]} not all in chosen scale"
                   elsif others[scale] && unique[scale]
                     "other scales and unique holes at once"
                   else
                     nil
                   end ) && 
            err("Internal error:\n  scale = #{scale}\n  holes = #{holes}\n  scale2holes = #{@scale2holes}\n\n#{ierr}")
        end
      end
    end
    begin
      @solution = pool.keys.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @holes = pool[@solution]
    @others = others[@solution]
    @unique = unique[@solution]
    @holes_scale = @scale2holes[@solution]
    @prompt = "Choose the #{@others ? 'SHORTEST' : 'single'} scale, that contains all the holes:"
    @help_head = 'Scale'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$all_quiz_scales[$opts[:difficulty]].length} scales out of #{$all_scales.length}"
  end
  
  def after_solve
    puts
    puts "Playing #{@others ? 'shortest' : 'single'} solution scale #{@solution} ..."
    sleep 0.2
    puts
    play_hons hons: @holes_scale
    puts
    sleep 0.5
    puts "Playing the holes in question ..."
    sleep 0.2
    puts
    play_hons
    puts "\n\e[2m"
    if @others
      puts "The other, but longer scales are:  #{@others.join(', ')}"
    elsif @unique
      puts "These holes make this sequence a\nunique fit for scale #{@solution} only:  #{@unique.join(', ')}"
    else
      puts "The sequence shares all its holes with two or more scales,\nbut only with #{@solution} it shares them all."
    end
    puts "\nChoice of scale was among:   #{@choices_orig.join('  ')}"
    puts "\e[0m"
    sleep 0.2
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying #{@holes.length} holes\e[0m\e[2m, which are a subset of #{@others ? 'MULTIPLE scales at once' : 'a SINGLE scale'} ...\e[0m"
    puts "\e[2mThe " + self.class.describe_difficulty + "\e[0m"
    puts
    play_hons hide: @state[:hide_holes]
  end

  def tag_desc tag
    holes = @scale2holes[tag]
    return nil unless holes
    "#{$scale2desc[tag] || tag} (#{holes.length} holes)"
  end

  def help2
    choose_and_play_answer_scale
  end

  def help2_desc
    ['.HELP-PLAY-COMPARE', 'Select a scale and play it for comparison']
  end

  def help3
    puts "\n\e[2mPlaying unique holes of sequence sorted by pitch.\n\n"
    play_hons hide: @state[:hide_holes],
              hons: @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]}.uniq
  end

  def help3_desc
    ['.HELP-PLAY-ASCENDING', 'Play holes-in-question in ascending order']
  end

  def help4
    puts "Showing all holes played (this question only)."
    @state[:hide_holes] = nil
    play_hons hide: [@state[:hide_holes], :help]
  end

  def help4_desc
    ['.HELP-SHOW-HOLES', 'Show the holes played']
  end

  def help5
    puts "\n\e[2mPrinting all scales with their holes.\n\n"
    maxl = @scale2holes.keys.max_by(&:length).length
    @scale2holes.each do |k, v|
      puts "   \e[2m#{k.rjust(maxl)}:\e[0m\e[32m   #{v.join('  ')}\e[0m"
    end
    puts "\n\e[2m#{@choices.length} scales\n\n"
    puts "\e[2mAnd the holes in question:\e[0m\e[32m   #{@holes.join('  ')}\e[0m"
  end

  def help5_desc
    ['.HELP-PRINT-SCALES', 'print all the hole-content of all possible scales']
  end

end


class HearInter < QuizFlavour

  $q_f2t[self] = %w(inters no-mic)
  
  def initialize
    super
    @choices = $intervals_quiz[$opts[:difficulty]].map {|i| $intervals[i][0]}
    @choices_orig = @choices.clone    
    begin
      inter = get_random_interval
      @holes = inter[0..1]
      @dsemi = inter[2]
      @solution = inter[3]
    end while @@prevs.include?(@holes)
    @@prevs << @holes
    @@prevs.shift if @@prevs.length > 2
    @prompt = 'Choose the Interval you have heard:'
    @help_head = 'Interval'
  end

  def self.describe_difficulty
    AddInter.describe_difficulty
  end

  def after_solve
    after_solve_interval
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying an interval\e[0m\e[2m; one out of #{@choices.length} ...\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    sleep 0.1
    puts
    play_hons hide: [:help, :all]
  end

  def help2
    puts "Playing interval reversed:"
    play_hons reverse: true, hide: :all
  end

  def help2_desc
    ['.HELP-REVERSE', 'Play interval reversed']
  end

  def help3
    puts "Playing all intervals:"
    puts "\e[2mPlease note, that some may not be available as holes.\e[0m"
    puts
    maxlen = $intervals_quiz[$opts[:difficulty]].map {$intervals[_1][0].length}.max
    $intervals_quiz[$opts[:difficulty]].each do |inter|
      sleep 0.5
      note_inter = semi2note($harp[@holes[0]][:semi] + inter * (@dsemi <=> 0))
      print "  \e[32m%-#{maxlen}s\e[0m\e[2m   \e[0m" % $intervals[inter][0]
      play_hons hons: [@holes[0], note_inter], hide: :all, newline: false
    end
    sleep 0.5
  end

  def help3_desc
    ['.HELP-PLAY-ALL', 'Play all intervals over first note']
  end

end


class AddInter < QuizFlavour

  $q_f2t[self] = %w(silent inters no-mic)

  def initialize
    super
    begin
      inter = get_random_interval
      @holes = inter[0..1]
      @dsemi = inter[2]
      @verb = inter[2] > 0 ? 'add' : 'subtract'
      @solution = [@holes[1], $harp[@holes[1]][:equiv]].flatten.uniq
    end while @@prevs.include?(@holes)
    @@prevs << @holes
    @@prevs.shift if @@prevs.length > 2
    @choices = []
    $intervals_quiz[$opts[:difficulty]].each do |inter|
      [inter, -inter].each do |int|
        @choices << $semi2hole[$harp[@holes[0]][:semi] + int]
      end
    end
    @choices.compact!
    @choices_orig = @choices.clone
    @prompt = "Enter the result of #{@verb}ing hole #{@holes[0]} and interval #{$intervals[@dsemi.abs][0]}:"
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$intervals_quiz[$opts[:difficulty]].length} intervals out of #{$intervals.length}"
  end

  def after_solve
    after_solve_interval
  end
  
  def issue_question
    puts
    puts "\e[34mTake hole \e[94m#{@holes[0]}\e[34m and #{@verb} interval '\e[94m#{$intervals[@dsemi.abs][0]}\e[34m'\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Playing interval:"
    play_hons hide: @holes[1]
  end

  def help2_desc
    ['.HELP-PLAY-INTER', 'Play interval']
  end

  def help3
    puts "Show holes as semitones:"
    chart = get_chart_with_intervals(prefer_names: false, ref: @holes[0])
    chart.each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        print cell
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
  end

  def help3_desc
    ['.HELP-CHART-SEMIS', 'Show chart with holes as semitones']
  end

  def help4
    puts "Printing intervals semitones and names:"
    puts "\e[2m"
    $intervals_quiz[$opts[:difficulty]].each do |st|
      puts "  %3dst: #{$intervals[st][0]}" % st
    end
    puts "\e[0m"
  end

  def help4_desc
    ['.HELP-SHOW-INTERVALS', 'Show intervals and semitones']
  end

end


class TellInter < QuizFlavour

  $q_f2t[self] = %w(silent inters no-mic)

  def initialize
    super
    begin
      inter = get_random_interval sorted: true
      @holes = inter[0..1]
      @dsemi = inter[2]
      @solution = inter[3]
    end while @@prevs.include?(@holes)
    @@prevs << @holes
    @@prevs.shift if @@prevs.length > 2
    @choices = $intervals_quiz[$opts[:difficulty]].map {|st| $intervals[st][0]}
    @choices_orig = @choices.clone
    @prompt = "Enter the interval between holes #{@holes[0]} and #{@holes[1]}:"
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$intervals_quiz[$opts[:difficulty]].length} intervals out of #{$intervals.length}"
  end

  def after_solve
    after_solve_interval
  end
  
  def issue_question
    puts
    puts "\e[34mWhat is the interval between holes \e[94m#{@holes[0]}\e[34m and \e[94m#{@holes[1]}\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Playing interval:"
    play_hons
  end

  def help2_desc
    ['.HELP-PLAY-INTER', 'Play interval']
  end

  def help3
    puts "Show holes as notes:"
    notes = @holes.map {|h| $hole2note[h]}
    chart = $charts[:chart_notes]
    chart.each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        if notes.include?(cell.strip)
          print "\e[34m#{cell}\e[0m"
        else
          print cell
        end
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
  end

  def help3_desc
    ['.HELP-CHART-NOTES', 'Show chart with notes']
  end

end


class Players < QuizFlavour

  $q_f2t[self] = %w(silent no-mic)

  def initialize
    super
    $players ||= FamousPlayers.new
    @pitems = %w(bio notes songs).shuffle
    @qitem = @pitems.sample
    @hitems = @pitems.clone
    @hitems.rotate!(@hitems.find_index(@qitem))

    begin
      @solution = $players.structured.keys.sample
    end while @@prevs.include?(@solution) || !$players.has_details?[@solution]
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2

    # take 8 players to choose from
    @choices = (($players.structured.keys - [@solution]).sample(7) + [@solution]).shuffle
    @@choices = @choices_orig = @choices.clone

    @structured = $players.structured[@solution]
    @prompt = "Enter the name of the player described above:"
  end

  def self.describe_difficulty
    "Selecting one of #{@@choices.length} players"
  end

  def after_solve
    puts
    print_player $players.structured[@solution]
  end
  
  def issue_question
    puts
    puts "\e[34mWhat is the name of the player with  \e[94m#{@qitem.upcase}\e[34m  given below.\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    puts
    puts "\e[32m#{@qitem.capitalize}:\e[0m"
    @structured[@qitem].each {|l| puts '  ' + l}
  end

  def help2
    @hitems.rotate!
    puts "\e[32m#{@hitems[0].capitalize}:\e[0m"
    @structured[@hitems[0]].each {|l| puts '  ' + l}
    puts
    puts "\e[2m(invoke again for more information)\e[0m"
  end

  def help2_desc
    ['.HELP-MORE-INFO', 'Show additional information about player']
  end

end


class KeyHarpSong < QuizFlavour

  $q_f2t[self] = %w(silent no-mic)

  def initialize
    super
    harp2song = get_harp2song(basic_set: $opts[:difficulty] == :easy)

    @qdesc, @adesc, qi2ai = if rand > 0.5
                              ['harp', 'song', harp2song]
                            else
                              ['song', 'harp', harp2song.invert]
                            end
    @choices = qi2ai.values    
    @choices_orig = @choices.clone
    begin
      @qitem = qi2ai.keys.sample
    end while @@prevs.include?(@qitem)
    @solution = qi2ai[@qitem]
    @@prevs << @qitem
    @@prevs.shift if @@prevs.length > 2
    @prompt = "Key of #{@adesc}:"
    @help_head = "#{@adesc} with key of".capitalize
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$opts[:difficulty] == :easy ? 4 : 12} keys out of 12"
  end

  def issue_question
    puts
    puts "\e[34mGiven a \e[94m#{@qdesc.upcase}\e[34m with key of '\e[94m#{@qitem}\e[34m', name the matching key for the \e[94m#{@adesc}\e[34m\n(2nd position)\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    note = semi2note(key2semi(@solution.downcase))
    puts "Playing note (octave #{note[-1]}) for answer-key of #{@adesc}:"
    make_term_immediate
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_simple [note], hide: [note, :help]
    make_term_cooked
  end

  def help2_desc
    ['.HELP-PLAY-ANSWER', "Play note for answer-key of #{@adesc}"]
  end

end


class HoleNote < QuizFlavour

  $q_f2t[self] = %w(silent no-mic)

  def initialize
    super

    # if our harp has lines with different count of holes, we assume
    # that those lines with the maximum count are also easy to
    # play. If all lines have the same number of holes, they are all
    # assumed to be alike playable
    line2count = $hole2chart.values.map {|pairs| pairs.map {|pair| pair[1]}}.flatten.tally
    maxcount = line2count.values.max
    lines_w_maxcount = line2count.keys.select {|l| line2count[l] == maxcount}
    
    @@diffi_matters = ( lines_w_maxcount.length != line2count.keys.length )
    holes = if !@@diffi_matters || $opts[:difficulty] == :hard
              $harp_holes
            else
              $hole2chart.select do |hole,cls|
                cls.any? do |c,l|
                  lines_w_maxcount.include?(l)
                end
              end.map {|hole,cls| hole}
            end
    hole2note = holes.map {|h| [h,$harp[h][:note].gsub(/\d+/,'')]}.to_h
    note2hole = hole2note.inject(Hash.new {|h,k| h[k] = Array.new}) do |memo, hn|
      memo[hn[1]] << hn[0]
      memo
    end

    q_is_hole = ( rand > 0.5 )
    @qdesc, @adesc, qi2ai = if q_is_hole
                              ['hole', 'note', hole2note]
                            else
                              ['note', 'hole', note2hole]
                            end

    @choices = qi2ai.values    
    @choices_orig = @choices.clone
    begin
      @qitem = qi2ai.keys.sample
    end while @@prevs.include?(@qitem)
    @solution = qi2ai[@qitem]
    @@prevs << @qitem
    @@prevs.shift if @@prevs.length > 2

    @mark_in_chart = if q_is_hole
                       hole2note[@qitem]
                     else
                       @qitem
                     end
    
    @any_clause = ( @solution.is_a?(Array)  ?  "(any of #{@solution.length})"  :  '(single choice)' )
    @prompt = "#{@adesc.capitalize} #{@any_clause} for #{@qdesc} #{@qitem}:"
    @help_head = "#{@adesc} with key of".capitalize
  end

  def self.describe_difficulty
    if @@diffi_matters
      QuizFlavour.difficulty_head + ', taking ' +
        if $opts[:difficulty] == :easy
          'only simple holes (e.g. without bends)'
        else
          'even not-so-simple holes (e.g. with bends)'
        end
    else
      'Selecting all holes of harp'
    end
  end

  def issue_question
    puts
    puts "\e[34mGiven the \e[94m#{@qdesc.upcase}\e[34m '\e[94m#{@qitem}\e[34m', name the matching \e[94m#{@adesc}\e[34m #{@any_clause}\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Printing chart with notes:"
    chart = $charts[:chart_notes]
    chart.each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        if cell.gsub(/\d+/,'').strip == @mark_in_chart
          print "\e[34m#{cell}\e[0m"
        else
          print cell
        end
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
  end

  def help2_desc
    ['.HELP-CHART-NOTES', "Print harmonica chart with notes"]
  end

end


class HearKey < QuizFlavour

  $q_f2t[self] = %w(no-mic)
  
  @@seqs = [[[0, 3, 0, 3, 2, 0, 0], 'st louis'],
            [[0, 3, 0, 3, 0, 0, 0, -1, -5, -1, 0], 'wade in the water'],
            [[0, 4, 0, 7, 10, 12, 0], 'intervals'],
            [[0, 0, 8, 8, 6, 6, 3, 3], 'box'],
            [[0, 0, 0], 'repeated'],
            [:chord, 'chord']]
  
  def initialize
    super
    @@seqs.rotate!(rand(@@seqs.length).to_i)
    @seq = @@seqs[0][0]
    @nick = @@seqs[0][1]
    @ia_key = nil
    harp2song = get_harp2song(basic_set: $opts[:difficulty] == :easy)
    @choices = harp2song.keys 
    @choices_orig = @choices.clone
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @prompt = "Key of sequence that has been played:"
    @help_head = "Key"
    @wavs_created = false
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$opts[:difficulty] == :easy ? 4 : 12} keys out of 12"
  end

  def issue_question silent: false
    unless silent
      puts
      puts "\e[34mHear the sequence of notes '#{@nick}' and name its key\e[0m"
      puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    end
    isemi = key2semi(@solution.downcase)
    make_term_immediate
    $ctl_kb_queue.clear
    if @seq == :chord
      semis = [0, 4, 7].map {|s| isemi + s}
      tfiles = (1 .. semis.length).map {|i| "#{$dirs[:tmp]}/semi#{i}.wav"}
      unless @wavs_created
        synth_for_inter_or_chord(semis, tfiles, 0.2, 2, :sawtooth)
        @wavs_created = true
      end
      play_recording_and_handle_kb_simple tfiles, true
    elsif @seq.is_a?(Array)
      notes = @seq.map {|s| semi2note(isemi + s)}
      puts
      play_holes_or_notes_simple notes, hide: [semi2note(isemi), :help]
    else
      err "Internal error: #{seq}"
    end
    make_term_cooked
  end

  def help2
    @@seqs.rotate!
    @seq = @@seqs[0][0]
    @nick = @@seqs[0][1]
    puts "\nSequence of notes changed to '#{@nick}'."
    issue_question silent: true
  end

  def help2_desc
    ['.HELP-OTHER-SEQ', "Choose a different sequence of notes"]
  end

  def help3
    puts "Change (via +-RET) the adjustable pitch played until\nit matches the key of the sequence"
    make_term_immediate
    $ctl_kb_queue.clear
    harp2song = get_harp2song(downcase: true, basic_set: false)
    song2harp = harp2song.invert
    ia_key_harp = ( @ia_key && song2harp[@ia_key] )
    ia_key_harp = play_interactive_pitch explain: false, start_key: ia_key_harp, return_accepts: true
    make_term_cooked
    @ia_key = harp2song[ia_key_harp]
    puts "\nPlease note, that this key '#{@ia_key}' is not among possible solutions !\n" unless @choices.map(&:downcase).include?(@ia_key)
    puts "\nNow compare key '#{@ia_key}' back to sequence:"
    issue_question silent: true
  end

  def help3_desc
    ['.HELP-PITCH', "Play an adjustable pitch to compare"]
  end

  def after_solve
    puts
    puts "Playing key (of sequence) #{@solution}"
    sleep 0.1
    puts
    make_term_immediate
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_simple [semi2note(key2semi(@solution))], hide: :help
    make_term_cooked
  end

end


class KeepTempo < QuizFlavour

  $q_f2t[self] = %w(mic)
  
  @@explained = false
  @@history = Array.new

  def self.describe_difficulty
    # implement this for unit-test only
  end
  
  def clear_history
    @@history = Array.new
  end
  
  def set_params
    # dont go faster, because precision of record and play does not allow
    @tempo = if $opts[:difficulty] == :easy
               60 + 5 * rand(3)
             else
               50 + 5 * rand(5)
             end
    @beats_intro = 6
    @beats_keep = if $opts[:difficulty] == :easy
                    4 + 2 * rand(4)
                  else
                    8 + 2 * rand(6)
                  end
    @beats_outro = 4

    if $testing
      @beats_intro = @beats_keep = @beats_outro = 2
    end
    
    @slice = 60.0 / @tempo
    @template = @markers = nil

    @recording = "#{$dirs[:tmp]}/tempo_recording.wav"
    @trimmed = "#{$dirs[:tmp]}/tempo_recording_trimmed.wav"
  end

  
  def issue_question

    if @@explained
      puts
      puts "\e[0mParameters (#{$opts[:difficulty]}):"
      puts "  Tempo:           #{@tempo} bpm"
      puts "  PICK-UP-TEMPO:   %2s beats" % @beats_intro.to_s
      puts "  KEEP-TEMPO:      %2s" % @beats_keep.to_s
      puts "  TOGETHER-AGAIN:  %2s" % @beats_outro.to_s
      puts "\n\n"
    else
      puts
      puts "\e[34mAbout to play and record the keep-tempo challenge with tempo \e[0m#{@tempo}\e[34m bpm\nand #{@beats_keep} beats to keep (hole '#{$typical_hole}'); #{QuizFlavour.difficulty_head}.\n\e[0m\e[2mThese are the steps:\n\n"
      puts " \e[0mPICK-UP-TEMPO:  %2s\e[2m ; Harpwise plays a stretch of #{@beats_intro} beats and you are\n    invited to join with the same tempo and hole '#{$typical_hole}'" % @beats_intro.to_s
      puts " \e[0mKEEP-TEMPO:     %2s\e[2m ; Playing pauses for #{@beats_keep} beats, but you should\n   continue on your own; this will be recorded for later analysis" % @beats_keep
      puts " \e[0mTOGETHER-AGAIN: %2s\e[2m ; The wise plays again for #{@beats_outro} beats and in time with the\n    initial stretch, so that you can hear, if you are still on the beat" % @beats_outro
      puts " \e[0mANALYSIS:\e[2m The recording will be analysed and the result displayed"
      puts "\n(and then repeat with same or with changed params)\n\n"
      @@explained = true
    end
    
    # These descriptive markers will be used (and consumed) in
    # play_and_record; the labels should be the same as above
    @markers = [[0, "\e[32mPICK-UP-TEMPO    \e[0m\e[2m" + ('%2d' % @beats_intro) + " beats\e[0m"],
                [@beats_intro, "\e[34mKEEP-TEMPO       \e[0m\e[2m" + ('%2d' % @beats_keep) + " beats\e[0m"],
                [@beats_intro + @beats_keep, "\e[32mTOGETHER-AGAIN   \e[0m\e[2m" + ('%2d' % @beats_outro) + " beats\e[0m"],
                [@beats_intro + @beats_keep + @beats_outro, "\e[0mANALYSIS\e[0m"]]
  end

  
  def play_and_record

    # generate needed sounds
    silence = quiz_generate_tempo('s', 120, 0, 1, 0)
    @template = quiz_generate_tempo('t', @tempo, @beats_intro, @beats_keep, @beats_outro)

    puts "\e[2K\r\e[0mReady to play ?\n\nThen press any key, wait for count-down and start playing in sync ..."
    puts "\e[2mOr press BACKSPACE to get another set of parameters\e[0m"
    print "\e[?25l"  ## hide cursor
    return false if one_char == 'BACKSPACE'
    puts
    print "\e[?25l"
    puts
    puts "\e[2m#{@tempo} bpm; no help or pause, while playing this.\e[0m\n\n"

    12.times do
      puts
      sleep 0.02
    end
    print "\e[12A"
    print "\e[0m\e[2mPreparing ... "
    # wake up (?) and drain sound system to ensure prompt reaction
    if $testing
      sleep 3
      rec_pid = Process.spawn "sleep 1000"
    else
      # trigger sox error up front instead of after recording
      sys "play --norm=#{$vol.to_i} -q #{silence}", $sox_fail_however
      # record and throw away all stuff that might be in the recording pipeline
      rec_pid = Process.spawn "sox -d -q -r #{$conf[:sample_rate]} #{@recording}"
    end
    [3,2,1].each do |x|
      print "#{x} ... "
      sleep 1
    end
    Process.kill('HUP', rec_pid)
    Process.wait(rec_pid)
    puts "\e[0mGO !\n\n"

    # play and record
    wait_thr = Thread.new do
      cmd_play = if $testing
                   "sleep 5"
                 else
                   "play --norm=#{$vol.to_i} -q #{@template}"
                 end  
      cmd_rec = if $testing
                  FileUtils.cp $test_wav, @recording
                  "sleep 1000"
                else
                  "sox -d -q -r #{$conf[:sample_rate]} #{@recording}"
                end  
      # start play and record as close together as possible
      rec_pid = Process.spawn cmd_rec
      # play intro, silence and outro synchronously
      sys cmd_play, $sox_fail_however
      # stop recording
      Process.kill('HUP', rec_pid)
      Process.wait(rec_pid)
    end

    # issue (and consume) markers in parallel to play and record
    loops_per_slice = 40
    started = Time.now.to_f
    begin
      beatno = ((Time.now.to_f - started) / @slice).to_i
      if beatno >= @markers[0][0] && @markers.length > 1 && beatno < @markers[1][0]
        print @markers[0][1]
        @markers.shift
        if @markers.length == 1
          sleep 1
          print "  \e[0m\e[2m   ... Still in time ?\e[0m"
        end
        puts
      end
      sleep(@slice / loops_per_slice) if @markers.length == 1
    end while wait_thr.alive?
    # wait for end of thread
    wait_thr.join

    sleep 0.5
    puts
    return true
  end

  
  def extract_beats

    puts
    puts @markers[0][1]

    # check lengths
    len_tempo = sox_query(@template, 'Length')
    len_rec = ( @warned  ?  len_tempo  :  sox_query(@recording, 'Length') )
    puts "\e[2m  Length of played template = %.2f sec, length of untrimmed recording = %.2f\e[0m" % [len_tempo, len_rec]

    @warned = if (len_tempo - len_rec).abs > @slice / 4
                puts "\n\n\e[0;101mWARNING:\e[0m Length of generated wav (intro + silence + outro) = #{len_tempo}\n  is much different from length of parallel recording = #{len_rec} !\n  So your solo playing cannot be extracted with good precision,\n  and results of analysis below may therefore be dubious.\n\n      \e[32mBut you can still judge by ear !\n\n      Have you still been   \e[34mIN TIME\e[32m   at the end ?\n\n\e[0m  Remark: Often a second try is fine; if not however,\n          restarting your computer may help ...\n\n"                
                true
              else
                false
              end

    # Extract solo-part of user audio

    # Each beat is less than half silent (see its generation), so the
    # stretch where sound is expected is @beats_keep - 0.5. We also
    # have ensured, that overall jitter is not more than 0.25 beats
    # (see above); so we should be safe, if we extend start by 0.25
    # beats to the left and extend end by 0.25 beats to the right
    # (hence duration by 0.5 beats)

    # Example for steady playing throught intro, keep and outro
    # beats_intro == beats_outro == 1
    # beats_keep == 3
    # 
    #         ####    ####    ####    ####    ####            sound
    #             ....    ....    ....    ....    ....        silence
    #               rrrrrrrrrrrrrrrrrrrrrrrr                  record
    #

    # for calculation below we assume, that recording starts after
    # playing and that both end at the same time, but this is only a
    # guess. Later we will assume, that the first beat is on time
    
    total_len = 60.0 * (@beats_intro + @beats_keep + @beats_outro) / @tempo
    start = [0.0,
             (total_len - len_rec) + 60.0 * (@beats_intro - 0.25) / @tempo].max
    duration = 60.0 * @beats_keep / @tempo
    puts "\e[2m  Analysis start = %.2f sec, duration = %.2f\e[0m" % [start, duration]
    
    sys "sox #{@recording} #{@trimmed} trim #{start} #{duration}"

    # get frequency content
    times_freqs = sys("aubiopitch --bufsize %s --hopsize %s --pitch %s -i #{@trimmed}" % [$aubiopitch_sizes[$opts[:time_slice]], $conf[:pitch_detection]].flatten, $sox_fail_however).lines.map {|l| l.split.map {|x| Float(x)}}

    # compute timestamps of desired hole
    hole_was = hole = nil
    hole_started_at = nil
    first_beat_at = nil
    holes_in_a_row = 0
    @beats_found = Array.new
    times_freqs.each do |t, f|
      hole_was = hole
      hole, _, _, _ = describe_freq(f)
      if hole == $typical_hole
        hole_started_at = t if hole != hole_was
        holes_in_a_row += 1
        if holes_in_a_row == 3
          @beats_found << hole_started_at
          # let beats start at 0.0
          first_beat_at ||= @beats_found[0]
          @beats_found[-1] -= first_beat_at
        end
      else
        holes_in_a_row = 0
      end
    end

    # plot results
    @beats_expected = (0 ... @beats_keep).to_a.map {|x| x*@slice}
    maxchars = ($term_width - 30) * 0.8
    scale = maxchars / @beats_expected[-1]
    puts
    puts "\e[2mTimestamps:\n\n"
    [['E', "\e[0m\e[34m  Expected:", @beats_expected],
     ['Y', "\e[0m\e[32mYou played:", @beats_found]].each do |char, label, beats|
      print "  #{label}  "
      nchars = 0
      # this could be done simpler, but then rounding-errors may add up
      beats.each do |beat|
        while nchars < ((beat - beats[0]) * scale).round do
          print '.'
          nchars += 1
        end
        print char
        nchars += 1
      end
      print "    \e[0m\e[2m(%.2f s)" % beats[-1] if beats.length > 1
      print "... no beats found ..." if beats.length == 0
      puts "\e[0m\n"
    end
  end

  
  def judge_result
    puts
    if @@history.length > 0
      puts "History of results with the current set of parameters so far:\e[2m"
      @@history.each {|h| puts "  #{h}"}
      puts "(and see the new result below)"
    else
      puts "\e[2mNo history of results with the current set of parameters so far."
    end
    puts "\e[0m"
    
    if @warned
      stand_out "Unfortunately, further analysis is NOT POSSIBLE\ndue to the warning above.\n\nPlease try again.", turn_red: 'NOT POSSIBLE'
      @@history << 'analysis-not-possible'
    elsif @beats_found.length != @beats_keep
      lom = ( @beats_found.length < @beats_keep ? 'LESS' : 'MORE' )
      what = lom + '  than expected'
      stand_out "You played #{(@beats_keep - @beats_found.length).abs} beats  #{what}\n(#{@beats_found.length} instead of #{@beats_keep}) !\nYou need to get this right, before further\nanalysis is possible.   Please try again.", turn_red: what
      @@history << 'you-played-' + lom.downcase + '-than-expected'

    else
      avg_diff = @beats_found.zip(@beats_expected).
                   map {|x, y| (x - y).abs}.sum / @beats_keep
      deviation = '%.1f' % ( 100.0 * avg_diff / @slice )
      stand_out "Number of beats matches.\n\n#{deviation} percent average deviation", all_green: true
      puts "\n\e[2mAverage deviation for #{@beats_keep} beats is %.3f sec, time-slice %3.1f sec.\e[0m" % [avg_diff, @slice]

      @@history << "#{deviation}-percent-deviation"
    end
    puts
  end
  
end


class HearTempo < QuizFlavour

  $q_f2t[self] = %w(no-mic)
  
  @@choices = {:easy => %w(70 90 110 130),
               :hard => %w(50 60 70 80 90 100 110 120 130 140 150 160)}
  
  def initialize
    super
    @choices = @@choices[$opts[:difficulty]].clone
    @choices_orig = @choices.clone
    @num_beats = 6
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @prompt = 'Choose the Tempo you have heard:'
    @help_head = 'Tempo'
    @sample = quiz_generate_tempo('s', Integer(@solution), @num_beats, 0, 0)
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", one tempo out of #{@@choices[$opts[:difficulty]].length}"
  end

  def issue_question
    puts
    puts "\e[34mPlaying #{@num_beats} beats of Tempo to find\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    sleep 0.1
    puts
    make_term_immediate
    $ctl_kb_queue.clear    
    play_recording_and_handle_kb_simple @sample, true
    make_term_cooked
  end

  def help2
    puts "For help, choose one of the answer-tempos to be played:"
    choose_prepare_for
    answer = choose_interactive('Tempo to compare:', @choices.map {|x| "compare-#{x}"}) do |tag|
      "compare with #{@help_head} #{tag_desc(tag)}" 
    end
    choose_clean_up
    if answer
      help = quiz_generate_tempo('h', Integer(answer.gsub('compare-','')), @num_beats, 0, 0)
      puts "\nPlaying #{@num_beats} beats in tempo #{answer} bpm"
      make_term_immediate
      $ctl_kb_queue.clear    
      play_recording_and_handle_kb_simple help, true
      make_term_cooked
    else
      puts "\nNo Tempo selected to play.\n\n"
    end
    puts "\n\e[2mDone with compare, BACK to original question.\e[0m"
  end

  def help2_desc
    ['.HELP-COMPARE', 'Play one of the choices']
  end

end


class NotInScale < QuizFlavour

  $q_f2t[self] = %w(scales no-mic)

  def initialize
    super
    @scale_name = $all_quiz_scales[$opts[:difficulty]].sample
    @scale_holes, _, _, _ = read_and_parse_scale(@scale_name, $harp)
    # choose one harp-hole, which is not in scale but within range or nearby
    holes_notin = $harp_holes - @scale_holes
    # Remove holes above and below scale
    # neighbours; calculate in semis to catch equivs
    holes_notin.shift while holes_notin.length > 0 &&
                            $harp[holes_notin[0]][:semi] < $harp[@scale_holes[0]][:semi]
    holes_notin.pop while holes_notin.length > 0 &&
                          $harp[holes_notin[-1]][:semi] > $harp[@scale_holes[-1]][:semi]
    @hole_notin = holes_notin.sample
    @holes = @scale_holes.shuffle
    @scale_holes_shuffled = @holes.clone
    @holes[rand(@holes.length)] = @hole_notin

    # hide holes as x1, x2, ...
    @hide = @holes.each_with_index.map {|h,i| [h, "h#{i+1}"]}.to_h
    @hide[(@scale_holes - @holes)[0]] = 'h0'
    @choices = @holes.map {|h| @hide[h]}
    @choices_orig = @choices.clone
    @solution = @hide[@hole_notin]
    @prompt = "Which hole does not belong to scale '#{@scale_name}' ?"
    @help_head = 'Hole (in disguise)'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", choosing one of #{$all_quiz_scales[$opts[:difficulty]].length} scales"
  end
  
  def after_solve
    puts
    puts "Playing note #{@solution}, hole #{@hole_notin}, that was foreign in scale #{@scale_name} ..."
    sleep 0.1
    puts
    play_hons(hons: [@hole_notin])
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying scale \e[94m#{@scale_name}\e[34m modified: shuffled and one note replaced by a foreign one\e[0m"
    puts "\e[2mThe " + self.class.describe_difficulty + "\e[0m"
    puts
    play_hons(hons: @holes, hide: @hide)
  end

  def help2
    puts "Play notes of modified scale in ascending order:"
    @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]}
    play_hons(hons: @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]},
              hide: @hide)
  end

  def help2_desc
    ['.HELP-MOD-ASC', 'Play holes of modified scale in ascending order']
  end
  
  def help3
    puts "Playing original scale in ascending order:"
    play_hons(hons: @scale_holes, hide: :all)
  end

  def help3_desc
    ['.HELP-ORIG-ASC', 'Play original scale ascending']
  end

  def help4
    puts "Playing original scale shuffled, just like the question:"
    play_hons(hons: @scale_holes_shuffled, hide: :all)
  end

  def help4_desc
    ['.HELP-ORIG-SHUF', 'Play original scale shuffled']
  end

  def help5
    puts "Play and show original scale shuffled ('h0' is the foreign hole):"
    play_hons(hons: @scale_holes_shuffled, hide: @hide)
  end

  def help5_desc
    ['.HELP-SHOW-ORIG-SHUF', 'Kind of solve: Play and show original scale shuffled']
  end

end


def get_random_interval sorted: false
  # favour lower holes
  all_holes = ($harp_holes + Array.new(6, $harp_holes[0 .. $harp_holes.length/2])).flatten.shuffle
  loop do
    err "Internal error: no more holes to try" if all_holes.length == 0
    holes_inter = [all_holes.shift, nil]
    $intervals_quiz[$opts[:difficulty]].clone.shuffle.each do |inter|
      holes_inter[1] = $semi2hole[$harp[holes_inter[0]][:semi] + inter]
      if holes_inter[1]
        if rand > 0.8 && !sorted
          holes_inter.rotate!
          holes_inter << -inter
        else
          holes_inter << inter
        end
        holes_inter << $intervals[inter][0]
        # some compositions for consistency and convenience
        holes_inter << holes_inter[0] +
                       ' .. ' + ( holes_inter[2] > 0 ? 'up' : 'down' ) + ' .. ' +
                       holes_inter[3]
        # 0,1: holes,
        #   2: numerical semitone-interval with sign
        #   3: interval long name
        #   4: description, e.g. '+1 ... up ... maj Third'
        return holes_inter
      end
    end
  end
end


def get_holes_shifts

  # favour lower holes and allow a hole to appear multiple times
  all_holes = ($harp_holes + Array.new(6, $harp_holes[0 .. $harp_holes.length/2])).then {|x| [x,x,x,x]}.flatten
  # favour intervals up to perfect fifth
  all_shifts = ($std_semi_shifts + $std_semi_shifts.select {|s| s.abs <= 7}.then {|x| [x,x,x,x]}).flatten

  unshifted = shift = shifted = nil
  400.times do
    unshifted = all_holes.sample($num_quiz_replay)
    semi_span = all_holes.map {|h| $harp[h][:semi]}.minmax
    # mostly avoid holes, that span more than one octave
    redo if semi_span[1] - semi_span[0] > 12 && rand > 0.1
    shift = all_shifts.sample
    shifted = unshifted.map{|h| $harp[h][:shifted_by][shift]}
    break(:found) if shifted.all?
  end == :found or err "Internal error: too many tries"
  idesc = if shift > 0
            $intervals[shift][0] + ' UP'
          else
            $intervals[-shift][0] + ' DOWN'
          end

  return [unshifted,
          shift,
          "%+dst, #{idesc}" % shift,
          unshifted + shifted,
          shifted[0],
          shifted]
end


def stand_out text, all_green: false, turn_red: nil
  print "\e[32m" if all_green
  puts
  lines = text.lines.map(&:chomp)
  maxl = lines.map(&:length).max
  puts '  + ' + ( '-' * maxl ) + ' +'
  lines.each do |l|
    sleep 0.05
    if turn_red && md = l.match(/^(.*)(\b#{turn_red}\b)(.*)$/)
      ll = md[1] + "\e[31m" + md[2] + "\e[0m" + md[3] + (' ' * (maxl - l.length))
    else
      ll = ( "%-#{maxl}s" % l )
    end
    puts "  | #{ll} |"
  end
  puts '  + ' + ( '-' * maxl ) + ' +'
  sleep 0.05
  print "\e[0m"
end


def get_harp2song downcase: false, basic_set: false
  harps = if basic_set
            %w(G A C D)
          else
            if $opts[:sharps_or_flats] == :flats
              %w(G Af A Bf B C Df D Ef E F Gf)
            else
              %w(G Gs A As B C Cs D Ds E F Fs)
            end
          end
  harps.map!(&:downcase) if downcase
  harp2song = Hash.new
  harps.each do |harp|
    harp2song[harp] = semi2note(note2semi(harp + '4') + 7)[0..-2].capitalize
    harp2song[harp].downcase! if downcase
  end
  harp2song
end


def key2semi note
  semi = note2semi(note.downcase + '4')
  semi += 12 if semi < note2semi('gf4')
  semi
end


def quiz_hint_in_handle_holes_simple solve_text, item, holes, hide
  choices2desc = {'SOLVE-PRINT' => "Solve: Print #{item}, but keep current question",
                  'HELP-PLAY' => "Play #{item}, so that you may replay it"}
  answer = choose_interactive($resources[:quiz_hints] % $quiz_flavour,
                              choices2desc.keys + [$resources[:just_type_one]]) {|tag| choices2desc[tag]}
  clear_area_comment
  clear_area_message
  case answer
  when 'SOLVE-PRINT'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0mSolution:"
    print solve_text
    puts "\n\n\e[0m\e[2many char to continue ..."
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
    $msgbuf.print 'Solution:   ' + holes.join('  '), 6, 8, :quiz_solution
  when 'HELP-PLAY'
    puts "\e[#{$lines[:comment] + 1}H"
    puts "Help: Playing #{item}"
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_simple(holes, hide: [hide, :help])
    sleep 1
  end
  clear_area_comment
  clear_area_message
end


def quiz_hint_in_handle_holes_shifts holes_shifts
  choices2desc = {'HELP-PRINT-UNSHIFTED' => "Solve: Print unshifted sequence, but keep current question",
                  'SOLVE-PRINT-SHIFTED' => "Solve: Print shifted sequence, but keep current question",
                  'HELP-PLAY-UNSHIFTED' => "Play unshifted sequence; similar to '.'",
                  'HELP-PLAY-BOTH' => "Play unshifted sequence first and then shifted, so that you may replay it"}
  answer = choose_interactive($resources[:quiz_hints] % $quiz_flavour,
                              choices2desc.keys + [$resources[:just_type_one]]) {|tag| choices2desc[tag]}
  clear_area_comment
  clear_area_message
  $ctl_kb_queue.clear
  case answer
  when 'HELP-PRINT-UNSHIFTED'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0mHelp: unshifted sequence is:\n\n\n"
    puts "\e[32m  #{holes_shifts[0].join('  ')}"
    puts "\n\n\e[0m\e[2many char to continue ..."
    $ctl_kb_queue.deq
    $msgbuf.print 'Help, unshifted:   ' + holes_shifts[0].join('  '), 6, 8, :quiz_solution
  when 'SOLVE-PRINT-SHIFTED'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0m\e[2mUnshifted is:"
    puts "  #{holes_shifts[0].join('  ')}"
    puts "\n\e[0mSolution: shifted sequence is:"
    puts "\e[32m  #{holes_shifts[5].join('  ')}"
    puts "\n\e[0m\e[2mShifted by: #{holes_shifts[2]}"
    puts "\e[0m\e[2many char to continue ..."
    $ctl_kb_queue.deq
    $msgbuf.print 'Solution, shifted:   ' + holes_shifts[5].join('  '), 6, 8, :quiz_solution
  when 'HELP-PLAY-UNSHIFTED'
    puts "\e[#{$lines[:comment] + 1}H"
    puts
    print "      \e[32mUnshifted:   "
    play_holes_or_notes_simple(holes_shifts[0], hide: :help)
    sleep 2
    print "  \e[32mFirst shifted:   "
    play_holes_or_notes_simple([holes_shifts[4]], hide: :help)
    sleep 1
  when 'HELP-PLAY-BOTH'
    puts "\e[#{$lines[:comment] + 1}H"
    puts
    print "  \e[32mUnshifted:   "
    play_holes_or_notes_simple(holes_shifts[0], hide: :help)
    sleep 2
    print "    \e[32mShifted:   "
    play_holes_or_notes_simple(holes_shifts[5], hide: [:all, :help])
    sleep 1
  else
    fail "Internal error: #{answer}" if answer
  end
  print "\e[0m"
  clear_area_comment
  clear_area_message
  $ctl_kb_queue.clear
end


def prepare_listen_perspective_for_quiz
  $msgbuf.print "or issue signal ctrl-z for another flavour", 3, 5, later: true
  $msgbuf.print "Type 'H' for quiz-hints, RETURN for next question,", 3, 5, :quiz
end


def quiz_generate_tempo prefix, bpm, num_intro, num_silence, num_outro
  # we always use to files to generate a whole period, so use 30
  # instead of 60 below
  half_slice = 30.0 / bpm
  # make sure that sound is always slightly less than half a period
  less_half_slice = '%.2f' % ( half_slice * 0.7 )
  more_half_slice = '%.2f' % ( half_slice * 1.3 )
  pluck = "#{$dirs[:tmp]}/pluck.wav"
  less_silence = "#{$dirs[:tmp]}/less_silence.wav"
  more_silence = "#{$dirs[:tmp]}/more_silence.wav"
  result = "#{$dirs[:tmp]}/#{prefix}.wav"
  
  sys "sox -q -n #{pluck} synth #{less_half_slice} pluck %#{$harp[$typical_hole][:semi]}", $sox_fail_however
  sys "sox -q -n #{less_silence} trim 0.0 #{less_half_slice}", $sox_fail_however
  sys "sox -q -n #{more_silence} trim 0.0 #{more_half_slice}", $sox_fail_however
  files = [Array.new(num_intro, [pluck, more_silence]),
           Array.new(num_silence, [less_silence, more_silence]),
           Array.new(num_outro, [pluck, more_silence])].flatten
  sys "sox #{files.join(' ')} #{result}", $sox_fail_however

  result
end


def choose_clean_up
  clear_area_comment
  clear_area_message
  make_term_cooked
  print "\e[#{$lines[:comment_tall] - 1}H\e[K"
end


def choose_prepare_for
  prepare_term
  make_term_immediate
  $ctl_kb_queue.clear
  ($term_height - $lines[:comment_tall] + 3).times do
    sleep 0.01
    puts
  end
  print "\e[#{$lines[:comment_tall] - 1}H" + get_dim_hline + "\e[0m"
end


def do_restart_animation

  puts "\e[?25l"  ## hide cursor
  $splashed = true
  info = 'quiz'
  dots = '...'
  push_front = dots + info
  shift_back = info + dots
  txt = dots + info + dots + info + dots
  ilen = txt.length
  nlines = ($term_height - $lines[:comment_tall] - 1)
  nlines.times do
    len = push_front.length
    txt[0 .. len - 1] = push_front if txt[0 .. len - 1] == ' ' * len
    puts "\e[2m\e[34m#{txt}\e[0m\e[K"
    sleep 0.02
    txt.prepend(' ')
    txt.chomp!(shift_back) if txt.length > ilen  + shift_back.length - 3
  end
  puts "\e[K"
  sleep 0.03
end


# extra may contain meta-keywords like 'choose'; flavour only real
# flavours like 'hear-scale'
def get_accepted_flavour_from_extra

  # flavour is nil or the flavour that can be determined directly from
  # $extra; flavour_choices is the range of flavours to choose from at
  # random, e.g. after ctrl-z
  env_flavour = ENV['HARPWISE_RESTARTED_AFTER_SIGNAL']
  flavour,
  flavour_collection,
  flavour_choices = if env_flavour
                      [get_random_flavour($quiz_tag2flavours[env_flavour]),
                       env_flavour,
                       $quiz_tag2flavours[env_flavour]]
                    else
                      if $quiz_tag2flavours['meta'].include?($extra) 
                        if $quiz_tag2flavours['collections'].include?($extra)
                          [nil, $extra, $quiz_tag2flavours[$extra]]
                        else
                          # variations of random
                          [nil, nil, $quiz_flavour2class.keys]
                        end
                      elsif $extra == 'choose'
                        [nil, nil, $quiz_flavour2class.keys]
                      else
                        [$extra, nil, $quiz_flavour2class.keys]
                      end
                    end

  ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] = flavour_collection || 'all'
  
  print "\e[2mChoosing flavour at random, 1 out of #{flavour_choices.length}.  " if !flavour && $extra != 'choose'
  puts "\e[2mTo start over issue signal \e[0m\e[32mctrl-z\e[0m"
  puts
  sleep 0.1
  
  if $extra == 'choose' && !env_flavour
    while !flavour
      flavour = choose_flavour(flavour_choices, flavour_collection)
    end
    # maybe user has chosen a collection right above
    if $quiz_tag2flavours['collections'].include?(flavour)
      flavour_choices = $quiz_tag2flavours[flavour]
      ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] = flavour_collection = flavour
      flavour = nil
    end
  end
  
  first_iteration = true

  # loop until chosen flavour is accepted; endless loop, left via
  # return
  loop do 

    flavour ||= get_random_flavour(flavour_choices, true)
    
    # now we have a valid flavour, so inform user and get confirmation
    has_issue_question = $quiz_flavour2class[flavour].method_defined?(:issue_question)
    puts
    unless first_iteration
      puts get_dim_hline
      puts
    end
    puts "Quiz Flavour is:   \e[34m#{flavour}\e[0m"
    puts "switches \e[2m>>>> to full listen-perspective\e[0m" unless has_issue_question
    sleep 0.05
    puts
    sleep 0.05
    puts get_extra_desc_single(flavour)[1..-1].
           map {|l| '  ' + l + "\n"}.
           join.chomp +
         ".\n"
    if has_issue_question
      # describe_difficulty will be done in issue_question
    else
      # these flavours will switch to listen perspective
      puts
      print "  \e[2m"
      print 'First ' + $quiz_flavour2class[flavour].describe_difficulty
      puts "\e[0m"
      sleep 0.1
    end
    puts

    # ask for user feedback
    clause = ( )
    puts "\e[32mPress any key to start\e[0m\e[2m, BACKSPACE for another random flavour" +
         ( flavour_collection  ?  " (#{flavour_collection})"  :  '' ) +
         "\nor TAB to choose one explicitly ...\e[0m"
    char = one_char

    if char == 'BACKSPACE'
      flavour = nil
    elsif char == 'TAB'
      flavour = choose_flavour(flavour_choices, flavour_collection)
      # maybe user has chosen a collection
      if $quiz_tag2flavours['collections'].include?(flavour)
        ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] = flavour_collection = flavour
        flavour_choices = $quiz_tag2flavours[flavour]
        flavour = get_random_flavour($quiz_tag2flavours[flavour])
      end
    else
      return flavour
    end
    puts
    first_iteration = false
    # next loop iteration
  end
end


def choose_flavour flavour_choices, flavour_collection
  flavour = nil
  loop do
    choose_prepare_for
    flavour = choose_interactive("Please choose among #{flavour_choices.length} flavours and #{$quiz_tag2flavours['collections'].length} collections" +
                                 ( flavour_collection  ?  " (#{flavour_collection})"  :  '' ) + ':',
                                 [flavour_choices, ';COLLECTIONS->',
                                  $quiz_tag2flavours['collections'],
                                  'describe-all'].flatten) do |tag|
      if tag == 'describe-all'
        'Describe all flavours and flavour collections in detail'
      elsif $quiz_tag2flavours['meta'].include?(tag)
        make_extra_desc_short(tag, "Flavour collection '#{tag}' (#{$quiz_tag2flavours[tag].length})")
      else
        make_extra_desc_short(tag, "Flavour '#{tag}'")
      end
    end
    choose_clean_up
    if !flavour
      puts "\e[0mNo flavour chosen, please try again."
      puts "\e[2m#{$resources[:any_key]}\e[0m"
      one_char
      redo
    elsif flavour == "describe-all"
      puts "The #{$extra_desc[:quiz].length} available flavours and flavour-collections:"
      puts
      puts get_extra_desc_all.join("\n")
      puts
      puts "\e[2mPress any key to choose again ...\e[0m"
      one_char
      redo
    end
    break
  end
  flavour
end


def get_random_flavour flavour_choices, silent = false
  # choose a random flavour that has not been used recently
  unless silent
    puts "\e[2mChoosing a random flavour ...\e[0m"
    sleep 0.1
  end
  flavours_last = $pers_data['quiz_flavours_last'] || []
  try_flavour = nil
  choices = flavour_choices.shuffle
  loop do
    try_flavour = choices.shift
    break if !flavours_last.include?(try_flavour) || choices.length == 0
  end
  flavours_last << try_flavour
  flavours_last.shift if flavours_last.length > 4
  $pers_data['quiz_flavours_last'] = flavours_last
  try_flavour
end


def get_dim_hline
  "\e[2m" + ( '-' * ( $term_width * 0.5 )) + "\e[0m"
end


def back_to_comment_after_mode_switch
  if $other_mode_saved[:conf]
    clear_area_comment
    puts "\e[#{$lines[:comment_tall]}H"
  end
end


def choose_and_play_answer_scale
  puts "For help, choose one of the answer-scales to be played:"
  choose_prepare_for
  answer = choose_interactive("Scale to compare:", @choices.map {|s| "compare-#{s}"}) do |tag|
    "#{@help_head} #{tag_desc(tag)}" 
  end
  choose_clean_up
  if answer
    scale = answer.gsub('compare-','')
    puts "\e[2mPlaying scale \e[0m\e[34m#{scale}\e[0m\e[2m with \e[0m\e[34m#{@scale2holes[scale].length}\e[0m\e[2m holes."
    puts
    play_hons(hons: @scale2holes[scale], hide: @state[:hide_holes])
  else
    puts "\nNo scale selected to play.\n\n"
  end
  puts "\n\e[2mDone with compare, BACK to original question.\e[0m"
end


def re_calculate_quiz_difficulty
  $opts[:difficulty] = (rand(100) > $opts[:difficulty_numeric] ? :easy : :hard)
  unless $num_quiz_replay_explicit
    nqr = case $quiz_flavour
          when 'play-shifted'
            $opts[:difficulty] == :easy  ?  3  :  6
          when 'replay'
            $opts[:difficulty] == :easy  ?  4  :  8
          end
    $num_quiz_replay = nqr if nqr
  end
end


def make_extra_desc_short extra, head
  desc_lines = get_extra_desc_single(extra)
  head += " (#{desc_lines[0].gsub(' ','')})" if desc_lines[0] != extra
  head += ': '
  desc = desc_lines[1..-1].join(' ').
           split(/(?=\s+)/).
           inject("") {|m,w| m += w if m.length < ($term_width - w.length - head.length - 8); m}.
           strip
  head + desc + ' ...'
end
