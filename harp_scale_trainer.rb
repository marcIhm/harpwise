#!/usr/bin/ruby

require 'set'
require 'json'
require 'fileutils'
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
  err "Key can only be one on #{allowed_keys.inspect}, not '#{arg_for_key}'" if !allowed_keys.include?(arg_for_key)
  $key = arg_for_key.to_sym
end

if arg_for_scale
  allowed_scales = %w(blues mape)
  $scale = allowed_scales.select do |scale|
    scale.start_with?(arg_for_scale)
  end.tap do |matches|
    err "Given scale '#{arg_for_scale}' matches none or multiple of #{allowed_scales.inspect}" if matches.length != 1
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
  for i in (1 .. $freqs.length - 2) do
    fr = $freqs[i]
    lbor = ($freqs[i-1]+fr)/2
    ubor = (fr+$freqs[i+1])/2
    higher_than_prev = (freq >= lbor)
    lower_than_next = (freq < ubor)
    return $fr2ho[fr],lbor,ubor if higher_than_prev and lower_than_next
    return $fr2ho[$freqs[0]] if lower_than_next
  end
  return $fr2ho[$freqs[-1]]
end
  

def get_hole issue

  samples = Array.new
  if issue
    puts
    puts issue
    sleep 1
  end

  while true do
    tn = Time.now.to_i

    # get and filter new samples
    FileUtils.rm $sample_file if File.exist?($sample_file)
    system("arecord -D pulse -s 4096 #{$sample_file} >/dev/null 2>&1") or fail 'arecord failed'
    # when changing argument to '--pitch' below, $freq needs to be adjusted
    new_samples = %x(aubiopitch --pitch mcomb #{$sample_file} 2>/dev/null).lines.
                    map {|l| f = l.split; [f[0].to_f + tn, f[1].to_i]}.
                    select {|f| f[1]>0}

    # curate our pool of samples
    samples += new_samples
    samples = samples[-32 .. -1] if samples.length > 32
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
    puts "\033[#{good ? 32 : 31}m"
    system("figlet -f mono12 -c \" #{hole}\"") or fail 'figlet failed'
    puts "\033[0m"
    puts "Samples total: #{samples.length}, new: #{new_samples.length}"
    puts extra if extra
    return hole if done
    if issue
      puts
      puts issue
    end
  end
end


def do_quiz
  wanted = $scale.sample
  get_hole("Please play #{wanted}") {|played| [played == wanted, played == wanted]}
end


def do_listen
  get_hole("Please play any note from the scale !\nctrl-c to stop") {|played| [$scale.include?(played), false]}
end


def do_calibrate
  holes = $harp.keys.reject {|x| %w(low high).include?(x)}
  puts "\nThis is an interactive assistant, that will ask you to play these"
  puts "holes of your harmonica one after the other, each for one second:"
  puts "\n  #{holes.join(' ')}"
  puts "\nAfter each whole the recorded sound will be replayed for confirmation."
  puts "\nEach recording is preceded by a short countdown (2,1); the recording starts,"
  puts "when the word 'recording to ...' is printed; when done, the word 'done'."
  puts "To avoid silence in the recording, you should start playing"
  puts "within the countdown already."
  puts "\nBackground: Those samples will be used to determine the frequencies of your"
  puts "particular harp; so this should be the one, you will use for practice later."
  puts "Moreover those samples will be played in mode 'quiz'."
  puts "\nPress RETURN to start:"
  puts "(first hole will be  \033[32m#{holes[0]}\033[0m)"
  STDIN.gets

  hole2freq = Hash.new
  freq = 0
  (holes + ['end']).each_cons(2) do |hole, next_hole|
    freq = record_hole(hole, freq, next_hole)
    hole2freq[hole] = freq
  end
  File.write("#{$sample_dir}/frequencies.json", JSON.pretty_generate(hole2freq))
  puts "All recordings done:"
  system("ls -lrt #{$sample_dir}")
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
    FileUtils.rm file if File.exist?(file)
    system("arecord -D pulse -d 2 #{file} >/dev/null 2>&1")
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
    system("aplay #{file} >/dev/null 2>&1") or fail 'aplay failed'
    puts "done"

    if freq < prev_freq
      puts "The frequency just recorded #{freq} is LOWER than the frequency recorded before #{prev_freq} !"
      puts "Therefore this recording cannot be accepted and you need to redo;"
      puts "if however you feel, that the error is in the PREVIOUS recording already,"
      puts "you need to redo it all, and should bail out by pressing ctrl-C to start over."
      puts "\nPress RETURN to redo or ctrl-c to abort"
      STDIN.gets
    else
      puts "Okay ? Empty input for Okay, everything else for redo:"
      puts "(next hole will be  \033[32m#{next_hole}\033[0m)"
      okay = ( STDIN.gets.chomp.length == 0 )
      if okay
        puts "Recording Okay, continue."
      else
        puts "Recording NOT Okay, please redo !"
      end
    end
  end while !okay

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
              '-3' => {note: 'gs4'},
              '-3/' => {note: 'g4'},
              '-3//' => {note: 'gf4'},
              '+4' => {note: 'a4'},
              '-4' => {note: 'b4'},
              '-4/' => {note: 'bf4'},
              '+5' => {note: 'cs5'},
              '-5' => {note: 'd5'},
              '+6' => {note: 'e5'},
              '-6' => {note: 'fs5'},
              '+7' => {note: 'a5'},
              '-7' => {note: 'gs6'},
              '+8' => {note: 'cs6'},
              '-8' => {note: 'b5'},
              '+9' => {note: 'e6'},
              '-9' => {note: 'd6'},
              '+10' => {note: 'a6'},
              '-10' => {note: 'fs6'},
              'high' => {note: 'high'}},
         c: { 'low' => {note: 'low'},
              '+1' => {note: 'c4'},
              '-1' => {note: 'd4'},
              '+2' => {note: 'e4'},
              '-2+3' => {note: 'g4'},
              '-3' => {note: 'b4'},
              '-3/' => {note: 'bf4'},
              '-3//' => {note: 'a4'},
              '+4' => {note: 'c5'},
              '-4' => {note: 'd5'},
              '-4/' => {note: 'df5'},
              '+5' => {note: 'e5'},
              '-5' => {note: 'f5'},
              '+6' => {note: 'g5'},
              '-6' => {note: 'a5'},
              '+7' => {note: 'c6'},
              '-7' => {note: 'b5'},
              '+8' => {note: 'e6'},
              '-8' => {note: 'd6'},
              '+9' => {note: 'g6'},
              '-9' => {note: 'f6'},
              '+10' => {note: 'c7'},
              '-10' => {note: 'a6'},
              'high' => {note: 'high'}}}

