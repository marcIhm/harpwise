#
# Set some global vars directly and read configuration for others
#

def set_global_vars_early

  $move_down_on_exit = false
  $err_binding = nil
  
  $sample_rate = 48000

  $ctl_kb_queue = Queue.new
  $ctl_default_issue = ''
  $ctl_skip = $ctl_loop = $ctl_start_loop = $ctl_named_lick = false
  $ctl_can_next = $ctl_can_back = $ctl_can_loop = $ctl_toggle_journal = $ctl_show_help = $ctl_change_key = $ctl_change_scale = $ctl_quit = $ctl_can_named = false
  $ctl_change_display = $ctl_change_comment = $ctl_set_ref = $ctl_update_after_set_ref = $ctl_redraw = false
  $ctl_issue_width = 36
  $ctl_non_def_issue_ts = nil
  $ctl_sig_winch = false
  $all_licks = $licks = nil
  
  $tmp_dir = Dir.mktmpdir(File.basename($0) + '_')
  $data_dir = "#{Dir.home}/.#{File.basename($0)}"
  FileUtils.mkdir_p($data_dir) unless File.directory?($data_dir)

  # will be created by test-driver
  $test_wav = "/tmp/#{File.basename($0)}_testing.wav"
  
  $journal_listen = Array.new
  $testing_log = "/tmp/#{File.basename($0)}_testing.log"
  $write_journal = false
  $message_shown = false

  $notes_with_sharps = %w( c cs d ds e f fs g gs a as b )
  $notes_with_flats = %w( c df d ef e f gf g af a bf b )
  $scale_files_template = 'config/%s/scale_%s_with_%s.yaml'

  $jitter = 0.0
  $freqs_queue = Queue.new

  $figlet_count = 0
  $first_round_ever_get_hole = true

  $display_choices = [:hole, :chart_notes, :chart_scales, :chart_intervals, :bend]
  $comment_choices = Hash.new([:holes_large, :holes_all, :holes_scales, :holes_intervals])
  $comment_choices[:listen] = [:note, :interval, :hole, :cents]                       

end


def calculate_screen_layout
  squeeze = stretch = 0
  stretch += 1 if $term_height > 30
  stretch += 1 if $term_height > 36
  squeeze = 1 if $term_height < 27
  lines = Hash.new
  lines[:issue] = 1
  lines[:key] = 2
  lines[:display] = 4 + stretch - squeeze
  lines[:hole] = 15 + 2 * stretch - 2 * squeeze
  lines[:frequency] = lines[:hole] + 1
  lines[:interval] = lines[:hole] + 2
  lines[:comment] = 18 + 3 * stretch - 2 * squeeze
  lines[:hint_or_message] = 26 + 5 * stretch - 2 * squeeze
  2.times do
    lines[:hint_or_message] += 1 if $term_height - lines[:hint_or_message] > 1
  end
  lines[:comment_tall] = lines[:comment]
  if $mode == :quiz || $mode == :memorize
    # font for quiz is fairly small, so we may leave some space
    lines[:comment] += 1
    # call starts on lines[:hint_or_message], so lines[:call2] is actually
    # its second line
    lines[:call2] = lines[:hint_or_message] + 1
  else
    # we do not need a second line for mode :listen
    lines[:call2] = -1
  end
  lines[:help] = lines[:comment]
  lines
end


def set_global_vars_late
  $sample_dir = this_or_equiv("#{$data_dir}/samples/#{$type}/key_of_%s", $key.to_s)
  $lick_dir = "#{$data_dir}/licks/#{$type}"
  $lick_file_template = "#{$lick_dir}/licks_with_%s.txt"
  $freq_file = "#{$sample_dir}/frequencies.yaml"
  $holes_file = "config/#{$type}/holes.yaml"
  $helper_wave = "#{$tmp_dir}/helper.wav"
  $recorded_data = "#{$tmp_dir}/recorded.dat"
  $trimmed_wave = "#{$tmp_dir}/trimmed.wav"
  $journal_file = if $mode == :memorize || $mode == :play
                    "#{$data_dir}/journal_memorize_play.txt"
                  else
                    "#{$data_dir}/journal_#{$mode}.txt"
                  end
end


def check_installation install_dir
  # check for some required programs
  not_found = %w( figlet arecord aplay aubiopitch sox gnuplot stdbuf ).reject {|x| system("which #{x} >/dev/null 2>&1")}
  err "These programs are needed but cannot be found: \n  #{not_found.join("\n  ")}\nyou may need to install them" if not_found.length > 0

  # Check some sample dirs and files
  %w(fonts/mono12.tlf config/intervals.yaml recordings/juke.mp3).each do |file|
    if !File.exist?(install_dir + '/' + file)
      err "Installation is incomplete: The file #{file} does not exist in #{install_dir}"
    end
  end
