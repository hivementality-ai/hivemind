import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "rulesSection"]

  connect() {
    this.toggleRules()
  }

  modeChanged() {
    this.toggleRules()
  }

  toggleRules() {
    const mode = this.modeTarget.value
    const show = mode === "allowlist" || mode === "blocklist"
    this.rulesSectionTarget.style.display = show ? "block" : "none"
  }
}
