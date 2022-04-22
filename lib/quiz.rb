#
# Perform quiz
#

def do_quiz

  read_licks if $mode == :memorize

  prepare_term
  start_kb_handler
  start_collect_freqs
  $ctl_can_next = true
  $ctl_can_loop = true
  $ctl_can_change_comment = false
  
  first_lap = true
  all_wanted_before = all_wanted = nil
  puts
  
  loop do   # forever until ctrl-c, sequence after sequence
    if first_lap
      print "\n"
      print "\e[#{$term_height}H\e[K"
      print "\e[#{$term_height-1}H\e[K"
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
      print "\e[#{$line_issue}H\e[0mListen ...\e[K"
      ctl_issue
    end

    if $ctl_back
      if !all_wanted_before || all_wanted_before == all_wanted
        print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
        sleep 1
      else
        all_wanted = all_wanted_before
      end
      $ctl_loop = true
    elsif $ctl_replay
      # nothing to do
    else # also good for $ctl_next
      all_wanted_before = all_wanted
      all_wanted = $mode == :quiz  ?  get_sample($num_quiz)  :  get_lick
      $ctl_loop = $opts[:loop]
    end
    $ctl_back = $ctl_next = $ctl_replay = false
    
    sleep 0.3

    jtext = ''
    ltext = "\e[2m"
    all_wanted.each_with_index do |hole, idx|
      if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
        ltext = "\e[2m"
        if first_lap
          print "\e[#{$term_height}H\e[K"
          print "\e[#{$term_height-1}H\e[K"
        else
          print "\e[#{$line_hint_or_message}H\e[K"
          print "\e[#{$line_call2}H\e[K"
        end
      end
      if idx > 0
        isemi, itext = describe_inter(hole, all_wanted[idx - 1])
        part = ' ' + ( itext || isemi ).tr(' ','') + ' '
        ltext += part
        jtext += " #{part} "
      end
      ltext += if $opts[:immediate]
                 "\e[0m#{hole},#{$harp[hole][:note]}\e[2m"
               else
                 "\e[0m#{$harp[hole][:note]}\e[2m"
               end
      jtext += "#{$harp[hole][:note]},#{hole}"
      if $opts[:merge]
        part = '(' +
               $hole2flags[hole].map {|f| {merged: 'm', root: 'r'}[f]}.compact.join(',') +
               ')'
        part = '' if part == '()'
        ltext += part
        jtext += part
      end

      print "\e[#{first_lap ? $term_height-1 : $line_hint_or_message }H#{ltext.strip}\e[K"
      play_thr = Thread.new { play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]) }
      begin
        sleep 0.1
        handle_kb_listen
      end while play_thr.alive?
      play_thr.join   # raises any errors from thread
      if $ctl_back || $ctl_next || $ctl_replay
        sleep 1
        break
      end
    end

    if !$journal_quiz.include?(jtext)
      IO.write($journal_file, "#{jtext}\n\n", mode: 'a') if $write_journal
      $journal_quiz << jtext
    end
    redo if $ctl_back || $ctl_next || $ctl_replay
    print "\e[0m\e[32m and !\e[0m"
    sleep 1

    if first_lap
      system('clear')
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
    end
    full_hint_shown = false

    begin   # while looping over one sequence

      lap_start = Time.now.to_f

      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        get_hole( -> () do      # lambda_issue
                    if $ctl_loop
                      "\e[32mLooping\e[0m over #{all_wanted.length} notes"
                    else
                      if $num_quiz == 1 
                        "Play the note you have heard !"
                      else
                        "Play note \e[32m#{idx+1}\e[0m of #{$num_quiz} you have heard !"
                      end
                    end
                  end,
          -> (played, since) {[played == wanted,  # lambda_good_done
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next || $ctl_back || $ctl_replay},  # lambda_skip
          
          -> (_, _, _, _, _, _, _) do  # lambda_comment
                    if $num_quiz == 1
                      [ "\e[2m", '.  .  .', 'smblock', nil ]
                    elsif $opts[:immediate]
                      [ "\e[2m", 'Play  ' + ' .' * idx + all_wanted[idx .. -1].join(' '), 'smblock', 'play  ' + '--' * all_wanted.length, :right ]
                    else
                      [ "\e[2m", 'Yes  ' + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(' ')) + ' _' * (all_wanted.length - idx), 'smblock', 'yes  ' + '--' * all_wanted.length ]
                    end
                  end,
          
          -> (_) do  # lambda_hint
            hole_passed = Time.now.to_f - hole_start
            lap_passed = Time.now.to_f - lap_start

            if $opts[:immediate] 
              "\e[2mPlay: " + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(', ')) + ' * ' + all_wanted[idx .. -1].join(', ')
            elsif all_wanted.length > 1 &&
               hole_passed > 4 &&
               lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
              full_hint_shown = true
              "\e[0mSolution: The complete sequence is: #{all_wanted.join(', ')}" 
            elsif hole_passed > 4
              "\e[2mHint: Play \e[0m\e[32m#{wanted}\e[0m"
            else
              if idx > 0
                isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                if isemi
                  "Hint: Move " + ( itext ? "a #{itext}" : isemi )
                end
              end
            end
          end,

          -> (_, _) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter

        break if $ctl_next || $ctl_back || $ctl_replay

      end # notes in a sequence

      text = if $ctl_next
               "skip"
             elsif $ctl_back
               "jump back"
             elsif $ctl_replay
               "replay"
             else
               ( full_hint_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
             end
      print "\e[#{$line_comment}H\e[2m\e[32m"
      do_figlet text, 'smblock'
      print "\e[0m"
      
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[0m#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{all_wanted.join(', ')}   ...   "
      print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
      full_hint_shown = true
        
      sleep 1
    end while $ctl_loop && !$ctl_back && !$ctl_next && !$ctl_replay # looping over one sequence

  print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
    first_lap = false
  end # forever sequence after sequence
end

      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale and merged scale
  holes = Array.new
  # favor lower starting notes
  if rand > 0.5
    holes[0] = $scale_holes[0 .. $scale_holes.length/2].sample
  else
    holes[0] = $scale_holes.sample
  end

  what = Array.new(num)
  for i in (1 .. num - 1)
    ran = rand
    tries = 0
    if ran > 0.7
      what[i] = :nearby
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(-6 .. 6)
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    else
      what[i] = :interval
      begin
        # semitone distances 4,7 and 12 are major third, perfect fifth
        # and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * [-1,1].sample
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    end
  end

  if $opts[:merge]
    # (randomly) replace notes with merged ones and so prefer them 
    for i in (1 .. num - 1)
      if rand >= 0.6
        holes[i] = nearest_hole_with_flag(holes[i], :merged)
        what[i] = :nearest_merged
      end
    end
    # (randomly) make last note a root note
    if rand >= 0.6
      holes[-1] = nearest_hole_with_flag(holes[-1], :root)
      what[-1] = :nearest_root
    end
  end

  for i in (1 .. num - 1)
    # make sure, there is a note in every slot
    unless holes[i]
      holes[i] = $scale_holes.sample
      what[i] = :fallback
    end
    $sample_stats[what[i]] += 1
  end

  IO.write($debug_log, "\n#{Time.now}:\n#{$sample_stats.inspect}\n", mode: 'a') if $opts[:debug]
  holes
end


def get_lick
  $all_licks.sample(1)[0]
end


def read_licks
  glob = $lick_file_template % '{holes,notes}'
  lfiles = Dir[glob]
  err "There are two files matching #{glob}; please check and remove one" if lfiles.length > 1
  if lfiles.length == 0
    lfile = $lick_file_template % 'holes'
    puts "\nLick file\n\n  #{lfile}\n\ndoes not exist !"
    puts "\nCreating it with a single sample lick (and comments);"
    puts "however, you need to add more licks yourself,"
    puts "to make this mode (memorize) really useful."
    puts
    notes = %w(g4 b4 d5 e5 g5 g5)
    holes = notes.map {|n| $note2hole[n]}.select(&:itself)
    File.open(lfile, 'w') do |f|
      f.write <<~end_of_content
        #
        # Library of licks used in mode memorize
        #
        # Each lick on its own line; empty lines
        # and comments are ignored
        #

        # Intro lick from Juke#{holes.length == notes.length ? '' : ' (truncated)'}
        #{holes.join(' ')}

      end_of_content
    end
    puts "Now you may try again with a single predefined lick ..."
    puts "...and then add some of your own !\n\n"
    exit
  else
    lfile = lfiles[0]
  end
  
  File.foreach(lfile) do |line|
    line.gsub!(/#.*/,'')
    line.chomp!
    line.strip!
    next if line.length == 0
    if lfile['holes']
      holes = line.split
      holes.each do |h|
        err("Hole #{h} from #{lfile} is not among holes of harp #{$harp_holes}") unless $harp_holes.include?(h)
      end
      $all_licks << holes
    else
      notes = line.split
      holes = []
      notes.each do |n|
        err("Note #{n} from #{lfile} is not among notes of harp #{$harp_notes}") unless $harp_notes.include?(n)
        holes << $note2hole[n]
      end
      $all_licks << holes
    end
  end

  err("No licks found in #{lfile}") unless $all_licks.length > 0

  # write derived lick file
  dfile = File.dirname(lfile) + '/derived_' + File.basename(lfile).sub(/holes|notes/, lfile['holes'] ? 'notes' : 'holes')
  comment = "#\n# derived lick file with %s,\n# created from #{lfile}\n#\n\n"
  File.open(dfile,'w') do |df|
    df.write comment % [ dfile['holes'] ? 'holes' : 'notes' ]
    $all_licks.each do |lick|
      transformed = lick.map {|hon| dfile['holes']  ?  hon  :  $harp[hon][:note]}
      df.write("# next lick has been truncated as some holes or notes are missing\n") if transformed.length != lick.length
      df.write transformed.join(' ')
      df.write "\n"
    end
  end 
  if $all_licks.length <= 2
    puts "\nThere are only #{$all_licks.length} licks in\n\n  #{lfile}\n\n"
    puts "memorizing them may become boring soon !"
    puts "\nBut continue anyway ...\n\n"
    sleep 2
  end
end


def nearest_hole_with_flag hole, flag
  delta_semi = 0
  found = nil
  begin
    [delta_semi, -delta_semi].shuffle.each do |ds|
      try_semi = $harp[hole][:semi] + ds
      try_hole = $semi2hole[try_semi]
      if try_hole
        try_flags = $hole2flags[try_hole]
        found = try_hole if try_flags && try_flags.include?(flag)
      end
      return found if found
    end
    # no near hole found
    return nil if delta_semi > 8
    delta_semi += 1
  end while true
end
