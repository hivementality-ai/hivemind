import { Controller } from "@hotwired/stimulus"

// Runs an integration's connection test and shows the result next to the button.
export default class extends Controller {
  static targets = ["status"]
  static values = { url: String, kind: String }

  async run() {
    this.show("Testing...", "text-text-muted")
    try {
      const response = await fetch(this.urlValue)
      const data = await response.json()
      if (data.status === "connected") {
        this.show(`Connected: ${this.describe(data)}`, "text-green-400")
      } else {
        this.show(data.message || "Connection failed", "text-red-400")
      }
    } catch (_error) {
      this.show("Connection failed", "text-red-400")
    }
  }

  describe(data) {
    if (this.kindValue === "search") return `${data.provider} returned ${data.results} results`
    if (this.kindValue === "trello") return `${data.user} (@${data.username})`
    return `${data.user} (${data.name})`
  }

  show(text, colorClass) {
    this.statusTarget.textContent = text
    this.statusTarget.className = `text-sm ${colorClass}`
  }
}
