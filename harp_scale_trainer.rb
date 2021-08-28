#!/usr/bin/ruby

require 'set'
require 'json'
#require 'byebug'

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

        Remark: Most arguments can be abreviated, e.g 'l' for 'listen'
          or 'cal' for 'calibrate'.


        Example to listen to your playing and show the note
        you played; green if it was from the scale:

          ./harp_scale_trainer.rb listen c ma



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


$mode = :listen if 'listen'.start_with?(ARGV[0])
$mode = :quiz if 'quiz'.start_with?(ARGV[0])
$mode = :calibrate if 'calibrate'.start_with?(ARGV[0])

if ![:listen, :quiz, :calibrate].include?($mode)
  err_h "First argument can be either 'listen', 'quiz' or 'calibrate', not '#{ARGV[0]}'"
end

if $mode == :listen
  if ARGV.length == 3
    arg_for_key = ARGV[1]
    arg_for_scale = ARGV[2]
  else
    err_h "Need exactly two additional arguments for mode listen"
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
  

def get_hole issue, hint = nil, hint_count = 0

  samples = Array.new
  if issue
    puts
    puts issue
    sleep 1
  end

  count = 0
  system('clear')
  $term_height, $term_width = %x(stty size).split.map(&:to_i)
  err_b "Terminal is too small: [width, height] = #{[$term_width,$term_height].inspect} < [100,28]" if $term_width < 100 || $term_height < 30
    
  pad = '           '
  while true do
    # See  https://en.wikipedia.org/wiki/ANSI_escape_code
    # home, hide cursor, down
    print "\033[H\033[?25l\033[5H"
    
    tn = Time.now.to_i

    # get and filter new samples
    system("arecord -D pulse -r 48000 -s 24000 #{$sample_file} >/dev/null 2>&1") or fail 'arecord failed'
    # when changing argument to '--pitch' below, $freq needs to be adjusted
    new_samples = %x(aubiopitch --pitch mcomb #{$sample_file} 2>/dev/null).lines.
                    map {|l| f = l.split; [f[0].to_f + tn, f[1].to_i]}.
                    select {|f| f[1]>0}

    # curate our pool of samples
    samples += new_samples
    samples = samples[-16 .. -1] if samples.length > 16
    samples.shift while samples.length > 0 && tn - samples[0][0] > 5

    hole = '-'
    extra = nil
    if samples.length > 8
      # each peak has structure [frequency in hertz, count]
      pks = get_two_peaks samples.map {|x| x[1]}.sort, 10
      pk = pks[0]

      good = done = false
      
      extra = "Frequency: #{pk[0]}"
      if pk[1] > 8
        hole, lbor, ubor = describe_freq pk[0]
        good, done = yield(hole)
        extra += ", in range [#{lbor},#{ubor}]" if lbor
      else
        extra += ', count below threshold'
      end
      extra += "\nPeaks: #{pks.inspect}"
    end
    fout = %x(figlet -f mono12 -c " #{hole}")
    puts "\033[#{good ? 32 : 31}m" unless hole == '-'
    puts_pad fout
    puts "\033[0m" unless hole == '-'
    # row 20
    puts "\033[20H"
    puts_pad "Samples total: #{samples.length}, new: #{new_samples.length}#{pad}"
    puts_pad extra || ''
    count += 1
    if done
      print "\033[?25h"
      return hole
    end
    puts "\033[25H"
    puts_pad issue
    puts_pad (hint && count > hint_count) ? hint : ''
  end
end


def puts_pad text
  text.lines.each do |line|
    puts line.chomp.ljust($term_width - 2) + "\n"
  end
end


def do_quiz
  loop do
    wanted = $scale_holes.sample($num_quiz)
    puts "Playing #{$num_quiz} note(s) from the scale; listen carefully ..."
    sleep 0.3
    wanted.each do |hole|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      system("paplay #{file} >/dev/null 2>&1") or fail 'paplay failed'
      sleep 0.1
    end

    puts "Now please play them back ..."
    sleep 1
    wanted.each_with_index do |want,idx|
      get_hole($num_quiz == 1 ?
                 "Play note number \033[31m#{idx+1}\033[0m from sequence you heard" :
                 "Play the note you heard",
               "Hint: play \033[32m#{want}\033[0m or hit ctrl-c to stop", 4) {|played| [played == want, played == want]}
    end
    puts "\n\n\033[32mGreat, that worked out !\033[0m"
    puts "\nAgain"
    sleep 0.2
  end
end


def do_listen
  puts "Just go ahead and play notes from the scale ..."
  sleep 0.3
  get_hole("Please play any note from the scale !\nctrl-c to stop") {|played, count| [$scale_holes.include?(played), false, nil]}
end


def do_calibrate
  puts "\nThis is an interactive assistant, that will ask you to play these"
  puts "holes of your harmonica one after the other, each for one second:"
  puts "\n  #{$holes.join(' ')}"
  puts "\nAfter each whole the recorded sound will be replayed for confirmation."
  puts "\nEach recording is preceded by a short countdown (2,1); the recording starts,"
  puts "when the word 'recording to ...' is printed; when done, the word 'done'."
  puts "To avoid silence in the recording, you should start playing"
  puts "within the countdown already."
  puts "\nBackground: Those samples will be used to determine the frequencies of your"
  puts "particular harp; so this should be the one, you will use for practice later."
  puts "Moreover those samples will be played in mode 'quiz'."
  puts "\nPress RETURN to start:"
  puts "(first hole will be  \033[32m#{$holes[0]}\033[0m)"
  STDIN.gets

  hole2freq = Hash.new
  freq = 0
  ($holes + ['end']).each_cons(2) do |hole, next_hole|
    freq = record_hole(hole, freq, next_hole)
    hole2freq[hole] = freq
  end
  File.write("#{$sample_dir}/frequencies.json", JSON.pretty_generate(hole2freq))
  puts "All recordings done:"
  system("ls -lrt #{$sample_dir}")
end


def read_answer answer2keys_desc
  puts 'A single key answer is expected:'
  klists = Hash.new
  default = nil
  answer2keys_desc.each do |an, ks_d|
    klists[an] = ks_d[0].reject {|k| k == :default}.join(', ')
  end
  maxlen = klists.map {|k,v| v.length}.max
  answer2keys_desc.each do |an, ks_d|
    puts "  %*s :  %s" % [maxlen, klists[an], ks_d[1]]
  end

  begin
    print "Your choice: "
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
    answer = default = nil
    answer2keys_desc.each do |an, ks_d|
      answer = an if ks_d[0].include?(char)
    end
    answer ||= default
    puts "Invalid key: '#{char}' (#{char.ord})" unless answer
  end while !answer
  answer
end


def record_hole hole, prev_freq, next_hole

  begin
    puts "\nRecording hole  \033[32m#{hole}\033[0m  after countdown reaches 1"
    [2,1].each do |c|
      puts c
      sleep 1
    end

    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"

    puts "\033[31mrecording\033[0m to #{file} ..."
    system("arecord -D pulse -r 48000 -d 1 #{file} >/dev/null 2>&1")
    puts "\033[32mdone\033[0m"

    samples = %x(aubiopitch --pitch mcomb #{file} 2>/dev/null).lines.
                map {|l| l.split[1].to_i}.
                select {|f| f>0}.
                sort
    pks = get_two_peaks samples, 10
    puts "Peaks: #{pks.inspect}"
    freq = pks[0][0]
    
    sleep 1
    puts "\nreplay ..."
    system("paplay #{file} >/dev/null 2>&1") or fail 'paplay failed'
    puts "done"

    if freq < prev_freq
      puts "The frequency just recorded #{freq} is LOWER than the frequency recorded before #{prev_freq} !"
      puts "Therefore this recording cannot be accepted and you need to redo !"
      puts "\nIf however you feel, that the error is in the PREVIOUS recording already,"
      puts "you need to REDO IT ALL, and should bail out by pressing ctrl-C to start over ..."
    else
      puts "(next hole will be  \033[32m#{next_hole}\033[0m)"
    end
    begin
      puts "Whats next ?"
      if freq < prev_freq
        answer = read_answer({:play => [['p', 'SPACE'], 'play recorded sound'],
                              :redo => [['r', :default], 'redo recording (default)'],
                              :exit => [['x'], 'exit so you may to start over']})
      else
        answer = read_answer({:play => [['p', 'SPACE'], 'play recorded sound'],
                             :okay => [['RETURN'], 'Okay and continue'],
                             :redo => [['r', :default], 'redo recording (default)']})
      end
      case answer
      when :play
        puts "\nplay ..."
        system("paplay #{file} >/dev/null 2>&1") or fail 'paplay failed'
        puts "done"
      when :exit
        exit 1
      end
    end while answer == :play
  end while answer != :okay
  return freq
end


#
# Early initialization
#

$key = :c
$sample_dir = "samples/key_of_#{$key}"
$sample_file = "#{$sample_dir}/sample.wav"

# we never invoke it directly, so check
system('which toilet >/dev/null 2>&1') or err_b "Program 'toilet' is needed (for its extra figlet-fonts) but not installed"
# show cursor
at_exit { print "\033[?25h\033[25H" }


#
# Some sanity checks
#

if !File.exist?(File.basename($0))
  err_b "Please invoke this program from within its directory (cannot find #{File.basename($0)} in current dir)"
end
Dir.mkdir('samples') unless File.directory?('samples')
Dir.mkdir($sample_dir) unless File.directory?($sample_dir)

  
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
  err_b "Frequency file #{ffile} does not exist, you need to calibrate" unless File.exist?(ffile)
  freqs = JSON.parse(File.read(ffile))
  err_b "Holes in #{ffile} #{freqs.keys.join(' ')} do not match those expected for scale #{$scale} #{$harp.keys.join(' ')}; maybe you need to redo the calibration" unless Set.new(freqs.keys) == Set.new($holes)
  freqs.map {|k,v| $harp[k][:freq] = v}
  $holes.each {|h| file = "#{$sample_dir}/#{$harp[h][:note]}.wav"; err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)}

  $fr2ho = $holes.map {|h| [$harp[h][:freq], h]}.to_h
  $freqs = $holes.map {|h| $harp[h][:freq]}.sort
end

case $mode
when :quiz
  do_quiz
when :listen
  do_listen
when :calibrate
  do_calibrate
end