fail "Internal error, not all harps have the same set of holes" unless Set.new(harps.values.map {|v| Set.new(v.keys)}).length == 1
$harp = harps[$key] or fail "Internal error, key #{$key} has no harp"
scales_holes = {mape: %w( -2+3 -3// -3 -4 +5 +6 -6 -7 -8 +8 +9 ),
                blues: %w( -2+3 -3/ +4 -4/ -4 -5 +6 )}
scales_holes.each {|scale,holes| fail "Internal error: Holes of scale #{scale} #{holes.inspect} is not a subset of holes of harp #{$harp.keys.inspect}" unless Set.new(holes).subset?(Set.new($harp.keys))}
$scale_holes = scales_holes[$scale]

unless $mode == :calibrate
  ffile = "#{$sample_dir}/frequencies.json"
  err_b "Frequency file #{ffile} does not exist, you need to calibrate" unless File.exist?(ffile)
  freqs = JSON.parse(File.read(ffile))
  err_b "Holes in #{ffile} #{freqs.keys.join(' ')} do not match those expected for scale #{$scale} #{$harp.keys.join(' ')}; maybe you need to redo the calibration" unless Set.new(freqs.keys) == Set.new($harp.keys)
  freqs.map {|k,v| $harp[k][:freq] = v}
  $harp.keys.reject {|x| %w(low high).include?(x)}.each {|h| file = "#{$sample_dir}/#{$harp[h][:note]}.wav"; err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)}

  $fr2ho = $harp.values.map {|v| [v[:freq], v[:hole]]}.to_h
  $freqs = ($harp.values.map {|v| v[:freq]}).sort
end

case $mode
when :quiz
  do_quiz
when :listen
  do_listen
when :calibrate
  do_calibrate
end
