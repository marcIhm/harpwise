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
  %w(TSTP QUIT).each do |sig|
    Signal.trap(sig) do
      # do some actions of at_exit-handler here
      sane_term
      puts "\e[#{$lines[:message_bottom]}H\e[0m\e[K"
      puts "\e[0m\e[34m ... quiz start over ... \e[0m\e[K"
      puts "\e[K"
      if $pers_file && $pers_data.keys.length > 0 && $pers_fingerprint != $pers_data.hash
        File.write($pers_file, JSON.pretty_generate($pers_data) + "\n")
      end
      ENV['HARPWISE_RESTARTED'] = 'yes'
      exec($full_command_line)
    end
  end

  inherited = ENV['HARPWISE_INHERITED_FLAVOUR_COLLECTION']
  
  if ENV['HARPWISE_RESTARTED']
    do_animation 'quiz', $term_height - $lines[:comment_tall] - 1
    puts "\e[0m\e[2mStarting over with a different flavour due to signal \e[0m\e[32mctrl-z\e[0m\e[2m (quit, tstp).\e[0m"
  else
    animate_splash_line
    puts "\e[2mPlease note, that when playing holes, the normal play-controls\n(e.g. space or 'h') are available but not advertised.\e[0m"
    puts "\e[2mTo start over issue signal \e[0m\e[32mctrl-z\e[0m\e[2m (quit, tstp) \e[0m\e[32mat any time\e[0m"
  end
  puts
  sleep 0.1

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
  $quiz_flavour = get_accepted_flavour_from_extra(inherited) unless $other_mode_saved[:conf]
  
  # for listen-perspective, dont show solution immediately
  $opts[:comment] = :holes_some
  $opts[:immediate] = false
  

  # Actually start different quiz cases; all contain their own
  # infinite loop; First some special flavours (e.g. tempo or replay),
  # which have their own methods of checking the answer; then the
  # generic case, which presents a list of choices.

  # grep marker-string 'comment-marker-quiz-and-listen-perspective' to find related pieces
  # of code in other files
  
  # Describing the question is done here for the first question, but from the second
  # question on it is done in mode_licks.rb
  
  if $quiz_flavour == 'replay'

    back_to_comment_after_mode_switch
    puts
    puts "\e[34mNumber of holes to replay is: #{$num_quiz_replay}\e[0m"
    puts "\n\n\n"
    prepare_listen_perspective_for_quiz
    do_licks_or_quiz(lambda_quiz_hint: -> (holes, _, _, _) do
                       solve_text = "\e[0mHoles  \e[34mto replay\e[0m  are:\n\n\n" +
                                    "\e[32m       #{holes.join('  ')}"
                       quiz_hint_in_handle_holes_std(solve_text, 'sequence', holes, :all)
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
                       quiz_hint_in_handle_holes_std(solve_text, 'scale', holes, :all)
                     end)

    
  elsif $quiz_flavour == 'play-inter'

    holes_inter = get_random_interval_as_holes
    back_to_comment_after_mode_switch
    prompt_for_quiz_interval holes_inter
    sleep 2
    prepare_listen_perspective_for_quiz
    $hole_ref = holes_inter[0]
    do_licks_or_quiz(quiz_holes_inter: holes_inter,
                     lambda_quiz_hint: -> (holes, holes_inter, _, _) do
                       solve_text = "\e[0mInterval  \e[34m#{holes_inter[4]}\e[0m  is:\n\n\n" +
                                    "\e[32m                #{holes_inter[0]}  to  #{holes_inter[1]}"
                       quiz_hint_in_handle_holes_std(solve_text, 'interval', holes, holes[-1], true)
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
          handle_win_change if $ctl_sig_winch
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
          puts "\e[0mWhat's next?"
          puts 
          puts "\e[0m\e[32mPress any key for a new set of parameters or\n      BACKSPACE to redo with the current set ... \e[0m"
          drain_chars
          char = one_char
          puts
          if char == 'BACKSPACE'
            puts "Same parameters \e[2magain.\e[0m"
          else
            puts "New parameters."
            $opts[:difficulty] = ( rand(100) > $opts[:difficulty_numeric]  ?  :easy  :  :hard )
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

      catch :next do
        sleep 0.1
        puts
        flavour = $quiz_flavour2class[$quiz_flavour].new(first_round)
        first_round = false
        loop do  ## repeats of question
          catch :reissue do
            handle_win_change if $ctl_sig_winch
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
$q_class2colls = Hash.new

class QuizFlavour

  @@prevs = Array.new

  def initialize first_round
    @state = Hash.new
    @state_orig = @state.clone
    @holes_descs = $named_hole_sets.keys
    # default: dont try uncommon keys, may be overriden per flavour
    @difficulty_to_key_set = {easy: $common_harp_keys, hard: $common_harp_keys}
    # -1: not relevant at all
    #  0: key is not part of solution, but can be changed for broader coverage
    # +1: key is part or all of solution
    @key_contributes_to_solution = 0
    @samples_needed = true
  end

  def get_and_check_answer
    choose_prepare_for
    all_helps = ['.help-narrow', 'not_defined', 'not_defined']
    all_choices = [',again', @choices, ';controls-and-help->', ',solve', ',skip', ',describe', all_helps[0]].flatten
    choices_desc = {',again' => 'Repeat question',
                    ',solve' => 'Give solution and go to next question',
                    ',skip' => 'Give solution and Skip to next question without extra info',
                    ',describe' => 'Repeat initial description of flavour',
                    all_helps[0] => 'Remove some solutions, leaving less choices'}
    
    [help2_desc, help3_desc, help4_desc, help5_desc, help6_desc, help7_desc].each_with_index do |desc, idx|
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
        stand_out "Yes, '#{answer}' is RIGHT!\n\nSome extra info below.", all_green: true
        after_solve
      else
        stand_out "Yes, '#{answer}' is RIGHT!", all_green: true
      end
      puts
      return next_or_reissue_and_set_key_plus_difficulty
    end
    case answer
    when nil
      stand_out "No input or invalid key?\nPlease try again or\nterminate with ctrl-c ..."
      return :reask
    when ',again'
      stand_out 'Asking question again.'
      puts
      return :reissue
    when ',solve', ',skip'
      sol_text = if @solution.is_a?(Array) && @solution.length > 1
                   "  any of  #{@solution.join(',')}"
                 else
                   "        #{[@solution].flatten[0]}"
                 end
      if answer != ',skip' && self.respond_to?(:after_solve)
        stand_out "The correct answer is:\n\n#{sol_text}\n\nSome extra info below."
        after_solve
      else
        stand_out "The correct answer is:\n\n#{sol_text}\n"
      end
      puts
      return next_or_reissue_and_set_key_plus_difficulty
    when ',describe'
      has_issue_question = $quiz_flavour2class[$quiz_flavour].method_defined?(:issue_question)
      describe_flavour $quiz_flavour, has_issue_question
      return :reask
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
    when all_helps[5]
      help6
      return :reask
    when all_helps[6]
      help7
      return :reask
    else
      stand_out "Sorry, your answer '#{answer}' is wrong\nplease try again ...", turn_red: 'wrong'
      @choices.delete(answer)
      return :reask
    end
  end

  def self.difficulty_head
    "difficulty is \e[0m\e[34m#{$opts[:difficulty].upcase}\e[0m\e[2m"
  end

  def play_hons hide: nil, reverse: false, hons: nil, newline: true
    hons ||= @holes
    make_term_immediate
    $ctl_kb_queue.clear
    puts if newline
    play_holes_or_notes_and_handle_kb( reverse  ?  hons.reverse  :  hons,
                                       hide: [hide, :help] )
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

  def help6_desc
    nil
  end

  def help7_desc
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

  # only called from get_and_check_answer
  def next_or_reissue_and_set_key_plus_difficulty
    puts
    puts get_dim_hline
    puts
    puts "\e[0mWhat's next?"
    puts
    if @key_contributes_to_solution > 0
      puts "\e[32m\e[92mAny key\e[0m\e[32m for next   \e[34m#{$quiz_flavour}\e[0m\e[32m   with a new random key"
    elsif @key_contributes_to_solution < 0
      puts "\e[32m\e[92mAny key\e[0m\e[32m for next   \e[34m#{$quiz_flavour}\e[0m\e[32m"
    else
      puts "\e[32m\e[92mAny key\e[0m\e[32m for next   \e[34m#{$quiz_flavour}\e[0m\e[32m      \e[92mTAB\e[0m\e[32m also changes key at random"
    end
    puts "\e[92mBACKSPACE\e[0m\e[32m to re-ask this one      \e[92mctrl-z\e[0m\e[32m for a different flavour\e[0m"
    char = one_char
    puts
    if char == 'BACKSPACE'
      puts "Same question again."
      puts
      sleep 0.2
      recharge
      return :reissue
    end
    re_calculate_quiz_difficulty
    if ( char == 'TAB' && @key_contributes_to_solution == 0) ||
       @key_contributes_to_solution > 0
      change_key(silent: true)
      if @key_contributes_to_solution > 0
        puts "New question and new key."
      else
        puts "New question and new key of #{$key}."
      end
    else
      if @key_contributes_to_solution > 0
        puts "New question but same key."
      elsif @key_contributes_to_solution < 0
        puts "New question."
      else
        puts "New question but same key of #{$key}."
      end
    end
    puts
    sleep 0.2
    return :next  
  end

  # only used in some flavours
  def print_chart_with_notes spread: nil, hide: nil, mark: nil
    chart = $charts[:chart_notes]
    chart.each_with_index do |row, ridx|
      spread_in_row = row[0 .. -2].any? {|c| spread && spread == c.strip.gsub(/\d+/,'')}
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        hcell = ' ' * cell.length
        hcell[hcell.length / 2] = ( spread_in_row  ?  '-'  :  '?' )
        cell_sg = cell.strip.gsub(/\d+/,'')
        print(
          if spread_in_row
            if rand > 0.7 || cell_sg == spread
              "\e[34m#{hcell}\e[0m"
            else
              cell
            end
          else
            if cell_sg == hide
              "\e[34m#{hcell}\e[0m"
            else
              if cell_sg == mark
                "\e[34m#{cell}\e[0m"
              else
                cell
              end
            end
          end
        )
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end
  end

  # only used in some flavours
  def print_mapping hide_note: nil, color: true, no_notes: false, no_semis: false, sets: nil
    cdim, cbright = if color
                      ["\e[34m", "\e[94m"]
                    else
                      ["\e[2m", "\e[0m"]
                    end
    semi_min = @holes_descs.map {|d| $named_hole_sets[d]}.flatten.
                 map {|h| $harp[h][:semi]}.min
    (sets || @holes_descs).each_with_index do |desc, idx|
      nmd_holes = $named_hole_sets[desc]
      err "Internal error: no named holes for '#{desc}'" unless nmd_holes && nmd_holes.length > 0
      holes = nmd_holes.map {|h| "#{h}  "}
      notes = nmd_holes.map do |h|
        n = $harp[h][:note].gsub(/\d+$/,'')
        n = '?' if hide_note && n == hide_note
        "#{n.rjust(3)}  "
      end
      semis = nmd_holes.map {|h| "%+dst  " % ( $harp[h][:semi] - semi_min )}
      maxlen = (holes + notes + semis).map(&:length).max

      puts "#{cdim}  holes '#{desc}':#{cbright}"
      pr_in_cols holes.map {|x| x.rjust(maxlen)}

      unless no_notes
        puts "#{cdim}  notes:#{cbright}"
        pr_in_cols notes.map {|x| x.rjust(maxlen)}
      end

      unless no_semis
        puts "#{cdim}  semis to first:#{cbright}"
        pr_in_cols semis.map {|x| x.rjust(maxlen)}
      end

      puts if idx == 0
    end
  end

  # only used in some flavours
  def pr_in_cols cells
    head = '        '
    print head
    column = head.length
    cells.each do |cell|
      if column + cell.length > $term_width - 2
        puts 
        print head
        column = head.length
      end
      print cell
    end
    puts
  end

  # Some methods, that are only used in some flavours
  
  def change_key silent: false, key: nil
    if key
      $key = key
    else
      $key = ( @difficulty_to_key_set[$opts[:difficulty]] - [$key] ).sample
    end
    $samples_needed = @samples_needed
    set_global_vars_late
    set_global_musical_vars
    unless silent
      if @key_contributes_to_solution > 0
        puts "New key."
      elsif @key_contributes_to_solution == 0
        puts "New key of #{$key}."
      else
        # no output
      end
      puts
    end
  end

  def print_chart_holes_as_semitones
    chart = get_chart_with_intervals(prefer_names: false, ref: @holes[0])
    chart.each_with_index do |row, ridx|
      print '  '
      row[0 .. -2].each_with_index do |cell, cidx|
        print cell
      end
      puts "\e[0m\e[2m#{row[-1]}\e[0m"
    end  
  end


  def print_chart_holes_as_notes
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
  
end



# The three classes below are mostly done within do_licks, so the
# classes here are not complete

class Replay < QuizFlavour

  $q_class2colls[self] = %w(mic)

  def self.describe_difficulty
    if $num_quiz_replay_explicit
      "number of holes to replay is #{$num_quiz_replay} (explicitly set)"
    else
      QuizFlavour.difficulty_head + ", number of holes to replay is #{$num_quiz_replay}"
    end
  end
end


class PlayScale < QuizFlavour

  $q_class2colls[self] = %w(mic scales)

  def self.describe_difficulty
    HearScale.describe_difficulty
  end
end


class PlayInter < QuizFlavour

  $q_class2colls[self] = %w(mic inters)

  def self.describe_difficulty
    AddInter.describe_difficulty
  end
end


class PlayShifted < QuizFlavour

  $q_class2colls[self] = %w(mic)

  def self.describe_difficulty
    $num_quiz_replay = {easy: 3, hard: 6}[$opts[:difficulty]]
    QuizFlavour.difficulty_head +
      ", #{$num_quiz_replay} holes to be shifted by one of #{$std_semi_shifts.length} intervals"
  end
end


class HearScale < QuizFlavour

  $q_class2colls[self] = %w(scales no-mic)
  
  def initialize first_round
    super
    
    @choices = $all_quiz_scales[$opts[:difficulty]].clone
    @choices_orig = @choices.clone

    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    
    @sorted, _ = read_and_parse_scale(@solution, $harp)
    @holes = @sorted.clone.shuffle
    @holes_orig = @holes.clone

    @prompt = 'Choose the scale you have heard:'
    @help_head = 'Scale'
    @scale2holes = @choices.map do |scale|
      holes, _ = read_and_parse_scale(scale, $harp)
      [scale, holes]
    end.to_h

  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking one scale out of #{$all_quiz_scales[$opts[:difficulty]].length}"
  end
  
  def after_solve
    puts
    puts "Playing original scale #{@solution}:"
    sleep 0.5
    play_hons hons: @sorted
    sleep 1
    puts
    puts
    puts "Repeating and showing the question, shuffled scale #{@solution}:"
    sleep 0.5
    play_hons
  end
  
  def issue_question
    puts "\e[34mPlaying a scale\e[0m\e[2m with \e[0m\e[34m#{@holes.length}\e[0m\e[2m holes\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
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
    ['.help-play-ascending', 'Play holes in ascending order']
  end

  def help3
    choose_and_play_answer_scale
  end

  def help3_desc
    ['.help-play-compare', 'Select a scale and play it for comparison']
  end

end


class MatchScale < QuizFlavour

  $q_class2colls[self] = %w(scales no-mic)

  def initialize first_round
    super
    
    scales = $all_quiz_scales[$opts[:difficulty]]
    @choices = scales.clone 
    @choices_orig = @choices.clone
    @state = Hash.new
    @state[:hide_holes] = :all
    @state_orig = @state.clone
    @scale2holes = scales.map do |scale|
      holes, _ = read_and_parse_scale(scale, $harp)
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
    puts "Playing #{@others ? 'shortest' : 'single'} solution scale #{@solution}:"
    sleep 0.2
    play_hons hons: @holes_scale
    sleep 0.5
    puts
    @state[:hide_holes] = nil
    help3
    puts
    sleep 0.5
    puts "Playing the holes in question:"
    sleep 0.2
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
    puts "\e[34mPlaying #{@holes.length} holes\e[0m\e[2m, which are a subset of #{@others ? 'MULTIPLE scales at once' : 'a SINGLE scale'}\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
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
    ['.help-play-compare', 'Select a scale and play it for comparison']
  end

  def help3
    puts "Playing unique holes of sequence sorted by pitch:"
    play_hons hide: @state[:hide_holes],
              hons: @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]}.uniq
  end

  def help3_desc
    ['.help-play-ascending', 'Play holes-in-question in ascending order']
  end

  def help4
    puts "Showing all holes played (this question only):"
    @state[:hide_holes] = nil
    play_hons hide: [@state[:hide_holes], :help]
  end

  def help4_desc
    ['.help-show-holes', 'Show the holes played']
  end

  def help5
    puts "Printing all scales with their holes:"
    puts 
    maxl = @scale2holes.keys.max_by(&:length).length
    @scale2holes.each do |k, v|
      puts "   \e[2m#{k.rjust(maxl)}:\e[0m\e[32m   #{v.join('  ')}\e[0m"
    end
    puts "\n\e[2m#{@choices.length} scales\n\n"
    puts "\e[2mAnd the holes in question:\e[0m\e[32m   #{@holes.join('  ')}\e[0m"
  end

  def help5_desc
    ['.help-print-scales', 'print all the hole-content of all possible scales']
  end

