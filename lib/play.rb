#
# Play from the commandline
#

def do_play
  $licks = read_licks
  holes = ARGV.map do |hnl|
    if $harp_holes.include?(hnl)
      hnl
    elsif $harp_notes.include?(hnl)
      $note2hole[hnl]
    else
      lick = $licks.find {|l| l[:remark] == hnl}
      err "Argument '#{hnl}' is not part of harp holes #{$harp_holes} or notes #{$harp_notes} or licks #{$licks.map {|l| l[:remark]}.select {|r| r.length > 0}.uniq}" unless lick
      lick[:holes]
    end
  end.flatten

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


