module StrategiesHelper
  def strategy_parameter_label(key)
    {
      "traffic_percentage" => "Доля заявок, %", "volume_share_pct" => "Доля суммы, %",
      "priority" => "Порядок в очереди", "preferred_amount_min" => "Сумма от, ₽",
      "preferred_amount_max" => "Сумма до, ₽", "requests_per_minute_limit" => "Запросов в минуту",
      "daily_turnover_min" => "Минимальный оборот, ₽", "daily_turnover_max" => "Максимальный оборот, ₽"
    }.fetch(key)
  end
end