end


class HearInter < QuizFlavour

  $q_class2colls[self] = %w(inters no-mic)
  
  def initialize first_round
    super

    @choices = $intervals_quiz[$opts[:difficulty]].map {|i| $intervals[i][0]} 
    @choices_orig = @choices.clone
    @inter2semi = $intervals.to_a.map {[_2[0], _1]}.to_h

    begin
      inter = get_random_interval_as_holes
      @holes = inter[0..1]
      @dsemi = inter[2]
      @solution = inter[3]
    end while @@prevs.include?(@holes) || @dsemi == 0
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
    puts "\e[34mPlaying an interval\e[0m\e[2m to ask for its name\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    sleep 0.1
    play_hons hide: [:help, :all]
  end

  def help2
    puts "Playing interval reversed:"
    play_hons reverse: true, hide: :all
  end

  def help2_desc
    ['.help-reverse', 'Play interval reversed']
  end

  def help3
    puts "Playing all intervals:"
    puts "\e[2mPlease note, that some notes may not be available as holes.\e[0m"
    puts
    maxlen = @inter2semi.keys.map(&:length).max
    @choices_orig.each do |inter|
      sleep 0.5
      note_inter = semi2note($harp[@holes[0]][:semi] + @inter2semi[inter] * (@dsemi <=> 0))
      print "  \e[32m%-#{maxlen}s\e[0m\e[2m   \e[0m" % inter
      play_hons hons: [@holes[0], note_inter], hide: :all, newline: false
    end
    sleep 0.5
  end

  def help3_desc
    ['.help-play-all', 'Play all intervals over first note']
  end

  def help4
    semis = @holes.map {|h| $harp[h][:semi]}
    if semis.min - 12 >= $min_semi
      semis.map! {|s| s - 12 }
      desc = 'lower'
    else
      semis.map! {|s| s + 12 }
      desc = 'higher'
    end
    
    puts "Playing interval one octave #{desc}:"
    puts "\e[2mPlease note, that some notes may not be available as holes.\e[0m"
    puts
    play_hons hons: semis.map {|s| semi2note(s)}, hide: :all
  end

  def help4_desc
    ['.help-move-octave', 'Play interval one octave lower or higher']
  end

  def help5
    print_intervals_etc
  end

  def help5_desc
    ['.help-all-inter-songs', 'Show list of all intervals, semitones and mnemonic songs']
  end

  def help6
    puts "One of the mnemonic songs (upward) for this interval is:"
    puts
    puts "  \e[94m" + $quiz_interval2song[@dsemi.abs].sample + "\e[0m"
    puts
  end

  def help6_desc
    ['.help-inter-song', 'Name the specific mnemonic song associated with this interval']
  end

  def help7
    choices = {'Up' => 'one Octave UP',
               'UpUp' => 'two Octaves UP',
               'Down' => 'one Octave DOWN',
               'DownDown' => 'two Octaves DOWN'}
    choose_prepare_for
    ud = choose_interactive("About to play the interval shifted by one or two octaves; please choose ", choices.keys) do |ud|
      'Shift ' + choices[ud]
    end
    choose_clean_up
    if ud
      num_oct = ( choices[ud].split[0] == 'one'  ?  1  :  2 )
      direction = ( choices[ud].split[-1] == 'UP'  ?  +1  :  -1 )
      puts "\nPlaying shifted by #{choices[ud]}:\n"
      hshifted = @holes.map do |h|
        semi = note2semi($hole2note[h]) + direction * num_oct * 8
        if semi > 26 || semi < -28
          puts "\nShifting hole #{h} results in unplayable semitone #{semi}:  TOO " +
               (semi > 0 ? 'HIGH' : 'LOW') + "\n\n"
          return
        end
        semi2note(semi)
      end
      play_hons hons: hshifted, hide: :all
    else
      puts "\nNo selection.\n\n"
    end
  end

  def help7_desc
    ['.help-play-shifted', 'Play the interval shifted by one or two octaves up or down']
  end

end


class HearChord < QuizFlavour

  $q_class2colls[self] = %w(no-mic)

  def get_variations chord
    $chords_quiz[:hard][chord].map do |var|
      var.map do |sm|
        sm - note2semi('a4') + note2semi(@base)
      end
    end    
  end
  
  def initialize first_round
    super
    
    @choices = $chords_quiz[$opts[:difficulty]].keys
    @choices_orig = @choices.clone
    @base = $key + '4'

    begin
      @solution = @choices.sample
      @variations = get_variations @solution
      @semis = if $opts[:difficulty] == :hard
                 @variations.sample
               else
                 @variations[0]
               end
    end while @@prevs.include?(@semis)
    @@prevs << @semis
    
    @@prevs.shift if @@prevs.length > 2

    @prompt = 'Choose the Chord you have heard:'
    @help_head = 'Chord'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$chords_quiz[$opts[:difficulty]].length} " +
      ($opts[:difficulty] == :hard  ?  "chords with a total of #{$chords_quiz[$opts[:difficulty]].values.flatten(1).length} variations"  :  'simple chords')
  end

  def play_base_note
    print "Base note:  #{@base}"
    wfile = this_or_equiv("#{$sample_dir}/%s", @base, %w(.wav .mp3))
    cmd = if $testing
            "sleep 1"
          else
            "play -q --norm=#{$vol.to_i} #{wfile} trim 0 1"
          end
    sys cmd, $sox_fail_however
  end

  def play_chord gap: 0, dura: 1, semis: @semis
    tfiles = synth_for_inter_or_chord(semis, gap, dura, 'pluck')
    cmd = if $testing
            "sleep 1"
          else
            "play -q --norm=#{$vol.to_i} --combine mix " + tfiles.join(' ')
          end
    sys cmd, $sox_fail_however
  end
  
  def after_solve
    puts
    play_base_note
    puts "\nChord as single notes:"
    tfiles = synth_for_inter_or_chord(@semis, 0, 0.7, 'pluck')
    @semis.zip(tfiles).each do |s,w|
      print '  ' + semi2note(s)
      cmd = if $testing
              "sleep 1"
            else
              "play -q --norm=#{$vol.to_i} " + w
            end
      sys cmd, $sox_fail_however    
    end
    puts
    puts "\nChord as a whole:\n  " + @semis.map {|s| semi2note(s)}.join('  ')
    play_chord
  end

  def issue_question
    puts "\e[94mKey of #{$key.upcase}\e[34m: Playing the base note #{@base} and then an unknown chord to ask for its name\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    sleep 0.1
    puts
    play_base_note
    puts
    sleep 0.1
    print 'Chord in question: '
    3.times do
      print ' ?'
      play_chord
    end
    puts
  end

  def help2
    puts
    play_base_note
    puts
    print 'Playing chord with gaps: '
    play_chord gap: 0.2, dura: 3
    puts '?'
  end

  def help2_desc
    ['.help-gapped', 'Play chord with gaps']
  end

  def plpr_vars show: false, vars: @variations, head: true
    if head
      if vars.length == 1
        puts "For this chord and difficulty there is only one variation. Playing it:"
      else
        puts "Playing #{vars.length} variations of chord (3 times each),\nwhere 1 of them is already known:"
      end
      puts
    end
    vars.each_with_index do |var, idx|
      sleep 0.5 if idx > 0
      print '  '
      play_base_note
      puts
      print "Variation #{idx+1}:"
      if show
        print "  \e[32m"
        print var.map {|s| semi2note(s)}.join('  ')
        print "\e[0m  "
      else
        print '  ?'
      end
      3.times {play_chord semis: var}
      puts
    end
  end

  def help3
    plpr_vars show: false
  end

  def help3_desc
    if $opts[:difficulty] == :hard
      ['.help-play-vars', 'Play all variations of chord']
    else
      nil
    end
  end

  def help4
    plpr_vars show: true
  end

  def help4_desc
    if $opts[:difficulty] == :hard
      ['.help-play-print-vars', 'Play and print all variations of chord']
    else
      nil
    end
  end

  def help5
    puts "Playing all chords%s, 3 times each:" %
         ($opts[:difficulty] == :hard  ?  ' (one variation only)'  :  '')
    @choices_orig.each do |chord|
      play_base_note
      puts
      print "\e[32mChord #{chord}\e[0m "
      semis = if chord == @solution
                @semis
              else
                get_variations(chord)[0]
              end
      3.times do
        print '.'
        play_chord semis: semis
      end
    puts
    end
  end

  def help5_desc
    if $opts[:difficulty] == :hard
      ['.help-play-all-chords', 'Play all chords one variation each']
    else
      ['.help-play-all-chords', 'Play all chords']
    end
  end

  def help6
    puts "Playing all chords with all variations, 3 times each:"
    @choices_orig.each do |chord|
      puts "\e[32mChord #{chord}\e[0m"
      plpr_vars vars: get_variations(chord), head: false
    end
  end

  def help6_desc
    if $opts[:difficulty] == :hard
      ['.help-play-all-chords-vars', 'Play all chords with all variations']
    else
      nil
    end
  end

  def help7
    puts "Printing chord (base #{$key}4),"
    print "                as notes:  "
    puts @semis.map {|s| semi2note(s)}.join('  ')
    print "  diff semitones to base:  "
    puts $chords_quiz[:hard][@solution].join('  ')
  end

  def help7_desc
    ['.help-print', 'Print notes and semitones of chord']
  end

