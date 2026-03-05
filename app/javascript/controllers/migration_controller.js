import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "spinner", "buttonText"]

  validate() {
    const value = this.inputTarget.value.trim()
    this.submitTarget.disabled = value.length === 0
  }

  submit() {
    this.submitTarget.disabled = true
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")
    if (this.hasButtonTextTarget) this.buttonTextTarget.textContent = "Scanning..."
  }
}
