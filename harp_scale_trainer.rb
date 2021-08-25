#!/usr/bin/ruby

require 'byebug'

usage = <<EOU

Usage:

        Listen (i.e. l) to your playing and show the note
        you played; green if it was from the scale:

          ./harp_scale_trainer.rb l

        Play 3 (e.g.) notes from the scale and ask (i.e. a) you to
        play them back:

          ./harp_scale_trainer.rb a 3

EOU

if ARGV.length == 0
  puts 'ERROR: At least one argument required'
  puts usage
  exit 1
end

$mode = ARGV[0].to_sym
if $mode != :a && $mode != :l
  puts "ERROR: First argument can be either 'l' or 'a', not '#{$mode}'"
  puts usage
  exit 1
end

if $mode == :l && ARGV.length > 1
  puts "ERROR: No further argument allowed for mode 'l'"
  puts usage
  exit 1
end
  
if $mode == :a
  if ARGV.length != 2
    puts "ERROR: Need exactly one additional argument after mode 'a'"
    puts usage
    exit 1
  end
  $num_ask = ARGV[1].to_i
  if $num_ask.to_s != ARGV[1] || $num_ask < 1
    puts "ERROR: Argument after mode 'a' mus be a number starting at 1, not '#{ARGV[1]}'"
    puts usage
    exit 1
  end
end


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
  arc = "arecord -s 4096 #{sfile}"
  samples = Array.new
  puts issue if issue

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
    puts issue if issue
  end
end


def do_ask
  wanted = $scale.sample
  get_note("Please play #{wanted}") {|played| [played == wanted, played == wanted]}
end


def do_listen
  get_note('Please play any note from the scale') {|played| [$scale.include?(played), false]}
end


# The frequencies are sensitive to argument '--pitch' for aubioptch below
$nota = { 'low' => {freq: 100, hole: 'low'},
          'c4' => {frq: 248, hole: '+1'},
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


switch $mode:
