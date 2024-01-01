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

  flavours_random = %w(random ran rand)
  # make sure, we do not reuse flavours too often
  flavours_last = $pers_data['quiz_flavours_last'] || []
  is_random = flavours_random.include?($extra)
  if is_random
    $extra = nil
    extras = ($quiz_flavour2class.keys - flavours_random).shuffle
    loop do
      $extra = extras.shift
      break if !flavours_last.include?($extra) || extras.length == 0
    end
    flavours_last << $extra
    flavours_last.shift if flavours_last.length > 2
    $pers_data['quiz_flavours_last'] = flavours_last
  end

  animate_splash_line
  
  puts
  puts "Quiz Flavour is: \e[34m#{$extra}\e[0m"
  puts "\e[2m1 out of #{($quiz_flavour2class.keys - flavours_random).length}\e[0m" if is_random
  puts
  sleep 0.05
  puts "Description is:"
  puts
  sleep 0.05
  puts $extra_desc[:quiz][$extra].lines.map {|l| '  ' + l}.join

  $num_quiz_replay = {easy: 5, hard: 12}[$opts[:difficulty]] if !$num_quiz_replay_explicit && $extra == 'replay'

  # print difficulty
  print "  \e[2m("
  if $extra == 'replay'
    print Replay.describe_difficulty
  elsif $extra == 'play-scale'
    print HearScale.describe_difficulty
  elsif $extra == 'play-inter'
    print AddInter.describe_difficulty
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    print $quiz_flavour2class[$extra].describe_difficulty
  else
    err "Internal error: #{$extra}, #{$quiz_flavour2class}"
  end
  puts ")\e[0m"
  sleep 0.1

  puts
  if is_random
    print "\e[32mPress any key to continue ... \e[0m"
    one_char
    puts
  end

  # actually start quiz
  if $extra == 'replay'
    do_licks_or_quiz
  elsif $extra == 'play-scale'
    $opts[:comment] = :holes_some
    scale_name = $quiz_scales.sample
    puts "\e[32mScale to play is:"
    puts
    do_figlet_unwrapped scale_name, 'smblock'
    puts
    puts
    sleep 2
    do_licks_or_quiz(quiz_scale_name: scale_name)
  elsif $extra == 'play-inter'
    $opts[:comment] = :holes_some
    holes_inter = get_random_interval
    puts "\e[32mInterval to play is:"
    puts
    do_figlet_unwrapped holes_inter[4], 'smblock'
    puts
    puts
    sleep 2
    do_licks_or_quiz(quiz_holes_inter: holes_inter)
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    first_round = true
    loop do  ## every new question
      $opts[:difficulty] = (rand(100) > $opts[:difficulty_numeric] ? :easy : :hard) unless first_round
      catch :next do
        sleep 0.1
        puts
        if !first_round
          puts
          puts_underlined 'Next Question', vspace: false
          puts "\e[2m#{$extra}, #{$quiz_flavour2class[$extra].describe_difficulty}\e[0m"
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

  def get_and_check_answer
    prepare_term
    make_term_immediate
    $ctl_kb_queue.clear
    ($term_height - $lines[:comment_tall] + 1).times do
      sleep 0.01
      puts
    end
    all_choices = [@choices, ';OR->', '.AGAIN', '.SOLVE', '.HELP'].flatten
    choices_desc = {'.AGAIN' => 'Ask same question again',
                    '.SOLVE' => 'Give solution and go to next question',
                    '.HELP' => 'Remove some solutions, leaving less choices'}
    if help2_desc
      all_choices << '.HELP2'
      choices_desc['.HELP2'] = help2_desc
    end
    if help3_desc
      all_choices << '.HELP3'
      choices_desc['.HELP3'] = help3_desc
    end
    answer = choose_interactive(@prompt, all_choices) do |tag|
      choices_desc[tag] ||
        ( tag_desc(tag) && "#{@help_head} #{tag_desc(tag)}" ) ||
        "#{@help_head} #{tag}"
    end
    clear_area_comment
    clear_area_message
    make_term_cooked
    print "\e[#{$lines[:comment_tall]}H"
    if answer == @solution
      if self.respond_to?(:after_solve)
        stand_out "Yes, '#{answer}' is RIGHT !\n\nSome extra info below.", all_green: true
        puts
        after_solve
      else
        stand_out "Yes, '#{answer}' is RIGHT !", all_green: true
      end
      puts
      print "\e[32mPress any key to move to next question ... \e[0m"
      one_char
      puts
      return :next
    end
    case answer
    when '.AGAIN'
      stand_out 'Asking question again.'
      puts
      return :reissue
    when '.SOLVE'
      if self.respond_to?(:after_solve)
        stand_out "The correct answer is:\n\n        #{@solution}\n\nSome extra info below."
        after_solve
      else
        stand_out "The correct answer is:\n\n        #{@solution}\n"
      end
      puts
      print "\e[32mPress any key to move to next question ... \e[0m"
      one_char
      puts
      return :next
    when '.HELP'
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
    when '.HELP2'
      help2
      return :reask
    when '.HELP3'
      help3
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
    "difficulty is '#{$opts[:difficulty]}'"
  end
  
  def play_holes hide: nil, reverse: false
    make_term_immediate
    $ctl_kb_queue.clear
    play_holes_or_notes_simple(reverse ? @holes.rotate : @holes, hide: hide)
    make_term_cooked
  end

  def help2_desc
    nil
  end

  def help3_desc
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
  
