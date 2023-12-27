#
# Mode quiz with its different flavours
#

def do_quiz to_handle

  print "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
  puts

  err "'harpwise quiz #{$extra}' does not take any arguments, these cannot be handled: #{to_handle}" if $extra != 'replay' && to_handle.length > 0

  if $extra == 'replay'
    if to_handle.length == 1
      err "'harpwise quiz replay' requires an integer argument, not: #{to_handle[0]}" unless to_handle[0].match(/^\d+$/)
      $num_quiz_replay = to_handle[0].to_i
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

  $num_quiz_replay ||= {easy: 5, hard: 12}[$opts[:difficulty]] if $extra == 'replay'

  animate_splash_line
  
  puts
  puts "Quiz Flavour is: \e[34m#{$extra}\e[0m"
  puts
  sleep 0.05
  puts "Description is:"
  puts
  sleep 0.05
  puts $extra_desc[:quiz][$extra].lines.map {|l| '  ' + l}.join

  print "  \e[2m("
  if $extra == 'replay'
    print "number of notes to replay is #{$num_quiz_replay}"
  elsif $extra == 'play-scale'
    HearScale.describe_difficulty
  elsif $extra == 'play-inter'
    AddInter.describe_difficulty
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    $quiz_flavour2class[$extra].describe_difficulty
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
    do_figlet_unwrapped holes_inter[-1], 'smblock'
    puts
    puts
    sleep 2
    do_licks_or_quiz(quiz_holes_inter: holes_inter)
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    first_round = true
    loop do  ## every new question
      catch :next do
        sleep 0.1
        puts
        if !first_round
          puts
          puts_underlined 'Next Question'
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
    all_choices = [@choices, ';OR->', 'SOLVE', 'AGAIN', 'HELP'].flatten
    choices_desc = {'SOLVE' => 'Give solution and go to next question',
                    'AGAIN' => 'Ask same question again',
                    'HELP' => 'Remove some solutions, leaving less choices'}
    if help2_desc
      all_choices << 'HELP2'
      choices_desc['HELP2'] = help2_desc
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
      stand_out "Yes, '#{answer}' is RIGHT !\n\nMoving to next question.", all_green: true
      puts
      after_right
      sleep 1
      return :next
    end
    case answer
    when 'AGAIN'
      stand_out 'Asking question again.'
      puts
      return :reissue
    when 'SOLVE'
      stand_out "The correct answer is:\n\n    #{@solution}\n"
      sleep 1
      if self.respond_to?(:after_solve)
        after_solve
        sleep 1
      end
      puts
      print "\e[32mPress any key to continue ... \e[0m"
      one_char
      puts
      return :next
    when 'HELP'
      if @choices.length > 1
        stand_out 'Removing some choices to make it easier'
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
    when 'HELP2'
      help2
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
  
  def play_holes hide_hole: nil
    make_term_immediate
    play_holes_or_notes_simple @holes, hide_hole: hide_hole
    make_term_cooked
  end

  def help2_desc
    nil
  end

  def tag_desc tag
    nil
  end

  def after_right
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
    print QuizFlavour.difficulty_head
    print ", taking #{$quiz_scales.length} scales out of #{$all_scales.length}"
  end
  
  def after_solve
    puts
    puts "Playing scale again ..."
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
      @inter = get_random_interval
      @holes = @inter[0..1]
      @holes.rotate! if rand > 0.7
      @solution = $intervals[@inter[2]][0]
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
    puts
    puts "Playing interval ..."
    sleep 0.1
    puts
    play_holes
  end
  
  def issue_question
    puts
    puts "\e[34mPlaying an interval\e[0m \e[2m; one out of #{@choices.length}\e[0m ..."
    sleep 0.1
    puts
    play_holes
  end

end


class AddInter < QuizFlavour

  def initialize
    @choices = $harp_holes.clone
    begin
      @inter = get_random_interval
      @holes = @inter[0..1]
      @verb = 'add'
      if rand > 0.7
        @holes.rotate!
        @verb = 'subtract'
      end
      @solution = @holes[1]
    end while @@prevs.include?(@holes)
    @@prevs << @holes
    @@prevs.shift if @@prevs.length > 2
    @prompt = "Enter the result of #{@verb}ing hole and interval:"
    @help_head = 'Hole'
  end

  def self.describe_difficulty
    print QuizFlavour.difficulty_head
    print ", taking #{$intervals_quiz.length} intervals out of #{$intervals.length}"
  end

  def after_solve
    puts
    puts "Playing interval ..."
    sleep 0.1
    puts
    play_holes
  end
  
  def issue_question
    puts
    puts "\e[34mTake hole #{@holes[0]} and #{@verb} interval '#{$intervals[@inter[2]][0]}' ...\e[0m"
  end

  def help2
    play_holes hide_hole: @holes[1]
  end

  def help2_desc
    'Play interval'
  end

  def after_right
    after_solve
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
        holes_inter << inter
        holes_inter << "#{holes_inter[0]} ... #{$intervals[inter][0]}"
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
