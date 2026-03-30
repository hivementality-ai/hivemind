import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["category", "counter"]

  toggleCategory(event) {
    const btn = event.currentTarget
    const categoryEl = btn.closest("[data-tool-select-target='category']")
    if (!categoryEl) return

    const checkboxes = categoryEl.querySelectorAll("input[type='checkbox']")
    const allChecked = Array.from(checkboxes).every(cb => cb.checked)

    checkboxes.forEach(cb => cb.checked = !allChecked)
    this.updateCounter()
  }

  updateCounter() {
    if (!this.hasCounterTarget) return
    const all = this.element.querySelectorAll("input[type='checkbox'][name='agent[tool_ids][]']")
    const checked = Array.from(all).filter(cb => cb.checked)
    this.counterTarget.textContent = checked.length > 0 ? `${checked.length} selected` : "none (all tools granted)"
  }

  connect() {
    this.updateCounter()
  }
}
