#
# Sense holes played
#

# See  https://en.wikipedia.org/wiki/ANSI_escape_code  for formatting options

def handle_holes lambda_issue, lambda_good_done_was_good, lambda_skip, lambda_comment, lambda_hint, lambda_hole_for_inter
  samples = Array.new
  $move_down_on_exit = true
  longest_hole_name = $harp_holes.max_by(&:length)
  
  hole_start = Time.now.to_f
  hole = hole_since = hole_was_for_disp = nil
  hole_held = hole_held_before = hole_held_since = nil
  was_good = was_was_good = was_good_since = nil
  hints_refreshed_at = Time.now.to_f - 1000.0
  hints = hints_old = nil
  first_round = true
  $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref

  loop do   # until var done or skip

    system('clear') if $ctl_redraw
    if first_round || $ctl_redraw
      print "\e[#{$lines[:issue]}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
      $ctl_default_issue = "SPACE to pause; h for help"
      ctl_issue
      print "\e[#{$lines[:key]}H" + text_for_key
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($conf[:display])
      if $ctl_redraw && $ctl_redraw != :silent
        print "\e[#{$lines[:hint_or_message]}H\e[2mTerminal [width, height] = [#{$term_width}, #{$term_height}] #{$term_width == $conf[:term_min_width] || $term_height == $conf[:term_min_height]  ?  "\e[0;91mON THE EDGE\e[0;2m of"  :  'is above'} minimum size [#{$conf[:term_min_width]}, #{$conf[:term_min_height]}]\e[K\e[0m"
        $message_shown_at = Time.now.to_f
      end
    end
    print "\e[#{$lines[:hint_or_message]}HWaiting for frequency pipeline to start ..." if $first_round_ever_get_hole

    freq = $opts[:screenshot]  ?  697  :  $freqs_queue.deq

    return if lambda_skip && lambda_skip.call()

    pipeline_catch_up if handle_kb_listen
    ctl_issue
    print "\e[#{$lines[:interval]}H\e[2mInterval:   --  to   --  is   --  \e[K" if first_round || $ctl_redraw
    $ctl_redraw = false

    handle_win_change if $ctl_sig_winch
    
    good = done = false
      
    hole_was_for_since = hole
    hole = nil
    hole, lbor, cntr, ubor = describe_freq(freq)
    hole_since = Time.now.to_f if !hole_since || hole != hole_was_for_since
    if hole != hole_held  &&  Time.now.to_f - hole_since > 0.1
      hole_held_before = hole_held
      write_to_journal(hole_held, hole_held_since) if $write_journal && $mode == :listen && regular_hole?(hole_held)
      if hole
        hole_held = hole
        hole_held_since = hole_since
      end
    end
    hole_for_inter = nil

    was_was_good = was_good
    good, done, was_good = if $opts[:screenshot]
                             [true, $ctl_can_next && Time.now.to_f - hole_start > 2, false]
                           else
                             lambda_good_done_was_good.call(hole, hole_since)
                           end
    done = false if $opts[:no_progress]

    was_good_since = Time.now.to_f if was_good && was_good != was_was_good

    print "\e[2m\e[#{$lines[:frequency]}HFrequency:  "
    just_dots_short = '.........:.........'
    format = "%6s Hz, %4s Cnt  [%s]\e[2m\e[K"
    if regular_hole?(hole)
      dots, _ = get_dots(just_dots_short.dup, 2, freq, lbor, cntr, ubor) {|hit, idx| hit ? "\e[0m#{idx}\e[2m" : idx}
      cents = cents_diff(freq, cntr).to_i
      print format % [freq.round(1), cents, dots]
    else
      print format % ['--', '--', just_dots_short]
    end

    hole_for_inter = lambda_hole_for_inter.call(hole_held_before, $hole_ref) if lambda_hole_for_inter
    inter_semi, inter_text, _, _ = describe_inter(hole_held, hole_for_inter)
    if inter_semi
      print "\e[#{$lines[:interval]}HInterval: #{hole_for_inter.rjust(4)}  to #{hole_held.rjust(4)}  is #{inter_semi.rjust(5)}  " + ( inter_text ? ", #{inter_text}" : '' ) + "\e[K"
    elsif hole_for_inter
      print "\e[#{$lines[:interval]}HInterval: #{hole_for_inter.rjust(4)}  to   --  is   --  \e[K"
    else
      # let old interval be visible
    end

    hole_disp = ({ low: '-', high: '-'}[hole] || hole || '-')
    hole_color = "\e[0m\e[%dm" %
                 if $opts[:no_progress]
                   get_hole_color_inactive(hole)
                 else
                   get_hole_color_active(hole, good, was_good, was_good_since)
                 end
    hole_ref_color = "\e[#{hole == $hole_ref ?  92  :  91}m"
    case $conf[:display]
    when :chart_notes, :chart_scales, :chart_intervals
      update_chart(hole_was_for_disp, :inactive) if hole_was_for_disp && hole_was_for_disp != hole
      hole_was_for_disp = hole if hole
      update_chart(hole, :active, good, was_good, was_good_since)
    when :hole
      print "\e[#{$lines[:display]}H\e[0m"
      print hole_color
      do_figlet hole_disp, 'mono12', longest_hole_name
    when :bend
      print "\e[#{$lines[:display] + 2}H"
      if $hole_ref
        semi_ref = $harp[$hole_ref][:semi]
        just_dots_long = '......:......:......:......'
        dots, hit = get_dots(just_dots_long.dup, 4, freq,
                             semi2freq_et(semi_ref - 2),
                             semi2freq_et(semi_ref),
                             semi2freq_et(semi_ref + 2)) {|ok,idx| idx}
        print ( hit  ?  "\e[0m\e[32m"  :  "\e[0m\e[31m" )
        do_figlet dots, 'smblock', 'fixed:' + just_dots_long
      else
        print "\e[2m"
        do_figlet 'set ref first', 'smblock'
      end
    else
      fail "Internal error: #{$conf[:display]}"
    end

    text = "Hole: %#{longest_hole_name.length}s, Note: %4s" %
           (regular_hole?(hole)  ?  [hole, $harp[hole][:note]]  :  ['-- ', '-- '])
    text += ", Ref: %#{longest_hole_name.length}s" % [$hole_ref || '-- ']
    text += ",  Rem: #{$hole2rem[hole] || '--'}" if $hole2rem
    print "\e[#{$lines[:hole]}H\e[2m" + truncate_text(text, $term_width - 4) + "\e[K"

    if lambda_comment
      case $conf[:comment]
      when :holes_scales
        print "\e[#{$lines[:comment]}H"
        lambda_comment.call(nil,nil,nil,nil,nil,nil,nil).each {|l| puts l}
      when :holes_intervals
        print "\e[#{$lines[:comment]}H"
        lambda_comment.call(nil,nil,nil,nil,nil,nil,nil).each {|l| puts l}
      when :holes_all
        # goes to $lines[:comment_tall] by itself
        lambda_comment.call(nil,nil,nil,nil,nil,nil,nil)
      else
        comment_color,
        comment_text,
        font,
        width_template,
        truncate =
        lambda_comment.call($hole_ref  ?  hole_ref_color  :  hole_color,
                            inter_semi,
                            inter_text,
                            hole && $harp[hole] && $harp[hole][:note],
                            hole_disp,
                            freq,
                            $hole_ref ? semi2freq_et($harp[$hole_ref][:semi]) : nil)
        print "\e[#{$lines[:comment]}H#{comment_color}"
        do_figlet comment_text, font, width_template, truncate
      end
    end

    if done
      print "\e[#{$lines[:message2]}H" if $lines[:message2] > 0
      return
    end

    if lambda_hint && Time.now.to_f - hints_refreshed_at > 0.5
      if $message_shown_at
        # triggers refresh of hint, once the current message has been elapsed
        hints_old = nil
      else
        hints = lambda_hint.call(hole)
        hints_refreshed_at = Time.now.to_f
        if hints != hints_old
          print "\e[#{$lines[:message2]}H\e[K" if $lines[:message2] > 0
          print "\e[#{$lines[:hint_or_message]}H"
          # Using truncate_colored_text might be too slow here
          if hints.length == 1
            print truncate_text(hints[0], $term_width - 4) + "\e[K"
          elsif hints.length == 2 && $lines[:message2] > 0
            print truncate_text(hints[0], $term_width - 4) + "\e[K"
            print "\e[#{$lines[:message2]}H\e[0m\e[2m"
            print truncate_text(hints[1], $term_width - 4) + "\e[K"
          else
            err "Internal error"
          end
          print "\e[0m\e[2m"
        end
        hints_old = hints
      end
    end      

    if $ctl_set_ref
      $hole_ref = regular_hole?(hole_held) ? hole_held : nil
      print "\e[#{$lines[:hint_or_message]}H\e[2m#{$hole_ref ? 'Stored' : 'Cleared'} reference for intervals and display of bends\e[0m\e[K"
      if $hole_ref 
        $charts[:chart_intervals] = get_chart_with_intervals
        if $conf[:display] == :chart_intervals
          clear_area_display
          print_chart
        end
      end
      $message_shown_at = Time.now.to_f
      $ctl_set_ref = false
      $ctl_update_after_set_ref = true
    end
    
    if $ctl_change_display
      choices = [ $display_choices, $display_choices ].flatten
      choices = choices.reverse if $ctl_change_display == :back
      $conf[:display] = choices[choices.index($conf[:display]) + 1]
      $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
      clear_area_display
      print_chart if [:chart_notes, :chart_scales, :chart_intervals].include?($conf[:display])
      print "\e[#{$lines[:hint_or_message]}H\e[2mDisplay is now #{$conf[:display].upcase}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
      $ctl_change_display = false
    end
    
    if $ctl_change_comment
      choices = [ $comment_choices[$mode], $comment_choices[$mode] ].flatten
      choices = choices.reverse if $ctl_change_comment == :back
      $conf[:comment] = choices[choices.index($conf[:comment]) + 1]
      clear_area_comment
      print "\e[#{$lines[:hint_or_message]}H\e[2mComment is now #{$conf[:comment].upcase}\e[0m\e[K"
      $message_shown_at = Time.now.to_f
      $ctl_change_comment = false
    end

    if $ctl_show_help
      clear_area_comment
      puts "\e[#{$lines[:help]}H\e[0mShort help on keys (see README.org for more details):\e[0m\e[32m\n"
      puts "   SPACE: pause               ctrl-l: redraw screen"
      puts " TAB,S-TAB,d,D: change display (upper part of screen)"
      puts "     c,C: change comment (lower, i.e. this, part of screen)"
      puts "       r: set reference hole       j: toggle writing of journal file"
      puts "       k: change key of harp       s: change scale"
      puts "       q: quit                     h: this help"
      if $ctl_can_next
        puts "\e[0mType any key to show more help ...\e[K"
        $ctl_kb_queue.clear
        $ctl_kb_queue.deq
        clear_area_comment
        puts "\e[#{$lines[:help]}H\e[0mMore help on keys:\e[0m\e[32m\n"
        puts "     .: replay current recording          ,: replay, holes only"
        puts "   :,p: replay recording but ignore '--partial'"
        puts "   RET: next sequence             BACKSPACE: previous sequence"
        puts "     i: toggle '--immediate'              l: loop current sequence"
        puts "   0,-: forget holes played           TAB,+: skip rest of sequence"
        puts "     #: toggle track progress in seq"
        puts "     n: switch to lick by name            t: change option --tags" if $ctl_can_named
      end
      puts "\e[0mType any key to continue ...\e[K"
      $ctl_kb_queue.clear
      $ctl_kb_queue.deq
      ctl_issue 'continue', hl: true
      clear_area_comment
      $ctl_show_help = false
    end

    if $ctl_can_loop && $ctl_start_loop
      $ctl_loop = true
      $ctl_start_loop = false
      print "\e[#{$lines[:issue]}H#{lambda_issue.call.ljust($term_width - $ctl_issue_width)}\e[0m"
    end
    
    if $ctl_toggle_journal
      $write_journal = !$write_journal
      if $write_journal
        journal_start
        $journal_listen = Array.new
      else
        write_to_journal(hole_held, hole_held_since) if $mode == :listen && regular_hole?(hole_held)
        IO.write($journal_file, "All holes: #{$journal_listen.join(' ')}\n", mode: 'a') if $mode == :listen && $journal_listen.length > 0
        IO.write($journal_file, "Stop writing journal at #{Time.now}\n", mode: 'a')
      end
      ctl_issue "Journal #{$write_journal ? ' ON' : 'OFF'}"
      print "\e[#{$lines[:hint_or_message]}H\e[2m"      
      print ( $write_journal  ?  "Appending to "  :  "Done with " ) + $journal_file
      print "\e[K"
      $message_shown_at = Time.now.to_f

      $ctl_toggle_journal = false

      print "\e[#{$lines[:key]}H" + text_for_key      
    end

    if $ctl_change_key || $ctl_change_scale
      print "\e[#{$lines[:hint_or_message]}H\e[J\e[0m\e[K"
      stop_kb_handler
      sane_term
      er = inp = nil
      begin
        if $ctl_change_key
          print "\e[0m\e[2mPlease enter \e[0mnew key\e[2m (current is #{$key}):\e[0m "
          inp = STDIN.gets.chomp
          inp = $key.to_s if inp == ''
          er = check_key_and_set_pref_sig(inp)
        else
          scales = scales_for_type($type)
          print "\e[0m\e[2mPlease enter \e[0mnew scale\e[2m (one of #{scales.join(', ')}; current is #{$scale}):\e[0m "
          inp = STDIN.gets.chomp
          inp = $scale if inp == ''
          scale = match_or(inp, scales) do |none, choices|
            er = "Given scale #{none} is none of #{choices}"
          end            
        end
        if er
          puts "\e[91m#{er}"
        else
          if $ctl_change_key
            $key = inp.to_sym
          else
            $scale = inp
          end
        end
      end while er
      # next two lines also appears in file harpwise
      $harp, $harp_holes, $harp_notes, $scale_holes, $scale_notes, $hole2rem, $hole2flags, $hole2scale_abbrevs, $semi2hole, $note2hole, $intervals, $dsemi_harp = read_musical_config
      $charts, $hole2chart = read_chart
      $charts[:chart_intervals] = get_chart_with_intervals if $hole_ref
      set_global_vars_late
      $freq2hole = read_calibration
      start_kb_handler
      prepare_term
      $ctl_redraw = :silent
      system('clear')
      print "\e[3J" # clear scrollback
      print "\e[#{$lines[:key]}H" + text_for_key
      if $ctl_change_key
        print "\e[#{$lines[:hint_or_message]}H\e[2mChanged key of harp to \e[0m#{$key}\e[K"
      else
        print "\e[#{$lines[:hint_or_message]}H\e[2mChanged scale in use to \e[0m#{$scale}\e[K"
      end
      $message_shown_at = Time.now.to_f
      $ctl_change_key = $ctl_change_scale = false
    end

    return if $ctl_named_lick || $ctl_change_tags

    if $ctl_quit
      print "\e[#{$lines[:hint_or_message]}H\e[K\e[0mTerminating on user request (quit) ...\n\n"
      exit 0
    end

    if done || ( $message_shown_at && Time.now.to_f - $message_shown_at > 8 )
      print "\e[#{$lines[:hint_or_message]}H\e[K"
      $message_shown_at = false
    end
    first_round = $first_round_ever_get_hole = false
  end  # loop until var done or skip
end


def text_for_key
  text = "\e[2m#{$mode}"
  text += "(#{$licks.length})" if $mode == :licks
  text += " #{$type} #{$key}"
  if $opts[:add_scales]
    text += "\e[0m"
    text += " \e[32m#{$scale}"
    text += "\e[0m\e[2m," + $scales[1..-1].map {|s| "\e[0m\e[34m#{s}\e[0m\e[2m"}.join(',')
    text += ",\e[0mall\e[2m"
  else
    text += " #{$scale}"
  end
  text += ', journal: ' + ( $write_journal  ?  ' on' : 'off' )
  truncate_colored_text(text, $term_width - 2 ) + "\e[K"
end


def regular_hole? hole
  hole && hole != :low && hole != :high
end


def get_dots dots, delta, freq, low, middle, high
  hdots = (dots.length - 1)/2
  if freq > middle
    pos = hdots + ( hdots + 1 ) * (freq - middle) / (high - middle)
  else
    pos = hdots - ( hdots + 1 ) * (middle - freq) / (middle - low)
  end

  hit = ((hdots - delta  .. hdots + delta) === pos )
  dots[pos] = yield( hit, 'I') if pos > 0 && pos < dots.length
  return dots, hit
end
