#
#  Non-interactive tools
#

def do_tools to_handle

  tools_allowed = %w(positions transpose)
  tool = match_or(to_handle.shift, tools_allowed) do |none, choices|
    err "Argument for mode 'tools' must be one of #{choices}, no #{none}; #{$for_usage}"
  end

  case tool
  when 'positions'
    tool_positions
  when 'transpose'
    tool_transpose to_handle
  else
    err "Unknown tool '#{tool}'; #{$for_usage}"
  end

end


def tool_positions
puts <<EOCHART

  | Key of Song  |              |              |              |
  | or Key       | Key of Harp  | Key of Harp  | Key of Harp  |
  | of Harp in   | 2nd Position | 3rd Position | 4th Position |
  | 1st Position |              |              |              |
  |--------------+--------------+--------------+--------------|
  | G            | C            | F            | Bf           |
  |--------------+--------------+--------------+--------------|
  | Af           | Df           | Fs           | B            |
  |--------------+--------------+--------------+--------------|
  | A            | D            | G            | C            |
  |--------------+--------------+--------------+--------------|
  | Bf           | Ef           | Af           | Cs           |
  |--------------+--------------+--------------+--------------|
  | B            | E            | A            | D            |
  |--------------+--------------+--------------+--------------|
  | C            | F            | Bf           | Ef           |
  |--------------+--------------+--------------+--------------|
  | Cs           | Fs           | B            | E            |
  |--------------+--------------+--------------+--------------|
  | D            | G            | C            | F            |
  |--------------+--------------+--------------+--------------|
  | Ef           | Af           | Cs           | Fs           |
  |--------------+--------------+--------------+--------------|
  | E            | A            | D            | G            |
  |--------------+--------------+--------------+--------------|
  | F            | Bf           | Ef           | Af           |
  |--------------+--------------+--------------+--------------|
  | Fs           | B            | E            | A            |

EOCHART
end


def tool_transpose to_handle
  err "Need at least two additional arguments: a second key and at least one hole (e.g. 'g -1'); #{to_handle.inspect} is not enough" unless to_handle.length > 1
  key_other = to_handle.shift
  err "Second key given '#{key_other}' is invalid" unless $conf[:all_keys].include?(key_other)
  to_handle.each do |hole|
    err "Argument '#{hole}' is not a hole of a #{$type}-harp" unless $harp_holes.include?(hole)
  end

  dsemi = diff_semitones($key, key_other, :g_is_lowest)
  puts
  puts "The distance between keys #{$key} and #{key_other} is #{-dsemi} semitones."
  puts
  print <<EOHEAD
  | Hole for the Key of #{$key}
  |        | Note for this key
  |        |        | Hole for the Key of #{key_other}
  |        |        |        | One Octave up
  |        |        |        |        | One Octave down
EOHEAD
  template = '  | %6s | %6s | %6s | %6s | %6s |'
  hline = '  |' + '-' * ( (template % Array.new(5)).length - 4 ) + '|'
  to_handle.each do |hole|
    puts hline
    puts template % [hole,
                     $harp[hole][:note],
                     [0, -12, +12].map do |shift|
                       $semi2hole[$harp[hole][:semi] + dsemi + shift] || '*'
                     end].flatten
  end
  puts
  puts
end