end


def load_technical_config
  file = 'config/config.yaml'
  merge_file = "#{$data_dir}/config.yaml"
  conf = yaml_parse(file).transform_keys!(&:to_sym)
  req_keys = Set.new([:type, :key, :comment_listen, :comment_quiz, :display_listen, :display_quiz, :display_memorize, :time_slice, :pitch_detection, :pref_sig_def, :min_freq, :max_freq, :term_min_width, :term_min_height, :play_holes_fast])
  file_keys = Set.new(conf.keys)
  fail "Internal error: Set of keys in #{file} (#{file_keys}) does not equal required set #{req_keys}" unless req_keys == file_keys
  if File.exist?(merge_file)
    merge_conf = yaml_parse(merge_file)
    err "Config from #{merge_file} is not a hash" unless merge_conf.is_a?(Hash)
    merge_conf.transform_keys!(&:to_sym)
    merge_conf.each do |k,v|
      err "Key '#{k}' from #{merge_file} is none of the valid keys #{req_keys}" unless req_keys.include?(k)
      conf[k] = v
    end
  end
  conf
end


def read_technical_config
  conf = load_technical_config
  # working some individual configs
  conf[:all_keys] = Set.new($notes_with_sharps + $notes_with_flats).to_a
  [:comment_listen, :comment_quiz, :display_listen, :display_quiz, :display_memorize, :pref_sig_def].each {|key| conf[key] = conf[key].gsub('-','_').to_sym}
  conf[:all_types] = Dir['config/*'].
                       select {|f| File.directory?(f)}.
                       map {|f| File.basename(f)}.
                       reject {|f| f.start_with?('.')}
  conf
end


def read_musical_config
  hole2note_read = yaml_parse($holes_file)
  dsemi_harp = note2semi($key.to_s + '0') - note2semi('c0')
  dsemi_harp -= 12 if dsemi_harp > 6
  dsemi_harp += 12 if dsemi_harp < -6
  harp = Hash.new
  hole2rem = Hash.new
  hole2flags = Hash.new {|h,k| h[k] = Set.new}
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
  harp_notes = harp.keys.map {|h| hole2note[h]}

  # process scales
  if $scale
    
    # get all holes to remove
    holes_remove = []
    if $opts[:remove]
      $opts[:remove].split(',').each do |sn|
        sc_ho, _ = read_and_parse_scale(sn, hole2note_read, hole2note, note2hole, dsemi_harp, min_semi, max_semi)
        holes_remove.concat(sc_ho)
      end
    end

    scale = []
    h2sabb = Hash.new {|h,k| h[k] = ''}
    $scales.each_with_index do |sname, idx|
      # read scale
      sc_ho, h2r = read_and_parse_scale(sname, hole2note_read, hole2note, note2hole, dsemi_harp, min_semi, max_semi)
      # build resulting scale
      holes_remove.each {|h| sc_ho.delete(h)}
      scale.concat(sc_ho) unless idx > 0 && $opts[:add_no_holes]
      h2r.each_key do |h|
        next if holes_remove.include?(h)
        if idx == 0
          hole2flags[h] << :main
        else
          next if $opts[:add_no_holes] && !hole2flags[h]
          hole2flags[h] << :added
        end
        hole2flags[h] << :both if hole2flags[h].include?(:main) && hole2flags[h].include?(:added)
        hole2flags[h] << :all if !$opts[:add_scales] || hole2flags[h].include?(:both)
        hole2flags[h] << :root if h2r[h] && h2r[h].match(/\broot\b/)
        h2sabb[h] += $scale2abbrev[sname]
        hole2rem[h] ||= [[],[]]
        hole2rem[h][0] << sname if $opts[:add_scales]
        hole2rem[h][1] << h2r[h]&.split(/, /)
      end
    end
    scale_holes = scale.sort_by {|h| harp[h][:semi]}.uniq
    scale_notes = scale_holes.map {|h| hole2note[h]}
    semi2hole = scale_holes.map {|hole| [harp[hole][:semi], hole]}.to_h
  else            
    semi2hole = scale_holes = scale_notes = nil
  end

  hole2rem.each_key do |h|
    hole2rem[h] = [hole2rem[h][0].uniq, hole2rem[h][1].uniq].flatten.select(&:itself).uniq.join(',')
  end
  
  # read from first available intervals file
  ifile = ["config/#{$type}/intervals.yaml", "config/intervals.yaml"].find {|f| File.exists?(f)}
  intervals = yaml_parse(ifile).transform_keys!(&:to_i)

  [ harp,
    harp_holes,
    harp_notes,
    scale_holes,
    scale_notes,
    hole2rem.values.all?(&:nil?)  ?  nil  :  hole2rem,
    hole2flags.values.all?(&:nil?)  ?  nil  :  hole2flags,
    h2sabb,
    semi2hole,
    note2hole,
    intervals,
    dsemi_harp]
