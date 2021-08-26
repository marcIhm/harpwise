#!/usr/bin/ruby

require 'set'


#
# Argument processing
#

$usage = <<EOU

Hint: Before first regular use you need to calibrate this program 
      with your own harp.

Usage: 

        Remark: The last one or two arguments in all examples below
          are the key of the harp (e.g. c or a) and the scale,
          e.g. blues or major_pentatonic, respectively.

        Remark: Most arguments can be abreviated, e.g 'l' for 'listen'
          or 'ma' for 'major_pentatonic'.


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
        frequencies will be extracted to file frequencies.yaml.
        This command does not need a scale-argument.

Hint: Maybe you need to scroll up to read this USAGE INFORMATION full.
      
EOU

def err_u text
  exit 1
end

def err_h text
  puts "\nERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  exit 1
end

def err_b text
  puts "\nERROR: #{text} !"
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
    err_h "Need exactly one additional argument for mode 'calibrate'"
  end
end
  
if arg_for_key
  allowed_keys = %w(a c)
  err "Key can only be one on #{allowed_keys.inspect}, not '#{arg_for_key}'" if !allowed_keys.include?(arg_for_key)
  $key = arg_for_key.to_sym
end

if arg_for_scale
  allowed_scales = %w(blues major_pentatonic)
  $scale = allowed_scales.select do |scale|
    scale.start_with?(arg_for_scale)
  end.tap do |matches|
    err "Given scale '#{arg_for_scale}' matches none or multiple of #{allowed_scales.inspect}" if matches.length != 1
  end.first.to_sym
end

puts $scale,$key
exit
  
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
  return [[(sum_m.to_f/cnt_m).to_i, cnt_m],
          if cnt_l > cnt_r
            [(sum_l.to_f/cnt_l).to_i, cnt_l]
          else
            if cnt_r == 0
              [0, 0]
            else
              [(sum_r.to_f/cnt_r).to_i, cnt_r]
            end
          end]
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
  

def get_note issue

  sfile = 'samples.wav'
  arc = "arecord -D pulse -s 4096 #{sfile}"
  samples = Array.new
  if issue
    puts
    puts issue
    sleep 1
  end

  while true do
    tn = Time.now.to_i

    # get and filter new samples
    system("#{arc} >/dev/null 2>&1") or fail 'arecord failed'
    # when changing argument to '--pitch' below, $freq needs to be adjusted
    new_samples = %x(aubiopitch --pitch mcomb samples.wav).lines.
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
      if pks[0][0] < 200 && pks[1][0] > 200 && pks[1][1] > 4
        pk = pks[1]
      else
        pk = pks[0]
      end

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
    system("figlet -f mono12 -c \" #{hole}\"")
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
  get_note("Please play #{wanted}") {|played| [played == wanted, played == wanted]}
end


def do_listen
  get_note("Please play any note from the scale !\nctrl-c to stop") {|played| [$scale.include?(played), false]}
end


def do_calibrate
end


#
# Early initialization
#

$key = :c
$sample_dir = "samples/key_of_#{key}"


#
# Some sanity checks
#

if !File.exist?(File.basename($0))
  err_b "Please invoke this program from within its directory (cannot find #{File.basename($0)} in current dir)"
end
Dir.mkdir('samples') unless File.dir('samples')
Dir.mkdir($sample_dir) unless File.dir($sample_dir)

  
#
# Initialization from files
#
  
# The frequencies are sensitive to argument '--pitch' for aubioptch below
# Frequency calues will later be overwritten from frequencies.yaml in sample_dir
$nota = { 'low' => {freq: 100, hole: 'low'},
          'c4' => {freq: 248, hole: '+1'},
          'd4' => {freq: 279, hole: '-1'},
          'e4' => {freq: 311, hole: '+2'},
          'g4' => {freq: 373, hole: '-2 +3'},
          'gb4' => {freq: 408, hole: '-3//'},
          'b4' => {freq: 468, hole: '-3'},
          'c5' => {freq: 500, hole: '+4'},
          'd5' => {freq: 561, hole: '-4'},
          'e5' => {freq: 628, hole: '+5'},
          'f5' => {freq: 663, hole: '-5'},
          'g5' => {freq: 753, hole: '+6'},
          'a5' => {freq: 844, hole: '-6'},
          'b5' => {freq: 944, hole: '-7'},
          'c6' => {freq: 1003, hole: '+7'},
          'd6' => {freq: 1124, hole: '-8'},
          'e6' => {freq: 1260, hole: '+8'},
          'f6' => {freq: 1330, hole: '-9'},
          'g6' => {freq: 1505, hole: '+9'},
          'a6' => {freq: 1694, hole: '-10'},
          'c7' => {freq: 2019, hole: '+10'},
        'high' => {freq: 10000, hole: 'high'}}

$freqs = ($nota.values.map {|v| v[:freq]}).sort
$scale = %w( g4 gb4 b4 d5 e5 g5 a5 b5 d6 e6 g6 )
fail 'Internal error' unless Set.new($scale).subset?(Set.new($nota.keys))
$fr2ho = $nota.values.map {|v| [v[:freq], v[:hole]]}.to_h

case $mode
when :quiz
  do_quiz
when :listen
  do_listen
when :calibrate
  do_calibrate
end
