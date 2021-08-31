#!/usr/bin/ruby

require 'set'
require 'json'
require 'fileutils'

## some useful debug code in this program is commented out with two hashes
require 'byebug'

#
# Argument processing
#

$usage = <<EOU

Hint: Before first regular use you need to calibrate this program 
      with your own harp.

Usage: 

        Remark: The last one or two arguments in all examples below
          are the key of the harp (e.g. c or a) and the scale,
          e.g. blues or mape (for major pentatonic), respectively.

        Remark: Most arguments can be abreviated, e.g 'l' for 'learn'
          or 'cal' for 'calibrate'.


        Example to listen to your playing and show the note
        you played; green if it was from the scale:

          ./harp_scale_trainer.rb learn c ma



        Example to play 3 (e.g.) notes from the scale and quiz you to
        play them back (then repeat):

          ./harp_scale_trainer.rb quiz 3 a blues



        Once in a lifetime of your c-harp you may want to calibrate
        this prgoram to the frequencies of your harp:

          ./harp_scale_trainer.rb calibrate c
          
        this will ask you to play notes on your harp. The samples will
        be stored in folder samples (will be reused for quiz) and
        frequencies will be extracted to file frequencies.json .
        This command does not need a scale-argument.

Hint: Maybe you need to scroll up to read this USAGE INFORMATION full.
      
EOU

def err_h text
  puts "ERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  exit 1
end

def err_b text
  puts "ERROR: #{text} !"
  exit 1
end

if ARGV.length == 0
  puts $usage
  exit 1
end


$mode = :learn if 'learn'.start_with?(ARGV[0])
$mode = :quiz if 'quiz'.start_with?(ARGV[0])
$mode = :calibrate if 'calibrate'.start_with?(ARGV[0])

if ![:learn, :quiz, :calibrate].include?($mode)
  err_h "First argument can be either 'learn', 'quiz' or 'calibrate', not '#{ARGV[0]}'"
end

if $mode == :learn
  if ARGV.length == 3
    arg_for_key = ARGV[1]
    arg_for_scale = ARGV[2]
  else
    err_h "Need exactly two additional arguments for mode learn"
  end
end
  
if $mode == :quiz
  if ARGV.length == 4
    arg_for_key = ARGV[2]
    arg_for_scale = ARGV[3]
  else
    err_h "Need exactly three additional argument for mode 'quiz'"
  end
  $num_quiz = ARGV[1].to_i
  if $num_quiz.to_s != ARGV[1] || $num_quiz < 1
    err_h "Argument after mode 'q' must be a number starting at 1, not '#{ARGV[1]}'"
  end
end

if $mode == :calibrate
  if ARGV.length == 2
    arg_for_key = ARGV[1]
    arg_for_scale = nil
  else
    err_h "Need exactly one additional argument (the key) for mode 'calibrate'"
  end
end
  
if arg_for_key
  allowed_keys = %w(a c)
  err_b "Key can only be one on #{allowed_keys.inspect}, not '#{arg_for_key}'" if !allowed_keys.include?(arg_for_key)
  $key = arg_for_key.to_sym
end

if arg_for_scale
  allowed_scales = %w(blues mape)
  $scale = allowed_scales.select do |scale|
    scale.start_with?(arg_for_scale)
  end.tap do |matches|
    err_b "Given scale '#{arg_for_scale}' matches none or multiple of #{allowed_scales.inspect}" if matches.length != 1
  end.first.to_sym
end


#
# Needed functions
#

def find_best_bin data, width
  len = data.length - 1
  idx_for_max = 0
  count_max = 0
  for idx in 0 .. len do
    count = 1
    while idx + count <= len
      break if (data[idx + count] - data[idx]).abs > width
      count += 1
    end
    if count > count_max
      idx_for_max = idx
      count_max = count
    end
  end
  return idx_for_max, count_max
end


