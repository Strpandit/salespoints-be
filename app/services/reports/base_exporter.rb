module Reports
  class BaseExporter
    attr_reader :filters, :current_user, :scope

    def initialize(filters: {}, current_user: nil, scope: :vendor)
      @filters      = (filters || {}).with_indifferent_access
      @current_user = current_user
      @scope        = scope
    end

    def current_dealer_id
      current_user&.id
    end

    def date_range
      period = filters[:period].presence || "monthly"
      case period.to_s
      when "today"     then Time.current.beginning_of_day..Time.current.end_of_day
      when "yesterday" then 1.day.ago.beginning_of_day..1.day.ago.end_of_day
      when "weekly", "last_7_days" then 7.days.ago.beginning_of_day..Time.current.end_of_day
      when "last_30_days"         then 30.days.ago.beginning_of_day..Time.current.end_of_day
      when "quarterly" then 3.months.ago.beginning_of_day..Time.current.end_of_day
      when "yearly"    then 1.year.ago.beginning_of_day..Time.current.end_of_day
      when "custom"
        start_date = filters[:start_date].presence ? Time.zone.parse(filters[:start_date].to_s).beginning_of_day : 1.month.ago.beginning_of_day
        end_date   = filters[:end_date].presence   ? Time.zone.parse(filters[:end_date].to_s).end_of_day     : Time.current.end_of_day
        start_date..end_date
      else
        1.month.ago.beginning_of_day..Time.current.end_of_day
      end
    end

    def generate
      raise NotImplementedError, "#{self.class.name} must implement #generate"
    end
  end
end
