import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status", "button"]

  connect() {
    this.buttonTarget.hidden = false
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())
      this.statusTarget.textContent = "Команда скопирована"
    } catch {
      this.statusTarget.textContent = "Не удалось скопировать. Выделите команду и скопируйте вручную."
    }
  }
}
