import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["weight", "sum", "warning", "config"]

  connect() { this.normalize() }

  normalize() {
    const sum = this.weightTargets.reduce((total, input) => total + Number(input.value || 0), 0)
    if (this.hasSumTarget) this.sumTarget.textContent = sum.toFixed(1)
    if (this.hasWarningTarget) this.warningTarget.hidden = sum > 0
  }

  save(event) {
    localStorage.setItem("duoroute-routing-config", this.configTarget.value)
    event.currentTarget.textContent = "Сохранено"
  }

  restore() {
    const value = localStorage.getItem("duoroute-routing-config")
    if (value) this.configTarget.value = value
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
