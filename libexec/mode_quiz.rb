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
    print "\e[32mpress RETURN to continue ... \e[0m"
    STDIN.gets
    puts
  end
  
  if $extra == 'replay'
    do_licks_or_quiz
  elsif $extra == 'play-scale'
    $opts[:comment] = :holes_some
    scale_name = $all_scales.sample
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


class HearScale < QuizFlavour
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
