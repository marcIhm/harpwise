#
# Immediately related to sound
#

def record_sound secs, file, **opts
  duration_clause = secs < 1 ? "-s #{(secs.to_f * $sample_rate).to_i}" : "-d #{secs}"
  output_clause = (opts[:silent] && (!$opts[:debug] || $opts[:debug] <= 2)) ? '>/dev/null 2>&1' : ''
  system(dbg "arecord -r #{$sample_rate} #{duration_clause} #{file} #{output_clause}") or fail 'arecord failed'
end


def play_sound file
  system(dbg "aplay #{file} >/dev/null 2>&1") or fail 'aplay failed'
end


def run_aubiopitch file, extra = nil
  %x(aubiopitch --pitch mcomb #{file} 2>&1)
end
