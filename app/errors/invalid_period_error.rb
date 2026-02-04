# frozen_string_literal: true

class InvalidPeriodError < StandardError
  attr_reader :period_string

  def initialize(message = nil, period_string: nil)
    @period_string = period_string
    super(message)
  end
end
