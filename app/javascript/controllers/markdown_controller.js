import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import DOMPurify from "dompurify"

// ponytail: thin wrapper so static pages can render markdown without a full chat controller
export default class extends Controller {
  static values = { content: String }

  connect() {
    if (!this.contentValue) return
    this.element.innerHTML = DOMPurify.sanitize(marked.parse(this.contentValue))
  }
}
