#
# Play from the commandline
#

def do_play
  holes = if $scale_holes
            $scale_holes
          else
            ARGV.each {|h| err "Hole '#{h}' is not part of harp #{$harp_holes}" unless $harp_holes.include?(h)}
            ARGV
          end
  lhn = holes.max_by(&:length)
  holes.each do |hole|
    puts "%-#{lhn.length}s   %s" % [hole, $harp[hole][:note]]
    play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
  end
end


