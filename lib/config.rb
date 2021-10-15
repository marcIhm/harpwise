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
  $line_driver = 16 + 2 * stretch
  $line_frequency = 17 + 2 * stretch
  $line_interval = 18 + 2 * stretch
  $line_comment_big = 20 + 3 * stretch
  $line_comment_small = 28 + 4 * stretch
  $line_hint = 29 + 4 * stretch
  $line_listen = 30 + 4 * stretch
  $line_listen2 = 31 + 4 * stretch

  $ctl_kb_queue = Queue.new
  $ctl_default_issue = ''
  $ctl_skip = $ctl_loop = nil
  $ctl_can_next = $ctl_can_back = false
  $ctl_issue_width = 42
  $ctl_non_def_issue_ts = nil

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
  $scale_files_template = 'config/%s/scale_%s_with_%s.yaml'

  $freqs_rate_ratio = 0
  $freqs_per_sec = 0
  $freqs_queue = Queue.new
end


def set_global_vars_late
  $sample_dir = this_or_equiv("samples/#{$type}/key_of_%s", $key.to_s)
  $freq_file = "#{$sample_dir}/frequencies.yaml"
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
  file = 'config/config.yaml'
  merge_file = 'config/config_merge.yaml'
  conf = yaml_parse(file).transform_keys!(&:to_sym)
  req_keys = Set.new([:type, :key, :comment_listen, :display_listen, :display_quiz, :time_slice])
  file_keys = Set.new(conf.keys)
  fail "Internal error: Set of keys in #{file} (#{file_keys}) does not equal required set #{req_keys}" unless req_keys == file_keys
  if File.exist?(merge_file)
    merge_conf = yaml_parse(merge_file)
    err_b "Config from #{merge_file} is not a hash" unless merge_conf.is_a?(Hash)
    merge_conf.transform_keys!(&:to_sym)
    merge_conf.each do |k,v|
      err_b "Key #{k} from #{merge_file} is none of the valid keys #{req_keys}" unless req_keys.include?(k)
      conf[k] = v
    end
  end

  # working some individual configs
  conf[:all_keys] = Set.new($notes_with_sharps + $notes_with_flats).to_a
  [:comment_listen, :display_listen, :display_quiz].each {|key| conf[key] = conf[key].to_sym}
  conf[:all_types] = Dir['config/*'].
                       select {|f| File.directory?(f)}.
                       map {|f| File.basename(f)}.
                       reject {|f| f.start_with?('.')}
  
  conf
end


