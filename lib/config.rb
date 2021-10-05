#
# Set some global vars directly and read configuration for others
#

def set_global_vars_early
  $sample_rate = 48000
  $move_down_on_exit = false
  stretch = $term_height >= 36 ? 1 : 0
  $line_issue = 1
  $line_key = 2
  $line_display = 5 + stretch
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

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
end


def set_global_vars_late
  $sample_dir = this_or_equiv("samples/#{$conf[:type]}/key_of_%s", $key.to_s)
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


def read_technical_config
  file = 'config/config.json'
  merge_file = 'config/config_merge.json'
  conf = JSON.parse(File.read(file)).transform_keys!(&:to_sym)
  req_keys = Set.new([:type, :key, :comment_listen, :display_listen, :display_quiz])
  file_keys = Set.new(conf.keys)
  fail "Internal error: Set of keys in #{file} (#{file_keys}) does not equal required set #{req_keys}" unless req_keys == file_keys
  if File.exist?(merge_file)
    begin
      merge_conf = JSON.parse(File.read(merge_file))
    rescue JSON::ParserError => e
      err_b "Cannot parse #{merge_file}: #{e}"
    end
    err_b "Config from #{merge_file} is not a hash" unless merge_conf.is_a?(Hash)
    merge_conf.transform_keys!(&:to_sym)
    merge_conf.each do |k,v|
      err_b "Key #{k} from #{merge_file} is none of the valid keys #{req_keys}" unless req_keys.include?(k)
      conf[k] = v
    end
  end
  
  [:comment_listen, :display_listen, :display_quiz].each {|key| conf[key] = conf[key].to_sym}
  conf[:type] = conf[:type]
  conf[:all_types] = Dir['config/*'].
                       select {|f| File.directory?(f)}.
                       map {|f| File.basename(f)}.
                       reject {|f| f.start_with?('.')}
  
  conf
end


def read_musical_config

  # read and compute from harps file
  hfile = "config/#{$conf[:type]}/holes.json"
  begin
    harp = JSON.parse(File.read(hfile))
  rescue JSON::ParserError => e
    err_b "Cannot parse #{hfile}: #{e}"
  end

  dsemi = note2semi($key.to_s + '0') - note2semi('c0')
  harp.each_value do |h|
    h.transform_keys!(&:to_sym)
    begin
      h[:semi] = note2semi(h[:note]) + dsemi
    rescue ArgumentError => e
      err_b "From #{hfile}, key #{$key}, note #{h[:note]}: #{e.message}"
    end
    h[:note] = semi2note(h[:semi]) unless dsemi == 0
  end

  sfile = "config/#{$conf[:type]}/scales.json"
  scales = JSON.parse(File.read(sfile)).transform_keys!(&:to_sym)
  scales.each do |scale, holes|
    unless Set.new(holes).subset?(Set.new(harp.keys))
      fail "Internal error with #{sfile}: Holes of scale #{scale} #{holes.inspect} is not a subset of holes of harp #{harp.keys.inspect}. Scale #{scale} has these extra holes not appearing in harp of key #{$key}: #{(Set.new(holes) - Set.new(harp.keys)).to_a.inspect}"
    end
  end

  harp_holes = harp.keys
  if $scale
    scale_holes = scales[$scale]
    scale_notes = scale_holes.map {|h| harp[h][:note]}
  else
    scale_holes = scale_notes = nil
  end

  unless harp_holes.map {|hole| harp[hole][:semi]}.each_cons(2).all? { |a, b| a < b }
    err_b "Internal error: Computed semitones are not strictly ascending in order of holes:\n#{harp.pretty_inspect}"
  end

  # read from first available intervals file
  ifile = ["config/#{$conf[:type]}/intervals.json", "config/intervals.json"].find {|f| File.exists?(f)}
  intervals = JSON.parse(File.read(ifile)).transform_keys!(&:to_i)

  [ harp, harp_holes, scale_holes, scale_notes, intervals ]
end


def read_chart
  cfile = "config/#{$conf[:type]}/chart.json"
  chart = JSON.parse(File.read(cfile))
  hole2chart = Hash.new {|h,k| h[k] = Array.new}
  len = chart.shift
  begin
    # check for completeness
    hchart = Set.new(chart.map {|r| r[0 .. -2]}.flatten.map(&:strip).reject {|x| comment_in_chart?(x)})
    hharp = Set.new($harp.keys)
    raise ArgumentError.new("holes from chart is not the same set as holes from harp; missing in chart: #{hharp - hchart}, extra in chart: #{hchart - hharp}") if hchart != hharp

    # map from holes to notes for given key
    (0 ... chart.length).each do |row|
      (0 ... chart[row].length - 1).each do |col|
        hole = chart[row][col]
        chart[row][col] = if comment_in_chart?(hole)
                            hole[0,len]
                          else
                            note = $harp[hole.strip][:note]
                            raise ArgumentError.new("hole '#{hole}' maps to note '#{note}' which is longer than given length '#{len}'") if note.length > len
                            hole2chart[hole.strip] << [col, row]
                            note.center(len)
                          end
      end
    end

    # check for size
    xroom = $term_width - chart.map {|r| r.join.length}.max - 2
    raise ArgumentError.new("chart is too wide (by #{-xroom} chars) for this terminal") if xroom < 0
    yroom = $line_samples - $line_display - chart.length
    raise ArgumentError.new("chart is too high by #{-yroom} lines for this terminal") if yroom < 0
    $conf[:chart_offset_xyl] = [ (xroom * 0.4).to_i, yroom / 2 - 1, len]
  rescue ArgumentError => e
    fail "Internal error with #{cfile}: #{e}"
  end

  [ chart, hole2chart ]
  
end


def read_calibration
  err_b "Frequency file #{$freq_file} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?($freq_file)
  hole2freq = JSON.parse(File.read($freq_file))
  unless Set.new($harp_holes).subset?(Set.new(hole2freq.keys))
    err_b "Holes in #{$freq_file} #{hole2freq.keys.join(' ')} is not a subset of holes for scale #{$scale} #{$harp.keys.join(' ')}. Missing in #{$freq_file} are holes #{(Set.new($harp_holes) - Set.new(hole2freq.keys)).to_a.join(' ')}. Probably you need to redo the calibration and play the missing holes"
  end
  unless Set.new(hole2freq.keys).subset?(Set.new($harp_holes))
    err_b "Holes for scale #{$scale} #{$harp.keys.join(' ')} is not a subset of holes in #{$freq_file} #{hole2freq.keys.join(' ')}. Extra in #{$freq_file} are holes #{(Set.new(hole2freq.keys) - Set.new($harp_holes)).to_a.join(' ')}. Probably you need to remove the frequency file #{$freq_file} and redo the calibration to rebuild the file properly"
  end
  unless $harp_holes.map {|hole| hole2freq[hole]}.each_cons(2).all? { |a, b| a < b }
    err_b "Frequencies in #{$freq_file} are not strictly ascending in order of #{$harp_holes.inspect}: #{hole2freq.pretty_inspect}"
  end

  hole2freq.map {|k,v| $harp[k][:freq] = v}

  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)
  end

  freq2hole = $harp_holes.map {|h| [$harp[h][:freq], h]}.to_h

  freq2hole

end