end


class AddInter < QuizFlavour

  $q_class2colls[self] = %w(silent inters no-mic)

  def initialize first_round
    super
    
    begin
      inter = get_random_interval_as_holes
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
    puts "\e[34mTake hole \e[94m#{@holes[0]}\e[34m and #{@verb} interval '\e[94m#{$intervals[@dsemi.abs][0]}\e[34m'\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Playing interval:"
    play_hons hide: @holes[1]
  end

  def help2_desc
    ['.help-play-inter', 'Play interval']
  end

  def help3
    print_intervals_etc
  end

  def help3_desc
    ['.help-show-all-intervals', 'Show list of all intervals, semitones and mnemonic songs']
  end

  def help4
    puts "Show holes as notes:"
    print_chart_holes_as_notes
  end

  def help4_desc
    ['.help-chart-notes', 'Show solution in chart with notes']
  end

  def help5
    puts "Show holes as semitones:"
    print_chart_holes_as_semitones
  end

  def help5_desc
    ['.help-chart-semis', 'Show solution in chart with holes as semitones']
  end

end


class InterSong < QuizFlavour

  $q_class2colls[self] = %w(silent inters no-mic)

  def initialize first_round
    super

    @interval2song = $intervals_quiz[$opts[:difficulty]].
                       select {|i| i > 0}.
                       map {|inter| [inter, $quiz_interval2song[inter].sample]}.to_h
    
    @qdesc, @adesc, qi2ai = if rand > 0.5
                              ['interval', 'song', @interval2song]
                            else 
                              ['song', 'interval', @interval2song.invert]
                            end
    
    @choices = qi2ai.values
        
    begin
      @qitem = qi2ai.keys.sample
    end while @@prevs.include?(@qitem)
    @@prevs << @qitem
    @@prevs.shift if @@prevs.length > 2

    @solution = qi2ai[@qitem]
    @base_semi = note2semi($key + '4')
    if @qdesc == 'interval'
      @inter_semi = @qitem
      @song = @solution
    else
      @inter_semi = qi2ai[@qitem]
      @choices.map! {|c| describe_inter_semis(c)}
      @solution = describe_inter_semis(@solution)
      @song = @qitem
    end
    @choices_orig = @choices.clone

    @prompt = "Matching #{@adesc}:"
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$intervals_quiz[$opts[:difficulty]].length} intervals out of #{$quiz_interval2song.length}"
  end

  def after_solve
    puts
    puts "Playing interval \e[32m#{describe_inter_semis(@inter_semi)}\e[0m starting at #{semi2note(@base_semi)};\nthis is the same interval as in song '#{@song}':"
    play_hons hons: [semi2note(@base_semi), semi2note(@base_semi + @inter_semi)]
  end
  
  def issue_question
    if @qdesc == 'interval'
      puts "\e[34mGiven the interval of \e[94m#{describe_inter_semis(@qitem)}\e[34m, name the song, that starts with this interval\e[0m"
    else
      puts "\e[34mGiven the song '\e[94m#{@qitem}\e[34m', name the the interval, that this song starts with\e[0m"
    end
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    if @qdesc == 'interval'
      print "Playing interval \e[32m#{describe_inter_semis(@inter_semi)}\e[0m:  "
    else
      print "Playing interval from song \e[32m'#{@qitem}'\e[0m:  "
    end
    play_hons hons: [semi2note(@base_semi), semi2note(@base_semi + @inter_semi)], newline: false
  end

  def help2_desc
    ['.help-play-inter', 'Play interval']
  end

  def help3
    @interval2song.each do |inter, song|
      if @qdesc == 'interval'
        print "Playing interval \e[32m#{describe_inter_semis(inter)}\e[0m:  "
      else
        print "Playing interval from song \e[32m'#{song}'\e[0m:  "
      end
      play_hons hons: [semi2note(@base_semi), semi2note(@base_semi + inter)], newline: false
    end
  end

  def help3_desc
    ['.help-play-all-inters', 'Play all intervals']
  end

  def help4
    @interval2song.each do |inter, song|
      puts "Interval: \e[32m#{describe_inter_semis(inter)}\e[0m"
      puts "    Song: \e[32m'#{song}'\e[0m"
      puts
    end
  end

  def help4_desc
    ['.help-print-all-inters', 'Print all intervals along with their mnemonic song']
  end

end


class TellInter < QuizFlavour

  $q_class2colls[self] = %w(silent inters no-mic)

  def initialize first_round
    super
    
    begin
      inter = get_random_interval_as_holes sorted: true
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
    puts "\e[34mAsking for the interval between holes \e[94m#{@holes[0]}\e[34m and \e[94m#{@holes[1]}\e[0m\e[2m\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Playing interval:"
    play_hons
    [['lower', -12],['higher', +12]].each do |text, dsemi|
      sleep 0.5
      puts "\nOne octave #{text}:"
      play_hons hons: @holes.map {|h| semi2note($harp[h][:semi] + dsemi)}, hide: :all
    end
  end

  def help2_desc
    ['.help-play-inter', 'Play interval']
  end

  def help3
    puts "Show holes as notes:"
    print_chart_holes_as_notes
  end

  def help3_desc
    ['.help-chart-notes', 'Show chart with notes']
  end

  def help4
    puts "Show holes as semitones:"
    print_chart_holes_as_semitones
  end

  def help4_desc
    ['.help-chart-semis', 'Show chart with holes as semitones']
  end
  
  def help5
    puts "One of the mnemonic songs (upward) for this interval is:"
    puts
    puts "  \e[94m" + $quiz_interval2song[@dsemi.abs].sample + "\e[0m"
    puts
  end
  
  def help5_desc
    ['.help-inter-song', 'Name the mnemonic song associated with this interval']
  end
  
end


class Players < QuizFlavour

  $q_class2colls[self] = %w(silent no-mic)

  def initialize first_round
    super

    @key_contributes_to_solution = -1

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
    "One of #{@@choices.length} of players (chosen at random from a total of #{$players.structured.length})"
  end

  def after_solve
    puts
    print_player $players.structured[@solution]
  end
  
  def issue_question
    puts
    puts "\e[34mAsking for the name of the player with  \e[94m#{@qitem.upcase}\e[34m  given below\e[0m"
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
    ['.help-more-info', 'Show additional information about player']
  end

end


class KeyHarpSong < QuizFlavour

  $q_class2colls[self] = %w(silent no-mic layout)

  def initialize first_round
    super

    @key_contributes_to_solution = -1
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
    @@prevs << @qitem
    @@prevs.shift if @@prevs.length > 2

    @solution = qi2ai[@qitem]
    
    @prompt = "Key of #{@adesc}:"
    @help_head = "#{@adesc} with key of".capitalize
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$opts[:difficulty] == :easy ? 4 : 12} keys out of 12"
  end

  def issue_question
    puts "\e[34mGiven a  \e[94m#{@qdesc.upcase}\e[34m  with key of '\e[94m#{@qitem}\e[34m', name the matching key for the  \e[94m#{@adesc}\e[0m\e[2m\n(2nd position)\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    note = semi2note(key2semi(@solution.downcase))
    puts "Playing note (octave #{note[-1]}) for answer-key of #{@adesc}:"
    make_term_immediate
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_and_handle_kb [note], hide: [note, :help]
    make_term_cooked
  end

  def help2_desc
    ['.help-play-answer', "Play note for answer-key of #{@adesc}"]
  end

end


class HoleNote < QuizFlavour

  $q_class2colls[self] = %w(silent no-mic layout)

  def initialize first_round
    super

    @samples_needed = false

    @hole_set  = if $opts[:difficulty] == :hard
                   nil
                 else
                   $named_hole_sets.keys.sample
                 end

    @holes = if @hole_set
               $named_hole_sets[@hole_set]
             else
               $harp_holes
             end

    hole2note = @holes.map {|h| [h,$harp[h][:note].gsub(/\d+/,'')]}.to_h
    note2hole = hole2note.inject(Hash.new {|h,k| h[k] = Array.new}) do |memo, hn|
      memo[hn[1]] << hn[0]
      memo
    end

    @a_is_hole = @q_is_note = ( rand > 0.5 )
    @qdesc, @adesc, qi2ai = if @a_is_hole
                              ['note', 'hole', note2hole]
                            else
                              ['hole', 'note', hole2note]
                            end    
    
    @choices = qi2ai.values
    @choices_orig = @choices.clone

    begin
      @qitem = qi2ai.keys.sample
    end while @@prevs.include?(@qitem)
    @solution = qi2ai[@qitem]
    @@prevs << @qitem
    @@prevs.shift if @@prevs.length > 2

    @note = if @q_is_note
              @qitem
            else
              hole2note[@qitem]
            end

    @any_clause = ( @solution.is_a?(Array)  ?  "(any of #{@solution.length})"  :  '(single choice)' )
    @prompt = "#{@adesc.capitalize} #{@any_clause} for #{@qdesc} #{@qitem}:"
    @help_head = "#{@adesc} with key of".capitalize
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head + ', taking ' +
      if @hole_set
        "only holes from set '#{@hole_set}'"
      else
        'all holes of harp'
      end
  end

  def issue_question
    puts "\e[34mGiven the \e[94m#{@qdesc.upcase}\e[34m '\e[94m#{@qitem}\e[34m'" +
         ( @hole_set  ?  " (taken from set '#{@hole_set}', with #{$named_hole_sets[@hole_set].length} holes)"  :  '(taken from all holes of harp)' ) +
         "\nname the matching \e[94m#{@adesc}\e[34m #{@any_clause}; \e[94mKEY of #{$key}\e[34m\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    if @a_is_hole
      puts 'Chart with answer spread:'
      print_chart_with_notes spread: @note
    else
      puts 'Chart with answer hidden:'
      print_chart_with_notes hide: @note
    end
  end

  def help2_desc
    ['.help-chart', "Print chart with context for solution"]
  end

  def help3
    print "The relevant hole set is "
    if @hole_set
      print "'#{@hole_set}'"
    else
      print 'all holes of harp'
    end
    print "; therefore the answer\nis among "
    
    if @adesc == 'note'
      puts "the notes from these holes:"
    else
      puts "these holes:"
    end
    puts
    puts @holes.join('  ')
  end

  def help3_desc
    ['.help-hole-set', "Print the relevant set of holes"]
  end

  def after_solve
    puts
    puts 'Chart with notes:'
    print_chart_with_notes mark: @note
  end
end


class HoleNoteKey < QuizFlavour

  $q_class2colls[self] = %w(silent no-mic layout)
  
  def initialize first_round
    super
    
    @samples_needed = false
    @difficulty_to_key_set = {easy: $common_harp_keys, hard: $all_harp_keys}
    @key_contributes_to_solution = 1

    @choices = @difficulty_to_key_set[$opts[:difficulty]].clone
    @choices_orig = @choices.clone

    change_key if first_round
    @solution = $key
            
    @prompt = "What is the key of harp for the hole-note relations given above:"
    @help_head = "#{@adesc} with key of".capitalize
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head + ', taking ' +
      if $opts[:difficulty] == :easy
        'common harp keys only'
      else
        'all harp keys'
      end
  end

  def issue_question
    puts "\e[34mGiven the mapping of holes to notes below, name the key of the harp\n\n"
    print_mapping hide_note: $key, no_semis: true
    puts "\e[0m\n"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts 'Chart with notes:'
    print_chart_with_notes    
  end

  def help2_desc
    ['.help-chart-notes', "Print harmonica chart with notes"]
  end
  
  def help3
    print_mapping color: false
  end

  def help3_desc
    ['.help-semis', "Print semitone-diffs for hole-sets"]
  end

  def after_solve
    puts "\nThese are some mappings of holes to notes:\n\n"
    print_mapping color: false
  end
end


class HoleHideNote < QuizFlavour

  $q_class2colls[self] = %w(silent no-mic layout)
  
  def initialize first_round
    super

    @difficulty_to_key_set = {easy: $common_harp_keys, hard: $all_harp_keys}
    @samples_needed = false
    @difficulty_to_key_set[$opts[:difficulty]]
    @choices = $all_harp_keys.clone
    @choices_orig = @choices.clone

    @desc = @holes_descs.sample
    begin
      @solution = ( $named_hole_sets[@desc].map {|h| $harp[h][:note].gsub(/\d+$/,'')} - [$key] ).sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    
    @prompt = "Pick the hidden note in the hole-set '#{@desc}' given above:"
    @help_head = 'Note'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head + ', taking ' +
      if $opts[:difficulty] == :easy
        'common harp keys only'
      else
        'all harp keys'
      end
  end

  def issue_question
    puts "\e[34mSee the mapping of holes to notes below, pick the hidden note\n\n"
    print_mapping no_semis: true, sets: [@desc], hide_note: @solution
    puts "\e[0m\n"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    print_mapping color: false, no_notes: true
  end

  def help2_desc
    ['.help-semis', "Print semitone-diffs for hole-sets"]
  end

  def after_solve
    puts "\nThese are some mappings of holes to notes:\n\n"
    puts "Key is #{$key}"
    puts
    print_mapping color: false
  end
end



class HearHoleSet < QuizFlavour

  $q_class2colls[self] = %w(no-mic)
  
  def initialize first_round
    super

    @difficulty_to_key_set = {easy: $common_harp_keys, hard: $all_harp_keys}
    @key_contributes_to_solution = 1
    
    @harp_keys = @difficulty_to_key_set[$opts[:difficulty]]

    change_key if first_round

    @choices = @harp_keys.map {|chk| $named_hole_sets.keys.map {|hs| "#{chk}-#{hs}"}}.flatten
    @choices_orig = @choices.clone

    @hole_set = $named_hole_sets.keys.sample
    @solution = "#{$key}-" + @hole_set.to_s
    @holes = $named_hole_sets[@hole_set]
      
    @prompt = "Pick the key and hole-set, that has been played:"
    @help_head = 'key and hole-set'

  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head + ', taking ' +
      if $opts[:difficulty] == :easy
        'common harp keys only'
      else
        'all harp keys'
      end + " and all (#{$named_hole_sets.length}) hole sets"
  end

  def issue_question
    puts "\e[34mUsing a key and playing a hole set\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    play_hons hide: :all
  end

  def help2
    maxlen = $named_hole_sets.keys.map(&:length).max
    puts "Showing all hole sets:"
    $named_hole_sets.each do |name, holes|
      puts "  #{name.to_s.rjust(maxlen)} : " + holes.join('  ')
    end
  end

  def help2_desc
    ['.help-show-all-hole-sets', "Show all hole sets"]
  end

  def help3
    puts "The hole set is   '#{@hole_set}':   #{@holes.join('  ')}"
  end

  def help3_desc
    ['.help-hole-set', "Reveal the hole-set"]
  end

  def help4
    puts "The key is   '#{$key}'."
  end

  def help4_desc
    ['.help-key', "Reveal the key"]
  end