def find_best_bin_bidi data, width
  # try data forward and backward
  ifw, cfw = find_best_bin data, width
  ibw, cbw = find_best_bin data.reverse, width
  if cfw >= cbw
    return ifw, cfw
  else
    return data.length - ibw - cbw, cbw
  end
end


def get_two_peaks data, width

  # find maximum
  idx_m, cnt_m = find_best_bin_bidi(data, width)
  sum_m = data[idx_m, cnt_m].sum

  # investigate left and right of max
  data_l = data[0, idx_m]
  data_r = data[idx_m + cnt_m .. -1]
  
  idx_l, cnt_l = find_best_bin_bidi(data_l, width)
  sum_l = data_l[idx_l .. idx_l + cnt_l - 1].sum

  idx_r, cnt_r = find_best_bin_bidi(data_r, width)
  sum_r = data_r[idx_r .. idx_r + cnt_r - 1].sum

  # maximum peak and higher of left or right peak
  pks = [divide(sum_m, cnt_m),
         if cnt_l > cnt_r
           divide(sum_l, cnt_l)
         else
           divide(sum_r, cnt_r)
         end]

  # use second peak if frequency of first is too low
  if pks[0][0] < 200 && pks[1][0] > 200 && pks[1][1] > 4
    pks.reverse!
  end

  return pks
end


def divide sum, cnt
  if cnt == 0
    [0, 0]
  else
    [(sum.to_f/cnt).to_i, cnt]
  end
end


def describe_freq freq
  fr_prev = -1
  $freqs.each_cons(3) do |pfr, fr, nfr|
    lbor = (pfr+fr)/2
    ubor = (fr+nfr)/2
    higher_than_prev = (freq >= lbor)
    lower_than_next = (freq < ubor)
    return $fr2ho[fr],lbor,ubor if higher_than_prev and lower_than_next
    return $fr2ho[$freqs[0]] if lower_than_next
  end
  return $fr2ho[$freqs[-1]]
end
  

