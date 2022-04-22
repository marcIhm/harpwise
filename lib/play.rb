#
# Play from the commandline
#

def do_play
  holes = if $scale_holes
            $scale_holes
          else
            ARGV.map do |hon|
              if $harp_holes.include?(hon)
                hon
              elsif $harp_notes.include?(hon)
                $note2hole[hon]
              else
                err "Argument '#{hon}' is not part of harp holes #{$harp_holes} or notes #{$harp_notes}" unless $harp_holes.include?(hon)
              end
            end
          end
  lhn = holes.max_by(&:length)
  holes.each_with_index do |hole, i|
    if i > 0
      semi, text = describe_inter(holes[i-1], hole)
      puts "  " + ( text || semi)
    end
    puts "%-#{lhn.length}s   %s" % [hole, $harp[hole][:note]]
    play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note])
  end
end


