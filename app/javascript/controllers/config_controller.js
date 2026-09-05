import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["weight", "sum", "warning", "config", "settings", "preset", "description"]
  static values = { catalog: Object, modes: Object }

  strategy(event) {
    const entry = this.catalogValue[event.target.value] || this.modesValue[event.target.value]
    if (!entry) return
    this.weightTargets.forEach(input => {
      const key = input.name.match(/\[(.+)\]/)[1]
      input.value = entry.weights[key] || 0
    })
    this.describe()
    this.normalize()
    this.settingsTarget.value = Object.entries(entry.parameters.provider_overrides || {}).flatMap(([name, values]) => Object.entries(values).map(([key, value]) => `provider_overrides.${name}.${key}=${JSON.stringify(value)}`)).join("\n")
  }

  connect() { this.normalize(); this.describe() }

  describe() {
    if (!this.hasDescriptionTarget || !this.hasPresetTarget) return
    this.descriptionTarget.textContent = this.catalogValue[this.presetTarget.value]?.description || (this.presetTarget.value === "balanced" ? "Комбинация факторов: распределение, конверсия и ограничения провайдеров. Подходит для первого запуска." : "Задайте собственную конфигурацию в расширенных параметрах или загрузите файл настроек.")
  }

  normalize() {
    const sum = this.weightTargets.reduce((total, input) => total + Number(input.value || 0), 0)
    if (this.hasSumTarget) this.sumTarget.textContent = sum.toFixed(1)
    if (this.hasWarningTarget) this.warningTarget.hidden = sum > 0
  }

  download() {
    const blob = new Blob([this.configTarget.value], { type: "application/yaml;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = "duoroute-routing.yml"
    link.click()
    URL.revokeObjectURL(url)
  }
}
