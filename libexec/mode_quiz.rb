#
# Mode quiz with its different flavours
#

def do_quiz to_handle

  print "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
  puts
  
  err "'harpwise quiz #{$extra}' does not take any arguments, these cannot be handled: #{to_handle}" if $extra != 'replay' && to_handle.length > 0

  $num_quiz_replay_explicit = false
  if $extra == 'replay'
    if to_handle.length == 1
      err "'harpwise quiz replay' requires an integer argument, not: #{to_handle[0]}" unless to_handle[0].match(/^\d+$/)
      $num_quiz_replay = to_handle[0].to_i
      $num_quiz_replay_explicit = true
    elsif to_handle.length > 1
      err "'harpwise quiz replay' allows only one argument, not: #{to_handle}"
    end
  end

  print "\e[?25l"  ## hide cursor

  is_random = if ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] == 'yes'
                true
              else
                animate_splash_line
                is_random = $quiz_flavours_random.include?($extra)
              end
  
  Signal.trap('TSTP') do
    ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] = 'yes'
    # do some actions of at_exit-handler here
    sane_term
    print "\e[?25l\e[2m\e[34m ... quiz start over ... \e[0m"  ## hide cursor
    if $pers_file && $pers_data.keys.length > 0 && $pers_fingerprint != $pers_data.hash
      File.write($pers_file, JSON.pretty_generate($pers_data))
    end
    exec($full_commandline)
  end

  if ENV['HARPWISE_RESTARTED_AFTER_SIGNAL'] == 'yes'
    $splashed = true
    puts "\e[K"
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
    if is_random
      puts "\e[0m\e[2mStarting over with a different flavour ...\e[0m\n\n"
    else
      puts "\e[0m\e[2mStarting over ...\e[0m\n\n"
    end
  else
    puts "\e[2mChoosing flavour at random: 1 of #{($quiz_flavour2class.keys - $quiz_flavours_random).length}\e[0m" if is_random
    puts "\e[2mIssue signal ctrl-z to start over.\e[0m"
    puts
    sleep 0.1
  end
    
  flavour_accepted = true
  # for random flavour loop until chosen flavour is accepted
  begin
    # make sure, we do not reuse flavours too often
    flavours_last = $pers_data['quiz_flavours_last'] || []
    if is_random
      $extra = nil
      extras = ($quiz_flavour2class.keys - $quiz_flavours_random).shuffle
      loop do
        $extra = extras.shift
        break if !flavours_last.include?($extra) || extras.length == 0
      end
      flavours_last << $extra
      flavours_last.shift if flavours_last.length > 4
      $pers_data['quiz_flavours_last'] = flavours_last
    end

    # dont show solution immediately
    $opts[:comment] = :holes_some
    $opts[:immediate] = false
    puts
    puts "Quiz Flavour is:   \e[34m#{$extra}\e[0m"
    puts "switches \e[2m>>>> to full listen-perspective\e[0m" unless $quiz_flavour2class[$extra].method_defined?(:issue_question)
    sleep 0.05
    puts
    sleep 0.05
    puts $extra_desc[:quiz][$extra].capitalize.lines.map {|l| '  ' + l}.join.chomp + ".\n"

    $num_quiz_replay = {easy: 4, hard: 8}[$opts[:difficulty]] if !$num_quiz_replay_explicit && $extra == 'replay'

    # only for those classes where it will not already be done in
    # issue_question
    unless $quiz_flavour2class[$extra].method_defined?(:issue_question)
      puts
      print "  \e[2m"
      print 'First ' + $quiz_flavour2class[$extra].describe_difficulty
      puts "\e[0m"
      sleep 0.1
    end

    puts
    if is_random
      print "\e[32mPress any key to continue or BACKSPACE for another flavour ... \e[0m"
      char = one_char
      if char == 'BACKSPACE'
        puts "\n\e[2mChoosing another flavour ...\e[0m"
        sleep 0.1
        flavour_accepted = false
      else
        flavour_accepted = true
      end
      puts
    end
  end until flavour_accepted
  
  # actually start quiz
  if $extra == 'replay'
    puts
    puts "\e[34mNumber of holes to replay is: #{$num_quiz_replay}\e[0m"
    puts "\n\n\n"
    msgbuf_quiz_listen_perspective is_random
    do_licks_or_quiz(lambda_quiz_hint: -> (holes, _, _) do
                       solve_text = "\e[0mHoles  \e[34mto replay\e[0m  are:\n\n\n" +
                                    "\e[32m       #{holes.join('  ')}"
                       quiz_hint_in_handle_holes(solve_text, holes, :all)
                     end)
  elsif $extra == 'play-scale'
    scale_name = $all_quiz_scales[$opts[:difficulty]].sample
    puts "\e[34mScale to play is:\e[0m\e[2m"
    puts
    do_figlet_unwrapped scale_name, 'smblock'
    puts
    puts
    sleep 2
    msgbuf_quiz_listen_perspective is_random
    do_licks_or_quiz(quiz_scale_name: scale_name,
                     lambda_quiz_hint: -> (holes, _, scale_name) do
                       solve_text = "\e[0mScale  \e[34m#{scale_name}\e[0m  is:\n\n\n" +
                                    "\e[32m       #{holes.join('  ')}"
                       quiz_hint_in_handle_holes(solve_text, holes, :all)
                     end)
  elsif $extra == 'play-inter'
    holes_inter = get_random_interval
    puts "\e[34mInterval to play is:\e[0m\e[2m"
    puts
    puts
    do_figlet_unwrapped holes_inter[4], 'smblock'
    puts
    puts
    sleep 2
    msgbuf_quiz_listen_perspective is_random
    do_licks_or_quiz(quiz_holes_inter: holes_inter,
                     lambda_quiz_hint: -> (holes, holes_inter, _) do
                       solve_text = "\e[0mInterval  \e[34m#{holes_inter[4]}\e[0m  is:\n\n\n" +
                                    "\e[32m                #{holes_inter[0]}  to  #{holes_inter[1]}"
                       quiz_hint_in_handle_holes(solve_text, holes, holes[-1])
                     end)
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    first_round = true
    loop do  ## every new question
      $opts[:difficulty] = (rand(100) > $opts[:difficulty_numeric] ? :easy : :hard) unless first_round
      $num_quiz_replay = {easy: 4, hard: 8}[$opts[:difficulty]] if !$num_quiz_replay_explicit && $extra == 'replay'
      catch :next do
        sleep 0.1
        puts
        if !first_round
          puts
          puts_underlined 'Next Question', vspace: false
          puts "\e[2m#{$extra}\e[0m"
          puts
          sleep 0.1
        end
        first_round = false
        flavour = $quiz_flavour2class[$extra].new
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
    err "Internal error: #{$extra}, #{$quiz_flavour2class}"
  end
