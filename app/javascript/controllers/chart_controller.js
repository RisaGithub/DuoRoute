import { Controller } from "@hotwired/stimulus"
import "chart.js"

export default class extends Controller {
  static values = { labels: Array, target: Array, fact: Array, title: String }

  connect() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.chart = new window.Chart(this.element, {
      type: "bar",
      data: {
        labels: this.labelsValue,
        datasets: [
          { label: "Цель", data: this.targetValue, backgroundColor: "rgba(113, 128, 255, .28)", borderColor: "#7180ff", borderWidth: 1 },
          { label: "Факт", data: this.factValue, backgroundColor: "rgba(45, 212, 191, .72)", borderColor: "#2dd4bf", borderWidth: 1 }
        ]
      },
      options: {
        animation: reduce ? false : { duration: 350 }, responsive: true, maintainAspectRatio: false,
        plugins: { legend: { labels: { color: "#a8afc2" } }, title: { display: false } },
        scales: { x: { ticks: { color: "#8891a7" }, grid: { display: false } },
          y: { beginAtZero: true, ticks: { color: "#8891a7", callback: value => `${value}%` }, grid: { color: "rgba(255,255,255,.06)" } } }
      }
    })
  }

  disconnect() { this.chart?.destroy() }
}