def read_musical_config

  # read and compute from harps file
  hfile = "config/#{$type}/holes.yaml"
  
  hole2note_orig = yaml_parse(hfile)
  note2hole_orig = hole2note_orig.invert
  dsemi_harp = note2semi($key.to_s + '0') - note2semi('c0')
  harp = Hash.new
  hole2note_orig.each do |hole,note|
    semi = note2semi(note) + dsemi_harp
    harp[hole] = [[:note, semi2note(semi)],
               [:semi, semi]].to_h
  end
  semis = harp.map {|hole, hash| hash[:semi]}
  min_semi = semis.min
  max_semi = semis.max
  harp_holes = harp.keys

  # for convenience
  hole2note = harp.map {|hole, hash| [hole, hash[:note]]}.to_h
  note2hole = hole2note.invert
      
  sfiles = Dir[$scale_files_template % [$type, $scale, '{holes,notes}']]
  # check for zero files is in arguments.rb
  err_b "Multiple files for scale #{$scale}:\n#{sfiles.inspect}" if sfiles.length > 1
  sfile = sfiles[0]

  if $scale
    scale_read = yaml_parse(sfile)
    scale = Array.new
    dscale = Array.new

    err_msg = if $opts[:transpose_scale_to]
                "Transposing scale #{$scale} to #{$opts[:transpose_scale_to]} results in %s (semitone = %d), which is not present in #{hfile} (but still in range of harp #{min_semi} .. #{max_semi}). Maybe choose another value for --transpose_scale_to"
              else
                "#{sfile} has %s (semitone = %d), which is not present in #{hfile} (but still in range of harp #{min_semi} .. #{max_semi}). Please correct these files"
              end
    # For convenience we have both note2hole and note2hole_orig and their respective inverse;
    # they only differ, if key does not equal c, and the following relation always holds true:
    # note2semi(hole2note[h]) - note2semi(hole2note_orig[h]) == note2semi(key) - note2semi('c') =: dsemi_harp
    # Note, that below we transpose the scale, regardless if they are written as notes or as holes.
    dsemi_scale = note2semi(($opts[:transpose_scale_to] || 'c') + '0') - note2semi('c0')
    if sfile['holes']  # sfile with holes
      scale_read.each do |hole|
        semi = note2semi(hole2note_orig[hole]) + dsemi_scale
        if semi >= min_semi && semi <= max_semi
          dscale << hole2note_orig[hole]
          # transposing happens by using note2hole below, while we had hole2note_orig above
          n = semi2note(semi)
          h = note2hole[n]
          err_b(err_msg % ["note #{n}", semi]) unless hole2note[h]
          err_b "Transposing hole #{hole} from c to #{$opts[:transpose_scale_to]} (by #{dsemi_scale} results in a note (#{semi2note(semi)}), that has no hole in harp; please use another value for --transpose_scale_to or leave it out altogether" unless h
          scale << h
        end
      end
    else  # sfile with notes
      scale_read.each do |note|
        semi = note2semi(note) + dsemi_scale
        if semi + dsemi_harp >= min_semi && semi + dsemi_harp <= max_semi
          dscale << note2hole_orig[note]
          # transposing happens by adding dsemi_harp explicitly
          n = semi2note(semi + dsemi_harp)
          err_b(err_msg % ["note #{n}", semi]) unless note2hole[n]
          h = note2hole[n]
          scale << h
        end
      end
    end

    scale_holes = scale
    scale_notes = scale_holes.map {|hole| hole2note[hole]}

    dfile = File.dirname(sfile) + '/derived_' + File.basename(sfile).sub(/holes|notes/, sfile['holes'] ? 'notes' : 'holes')
    comment = "#\n# derived scale-file with %s before any transposing has been applied,\n# created from #{sfile}\n#\n" 
    File.write(dfile, (comment % [ dfile['holes'] ? 'holes' : 'notes' ]) + YAML.dump(dfile['holes'] ? scale_holes : scale_notes))
  else              
    scale_holes = scale_notes = nil
  end

  unless harp_holes.map {|hole| harp[hole][:semi]}.each_cons(2).all? { |a, b| a < b }
    err_b "Internal error: Computed semitones are not strictly ascending in order of holes:\n#{harp.pretty_inspect}"
  end

  # read from first available intervals file
  ifile = ["config/#{$type}/intervals.yaml", "config/intervals.yaml"].find {|f| File.exists?(f)}
  intervals = yaml_parse(ifile).transform_keys!(&:to_i)

  [ harp, harp_holes, scale_holes, scale_notes, intervals ]
end


def read_chart
  cfile = "config/#{$type}/chart.yaml"
  chart = yaml_parse(cfile)
  chart.map! {|r| r.is_a?(String)  ?  r.split('|')  :  r}
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
    yroom = $line_driver - $line_display - chart.length
    raise ArgumentError.new("chart is too high by #{-yroom} lines for this terminal") if yroom < 0
    $conf[:chart_offset_xyl] = [ (xroom * 0.4).to_i, ( yroom - 1 ) / 2 - 1, len]
  rescue ArgumentError => e
    fail "Internal error with #{cfile}: #{e}"
  end

  [ chart, hole2chart ]
  
end


def read_calibration
  err_b "Frequency file #{$freq_file} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?($freq_file)
  hole2freq = yaml_parse($freq_file)
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
