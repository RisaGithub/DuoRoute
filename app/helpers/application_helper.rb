module ApplicationHelper
  def navigation_link(label, path, controllers:)
    active = Array(controllers).include?(controller_name)
    options = { class: class_names("nav__link", "nav__link--active": active) }
    options[:aria] = { current: "page" } if active
    link_to label, path, options
  end

  def money(value)
    number_to_currency(value.to_f, unit: "₽", precision: value.to_f == value.to_i ? 0 : 2, format: "%n %u", delimiter: " ")
  end

  def pct(value)
    value.nil? ? "—" : "#{number_with_precision(value, precision: 1, strip_insignificant_zeros: true)}%"
  end

  def status_class(status)
    { "completed" => "ok", "running" => "info", "queued" => "muted", "failed" => "fail",
      "active" => "ok", "approved" => "ok", "rejected" => "fail", "expired" => "warn" }.fetch(status.to_s, "muted")
  end

  def masked_phone(operation)
    phone = operation.dig("payout_requisite", "sbp", "phone").to_s
    phone.length >= 4 ? "+7 ••• •••-#{phone[-4, 2]}-#{phone[-2, 2]}" : "—"
  end
end
