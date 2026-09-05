import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["bar", "label", "event", "error"]

  connect() {
    if (this.element.dataset.terminal === "true") return
    this.poll()
  }

  disconnect() { clearTimeout(this.timer) }

  async poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      this.barTarget.style.width = `${data.progress_pct}%`
      this.barTarget.setAttribute("aria-valuenow", data.progress_pct)
      this.labelTarget.textContent = `${data.processed}/${data.total} · ${data.progress_pct}% · ${data.elapsed_seconds} с`
      this.eventTarget.textContent = data.last_event || "Ожидание"
      if (data.status === "completed") window.location.reload()
      else if (data.status === "failed") {
        this.errorTarget.textContent = data.error
        this.errorTarget.hidden = false
      } else this.timer = setTimeout(() => this.poll(), 700)
    } catch (error) {
      this.eventTarget.textContent = "Связь восстанавливается…"
      this.timer = setTimeout(() => this.poll(), 1500)
    }
  }
}
