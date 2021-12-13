#
# Set some global vars directly and read configuration for others
#

def set_global_vars_early
  $sample_rate = 48000
  $move_down_on_exit = false

  $ctl_kb_queue = Queue.new
  $ctl_default_issue = ''
  $ctl_skip = $ctl_loop = $ctl_start_loop = false
  $ctl_can_next = $ctl_can_back = $ctl_can_loop = $ctl_can_journal = $ctl_toggle_journal = $ctl_show_help = $ctl_change_key = $ctl_change_scale = $ctl_quit = false
  $ctl_change_display = $ctl_change_comment = $ctl_set_ref = $ctl_redraw = false
  $ctl_can_change_comment = false
  $ctl_issue_width = 36
  $ctl_non_def_issue_ts = nil
  $ctl_sig_winch = false
  
  $tmp_dir = Dir.mktmpdir(File.basename($0) + '_')
  at_exit {FileUtils.remove_entry $tmp_dir}
  $data_dir = "#{Dir.home}/.#{File.basename($0)}"
  FileUtils.mkdir_p($data_dir) unless File.directory?($data_dir)
  $journal_file = "#{$data_dir}/journal.txt"
  $write_journal = false
  $message_shown = false
  $display_choices = [:chart, :hole, :bend]
  $comment_choices = [:note, :interval, :hole, :cents]

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
  $scale_files_template = 'config/%s/scale_%s_with_%s.yaml'

  $jitter = 0.0
  $freqs_queue = Queue.new

  $figlet_count = 0
end


def calculate_screen_layout
  squeeze = stretch = 0
  stretch += 1 if $term_height > 30
  stretch += 1 if $term_height > 36
  squeeze = 1 if $term_height < 26
  $line_issue = 1
  $line_key = 2
  $line_display = 4 + stretch - squeeze
  $line_hole = 15 + 2 * stretch - 2 * squeeze
  $line_frequency = 16 + 2 * stretch - 2 * squeeze
  $line_interval = 17 + 2 * stretch - 2 * squeeze
  $line_comment = 18 + 3 * stretch - 2 * squeeze
  $line_hint_or_message = 26 + 4 * stretch - 2 * squeeze
  $line_call = 27 + 4 * stretch - 2 * squeeze
  if $mode == :listen
    # we dont use calls for mode listen
    $line_call = -1
  else
    # font for quiz is fairly small
    $line_comment += 1
    $line_hint_or_message -= 1 
    $line_call -= 1
  end

end


def set_global_vars_late
  $sample_dir = this_or_equiv("#{$data_dir}/samples/#{$type}/key_of_%s", $key.to_s)
  $freq_file = "#{$sample_dir}/frequencies.yaml"
  $helper_wave = "#{$tmp_dir}/helper.wav"
  $recorded_data = "#{$tmp_dir}/recorded.dat"
  $trimmed_wave = "#{$tmp_dir}/trimmed.wav"
end


def check_installation
  # check for some required programs
  not_found = %w( figlet arecord aplay aubiopitch sox gnuplot ).reject {|x| system("which #{x} >/dev/null 2>&1")}
  err_b "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0
  
  if !File.exist?(File.basename($0))
    err_b "Please invoke this program from within its own directory (cannot find #{File.basename($0)} in current dir)"
  end
end


def load_technical_config
  file = 'config/config.yaml'
  merge_file = "#{$data_dir}/config.yaml"
  conf = yaml_parse(file).transform_keys!(&:to_sym)
  req_keys = Set.new([:type, :key, :comment_listen, :display_listen, :display_quiz, :time_slice, :pitch_detection, :pref_sig_def, :min_freq, :max_freq, :term_min_width, :term_min_height])
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
  conf
end


def read_technical_config
  conf = load_technical_config
  # working some individual configs
  conf[:all_keys] = Set.new($notes_with_sharps + $notes_with_flats).to_a
  [:comment_listen, :display_listen, :display_quiz, :pref_sig_def].each {|key| conf[key] = conf[key].to_sym}
  conf[:all_types] = Dir['config/*'].
                       select {|f| File.directory?(f)}.
                       map {|f| File.basename(f)}.
                       reject {|f| f.start_with?('.')}
  conf
end


def read_musical_config
  # read and compute from harps file
  hfile = "config/#{$type}/holes.yaml"
  
  hole2note_read = yaml_parse(hfile)
  dsemi_harp = note2semi($key.to_s + '0') - note2semi('c0')
  dsemi_harp -= 12 if dsemi_harp > 6
  harp = Hash.new
  hole2note_read.each do |hole,note|
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

    err_msg = if $opts[:transpose_scale_to]
                "Transposing scale #{$scale} to #{$opts[:transpose_scale_to]} results in %s (semi = %d), which is not present in #{hfile} (but still in range of harp #{min_semi} .. #{max_semi}). Maybe choose another value for --transpose_scale_to or another type of harmonica"
              else
                "#{sfile} has %s (semi = %d), which is not present in #{hfile} (but still in range of harp #{min_semi} .. #{max_semi}). Please correct these files"
              end
    # For convenience we have both hole2note and hole2note_read; they only differ,
    # if key does not equal c, and the following relation always holds true:
    # note2semi(hole2note[h]) - note2semi(hole2note_read[h]) == note2semi(key) - note2semi('c') =: dsemi_harp
    # Please note, that below we transpose the scale, regardless if it is written as notes or as holes.
    dsemi_scale = note2semi(($opts[:transpose_scale_to] || 'c') + '0') - note2semi('c0')
    scale_read.each do |hole_or_note_read|
      semi = dsemi_harp + dsemi_scale +
             ( sfile['holes']  ?  note2semi(hole2note_read[hole_or_note_read])  :  note2semi(hole_or_note_read) )
      if semi >= min_semi && semi <= max_semi
        note = semi2note(semi)
        hole = note2hole[note]
        err_b(err_msg % [ sfile['holes']  ?  "hole #{hole_or_note_read}, note #{note}"  :  "note #{hole_or_note_read}",
                          semi]) unless hole
        scale << hole
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
  $chart_file = "config/#{$type}/chart.yaml"
  chart = yaml_parse($chart_file)
  chart.map! {|r| r.is_a?(String)  ?  r.split('|')  :  r}
  hole2chart = Hash.new {|h,k| h[k] = Array.new}
  len = chart.shift
  # first two elements will be set when checking for terminal size
  $conf[:chart_offset_xyl] = [0, 0, len] unless $conf[:chart_offset_xyl]
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

  rescue ArgumentError => e
    fail "Internal error with #{$chart_file}: #{e}"
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
