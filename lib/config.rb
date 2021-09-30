#
# Set some global vars directly and read configuration for others
#

def set_global_vars_early
  $sample_rate = 48000
  $move_down_on_exit = false
  stretch = $term_height >= 36 ? 1 : 0
  $line_issue = 1
  $line_key = 2
  $line_hole = 5 + stretch
  $line_samples = 15 + 2 * stretch
  $line_peaks = 16 + 2 * stretch
  $line_frequency = 17 + 2 * stretch
  $line_interval = 18 + 2 * stretch
  $line_comment_big = 20 + 3 * stretch
  $line_comment_small = 28 + 4 * stretch
  $line_hint = 29 + 4 * stretch
  $line_listen = 30 + 4 * stretch
  $line_listen2 = 31 + 4 * stretch

  $ctl_kb_queue = Queue.new
  $ctl_kb_queue_mutex = Mutex.new
  $ctl_default_issue = ''
  $ctl_skip = $ctl_loop = nil
  $ctl_can_next = $ctl_can_back = false
  $ctl_issue_width = 42
  $ctl_non_def_issue_ts = nil
end


def set_global_vars_late
  $sample_dir = "samples/diatonic/key_of_#{$key}"
  $freq_file = "#{$sample_dir}/frequencies.json"
  $collect_wave = 'tmp/collect.wav'
  $edit_data = 'tmp/edit_workfile.dat'
  $edit_wave = 'tmp/edit_workfile.wav'
end


def check_installation
  # check for some required programs
  not_found = %w( figlet arecord aplay aubiopitch sox gnuplot ).reject {|x| system("which #{x} >/dev/null 2>&1")}
  err_b "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0
  
  if !File.exist?(File.basename($0))
    err_b "Please invoke this program from within its own directory (cannot find #{File.basename($0)} in current dir)"
  end
end


def read_musical_config

  # read and compute from harps file
  file = 'config/diatonic_harps.json'
  harps = JSON.parse(File.read(file)).transform_keys!(&:to_sym)
  unless Set.new(harps.values.map {|v| v.keys}).length == 1
    fail "Internal error with #{file}, not all harps have the same list of holes"
  end
  harp = harps[$key] or fail "Internal error: Key #{$key} has no harp"

  harp.each_value {|h| h.transform_keys!(&:to_sym)}
  semi_before = -1
  harp.each_value do |h|
    begin
      h[:semi] = note2semi(h[:note])
    rescue ArgumentError => e
      err_b "From #{file}, key #{$key}, note #{h[:note]}: #{e.message}"
    end
  end
  
  scales_holes = JSON.parse(File.read('config/scales_holes.json')).transform_keys!(&:to_sym)
  scales_holes.each do |scale, holes|
    unless Set.new(holes).subset?(Set.new(harp.keys))
      fail "Internal error: Holes of scale #{scale} #{holes.inspect} is not a subset of holes of harp #{harp.keys.inspect}. Scale #{scale} has these extra holes not appearing in harp of key #{$key}: #{(Set.new(holes) - Set.new(harp.keys)).to_a.inspect}"
    end
  end

  holes = harp.keys
  scale_holes = scales_holes[$scale]

  unless holes.map {|hole| harp[hole][:semi]}.each_cons(2).all? { |a, b| a < b }
    err_b "Internal error: Computed semitones are not strictly ascending in order of holes:\n#{harp.pretty_inspect}"
  end
  
  # read from intervals file
  intervals = JSON.parse(File.read('config/intervals.json')).transform_keys!(&:to_i)
  
  [ harp, holes, scale_holes, intervals ]
end


def read_calibration
  err_b "Frequency file #{$freq_file} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?($freq_file)
  hole2freq = JSON.parse(File.read($freq_file))
  unless Set.new($holes).subset?(Set.new(hole2freq.keys))
    err_b "Holes in #{$freq_file} #{hole2freq.keys.join(' ')} is not a subset of holes for scale #{$scale} #{$harp.keys.join(' ')}. Missing in #{$freq_file} are holes #{(Set.new($holes) - Set.new(hole2freq.keys)).to_a.join(' ')}. Probably you need to redo the calibration and play the missing holes"
  end
  unless Set.new(hole2freq.keys).subset?(Set.new($holes))
    err_b "Holes for scale #{$scale} #{$harp.keys.join(' ')} is not a subset of holes in #{$freq_file} #{hole2freq.keys.join(' ')}. Extra in #{$freq_file} are holes #{(Set.new(hole2freq.keys) - Set.new($holes)).to_a.join(' ')}. Probably you need to remove the frequency file #{$freq_file} and redo the calibration to rebuild the file properly"
  end
  unless $holes.map {|hole| hole2freq[hole]}.each_cons(2).all? { |a, b| a < b }
    err_b "Frequencies in #{$freq_file} are not strictly ascending in order of #{$holes.inspect}: #{hole2freq.pretty_inspect}"
  end

  hole2freq.map {|k,v| $harp[k][:freq] = v}

  $holes.each do |hole|
    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
    err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)
  end

  freq2hole = $holes.map {|h| [$harp[h][:freq], h]}.to_h

  freq2hole

end