end


class HearKey < QuizFlavour

  $q_class2colls[self] = %w(no-mic)
  
  @@seqs = [[[0, 3, 0, 3, 2, 0, 0], 'st louis'],
            [[0, 3, 0, 3, 0, 0, 0, -1, -5, -1, 0], 'wade in the water'],
            [[0, 4, 0, 7, 10, 12, 0], 'intervals'],
            [[0, 0, 8, 8, 6, 6, 3, 3], 'box'],
            [[0, 0, 0], 'repeated'],
            [[0, 4, 7, -3, 0, 4, 2, 5, 9, -5, -1, 2, 0, 0], 'chord progression'],
            [:chord, 'chord']]
  
  def initialize first_round
    super

    @difficulty_to_key_set = {easy: $common_harp_keys, hard: $all_harp_keys}    
    @key_contributes_to_solution = 1

    @@seqs.rotate!(rand(@@seqs.length).to_i)
    @seq = @@seqs[0][0]
    @nick = @@seqs[0][1]
    @compare_key = nil

    harp2song = get_harp2song(basic_set: $opts[:difficulty] == :easy)
    @choices = harp2song.keys
    @choices_orig = @choices.clone

    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    change_key(key: @solution)
    
    @prompt = "Key of sequence that has been played:"
    @help_head = "Key"
    @wavs_created = nil
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking #{$opts[:difficulty] == :easy  ?  4  :  12} keys out of 12"
  end

  def issue_question silent: false
    unless silent
      puts "\e[34mHear the sequence of notes '#{@nick}' and name its key\e[0m"
      puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    end
    isemi = key2semi(@solution.downcase)
    make_term_immediate
    $ctl_kb_queue.clear
    if @seq == :chord
      semis = [0, 4, 7].map {|s| isemi + s}
      @wavs_created ||= synth_for_inter_or_chord(semis, 0.2, 2, :sawtooth)
      play_recording_and_handle_kb @wavs_created
    elsif @seq.is_a?(Array)
      notes = @seq.map {|s| semi2note(isemi + s)}
      puts
      play_holes_or_notes_and_handle_kb notes, hide: [semi2note(isemi), :help]
    else
      err "Internal error: #{seq}"
    end
    make_term_cooked
  end

  def help2
    @@seqs.rotate!
    @seq = @@seqs[0][0]
    @nick = @@seqs[0][1]
    puts "Sequence of notes changed to '#{@nick}'."
    issue_question silent: true
  end

  def help2_desc
    ['.help-other-seq', "Choose a different sequence of notes"]
  end

  def help3
    puts "Change (via +-RET) the adjustable pitch played until\nit matches the key of the sequence."
    make_term_immediate
    $ctl_kb_queue.clear
    harp2song = get_harp2song(basic_set: false)
    song2harp = harp2song.invert
    compare_key_harp = ( @compare_key && song2harp[@compare_key] )
    compare_key_harp = play_interactive_pitch explain: false, start_key: compare_key_harp, return_accepts: true
    make_term_cooked
    @compare_key = harp2song[compare_key_harp]
    puts "\nPlease note, that this key '#{@compare_key}' is not among possible solutions!\n" unless @choices.map(&:downcase).include?(@compare_key)
    puts "\nNow compare key '#{@compare_key}' back to sequence:"
    issue_question silent: true
  end

  def help3_desc
    ['.help-pitch', "Play an adjustable pitch to compare"]
  end

  def help4
    puts "Playing all possible solutions."
    notes = @choices.map {|k| semi2note(key2semi(k))}
    play_hons hons: notes
  end

  def help4_desc
    ['.help-play-choices', "Play each of the choices"]
  end

  def after_solve
    puts
    puts "Playing key (of sequence) #{@solution}:"
    sleep 0.1
    puts
    make_term_immediate
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_and_handle_kb [semi2note(key2semi(@solution))], hide: :help
    make_term_cooked
  end

end


class HearHole < QuizFlavour

  $q_class2colls[self] = %w(no-mic)
  
  def initialize first_round
    super

    @samples_needed = false
    @hole_set = $named_hole_sets.keys.sample

    @choices = $named_hole_sets[@hole_set]
    @choices_orig = @choices.clone
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @prompt = "Hole that has been played (hole set '#{@hole_set}', key of #{$key}):"
    @help_head = 'Hole'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", taking one key out of #{$common_harp_keys.length} keys and one hole-set from #{$named_hole_sets.keys.length}"
  end

  def issue_question silent: false
    unless silent
      puts "\e[34mHear a hole from set '#{@hole_set}' and key #{$key} and name it\e[0m"
      puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    end
    play_hons hide: :all, hons: [@solution]
  end

  def help2
    other = ($named_hole_sets[@hole_set] - [@solution]).sample
    puts "Another hole, but from the same hole set '#{@hole_set}':"
    play_hons hons: [other]
  end

  def help2_desc
    ['.help-other', "Play and name another hole from the same set"]
  end

  def help3
    other = ($named_hole_sets[@hole_set] - [@solution]).sample
    puts "Playing hole set   #{$named_hole_sets[@hole_set].join('  ')}   but shuffled:"
    @shuffled = $named_hole_sets[@hole_set].shuffle if !@shuffled || @shuffled.length != @choices.length
    play_hons hide: :all, hons: @shuffled
    puts
    puts "Shuffled set ist kept, so you may repeat."
  end

  def help3_desc
    ['.help-shuffle', "Play the hole set, shuffled"]
  end

  def after_solve
    puts
    puts "Playing hole #{@solution}, from set '#{@hole_set}', key of #{$key}:"
    sleep 0.1
    puts
    play_hons hons: [@solution]
    puts
  end

end


class KeepTempo < QuizFlavour

  $q_class2colls[self] = %w(mic)
  
  @@explained = false
  @@history = Array.new

  def self.describe_difficulty
    # implement this for unit-test only
  end
  
  def initialize
    @key_contributes_to_solution = -1
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
      puts "\e[0mParameters (#{$opts[:difficulty]}):"
      puts "  Tempo:           #{@tempo} bpm"
      puts "  PICK-UP-TEMPO:   %2s beats" % @beats_intro.to_s
      puts "  KEEP-TEMPO:      %2s" % @beats_keep.to_s
      puts "  TOGETHER-AGAIN:  %2s" % @beats_outro.to_s
      puts "\n\n"
    else
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

    puts "\e[2K\r\e[0mReady to play?\n\nThen press any key, wait for count-down and start playing in sync ..."
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
    puts "\e[0mGO!\n\n"

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
                puts "\n\n\e[0;101mWARNING:\e[0m Length of generated wav (intro + silence + outro) = #{len_tempo}\n  is much different from length of parallel recording = #{len_rec}!\n  So your solo playing cannot be extracted with good precision,\n  and results of analysis below may therefore be dubious.\n\n      \e[32mBut you can still judge by ear!\n\n      Have you still been   \e[34mIN TIME\e[32m   at the end?\n\n\e[0m  Remark: Often a second try is fine; if not however,\n          restarting your computer may help ...\n\n"                
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
        if holes_in_a_row == 4
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
      stand_out "You played #{(@beats_keep - @beats_found.length).abs} beats  #{what}\n(#{@beats_found.length} instead of #{@beats_keep})!\nYou need to get this right, before further\nanalysis is possible.   Please try again.", turn_red: what
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

  $q_class2colls[self] = %w(no-mic)
  
  @@choices = {:easy => %w(70 90 110 130 150),
               :hard => %w(50 60 70 80 90 100 110 120 130 140 150 160 170 180)}
  
  def initialize first_round
    super

    @key_contributes_to_solution = -1
    @choices = @@choices[$opts[:difficulty]].clone
    @choices_orig = @choices.clone
    @num_beats = 8

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
    puts "\e[34mPlaying #{@num_beats} beats of Tempo to find\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    sleep 0.1
    make_term_immediate
    $ctl_kb_queue.clear    
    play_recording_and_handle_kb @sample
    make_term_cooked
  end

  def help2
    puts "For help, choose one of the answer-tempos to be played:"
    choose_prepare_for
    answer = choose_interactive('Tempo to compare:',
                                @choices.map {|x| "compare-#{x}"}) do |tag|
      "compare with #{@help_head} #{tag_desc(tag)}" 
    end
    choose_clean_up
    if answer
      help = quiz_generate_tempo('h', Integer(answer.gsub('compare-','')), @num_beats, 0, 0)
      puts "\nPlaying #{@num_beats} beats in tempo #{answer} bpm"
      make_term_immediate
      $ctl_kb_queue.clear    
      play_recording_and_handle_kb help
      make_term_cooked
    else
      puts "\nNo Tempo selected to play.\n\n"
    end
    puts "\n\e[2mDone with compare, BACK to original question.\e[0m"
  end

  def help2_desc
    ['.help-compare', 'Play one of the choices']
  end

