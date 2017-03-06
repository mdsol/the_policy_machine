require 'set'

class Warn

  @displayed_warnings = Set.new

  def self.once(string, *interpolated_values)
    if @displayed_warnings.add?(string)
      string %= interpolated_values if interpolated_values.any?
      warn(string)
    end
  end

end
