#
# Mode quiz with its different flavours
#

def do_quiz to_handle

  print "\n\e[2mType is #{$type}, key of #{$key}.\e[0m"
  puts

  err "'harpwise quiz #{$extra}' does not take any arguments, these cannot be handled: #{to_handle}" if $extra != 'replay' && to_handle.length > 0

  if $extra == 'replay'
    err "'harpwise quiz replay' requires exactly one integer argument, not: #{to_handle}" unless to_handle.length == 1 && to_handle[0].match(/^\d+$/)
    $num_quiz_replay = to_handle[0].to_i
  end

  flavours_random = %w(random ran rand)
  random = flavours_random.include?($extra)
  $extra = ($quiz_flavour2class.keys - flavours_random).sample if random
  $num_quiz_replay = 5 if $extra == 'replay'

  animate_splash_line
  
  puts
  puts "Quiz Flavour is: #{$extra}"
  puts
  puts "Description is:"
  puts
  puts $extra_desc[:quiz][$extra].lines.map {|l| '  ' + l}.join
  puts
  if random
    print "\e[32mpress RETURN to continue ... \e[0m"
    STDIN.gets
    puts
  end
  
  if $extra == 'replay'
    do_licks_or_quiz
  elsif $extra == 'play-scale'
    $opts[:comment] = :holes_some
    quiz_scale_name = $all_scales.sample
    puts "\e[32mScale to play is:"
    puts
    do_figlet_unwrapped quiz_scale_name, 'smblock'
    puts
    puts
    do_licks_or_quiz quiz_scale_name
  elsif $quiz_flavour2class.keys.include?($extra) && $quiz_flavour2class[$extra]
    flavour = $quiz_flavour2class[$extra].new
  else
    err "Internal error: #{$extra}, #{$quiz_flavour2class}"
  end
end

class QuizFlavour
  def err_this_is_abstract
    err 'Internal error: this is an abstract method, that needs to be overridden'
  end

  # explain the hole concept of this flavour
  def explain
    err_this_is_abstract
  end

  # pose a query
  def query
    err_this_is_abstract
  end

  # check answer
  def check answer
    err_this_is_abstract
  end
end


class FindScaleShuffled < QuizFlavour
end

class FindScaleOrdered < QuizFlavour
end
