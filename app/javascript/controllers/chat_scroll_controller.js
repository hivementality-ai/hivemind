import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.scrollToBottom()
  }

  scrollToBottom() {
    const container = this.containerTarget
    container.scrollTop = container.scrollHeight
  }
}
