
module Theory
  extend self

  def musical_event? hole_or_note, type = :general
    has_paren = hole_or_note[0] == '(' && hole_or_note[-1] == ')'
    has_brack = hole_or_note[0] == '[' && hole_or_note[-1] == ']'
    has_head = ['.', '~'].include?(hole_or_note[0])
    is_comma = [',', ';'].include?(hole_or_note)
    case type
    when :general
      has_paren || has_brack || has_head || is_comma
    when :secs
      return false unless has_paren
      return false unless hole_or_note[-2] == 's'

      begin
        !!Float(hole_or_note[1..-3])
      rescue StandardError
        false
      end
    else
      err "Internal error: #{type}"
    end
  end

  def get_musical_duration hole_or_note
    duration = ( $opts[:fast] ? 0.5 : 1.0)
    return duration unless musical_event?(hole_or_note)
    return duration unless hole_or_note[-2..-1] == 's)'

    begin
      Float(hole_or_note[1..-3])
    rescue StandardError
      duration
    end
  end
  
  def file2scale file, type = $type
    $scale_files_templates.each do |template|
      %w[holes notes].each do |what|
        parts = (template % [type, '|', what]).split('|')
        return file[parts[0].length..- parts[1].length - 1] if file[parts[0]]
      end
    end
  end

  def scales_for_type type, check, builtin_only: false
    templates = if builtin_only
                  [$scale_files_templates[0]]
                else
                  $scale_files_templates
                end
    files = templates.map do |template|
      Dir[template % [type, '*', '{holes,notes}']]
    end.flatten
    return files.map {|file| file2scale(file, type)}.sort unless check

    scale2file = Hash.new
    files.each do |file|
      scale = file2scale(file, type)
      err "Duplicate scale   #{scale}   has already been defined in:\n#{scale2file[scale]}\ncannot redefine it in:\n#{file}"  if scale2file[scale]
      scale2file[scale] = file
    end
    [scale2file.keys.sort, scale2file]
  end

  def describe_scales_maybe scales, _type
    desc = Hash.new
    count = Hash.new
    scales.each do |scale|
      _, holes_rem = YAML.load_file($scale2file[scale]).partition {|x| x.is_a?(Hash)}
      holes = holes_rem.map {|hr| hr.split[0]}
      desc[scale] = "holes #{holes.join(',')}"
      count[scale] = holes.length
    rescue Errno::ENOENT, Psych::SyntaxError
    end
    [desc, count]
  end  

  def holes_equiv? h1, h2
    if h1.is_a?(String) && h2.is_a?(String)
      h1 == h2 || $harp[h1][:equiv].include?(h2)
    else
      false
    end
  end
end
