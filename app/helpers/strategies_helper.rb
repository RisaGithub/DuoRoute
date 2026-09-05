module StrategiesHelper
  def strategy_distribution_deviation(distribution)
    deviations = distribution.values.filter_map { |row| row["deviation_pp"] }
    deviations.empty? ? "цель не задана" : "#{deviations.sum(&:abs).round(1)} п.п."
  end

  def strategy_provider_description(provider)
    { "vipay" => "Основной поток", "payflow" => "Высокая конверсия", "quickpay" => "Быстрый ответ" }[provider]
  end

  def strategy_parameter_icon(key)
    { "traffic_percentage" => "count", "volume_share_pct" => "wallet", "priority" => "strategy",
      "preferred_amount_min" => "wallet", "preferred_amount_max" => "wallet",
      "requests_per_minute_limit" => "activity", "daily_turnover_min" => "chart",
      "daily_turnover_max" => "chart" }.fetch(key, "settings")
  end

  def strategy_parameter_label(key)
    {
      "traffic_percentage" => "Доля заявок, %", "volume_share_pct" => "Доля суммы, %",
      "priority" => "Порядок в очереди", "preferred_amount_min" => "Сумма от, ₽",
      "preferred_amount_max" => "Сумма до, ₽", "requests_per_minute_limit" => "Запросов в минуту",
      "daily_turnover_min" => "Минимальный оборот, ₽", "daily_turnover_max" => "Максимальный оборот, ₽"
    }.fetch(key)
  end
end
