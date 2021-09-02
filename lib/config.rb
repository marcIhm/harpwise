#
# Set some global vars directly and read configuration for others
#

#
# Global vars, which are not assigned in main program
#

def check_installation
  # check for some required programs
  %w( acrecord aplay aubiopitch ).each do |prog|
    system("which #{prog} >/dev/null 2>&1") or err_b "Program '#{prog}' is needed but cannot be found; you may need to install its package"
  end
  
  if !File.exist?(File.basename($0))
    err_b "Please invoke this program from within its own directory (cannot find #{File.basename($0)} in current dir)"
  end
  FileUtils.mkdir_p($sample_dir) unless File.directory?($sample_dir)
end


def read_musical_config
  harps = JSON.parse(File.read('config/diatonic_harps.json')).transform_keys!(&:to_sym)
  unless Set.new(harps.values.map {|v| v.keys}).length == 1
    fail "Internal error, not all harps have the same list of holes"
  end
  harp = harps[$key] or fail "Internal error, key #{$key} has no harp"

  harp['high'] = {'note': 'high'}
  harp['low'] = {'note': 'low'}
  harp.each_value {|h| h.transform_keys!(&:to_sym)}

  scales_holes = JSON.parse(File.read('config/scales_holes.json')).transform_keys!(&:to_sym)
  scales_holes.each do |scale, holes|
    unless Set.new(holes).subset?(Set.new(harp.keys))
      fail "Internal error: Holes of scale #{scale} #{holes.inspect} is not a subset of holes of harp #{harp.keys.inspect}"
    end
  end

  holes = harp.keys.reject {|x| %w(low high).include?(x)}
  scale_holes = scales_holes[$scale]
  
  [ harp, holes, scale_holes ]
end


def read_calibration
  ffile = "#{$sample_dir}/frequencies.json"
  err_b "Frequency file #{ffile} does not exist, you need to calibrate for key of #{$key} first" unless File.exist?(ffile)
  freqs = JSON.parse(File.read(ffile))
  unless Set.new(freqs.keys) == Set.new($holes)
    err_b "Holes in #{ffile} #{freqs.keys.join(' ')} do not match those expected for scale #{$scale} #{$harp.keys.join(' ')}; maybe you need to redo the calibration"
  end

  freqs.map {|k,v| $harp[k][:freq] = v}
  $harp['low'][:freq] = $harp['+1'][:freq]/2
  $harp['high'][:freq] = $harp['+10'][:freq]*2

  $holes.each do |hole|
    file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
    err_b "Sample file #{file} does not exist; you need to calibrate" unless File.exist?(file)
  end

  freq2hole = $holes.map {|h| [$harp[h][:freq], h]}.to_h
  freqs = (%w(low high).map {|x| $harp[x][:freq]} + $holes.map {|h| $harp[h][:freq]}).sort

  [ freqs, freq2hole ]
end
