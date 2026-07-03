import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

// ponytail: thin wrapper so static pages can render markdown without a full chat controller
export default class extends Controller {
  static values = { content: String }

  connect() {
    if (!this.contentValue) return
    const raw = marked.parse(this.contentValue)
    // Basic XSS sanitization — same approach as chat_controller
    this.element.innerHTML = raw
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "")
      .replace(/\son\w+\s*=/gi, " data-blocked=")
  }
}
