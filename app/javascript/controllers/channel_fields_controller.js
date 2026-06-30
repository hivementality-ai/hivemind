import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["discord", "slack", "telegram", "whatsapp", "signal", "matrix", "email", "feishu", "none"]
  static values = { type: String }

  connect() {
    this.showFields(this.typeValue)

    // Listen for channel_type dropdown changes
    const select = this.element.closest("form")?.querySelector("select[name='channel[channel_type]']")
    if (select) {
      select.addEventListener("change", (e) => this.showFields(e.target.value))
    }
  }

  showFields(type) {
    const platforms = ["discord", "slack", "telegram", "whatsapp", "signal", "matrix", "email", "feishu"]

    // Hide all
    platforms.forEach(p => {
      if (this[`has${this.capitalize(p)}Target`]) {
        this[`${p}Target`].style.display = "none"
      }
    })

    if (this.hasNoneTarget) {
      this.noneTarget.style.display = type ? "none" : "block"
    }

    // Show selected
    if (type && platforms.includes(type)) {
      const target = `${type}Target`
      if (this[`has${this.capitalize(type)}Target`]) {
        this[target].style.display = "block"
      }
    }
  }

  capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1)
  }
}