end


def read_and_parse_scale sname, hole2note_read, hole2note, note2hole, dsemi_harp, min_semi, max_semi
  err "Scale '#{sname}' should not contain chars '?' or '*'" if sname['?'] || sname['*']
  glob = $scale_files_template % [$type, sname, '{holes,notes}']
  sfiles = Dir[glob]
  if sfiles.length != 1
    snames = scales_for_type($type)
    err "Unknown scale '#{sname}' (none of #{snames.join(', ')}) as there is no file matching #{glob}" if sfiles.length == 0
    err "Invalid scale '#{sname}' (none of #{snames.join(', ')}) as there are multiple files matching #{glob}"
  end
  sfile = sfiles[0]

  scale_read = yaml_parse(sfile)
  scale_holes = Array.new
  hole2rem = Hash.new

  err_msg = if $opts[:transpose_scale_to]
              "Transposing scale #{sname} from key of c to #{$opts[:transpose_scale_to]} results in %s (semi = %d), which is not present in #{$holes_file} (but still in range of harp #{min_semi} .. #{max_semi}). Maybe choose another value for --transpose_scale_to or another type of harmonica"
            else
              "#{sfile} has %s (semi = %d), which is not present in #{$holes_file} (but still in range of harp #{min_semi} .. #{max_semi}). Please correct these files"
            end
  # For convenience we have both hole2note and hole2note_read; they only differ,
  # if key does not equal c, and the following relation always holds true:
  # note2semi(hole2note[h]) - note2semi(hole2note_read[h]) == note2semi(key) - note2semi('c') =: dsemi_harp
  # Please note, that below we transpose the scale, regardless if it is written as notes or as holes.
  dsemi_scale = note2semi(($opts[:transpose_scale_to] || 'c') + '0') - note2semi('c0')
  scale_read.each do |fields|
    hole_or_note, rem = fields.split(nil,2)
    semi = dsemi_harp + dsemi_scale + ( sfile['holes']  ?  note2semi(hole2note_read[hole_or_note])  :  note2semi(hole_or_note) )
    if semi >= min_semi && semi <= max_semi
      note = semi2note(semi)
      hole = note2hole[note]
      hole2rem[hole] = rem&.strip
      err(err_msg % [ sfile['holes']  ?  "hole #{hole_or_note}, note #{note}"  :  "note #{hole_or_note}", semi]) unless hole
      scale_holes << hole
    end
  end
  
  scale_holes_with_rem = scale_holes.map {|h| "#{h} #{hole2rem[h]}".strip}
  scale_notes_with_rem = scale_holes.map {|h| "#{hole2note[h]} #{hole2rem[h]}".strip}
  
  # write derived scale file
  dfile = File.dirname(sfile) + '/derived_' + File.basename(sfile).sub(/holes|notes/, sfile['holes'] ? 'notes' : 'holes')
  comment = "#\n# derived scale file with %s before any transposing has been applied,\n# created from #{sfile}\n#\n" 
  File.write(dfile, (comment % [ dfile['holes'] ? 'holes' : 'notes' ]) + YAML.dump(dfile['holes'] ? scale_holes_with_rem : scale_notes_with_rem))
  
  [scale_holes, hole2rem]
end


$chart_with_holes_raw = nil
$chart_cell_len = nil