end


class NotInScale < QuizFlavour

  $q_class2colls[self] = %w(scales no-mic)

  def initialize first_round
    super
    
    @scale_name = $all_quiz_scales[$opts[:difficulty]].sample
    @scale_holes, _ = read_and_parse_scale(@scale_name, $harp)
    @scale_semis = @scale_holes.map {|h| $harp[h][:semi]}

    # choose one harp-hole, which is not in scale but within range or nearby
    holes_notin = $harp_holes - @scale_holes
    
    # Remove holes above and below scale
    holes_notin.shift while holes_notin.length > 0 &&
                            $harp[holes_notin[0]][:semi] < $harp[@scale_holes[0]][:semi]
    holes_notin.pop while holes_notin.length > 0 &&
                          $harp[holes_notin[-1]][:semi] > $harp[@scale_holes[-1]][:semi]
    # We might still pick a hole equivalent to a scale hole (e.g. -2 vs +3) so check and
    # loop
    begin
      @hole_notin = holes_notin.sample
    end while @scale_semis.include?($harp[@hole_notin][:semi])
    
    @holes = @scale_holes.shuffle
    @scale_holes_shuffled = @holes.clone
    @holes[rand(@holes.length)] = @hole_notin

    # hide holes as h1, h2, ...
    @hide = @holes.each_with_index.map {|h,i| [h, "h#{i+1}"]}.to_h
    @hide[(@scale_holes - @holes)[0]] = 'h0'
    @choices = @holes.map {|h| @hide[h]}
    @choices_orig = @choices.clone
    @solution = @hide[@hole_notin]
    @prompt = "Which hole does not belong to scale '#{@scale_name}'?"
    @help_head = 'Hole (in disguise)'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
      ", choosing one of #{$all_quiz_scales[$opts[:difficulty]].length} scales"
  end
  
  def after_solve
    puts
    puts "Playing note #{@solution}, hole #{@hole_notin}, that was foreign in scale #{@scale_name}:"
    sleep 0.1
    play_hons(hons: [@hole_notin])
    puts
    sleep 0.5
    puts "And these are the holes of the modified scale:"
    puts
    lines = ['','']
    @holes.each do |hole|
      lines[0] += hole + '  '
      lines[1] += @hide[hole].ljust(hole.length) + '  '
    end
    puts lines[0]
    puts "\e[2m" + lines[1] + "\e[0m"
  end
  
  def issue_question
    puts "\e[34mPlaying scale \e[94m#{@scale_name}\e[34m modified: shuffled and one note replaced by a foreign one\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
    play_hons(hons: @holes, hide: @hide)
  end

  def help2
    puts "Play notes of modified scale in ascending order:"
    @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]}
    play_hons(hons: @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]},
              hide: @hide)
  end

  def help2_desc
    ['.help-play-mod-asc', 'Play holes of modified scale in ascending order']
  end
  
  def help3
    puts "Playing original scale in ascending order:"
    play_hons(hons: @scale_holes, hide: :all)
  end

  def help3_desc
    ['.help-play-orig-asc', 'Play original scale ascending']
  end

  def help4
    puts "Playing original scale shuffled, just like the question:"
    play_hons(hons: @scale_holes_shuffled, hide: :all)
  end

  def help4_desc
    ['.help-play-orig-shuf', 'Play original scale shuffled']
  end

  def help5
    puts "Play and show original scale shuffled ('h0' is the foreign hole):"
    play_hons(hons: @scale_holes_shuffled, hide: @hide)
  end

  def help5_desc
    ['.help-show-orig-shuf', 'Kind of solve: Play and show original scale shuffled']
  end

end


def get_random_interval_as_holes sorted: false
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
                       ' ' + ( holes_inter[2] > 0 ? 'up' : 'down' ) + ' ' +
                       holes_inter[3] + ( ' (%+dst)' % holes_inter[2] )
        holes_inter << $quiz_interval2song[holes_inter[2].abs].sample
        # 0,1: holes,
        #   2: numerical semitone-interval with sign
        #   3: interval long name
        #   4: description, e.g. '+1 ... up ... maj Third'
        #   5: mnemonic song
        return holes_inter
      end
    end
  end
end

