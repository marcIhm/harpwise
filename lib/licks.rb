#
# Handling of licks
#


def read_licks

  FileUtils.mkdir_p($lick_dir) unless File.directory?($lick_dir)
  FileUtils.mkdir_p($lick_dir + '/recordings') unless File.directory?($lick_dir + '/recordings')

  glob = $lick_file_template % '{holes,notes}'
  lfiles = Dir[glob]
  err "There are two files matching #{glob}; please check and remove one" if lfiles.length > 1
  if lfiles.length == 0
    lfile = $lick_file_template % 'holes'
    create_initial_lick_file lfile
  else
    lfile = lfiles[0]
  end

  section = ''
  i = 0
  all_licks = []
  File.foreach(lfile) do |line|
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    
    if md = line.match(/^ *\[(.*)\] *$/)
      section = md[1].strip
      next
    end

    i += 1
    lick, remark, recording, start = if md = line.match(/^(.*):(.*),(.*),(.*)$/)
                                       md[1..4]
                                     elsif  md = line.match(/^(.*):(.*),(.*)$/)
                                       [md[1],md[2],md[3],'']
                                     elsif md = line.match(/^(.*):(.*)$/)
                                       [md[1],md[2],'','']
                                     else
                                       [line,"Nr.#{i}",'','']
                                     end

    lick.strip!
    remark.strip!
    recording.strip!
    start = start.strip.to_i
    next if lick.length == 0
    holes = lick.split.map do |hon|
      if lfile['holes']
        err("Hole #{hon} from #{lfile} is not among holes of harp #{$harp_holes}") unless $harp_holes.include?(hon)
        hon
      else
        # lick with notes
        err("Note #{hon} from #{lfile} is not among notes of harp #{$harp_notes}") unless $harp_notes.include?(hon)
        $note2hole[hon]
      end
    end
    rfile = $lick_dir + '/recordings/' + recording
    err("Recording  #{rfile} not found") unless File.exists?(rfile)
    all_licks << {section: section, remark: remark, holes: holes, recording: recording, start: start}
  end

  err("No licks found in #{lfile}") unless all_licks.length > 0

  write_derived_lick_file all_licks, lfile
  
  err "No licks in #{lfile}" if all_licks.length == 0
  if all_licks.length <= 2
    puts "\nThere are only #{all_licks.length} licks in\n\n  #{lfile}\n\n"
    puts "memorizing them may become boring soon !"
    puts "\nBut continue anyway ...\n\n"
    sleep 2
  end

  # keep only those licks, that match argument --section
  discard, keep = ($opts[:sections] || '').split(',').partition {|s| s.start_with?('no-') || s.start_with?('not-')}
  discard.map! {|s| s.start_with?('no-')  ?  s[3 .. -1]  :  s[4 .. -1]}
  sects_in_opt = Set.new(discard + keep)
  sects_in_licks = Set.new(all_licks.map {|l| l[:section]})
  err("There are some sections in option '--sections' #{sects_in_opt.to_a} which are not in lick file #{lfile} #{sects_in_licks.to_a}; unknown in '--sections' are: #{(sects_in_opt - sects_in_licks).to_a}") unless sects_in_opt.subset?(sects_in_licks)
      
  licks = all_licks.
            select {|lick| keep.length == 0 || keep.include?(lick[:section])}.
            select {|lick| !discard.include?(lick[:section])}.
            uniq {|lick| lick[:holes]}

  
  err("None of the #{all_licks}.length from #{lfile} has been passed when applying option '--sections #{$opts[:sections]}") if licks.length == 0

  licks
end


def create_initial_lick_file lfile
  puts "\nLick file\n\n  #{lfile}\n\ndoes not exist !"
  puts "\nCreating it with a single sample lick (and comments);"
  puts "however, you need to add more licks yourself,"
  puts "to make this mode (memorize) really useful."
  puts
  File.open(lfile, 'w') do |f|
    f.write <<~end_of_content
        #
        # Library of licks used in modes memorize or play
        #
        #
        # One lick per line; empty lines and comments are ignored.
        # A lick can optionally be followed by a single colon (':')
        # and a remark, that the program will show, while playing this
        # lick; this helps to find the lick within the file.
        # You are free to keep duplicates of a lick in multiple
        # sections.
        #
        # After colon and remark you may opionally add a comma and the
        # name of an mp3-file, that can be played on request; it will
        # be searched in subdir 'samples'; with another comma and a number
        # you may specify the start to play from.
        #
        # Sections (e.g. '[scales]' below) help to select groups of
        # licks with the option '--sections'. 
        #
        # Initially ths file is populated with sample licks for
        # richter harp; they may not work for other harps however.
        #
        # You will need to add your own licks before this file before
        # the feature memorize can be useful.
        #
        #
        # A great source of licks is the book:
        #
        #    100 Authentic Blues Harmonica Licks
        #
        # by Steve Cohen.
        #

        [favorites]
        # Intro lick from Juke
        -1 -2/ -3// -3 -4  +4 -3 -3// -3 -2// -2/ -1 -1   : juke
        
        [scales]
        +1 -1/ -1 -2// -2+3 -3/ +4 -4/ -4 -5 +6 -6/ -6 +7 -8 -9 +9 -10   : blues
        -1 +2 -2+3 -3// -3 -4 +5 +6 -6 -7 -8 +8 +9   : mape

        end_of_content
    if $opts[:testing]
      f.write <<~end_of_content

        [testing]
        +1 +1 -1   : one
        +1 +1 -1 +1   : two
        +1 +1 -1   : three

        end_of_content
    end
  end
  puts "Now you may try again with a single predefined lick ..."
  puts "...and then add some of your own !\n\n"
end


def write_derived_lick_file licks, lfile
  dfile = File.dirname(lfile) + '/derived_' + File.basename(lfile).sub(/holes|notes/, lfile['holes'] ? 'notes' : 'holes')

  File.open(dfile,'w') do |df|
    licks.each do
      df.write <<~end_of_content

           #
           # derived lick file with #{dfile['holes'] ? 'holes' : 'notes'}
           # created from #{lfile}
           #
           
           end_of_content

      current_section = ''

      licks.each do |lick|

        if lick[:section].length > 0 && lick[:section] != current_section
          current_section = lick[:section]
          df.puts "\n[#{lick[:section]}]"
        end

        if dfile['holes']
          df.write lick[:holes].join(' ')
        else
          df.write lick[:holes].map {|h| $harp[h][:note]}.select(&:itself).join(' ')
        end

        df.puts '   : ' + lick[:remark] + ( lick[:recording].length > 0  ?  ",#{lick[:recording]},#{lick[:start]}"  :  '' )
      end
    end
  end 
end