def read_chart
  $chart_file = "config/#{$type}/chart.yaml"
  chart_with_holes_raw = yaml_parse($chart_file)
  len = chart_with_holes_raw.shift
  chart_with_holes_raw.map! {|r| r.split('|')}
  hole2chart = Hash.new {|h,k| h[k] = Array.new}
  # first two elements will be set when checking for terminal size
  $conf[:chart_offset_xyl] = [0, 0, len] unless $conf[:chart_offset_xyl]
  begin
    # check for completeness
    chart_holes = Set.new(chart_with_holes_raw.map {|r| r[0 .. -2]}.flatten.map(&:strip).reject {|x| comment_in_chart?(x)})
    harp_holes = Set.new($harp.keys)
    raise ArgumentError.new("holes from chart is not the same set as holes from harp; missing in chart: #{harp_holes - chart_holes}, extra in chart: #{chart_holes - harp_holes}") if chart_holes != harp_holes
    
    chart_with_notes = []
    chart_with_scales = []
    # will be used in get chart with intervals
    $chart_with_holes_raw = chart_with_holes_raw
    $chart_cell_len = len
    # for given key: map from holes to notes or scales
    (0 ... chart_with_holes_raw.length).each do |row|
      chart_with_notes << []
      chart_with_scales << []
      (0 ... chart_with_holes_raw[row].length - 1).each do |col|
        hole_padded = chart_with_holes_raw[row][col]
        hole = hole_padded.strip
        chart_with_notes[row][col] =
          if comment_in_chart?(hole_padded)
            hole_padded[0,len]
          else
            note = $harp[hole][:note]
            raise ArgumentError.new("hole '#{hole}' maps to note '#{note}' which is longer than given length '#{len}'") if note.length > len
            hole2chart[hole] << [col, row]
            note.center(len)
          end
        chart_with_scales[row][col] =
          if comment_in_chart?(hole_padded)
            hole_padded[0,len]
          else
            abbrevs = $hole2scale_abbrevs[hole]
            abbrevs = '-' if abbrevs == ''
            raise ArgumentError.new("hole '#{hole}' maps to scale abbreviations '#{abbrevs}' which are longer than given length '#{len}'") if abbrevs.length > len
            abbrevs.center(len)
          end
      end
      chart_with_notes[row] << chart_with_holes_raw[row][-1]
      chart_with_scales[row] << chart_with_holes_raw[row][-1]
    end

  rescue ArgumentError => e
    fail "Internal error with #{$chart_file}: #{e}"
  end

  [ {chart_notes: chart_with_notes,
     chart_scales: chart_with_scales,
     chart_intervals: nil},
    hole2chart ]
  
end


def get_chart_with_intervals
  err "Internal error: reference hole is not set" unless $hole_ref
  len = $chart_cell_len
  chart_with_holes_raw = $chart_with_holes_raw
  chart_with_intervals = []
  (0 ... chart_with_holes_raw.length).each do |row|
    chart_with_intervals << []
    (0 ... chart_with_holes_raw[row].length - 1).each do |col|
      hole_padded = chart_with_holes_raw[row][col]
      hole = hole_padded.strip
      chart_with_intervals[row][col] =
        if comment_in_chart?(hole_padded)
          hole_padded[0,len]
        else
          isemi ,_ ,itext, dsemi = describe_inter(hole, $hole_ref)
          idesc = itext || isemi
          idesc.gsub!(' ','')
          idesc = 'REF' if dsemi == 0
          raise ArgumentError.new("hole '#{hole}' maps to interval description '#{idesc}' which is longer than given length '#{len}'") if idesc.length > len
          idesc.center(len)
        end
    end
    chart_with_intervals[row] << chart_with_holes_raw[row][-1]
  end
  chart_with_intervals
end


def read_calibration
  err "Frequency file #{$freq_file} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?($freq_file)
  hole2freq = yaml_parse($freq_file)
  unless Set.new($harp_holes).subset?(Set.new(hole2freq.keys))
    err "There are more holes in #{$holes_file} #{$harp_holes} than in #{$freq_file} #{hole2freq.keys}. Missing in #{$freq_file} are holes #{(Set.new($harp_holes) - Set.new(hole2freq.keys)).to_a}. Probably you need to redo the calibration and play the missing holes"
  end
  unless Set.new(hole2freq.keys).subset?(Set.new($harp_holes))
    err "There are more holes in #{$freq_file} #{hole2freq.keys} than in #{$holes_file} #{$harp_holes}. Extra in #{$freq_file} are holes #{(Set.new(hole2freq.keys) - Set.new($harp_holes)).to_a.join(' ')}. Probably you need to remove the frequency file #{$freq_file} and redo the calibration to rebuild the file properly"
  end
  unless $harp_holes.map {|hole| hole2freq[hole]}.each_cons(2).all? { |a, b| a < b }
    err "Frequencies in #{$freq_file} are not strictly ascending in order of #{$harp_holes.inspect}: #{hole2freq.pretty_inspect}"
  end

  hole2freq.map {|k,v| $harp[k][:freq] = v}

  $harp_holes.each do |hole|
    file = this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
    err "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)
  end

  freq2hole = $harp_holes.map {|h| [$harp[h][:freq], h]}.to_h

  freq2hole

end
