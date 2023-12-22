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
  $num_quiz_replay = 5 if $extra == 'replay'

  animate_splash_line
  
  puts
  puts "Quiz Flavour is: #{$extra}"
  puts
  puts "Description is:"
  puts
  puts $extra_desc[:quiz][$extra].lines.map {|l| '  ' + l}.join
  puts
  if is_random
    print "\e[32mPress any key to continue ... \e[0m"
    one_char
    puts
    puts
  end
  
  if $extra == 'replay'
    do_licks_or_quiz
  elsif $extra == 'play-scale'
    $opts[:comment] = :holes_some
    scale_name = $shorter_scales.sample
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
        puts
        puts '  *** Next Question ***' unless first_round
        puts
        first_round = false
        flavour = $quiz_flavour2class[$extra].new
        loop do  ## repeats of question
          catch :reissue do
            flavour.issue_question
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

  def get_and_check_answer
    make_term_immediate
    ($term_height - $lines[:comment_tall] + 1).times { puts }
    answer = choose_interactive(@prompt, [@choices, ';OR->', 'SKIP', 'AGAIN', 'RESOLVE', 'HELP'].flatten) do |tag|
      {'SKIP' => 'Skip to next question',
       'RESOLVE' => 'Give solution and go to next question',
       'AGAIN' => 'Ask same question again',
       'HELP' => 'Remove some solutions, leaving less choices',
      }[tag] || "#{@help_head} #{tag}"
    end
    clear_area_comment
    clear_area_message
    make_term_cooked
    print "\e[#{$lines[:comment_tall]}H"
    if answer == @solution
      stand_out "Yes, '#{answer}' is RIGHT !\n\nSkipping to next question.", green: true
      puts
      return :next
    end
    if answer == 'SKIP'
      stand_out 'Skipping to next question.'
      puts
      return :next
    end
    if answer == 'AGAIN'
      stand_out 'Asking again.'
      puts
      return :reissue
    end
    if answer == 'RESOLVE'
      stand_out "The correct answer is:\n\n    #{@solution}\n\nSkipping to next question."
      sleep 1
      puts
      return :next
    end
    if answer == 'HELP'
      if @choices.length > 1
        stand_out 'Removing some choices to make it easier'
        orig_len = @choices.length 
        while @choices.length > orig_len / 2
          idx = rand(@choices.length)
          next if @choices[idx] == @solution
          @choices.delete_at(idx)
        end
      else
        stand_out "There is only one choice left;\nit should be pretty easy by now ..."
      end
      return :reask
    end
    stand_out "Sorry, your answer '#{answer}' is wrong;\nplease try again ..."
    @choices.delete(answer)
    return :reask
  end

end

  
class HearScale < QuizFlavour

  def initialize
    @choices = $shorter_scales.clone
    @solution = @choices.sample
    @prompt = 'Choose the scale you have heard !'
    @help_head = 'Scale '
  end

  def issue_question
    puts
    puts "Playing a scale ..."
    puts
    holes, _, _, _ = read_and_parse_scale_simple(@solution, $harp)
    make_term_immediate
    play_holes_or_notes_simple holes
    make_term_cooked
  end

end


class HearInter < QuizFlavour
end

def get_random_interval
  # favour lower holes
  all_holes = ($harp_holes + Array.new(3, $harp_holes[0 .. $harp_holes.length/2])).flatten.shuffle
  loop do
    err "Internal error: no more holes to try" if all_holes.length == 0
    holes_inter = [all_holes.shift, nil]
    $intervals_fav.clone.shuffle.each do |inter|
      holes_inter[1] = $semi2hole[$harp[holes_inter[0]][:semi] + inter]
      if holes_inter[1]
        holes_inter << inter
        holes_inter << "#{holes_inter[0]} ... #{$intervals[inter][0]}"
        return holes_inter
      end
    end
  end
end


def stand_out text, green: false
  print "\e[32m" if green
  puts
  lines = text.lines.map(&:chomp)
  maxl = lines.map(&:length).max
  puts '  + ' + ( '-' * maxl ) + ' +'
  lines.each {|l| puts '  | ' + ("%-#{maxl}s" % l) + ' |'}
  puts '  + ' + ( '-' * maxl ) + ' +'
  print "\e[0m"
end