def prompt_for_quiz_interval holes_inter
  puts
  puts "\e[34mInterval to play is:\e[0m"
  puts
  puts
  puts "\e[94m   #{holes_inter[4]}\e[34m"
  puts
  puts
  puts "The same as (upward) in song:  \e[94m" + holes_inter[5] + "\e[0m"
  puts
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
  lines = text.lines.map(&:chomp)
  maxl = lines.map(&:length).max
  puts '  +-' + ( '-' * maxl ) + '-+'
  lines.each do |l|
    sleep 0.05
    if turn_red && md = l.match(/^(.*)(\b#{turn_red}\b)(.*)$/)
      ll = md[1] + "\e[31m" + md[2] + "\e[0m" + md[3] + (' ' * (maxl - l.length))
    else
      ll = ( "%-#{maxl}s" % l )
    end
    puts "  | #{ll} |"
  end
  puts '  +-' + ( '-' * maxl ) + '-+'
  sleep 0.05
  print "\e[0m"
end


# map key of harp to key of song (2nd position, 7 semitones)
def get_harp2song basic_set: false
  harps = if basic_set
            $common_harp_keys
          else
            $all_harp_keys
          end
  harp2song = Hash.new
  harps.each do |harp|
    # add octave number 4, map to second position by adding 7
    # semitones, and remove octave number again
    harp2song[harp] = semi2note(note2semi(harp + '4') + 7)[0..-2].downcase
  end
  harp2song
end


def key2semi key
  semi = note2semi(key.downcase + '4')
  semi += 12 if semi < note2semi('gf4')
  semi
end


def quiz_hint_in_handle_holes_std solve_text, item, holes, hide, offer_disp = false
  choices2desc = {',solve-print' => "Solve: Print #{item}, but keep current question",
                  '.help-play' => "Play #{item}, so that you may replay it"}
  choices2desc['.help-display'] = "Switch display to show intervals" if offer_disp
  answer = choose_interactive($resources[:quiz_hints] % $quiz_flavour,
                              choices2desc.keys + [$resources[:just_type_one]]) {|tag| choices2desc[tag]}
  clear_area_comment
  clear_area_message
  case answer
  when ',solve-print'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0mSolution:"
    print solve_text
    puts "\n\n\e[0m\e[2m#{$resources[:any_key]}"
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
  when '.help-play'
    puts "\e[#{$lines[:comment] + 1}H"
    puts "Help: Playing #{item}"
    $ctl_kb_queue.clear
    puts
    play_holes_or_notes_and_handle_kb(holes, hide: [hide, :help])
    sleep 1
  when '.help-display'
    $opts[:display] = :chart_intervals
    $msgbuf.print "Changed display, so that you may spot the solution", 6, 8, :quiz_help
  end
  clear_area_comment
  clear_area_message
end


def quiz_hint_in_handle_holes_shifts holes_shifts
  choices2desc = {'.help-print-unshifted' => "Solve: Print unshifted sequence, but keep current question",
                  ',solve-print-shifted' => "Solve: Print shifted sequence, but keep current question",
                  '.help-play-unshifted' => "Play unshifted sequence; similar to '.'",
                  '.help-play-both' => "Play unshifted sequence first and then shifted, so that you may replay it"}
  answer = choose_interactive($resources[:quiz_hints] % $quiz_flavour,
                              choices2desc.keys + [$resources[:just_type_one]]) {|tag| choices2desc[tag]}
  clear_area_comment
  clear_area_message
  $ctl_kb_queue.clear
  case answer
  when '.help-print-unshifted'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0mHelp: unshifted sequence is:\n\n\n"
    puts "\e[32m  #{holes_shifts[0].join('  ')}"
    puts "\n\n\e[0m\e[2m#{$resources[:any_key]}"
    $ctl_kb_queue.deq
    $msgbuf.print 'Help, unshifted:   ' + holes_shifts[0].join('  '), 6, 8, :quiz_solution
  when ',solve-print-shifted'
    puts "\e[#{$lines[:comment_tall]}H"
    puts "\e[0m\e[2mUnshifted is:"
    puts "  #{holes_shifts[0].join('  ')}"
    puts "\n\e[0mSolution: shifted sequence is:"
    puts "\e[32m  #{holes_shifts[5].join('  ')}"
    puts "\n\e[0m\e[2mShifted by: #{holes_shifts[2]}"
    puts "\e[0m\e[2m#{$resources[:any_key]}"
    $ctl_kb_queue.deq
    $msgbuf.print 'Solution, shifted:   ' + holes_shifts[5].join('  '), 6, 8, :quiz_solution
  when '.help-play-unshifted'
    puts "\e[#{$lines[:comment] + 1}H"
    puts
    print "      \e[32mUnshifted:   "
    play_holes_or_notes_and_handle_kb(holes_shifts[0], hide: :help)
    sleep 2
    print "  \e[32mFirst shifted:   "
    play_holes_or_notes_and_handle_kb([holes_shifts[4]], hide: :help)
    sleep 1
  when '.help-play-both'
    puts "\e[#{$lines[:comment] + 1}H"
    puts
    print "  \e[32mUnshifted:   "
    play_holes_or_notes_and_handle_kb(holes_shifts[0], hide: :help)
    sleep 2
    print "    \e[32mShifted:   "
    play_holes_or_notes_and_handle_kb(holes_shifts[5], hide: [:all, :help])
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
  $msgbuf.print ["Type 'H' or '4' for quiz-hints, RETURN for next question,",
                 "or issue signal ctrl-z (quit, tstp) for another flavour"], 3, 5
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


def choose_clean_up skip_term: false
  clear_area_comment
  clear_area_message
  make_term_cooked unless skip_term
  print "\e[#{$lines[:comment_tall] - 1}H\e[K"
end


def choose_prepare_for skip_term: false
  prepare_term
  make_term_immediate unless skip_term
  $ctl_kb_queue.clear
  ($term_height - $lines[:comment_tall] + 2).times do
    sleep 0.01
    puts
  end
  print "\e[#{$lines[:comment_tall] - 1}H" + get_dim_hline + "\e[0m"
end


def do_animation info, nlines
  puts "\e[?25l"  ## hide cursor
  $splashed = true
  dots = '...'
  push_front = dots + info
  shift_back = info + dots
  txt = dots + info + dots + info + dots
  ilen = txt.length
  prev = nil
  nlines.times do
    len = push_front.length
    txt[0 .. len - 1] = push_front if txt[0 .. len - 1] == ' ' * len
    puts "\e[G\e[2m\e[34m#{prev}\e[0m" if prev
    txt.prepend(' ')
    txt.chomp!(shift_back) if txt.length > ilen  + shift_back.length - 3
    print "\e[0m\e[34m#{txt}\e[0m\e[K"
    prev = txt
    sleep 0.04
  end
  puts "\e[G\e[2m\e[34m#{txt}\e[0m"
  puts "\e[K"
  sleep 0.03
end


# $extra may contain meta-keywords like 'choose'; flavour only real
# flavours like 'hear-scale'
def get_accepted_flavour_from_extra inherited

  flavour,
  collection = if inherited
                 # we only ever inherit a collection; never a
                 # specific flavour
                 [get_random_flavour(inherited), inherited]
               elsif $extra == 'choose'
                 choose_flavour_or_collection('all')
               elsif $quiz_coll2flavs[$extra]
                 # a flavour collection
                 [nil, $extra]
               elsif $quiz_coll2flavs['all'].include?($extra)
                 # a specific flafour
                 [$extra, 'all']
               else
                 # this handles 'ran' and 'random' as synonyms for
                 # 'all' (which itself is handled above)
                 [nil, 'all']
               end
  
  first_iteration = true

  # loop until chosen flavour is accepted; endless loop, left via
  # return
  loop do 

    # maybe user has chosen a collection (above or in previous iteration)
    if $quiz_coll2flavs[flavour]
      collection = flavour
      flavour = nil
    end

    # remember collection for maybe restart
    ENV['HARPWISE_INHERITED_FLAVOUR_COLLECTION'] = collection

    flavour ||= get_random_flavour(collection)
    
    # now we have a valid flavour, so inform user and get confirmation
    puts
    unless first_iteration
      puts get_dim_hline
      puts
    end
    has_issue_question = $quiz_flavour2class[flavour].method_defined?(:issue_question)
    describe_flavour flavour, has_issue_question
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
    puts "\e[32mPress any key to start\e[0m\e[2m,\nBACKSPACE or ctrl-z for another random flavour (#{collection}) or\nTAB to choose a flavour or collection explicitly ...\e[0m"
    char = one_char
    if char == 'BACKSPACE'
      flavour = nil
      puts "\e[2mAnother flavour at random ...\e[0m"
    elsif char == 'TAB'
      puts "\e[2mChoose a different flavour ...\e[0m"
      flavour, collection = choose_flavour_or_collection(collection)
    else
      puts "\e[2mFlavour accepted.\e[0m"
      return flavour
    end
    puts
    first_iteration = false
    # next loop iteration
  end
end


def choose_flavour_or_collection collection
  choices = $quiz_coll2flavs[collection]
  answer = nil
  loop do
    choose_prepare_for
    answer = choose_interactive("Please choose among #{choices.length} (#{collection}) flavours and #{$quiz_coll2flavs.keys.length} collections:",
                                [choices, ';COLLECTIONS->',
                                 $quiz_coll2flavs.keys,
                                 'describe-all'].flatten) do |tag|
      if tag == 'describe-all'
        'Describe all flavours and flavour collections in detail'
      elsif $quiz_coll2flavs[tag]
        make_extra_desc_short(tag, "Flavour collection '#{tag}' (#{$quiz_coll2flavs[tag].length})")
      else
        make_extra_desc_short(tag, "Flavour '#{tag}'")
      end
    end || collection
    choose_clean_up
    if answer == "describe-all"
      puts "The #{$extras_joined_to_desc[:quiz].length} available flavours and flavour-collections:"
      puts
      puts get_extra_desc_all.join("\n")
      puts
      puts "\e[2mPress any key to choose again ...\e[0m"
      one_char
      redo
    end

    if $quiz_coll2flavs[answer]
      return [nil, answer]
    else
      return [answer, collection]
    end
  end
end


def get_random_flavour collection
  choices = $quiz_coll2flavs[collection]
  puts "\e[2mChoosing a random flavour, 1 out of #{choices.length} (#{collection}).\e[0m"
  sleep 0.1
  flavours_last = $pers_data['quiz_flavours_last'] || []
  try_flavour = nil
  choices = choices.shuffle
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
    play_hons(hons: @scale2holes[scale], hide: @state[:hide_holes])
  else
    puts "\nNo scale selected to play.\n\n"
  end
  puts "\n\e[2mDone with compare, BACK to original question.\e[0m"
end


def re_calculate_quiz_difficulty
  $opts[:difficulty] = ( rand(100) > $opts[:difficulty_numeric]  ?  :easy  :  :hard)
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
  head + desc_lines[1..-1].join(' ')
end


def describe_flavour flavour, has_issue_question
  puts "Quiz Flavour is:   \e[34m#{flavour}\e[0m"
  puts "switches \e[2m>>>> to full listen-perspective\e[0m" unless has_issue_question
  sleep 0.05
  puts
  sleep 0.05
  puts get_extra_desc_single(flavour)[1..-1].
         map {|l| '  ' + l + "\n"}.
         join.chomp +
       ".\n"
end


def print_intervals_etc
  puts "Printing intervals semitones and names as well as a mnemonic song:"
  puts "\e[2m"
  $intervals_quiz[$opts[:difficulty]].each do |st|
    puts "  \e[0m\e[32m%3dst\e[0m\e[2m: #{$intervals[st][0]}" % st
    puts "         " + $quiz_interval2song[st].sample
  end
  puts "\e[0m"
end
