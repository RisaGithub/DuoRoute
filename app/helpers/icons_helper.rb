module IconsHelper
  ICON_PATHS = {
    "dashboard" => [ "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z" ],
    "providers" => [ "M4 3h16v6H4z M4 15h16v6H4z M7 6h.01 M7 18h.01 M12 9v6" ],
    "runs" => [ "M5 3h14v18H5z M8 7h8 M8 11h8 M8 15h5" ],
    "strategy" => [ "M4 4h4v4H4z M16 16h4v4h-4z M16 4h4v4h-4z M8 6h8 M6 8v10h10" ],
    "generate" => [ "M12 3v4 M12 17v4 M3 12h4 M17 12h4 M5.6 5.6l2.8 2.8 M15.6 15.6l2.8 2.8 M5.6 18.4l2.8-2.8 M15.6 8.4l2.8-2.8", "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8" ],
    "play" => [ "M8 4l12 8-12 8z" ],
    "plus" => [ "M12 5v14 M5 12h14" ],
    "check" => [ "M20 6L9 17l-5-5" ],
    "copy" => [ "M9 9h12v12H9z M15 9V3H3v12h6" ],
    "clock" => [ "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M12 7v5l3 2" ],
    "fallback" => [ "M5 4v10a4 4 0 0 0 4 4h10 M15 14l4 4-4 4 M5 8h10a4 4 0 0 0 4-4" ],
    "chart" => [ "M4 3v17h17 M8 15V9 M13 15V5 M18 15v-4" ],
    "wallet" => [ "M4 6V4h14v3 M3 7h18v13H3z M16 11h5v5h-5z" ],
    "alert" => [ "M12 3L2 21h20z M12 9v5 M12 17h.01" ],
    "settings" => [ "M4 6h16 M4 12h16 M4 18h16 M8 3v6 M16 9v6 M10 15v6" ],
    "download" => [ "M12 3v12 M7 10l5 5 5-5 M4 15v6h16v-6" ],
    "upload" => [ "M12 16V4 M7 9l5-5 5 5 M4 15v6h16v-6" ],
    "file" => [ "M5 3h9l5 5v13H5z M14 3v6h5 M8 13h8 M8 17h5" ],
    "code" => [ "M8 6l-6 6 6 6 M16 6l6 6-6 6 M14 3l-4 18" ],
    "shield" => [ "M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6z M8 12l3 3 5-6" ],
    "bulb" => [ "M9 18h6 M9 21h6 M9 15c0-2-4-3-4-7a7 7 0 0 1 14 0c0 4-4 5-4 7" ],
    "compare" => [ "M4 7h16 M16 3l4 4-4 4 M20 17H4 M8 13l-4 4 4 4" ],
    "eye" => [ "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z", "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6" ],
    "save" => [ "M4 3h13l4 4v14H3V3z M7 3v6h9V3 M7 21v-8h10v8" ],
    "restore" => [ "M3 4v6h6 M3 10a9 9 0 1 1 1 8" ],
    "arrow" => [ "M4 12h16 M14 6l6 6-6 6" ],
    "close" => [ "M6 6l12 12 M6 18L18 6" ],
    "info" => [ "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M12 11v6 M12 7h.01" ],
    "count" => [ "M4 5h3v3H4z M11 6h9 M4 11h3v3H4z M11 12h9 M4 17h3v3H4z M11 18h9" ],
    "activity" => [ "M2 12h5l3-8 4 16 3-8h5" ],
    "hash" => [ "M9 3L7 21 M17 3l-2 18 M4 8h17 M3 16h17" ]
  }.freeze

  def ui_icon(name)
    tag.svg(viewBox: "0 0 24 24", width: 18, height: 18, fill: "none", stroke: "currentColor",
      "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round", class: "ui-icon",
      aria: { hidden: true }, focusable: "false") do
      safe_join(ICON_PATHS.fetch(name.to_s, ICON_PATHS.fetch("info")).map { |path| tag.path(d: path) })
    end
  end

  def icon_label(label, icon = nil)
    tag.span(class: "icon-label") do
      safe_join([ ui_icon(icon || label_icon(label)), tag.span(label, class: "icon-label__text") ])
    end
  end

  def section_icon
    { "dashboard" => "dashboard", "providers" => "providers", "routing_runs" => "runs",
      "strategies" => "strategy", "generators" => "generate" }.fetch(controller_name, "dashboard")
  end

  def label_icon(label)
    return "close" if %w[inactive disabled rejected failed blocked].include?(label.to_s)
    case label.to_s.downcase
    when /скач|download|bundle|decisions json|report json|manifest/ then "download"
    when /новый|первый|использовать/ then "plus"
    when /сравн|компромисс|конфликт|state/ then "compare"
    when /запуст|маршрутизац/ then "play"
    when /сохран/ then "save"
    when /восстанов/ then "restore"
    when /preview|обзор/ then "eye"
    when /approval|success|conversion|approved|completed|active|успеш|selected|eligible/ then "check"
    when /reject|failed|blocked/ then "close"
    when /latency|expired|timeout|истор|history|running|queued/ then "clock"
    when /fallback|каскад|cascade/ then "fallback"
    when /рекоменд/ then "bulb"
    when /огранич|воспроизвод|hard/ then "shield"
    when /исключ|отклон|останов|ошиб/ then "alert"
    when /сумм|объем|объём|volume|оборот|turnover|марж/ then "wallet"
    when /провайдер|provider/ then "providers"
    when /операц|operation|колич|count|решени/ then "count"
    when /capacity|интенсив|intensity|загруз/ then "activity"
    when /seed|sha|hash/ then "hash"
    when /стратег|strateg|polic|фактор/ then "strategy"
    when /файл|данные|json|csv|outcomes/ then "file"
    when /config|параметр|настро|вес|выбор/ then "settings"
    when /запуск|runs/ then "runs"
    else "info"
    end
  end
end