end


class Replay < QuizFlavour
  def self.describe_difficulty
    if $num_quiz_replay_explicit
      "number of notes to replay is #{$num_quiz_replay} (explicitly set)"
    else
      QuizFlavour.difficulty_head + ", number of notes to replay is #{$num_quiz_replay}"
    end
  end
end


class HearScale < QuizFlavour

  def initialize
    @choices = $quiz_scales.clone
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
    ", taking #{$quiz_scales.length} scales out of #{$all_scales.length}"
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
    puts "\e[34mPlaying a scale\e[0m \e[2m; one scale out of #{@choices.length}; with #{@holes.length} holes ...\e[0m"
    puts
    play_holes
  end

  def tag_desc tag
    $scale2desc[tag]
  end

end


class HearInter < QuizFlavour

  def initialize
    @choices = $intervals_quiz.map {|i| $intervals[i][0]}
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
    sleep 0.1
    puts
    play_holes
  end

  def help2
    puts "Playing interval reversed:"
    play_holes reverse: true
  end

  def help2_desc
    'Play interval reversed'
  end

end


class AddInter < QuizFlavour

  def initialize
    @choices = $harp_holes.clone
    begin
      inter = get_random_interval
      @holes = inter[0..1]
      @dsemi = inter[2]
      @verb = inter[2] > 0 ? 'add' : 'subtract'
      @solution = @holes[1]
    end while @@prevs.include?(@holes)
    @@prevs << @holes
    @@prevs.shift if @@prevs.length > 2
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
  end

  def help2
    puts "Playing interval:"
    play_holes hide: @holes[1]
  end

  def help2_desc
    'Play interval'
  end

end


class KeyHarpSong < QuizFlavour

  def initialize

    harp2song = get_harp2song(basic_set: $opts[:difficulty] == :easy)

    @qdesc, @adesc, qi2ai = if rand > 0.5
                              ['harp', 'song', harp2song]
                            else
                              ['song', 'harp', harp2song.invert]
                            end
    @choices = qi2ai.values    
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
    "Play note for answer-key of #{@adesc}"
  end

end


class HearKey < QuizFlavour

  @@seqs = [[[0, 3, 0, 3, 2, 0, 0], 'st louis'],
            [[0, 3, 0, 3, 0, 0, 0, -1, -5, -1, 0], 'wade in the water'],
            [[0, 4, 0, 7, 10, 12, 0], 'chord and octave'],
            [[0, 0, 0], 'key only']]
             
  def initialize
    @@seqs.rotate!(rand(@@seqs.length).to_i)
    @seq = @@seqs[0][0]
    @nick = @@seqs[0][1]
    @ia_key = nil
    harp2song = get_harp2song(basic_set: $opts[:difficulty] == :easy)
    @choices = harp2song.keys 
    begin
      @solution = @choices.sample
    end while @@prevs.include?(@solution)
    @@prevs << @solution
    @@prevs.shift if @@prevs.length > 2
    @prompt = "Key of sequence that has been played:"
    @help_head = "Key"
  end

  def self.describe_difficulty
    QuizFlavour.difficulty_head +
    ", taking #{$opts[:difficulty] == :easy ? 4 : 12} keys out of 12"
  end

  def issue_question silent: false
    unless silent
      puts
      puts "\e[34mHear a sequence of notes '#{@nick}' and name its key\e[0m"
    end
    isemi = key2semi(@solution.downcase)
    notes = @seq.map {|s| semi2note(isemi + s)}
    make_term_immediate
    $ctl_kb_queue.clear
    play_holes_or_notes_simple notes, hide: semi2note(isemi)
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
    "Choose a different sequence of notes"
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
    "Play an adjustable pitch to compare"
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
  all_holes = ($harp_holes + Array.new(3, $harp_holes[0 .. $harp_holes.length/2])).flatten.shuffle
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
            if $conf[:pref_sig] == :flat
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
