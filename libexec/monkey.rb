# Some monkey-patching

class Symbol
  def o2str
    to_s.gsub('_', '-') if self
  end
end

class String
  def o2sym
    gsub('-', '_').to_sym if self
  end

  def o2sym2
    gsub('.', '_').to_sym if self
  end

  def to_b
    case self
    when 'true'
      true
    when 'false'
      false
    end
  end

  def empty2nil
    empty? ? nil : self
  end

  def underscore
    gsub(/::/, '/')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr('-', '_')
      .downcase
  end
end
