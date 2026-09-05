import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "title", "body", "status", "pre", "content"]
  static values = { url: String }

  async open() {
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    this.contentTarget.textContent = ""
    this.preTarget.hidden = true
    this.statusTarget.hidden = false
    this.statusTarget.textContent = "Загрузка файла…"
    this.bodyTarget.setAttribute("aria-busy", "true")
    this.dialogTarget.showModal()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" }, signal: request.signal
      })
      if (!response.ok) throw new Error("Preview failed")
      const file = await response.json()
      if (request.signal.aborted) return
      this.titleTarget.textContent = file.filename
      this.contentTarget.textContent = file.content
      this.preTarget.hidden = !file.content
      this.statusTarget.hidden = !!file.content
      this.statusTarget.textContent = "Файл пуст или ещё не сформирован."
    } catch (error) {
      if (error.name !== "AbortError") {
        this.statusTarget.textContent = "Не удалось загрузить файл. Закройте предпросмотр и попробуйте ещё раз."
      }
    } finally {
      if (this.request === request) this.bodyTarget.setAttribute("aria-busy", "false")
    }
  }

  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const rect = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.close()
  }

  close() {
    this.cleanup()
    this.dialogTarget.close()
  }

  cleanup() {
    this.request?.abort()
  }

  disconnect() {
    this.close()
  }
}