def get_hole issue, lambda_good_done, lambda_skip, lambda_comment, lambda_hint

  samples = Array.new
  system('clear')
  # See  https://en.wikipedia.org/wiki/ANSI_escape_code
  print "\e[?25l"  # hide cursor
  $move_down_on_exit = true

  print issue

  tstart = Time.now.to_f
  hole = '-'
  while true do   
    tnow = Time.now.to_f

    print "\e[#{$line_comment}H"
    lambda_comment.call if lambda_comment
    print "\e[H\e[1H"
    
    # Get and filter new samples
    # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
    begin
      tstart_record = Time.now.to_f
      system("arecord -D pulse -r 48000 -s 9600 #{$sample_file} >/dev/null 2>&1") or $ctl_paused or fail 'arecord failed'
    end while Time.now.to_f - tstart_record < 0.05
    $ctl_paused = false
    new_samples = %x(aubiopitch --pitch mcomb #{$sample_file} 2>/dev/null).lines.
                    map {|l| f = l.split; [f[0].to_f + tnow, f[1].to_i]}.
                    select {|f| f[1]>0}
    # curate our pool of samples
    samples += new_samples
    samples = samples[-16 .. -1] if samples.length > 16
    samples.shift while samples.length > 0 && tnow - samples[0][0] > 2
    hole_was = hole
    hole = '-'
    extra = ''
## Input simulation for taking Screenshots
##    if Time.now.to_f - tstart > 0.5
##      samples = (1..78).to_a.map {|x| [tnow + x/100.0, 797]}
##      new_samples = samples[0, 20]
##    end
    return if lambda_skip && lambda_skip.call()
    if samples.length > 8
      # each peak has structure [frequency in hertz, count]
      pks = get_two_peaks samples.map {|x| x[1]}.sort, 10
      pk = pks[0]

      good = done = false
      
      extra = "Frequency: #{pk[0]}"
      if pk[1] > 8
        hole, lbor, ubor = describe_freq pk[0]
        hole_since = Time.now.to_f if hole != hole_was
        good, done = lambda_good_done.call(hole, hole_since)
## Override decision for taking Screenshots
##        good = true
##        done = true if Time.now.to_f - tstart > 2        
        extra += " in range [#{lbor},#{ubor}], Note \e[0m#{$harp[hole][:note]}\e[2m" if lbor
      else
        extra += ' but count below threshold'
      end
      extra += "\nPeaks: #{pks.inspect}"
    end
    figlet_out = %x(figlet -f mono12 -c " #{hole}")
    # See  https://en.wikipedia.org/wiki/ANSI_escape_code
    print "\e[#{$line_note}H"
    if hole == '-'
      print "\e[2m"
    else
      print "\e[#{good ? 32 : 31}m"
    end
    puts_pad figlet_out
    print "\e[#{$line_samples}H"
    puts_pad "\e[0m\e[2mSamples total: #{samples.length}, new: #{new_samples.length}"
    puts_pad extra
    print "\e[0m"
    if done
      print "\e[?25h"  # show cursor
      print "\e[#{$line_comment}H"
      $move_down_on_exit = false
      return hole
    end
    print "\e[#{$line_hint}H"
    lambda_hint.call(tstart) if lambda_hint
  end
end


def puts_pad text
  text.lines.each do |line|
    puts line.chomp.ljust($term_width - 2) + "\n"
  end
end


def install_ctl
  Signal.trap('SIGQUIT') do
    system("stty quit '^\'")
    print "\e[s"
    text = $ctl_can_skip ? "SPACE to continue, TAB to skip" : "SPACE to continue"
    print "\e[1;#{$term_width-text.length-1}H#{text}"
    system("stty raw -echo")
    begin
      key = STDIN.getc
    end until key == " " || ( key == "\t" && $ctl_can_skip )
    system("stty -raw")
    system("stty quit ' '")
    print "\e[1;#{$term_width-text.length-1}H#{' ' * text.length}"
    print "\e[u"
    $ctl_paused = true
    $ctl_skip = ( key == "\t" )
  end
  system("stty quit ' '")
  $ctl_pause_continue = "\e[2m[type SPACE to pause]\e[0m"
end


def do_quiz
  system("stty -echo")
  install_ctl
  puts "\n\nLooping: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  puts $ctl_pause_continue
  [2,1].each do |c|
    puts c
    sleep 1
  end
  
  loop do
    all_wanted = $scale_holes.sample($num_quiz)
    sleep 0.3
    print ' '.ljust($term_width - 2)
    print "\r"
    all_wanted.each do |hole|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      print "listen ... "
      system("aplay -D pulse #{file} >/dev/null 2>&1") or $ctl_paused or fail 'aplay failed'
      $ctl_paused = false
    end

    print "\e[32mand !\e[0m"
    sleep 0.5

    $ctl_can_skip = true
    all_wanted.each_with_index do |wanted,idx|
      tstart = Time.now.to_f
      get_hole(
        if $num_quiz == 1 
          "Play the note you have heard !"
        else
          "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
        end + '    ' + $ctl_pause_continue,
        -> (played, since ) {[played == wanted,
                              played == wanted &&
                              Time.now.to_f - since > 0.5]}, # do not return okay immediately
        -> () {$ctl_skip},
        -> () do
          if idx < all_wanted.length
            if all_wanted.length == 1
              text = '.  .  .'
            else
              text = 'Yes  ' + '*' * idx + '-' * (all_wanted.length - idx)
            end
            print "\e[2m"
            system("figlet -c -k -f smblock \"#{text}\"")
            print "\e[0m"
            print "\e[#{$line_comment2}H"
            print "... and on ..."
          end
        end,
        -> (tstart) do
          if Time.now.to_f - tstart > 3
            print "Hint: play \e[32m#{wanted}\e[0m (#{$harp[wanted][:note]}) \e[2mor type ctrl-c to stop or SPACE for options\e[0m"
          end
        end)
    end
    if $ctl_skip
      print "\e[#{$line_comment2}H"
      puts_pad "... skipping ..."
      $ctl_skip = false
      sleep 1
      next
    end
    print "\e[#{$line_comment}H"
    figlet_out = %x(figlet -c -f smblock Great !)
    print "\e[32m"
    puts_pad figlet_out
    print "\e[0m"
    print "\e[#{$line_comment2}H"
    puts_pad "... and \e[32magain\e[0m !"
    puts
    sleep 1
  end
end


def do_learn
  system("stty -echo")
  install_ctl
  $ctl_can_skip = false
  puts "\n\nJust go ahead and play notes from the scale ..."
  puts $ctl_pause_continue
  [2,1].each do |c|
    puts c
    sleep 1
  end
  get_hole("Play any note from the scale to get \e[32mgreen\e[0m ...        #{$ctl_pause_continue}",
           -> (played, _) {[$scale_holes.include?(played),
                            false]},
           nil,
           nil,
           -> (_) do
             print "Hint: \e[2mchosen scale '#{$scale}' has these holes: #{$scale_holes.join(' ')}\e[0m"
          end
)
end


def do_calibrate
  puts "\n\nThis is an interactive assistant, that will ask you to play these"
  puts "holes of your harmonica one after the other, each for one second:"
  puts "\n  \e[32m#{$holes.join(' ')}\e[0m"
  puts "\nEach recording is preceded by a short countdown (2,1)."
  puts "To avoid silence in the recording, you should start playing within the"
  puts "countdown already and play a moment over the end of the recording."
  puts "The harp you use now for calbration should be the one,"
  puts "that you will use for your practice later."
  puts "\nBackground: Those samples will be used to determine the frequencies of your"
  puts "particular harp and will be played directly in mode 'quiz'."
  puts "\nHint: If you plan to calibrate for more than one key of harp, you should"
  puts "consider copying the whole directory below 'samples' and record only those notes"
  puts "that are missing. Note, that the recorded samples are named after the note,"
  puts "not the hole, so that they can be copied and used universally."
  puts "\nTip: You may invoke this assistant again at any later time, just to review your"
  puts "recorded notes and maybe correct some of them."
  print "\n\nPress RETURN to start the step-by-step process ... "
  STDIN.gets
  puts

  hole2freq = Hash.new
  freqs = Array.new
  i = 0
  begin
    hole = $holes[i]
    freqs[i] = record_hole(hole, freqs[i-1] || 0)
    if freqs[i] < 0
      if i >0 
        puts "Skipping  \e[32mback\e[0m  !"
        i -= 1
      else
        puts "Cannot skip, back already at first hole ..."
      end
    else
      hole2freq[hole] = freqs[i]
      i += 1
    end
  end while i <= $holes.length - 1
  File.write("#{$sample_dir}/frequencies.json", JSON.pretty_generate(hole2freq))
  puts "All recordings done:"
  system("ls -lrt #{$sample_dir}")
end


def read_answer answer2keys_desc
  klists = Hash.new
  answer2keys_desc.each do |an, ks_d|
    klists[an] = ks_d[0].join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  answer2keys_desc.each do |an, ks_d|
    puts "  %*s :  %s" % [maxlen, klists[an], ks_d[1]]
  end

  begin
    print "Your choice (press a single key): "
    system("stty raw -echo")
    char = STDIN.getc
    system("stty -raw echo")
    char = case char
           when "\r"
             'RETURN'
           when ' '
             'SPACE'
           else
             char
           end
    if char.ord == 3
      puts "ctrl-c; aborting ..."
      exit 1
    end
    puts char
    puts
    answer = nil
    answer2keys_desc.each do |an, ks_d|
      answer = an if ks_d[0].include?(char)
    end
    puts "Invalid key: '#{char}' (#{char.ord})" unless answer
  end while !answer
  answer
end


def record_hole hole, prev_freq

  redo_recording = false
  begin
    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
    if File.exists?(file) && !redo_recording
      puts "\nHole  \e[32m#{hole}\e[0m  need not be recorded, because file #{file} already exists."
      print "\nPress RETURN to see choices: "
      STDIN.gets
      print "Analysis of old: "
    else
      puts "\nRecording hole  \e[32m#{hole}\e[0m  after countdown reaches 1,"
      print "\nPress RETURN to start recording: "
      STDIN.gets
      [2,1].each do |c|
        puts c
        sleep 1
      end
      
      puts "\e[31mrecording\e[0m to #{file} ..."
      # Discard if too many stale samples (which we recognize, because they are delivered faster than expected)
      begin
        tstart_record = Time.now.to_f
        system("arecord -D pulse -r 48000 -s 9600 #{$sample_file} >/dev/null 2>&1") or fail 'arecord failed'
      end while Time.now.to_f - tstart_record < 0.05

      system("arecord -D pulse -r 48000 -d 1 #{file}")
      puts "\e[32mdone\e[0m"
      print "Analysis: "
    end

    samples = %x(aubiopitch --pitch mcomb #{file} 2>&1).lines.
                map {|l| l.split[1].to_i}.
                select {|f| f>0}.
                sort
    pks = get_two_peaks samples, 10
    puts "Peaks: #{pks.inspect}"
    freq = pks[0][0]
    
    if freq < prev_freq
      puts "\nThe frequency just recorded (= #{freq}) is \e[32mLOWER\e[0m than the frequency recorded before (= #{prev_freq}) !"
      puts "Therefore this recording cannot be accepted and you need to redo !"
      puts "\nIf however you feel, that the error is in the PREVIOUS recording already,"
      puts "you may want to skip back to the previous hole ...\n\n"
    end
    begin
      puts "\nWhats next for hole \e[33m#{hole}\e[0m ?"
      choices = {:play => [['p', 'SPACE'], 'play recorded sound'],
                 :redo => [['r'], 'redo recording'],
                 :back => [['b'], 'skip back to previous hole']}
      if freq < prev_freq
        answer = read_answer(choices)
      else
        choices[:okay] = [['k', 'RETURN'], 'keep recording and continue']
        answer = read_answer(choices)
      end
      case answer
      when :play
        print "\nplay ... "
        system("aplay -D pulse #{file} >/dev/null 2>&1") or fail 'aplay failed'
        puts "done\n"
      when :redo
        redo_recording = true
      when :back
        return -1
      end
    end while answer == :play
  end while answer != :okay
  return freq
end


#
# Early initialization
#

$key = :c
$sample_dir = "samples/diatonic/key_of_#{$key}"
$sample_file = "#{$sample_dir}/sample.wav"

# we never invoke it directly, so check
system('which toilet >/dev/null 2>&1') or err_b "Program 'toilet' is needed (for its extra figlet-fonts) but not installed"
# show cursor
$move_down_on_exit = false
Signal.trap('SIGINT') do
  print "\e[?25h\e[#{$line_hint}H" if $move_down_on_exit
  puts "\nexit on ctrl-c"
  exit 1
end
at_exit do
  print "\e[?25h\e[#{$line_hint}H" if $move_down_on_exit
  system("stty sane")
end
$line_note = 5
$line_samples = 16
$line_comment = 22
$line_comment2 = 28
$line_hint = 30
STDOUT.sync = true
$term_height, $term_width = %x(stty size).split.map(&:to_i)
err_b "Terminal is too small: [width, height] = #{[$term_width,$term_height].inspect} < [94,28]" if $term_width < 84 || $term_height < 32
  

#
# Some sanity checks
#

if !File.exist?(File.basename($0))
  err_b "Please invoke this program from within its directory (cannot find #{File.basename($0)} in current dir)"
end
FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)

  
#
# Initialization from files
#
  
# The frequencies are sensitive to argument '--pitch' for aubioptch below
# Frequency calues will later be overwritten from frequencies.json in sample_dir
harps = {a: { 'low' => {note: 'low'},
              '+1' => {note: 'a3'},
              '-1' => {note: 'b3'},
              '+2' => {note: 'cs4'},
              '-2+3' => {note: 'e4'},
              '-3//' => {note: 'gf4'},
              '-3/' => {note: 'g4'},
              '-3' => {note: 'gs4'},
              '+4' => {note: 'a4'},
              '-4/' => {note: 'bf4'},
              '-4' => {note: 'b4'},
              '+5' => {note: 'cs5'},
              '-5' => {note: 'd5'},
              '+6' => {note: 'e5'},
              '-6' => {note: 'fs5'},
              '-7' => {note: 'gs6'},
              '+7' => {note: 'a5'},
              '-8' => {note: 'b5'},
              '+8' => {note: 'cs6'},
              '-9' => {note: 'd6'},
              '+9' => {note: 'e6'},
              '-10' => {note: 'fs6'},
              '+10' => {note: 'a6'},
              'high' => {note: 'high'}},
         c: { 'low' => {note: 'low'},
              '+1' => {note: 'c4'},
              '-1' => {note: 'd4'},
              '+2' => {note: 'e4'},
              '-2+3' => {note: 'g4'},
              '-3//' => {note: 'a4'},
              '-3/' => {note: 'bf4'},
              '-3' => {note: 'b4'},
              '+4' => {note: 'c5'},
              '-4/' => {note: 'df5'},
              '-4' => {note: 'd5'},
              '+5' => {note: 'e5'},
              '-5' => {note: 'f5'},
              '+6' => {note: 'g5'},
              '-6' => {note: 'a5'},
              '-7' => {note: 'b5'},
              '+7' => {note: 'c6'},
              '-8' => {note: 'd6'},
              '+8' => {note: 'e6'},
              '-9' => {note: 'f6'},
              '+9' => {note: 'g6'},
              '-10' => {note: 'a6'},
              '+10' => {note: 'c7'},
              'high' => {note: 'high'}}}

fail "Internal error, not all harps have the same list of holes" unless Set.new(harps.values.map {|v| v.keys}).length == 1
$harp = harps[$key] or fail "Internal error, key #{$key} has no harp"
scales_holes = {mape: %w( -2+3 -3// -3 -4 +5 +6 -6 -7 -8 +8 +9 ),
                blues: %w( -2+3 -3/ +4 -4/ -4 -5 +6 )}
scales_holes.each {|scale,holes| fail "Internal error: Holes of scale #{scale} #{holes.inspect} is not a subset of holes of harp #{$harp.keys.inspect}" unless Set.new(holes).subset?(Set.new($harp.keys))}
$scale_holes = scales_holes[$scale]
$holes = $harp.keys.reject {|x| %w(low high).include?(x)}

unless $mode == :calibrate
  ffile = "#{$sample_dir}/frequencies.json"
  err_b "Frequency file #{ffile} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?(ffile)
  freqs = JSON.parse(File.read(ffile))
  err_b "Holes in #{ffile} #{freqs.keys.join(' ')} do not match those expected for scale #{$scale} #{$harp.keys.join(' ')}; maybe you need to redo the calibration" unless Set.new(freqs.keys) == Set.new($holes)
  freqs.map {|k,v| $harp[k][:freq] = v}
  $harp['low'][:freq] = $harp['+1'][:freq]/2
  $harp['high'][:freq] = $harp['+10'][:freq]*2
  $holes.each {|h| file = "#{$sample_dir}/#{$harp[h][:note]}.wav"; err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)}

  $fr2ho = $holes.map {|h| [$harp[h][:freq], h]}.to_h
  $freqs = (%w(low high).map {|x| $harp[x][:freq]} + $holes.map {|h| $harp[h][:freq]}).sort
end

case $mode
when :quiz
  do_quiz
when :learn
  do_learn
when :calibrate
  do_calibrate
end