end


class QuizFlavour

  @@prevs = Array.new

  def initialize
    @state = Hash.new
    @state_orig = @state.clone
  end
  
  def get_and_check_answer
    choose_prepare_for
    all_helps = ['.HELP-NARROW', 'NOT_DEFINED', 'NOT_DEFINED']
    all_choices = [@choices, ';OR->', '.AGAIN', '.SOLVE', all_helps[0]].flatten
    choices_desc = {'.AGAIN' => 'Ask same question again',
                    '.SOLVE' => 'Give solution and go to next question',
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
    when '.AGAIN'
      stand_out 'Asking question again.'
      puts
      return :reissue
    when '.SOLVE'
      sol_text = if @solution.is_a?(Array) && @solution.length > 1
                   "  any of #{@solution}"
                 else
                   "        #{[@solution].flatten[0]}"
                 end
      if self.respond_to?(:after_solve)
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
    when nil
      stand_out "No input or invalid key ?\nPlease try again or\nterminate with ctrl-c ..."
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

  def play_holes hide: nil, reverse: false, holes: nil
    holes ||= @holes
    make_term_immediate
    $ctl_kb_queue.clear
    play_holes_or_notes_simple(reverse ? holes.rotate : holes, hide: hide)
    make_term_cooked
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
    play_holes
  end

  def next_or_reissue
    print "\e[32mPress any key for next question or BACKSPACE to re-ask this one ... \e[0m"
    char = one_char
    puts
    if char == 'BACKSPACE'
      puts "\nSame question again ..."
      @choices = @choices_orig.clone
      @state = @state_orig.clone
      return :reissue
    end
    return :next  
  end

  def choose_clean_up
    clear_area_comment
    clear_area_message
    make_term_cooked
    print "\e[#{$lines[:comment_tall]}H"
  end

  def choose_prepare_for
    prepare_term
    make_term_immediate
    $ctl_kb_queue.clear
    ($term_height - $lines[:comment_tall] + 1).times do
      sleep 0.01
      puts
    end
  end
end

# The three classes below are mostly done within do_licks, so the
# classes here are not complete

class Replay < QuizFlavour
  def self.describe_difficulty
    if $num_quiz_replay_explicit
      "number of holes to replay is #{$num_quiz_replay} (explicitly set)"
    else
      QuizFlavour.difficulty_head + ", number of holes to replay is #{$num_quiz_replay}"
    end
  end
end


class PlayScale < QuizFlavour
  def self.describe_difficulty
    HearScale.describe_difficulty
  end
end


class PlayInter < QuizFlavour
  def self.describe_difficulty
    AddInter.describe_difficulty
  end
end


class HearScale < QuizFlavour

  def initialize
    super
    @choices = $all_quiz_scales[$opts[:difficulty]].clone
    @choices_orig = @choices.clone
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @holes, _, _, _ = read_and_parse_scale(@solution, $harp)
    @prompt = 'Choose the scale you have heard:'
    @help_head = 'Scale'
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
    play_holes
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying a scale\e[0m\e[2m; one scale out of #{@choices.length}; with #{@holes.length} holes ...\e[0m"
    puts "\e[2mThe " + self.class.describe_difficulty + "\e[0m"
    puts
    play_holes
  end

  def tag_desc tag
    $scale2desc[tag]
  end

end


class MatchScale < QuizFlavour

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
    @prompt = "Choose the #{@others ? 'SHORTEST' : 'single'} scale, that contains the holes in question:"
    @help_head = 'Scale'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
    ", taking #{$all_quiz_scales[$opts[:difficulty]].length} scales out of #{$all_scales.length}"
  end
  
  def after_solve
    puts
    puts "Playing solution scale #{@solution} ..."
    sleep 0.2
    puts
    play_holes holes: @holes_scale
    puts
    sleep 0.5
    puts "Playing the holes in question ..."
    sleep 0.2
    puts
    play_holes
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
    play_holes hide: @state[:hide_holes]
  end

  def tag_desc tag
    holes = @scale2holes[tag]
    return nil unless holes
    "#{$scale2desc[tag]} (#{holes.length} holes)"
  end

  def help2
    puts "For help, choose one of the answer-scales to be played:"
    choose_prepare_for
    answer = choose_interactive("Scale to compare:", @choices) do |tag|
      "#{@help_head} #{tag_desc(tag)}" 
    end
    choose_clean_up
    if answer
      play_holes(holes: @scale2holes[answer], hide: @state[:hide_holes])
    else
      puts "\nNo scale selected to play.\n\n"
    end
  end

  def help2_desc
    ['.HELP-PLAY', 'Select a scale and play it for comparison']
  end

  def help3
    puts "Showing all holes played (this question only)."
    @state[:hide_holes] = nil
    play_holes hide: @state[:hide_holes]
  end

  def help3_desc
    ['.HELP-SHOW-HOLES', 'Show the holes played']
  end

  def help4
    puts "\n\e[2mPrinting all scales with their holes.\n\n"
    maxl = @scale2holes.keys.max_by(&:length).length
    @scale2holes.each do |k, v|
      puts "   \e[2m#{k.rjust(maxl)}:\e[0m\e[32m   #{v.join('  ')}\e[0m"
    end
    puts "\n\e[2m#{@choices.length} scales\n\n"
    puts "\e[2mAnd the holes in question:\e[0m\e[32m   #{@holes.join('  ')}\e[0m"
  end

  def help4_desc
    ['.HELP-PRINT-SCALES', 'print all the hole-content of all possible scales']
  end

  def help5
    puts "\n\e[2mPlaying unique holes of sequence sorted by pitch.\n\n"
    play_holes hide: @state[:hide_holes],
               holes: @holes.sort {|a,b| $harp[a][:semi] <=> $harp[b][:semi]}.uniq
  end

  def help5_desc
    ['.HELP-PLAY-SORTED', 'Play holes of sequence in ascending order']
  end

end


class HearInter < QuizFlavour

  def initialize
    super
    @choices = $intervals_quiz.map {|i| $intervals[i][0]}
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
    play_holes
  end

  def help2
    puts "Playing interval reversed:"
    play_holes reverse: true
  end

  def help2_desc
    ['.HELP-REVERSE', 'Play interval reversed']
  end

end


class AddInter < QuizFlavour

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
    $intervals_quiz.each do |inter|
      [inter, -inter].each do |int|
        @choices << $semi2hole[$harp[@holes[0]][:semi] + int]
      end
    end
    @choices.compact!
    @choices_orig = @choices.clone
    @prompt = "Enter the result of #{@verb}ing hole and interval:"
    @help_head = 'Hole'
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
    ", taking #{$intervals_quiz.length} intervals out of #{$intervals.length}"
  end

  def after_solve
    after_solve_interval
  end
  
  def issue_question
    puts
    puts "\e[34mTake hole #{@holes[0]} and #{@verb} interval '#{$intervals[@dsemi.abs][0]}'\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    puts "Playing interval:"
    play_holes hide: @holes[1]
  end

  def help2_desc
    ['.HELP-PLAY-INTER', 'Play interval']
  end

end


class KeyHarpSong < QuizFlavour

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
    puts "\e[34mGiven a #{@qdesc.upcase} with key of '#{@qitem}', name the matching key for the #{@adesc}\n(2nd position)\e[0m"
    puts "\e[2m" + self.class.describe_difficulty + "\e[0m"
  end

  def help2
    note = semi2note(key2semi(@solution.downcase))
    puts "Playing note (octave #{note[-1]}) for answer-key of #{@adesc}:"
    make_term_immediate
    $ctl_kb_queue.clear
    play_holes_or_notes_simple [note], hide: note
    make_term_cooked
  end

  def help2_desc
    ['.HELP-PLAY-ANSWER', "Play note for answer-key of #{@adesc}"]
  end

end


class HearKey < QuizFlavour

  @@seqs = [[[0, 3, 0, 3, 2, 0, 0], 'st louis'],
            [[0, 3, 0, 3, 0, 0, 0, -1, -5, -1, 0], 'wade in the water'],
            [[0, 4, 0, 7, 10, 12, 0], 'intervals'],
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
      play_holes_or_notes_simple notes, hide: semi2note(isemi)
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
    play_holes_or_notes_simple [semi2note(key2semi(@solution))]
    make_term_cooked
  end

end


def get_random_interval
  # favour lower holes
  all_holes = ($harp_holes + Array.new(4, $harp_holes[0 .. $harp_holes.length/2])).flatten.shuffle
  loop do
    err "Internal error: no more holes to try" if all_holes.length == 0
    holes_inter = [all_holes.shift, nil]
    $intervals_quiz.clone.shuffle.each do |inter|
      holes_inter[1] = $semi2hole[$harp[holes_inter[0]][:semi] + inter]
      if holes_inter[1]
        if rand > 0.7
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
        #   2: numerical interval with sign
        #   3: interval long name
        #   4: e.g. '+1 ... up ... maj Third'
        return holes_inter
      end
    end
  end
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


def quiz_hint_in_handle_holes solve_text, holes, hide
  choices2desc = {'SOLVE-PRINT' => 'Solve: Print interval, but keep current question',
                  'HELP-PLAY' => 'Play interval, so that you may replay it'}
  answer = choose_interactive("Available hints for quiz-flavour #{$extra}:",
                              choices2desc.keys) {|tag| choices2desc[tag]}
  clear_area_comment
  clear_area_message
  case answer
  when 'SOLVE-PRINT'
    puts "\e[#{$lines[:comment_tall]}H"
    print solve_text
    puts "\n\n\n\e[0m\e[2mAny char to continue ..."
    $ctl_kb_queue.clear
    $ctl_kb_queue.deq
    $msgbuf.print 'Solution:   ' + holes.join('  '), 6, 8, :quiz_solution
  when 'HELP-PLAY'
    puts "\e[#{$lines[:comment] + 1}H"
    $ctl_kb_queue.clear
    play_holes_or_notes_simple(holes, hide: hide)
    sleep 1
  end
  clear_area_comment
  clear_area_message
end


def msgbuf_quiz_listen_perspective is_random
  $msgbuf.print("or issue signal ctrl-z for another flavour", 3, 5, later: true) if is_random
  $msgbuf.print "Type 'H' for quiz-hints, RETURN for next question" + (is_random ? ',' : ''), 3, 5, :quiz
end
