import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "spinner", "sort"]

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.performSearch(), 300)
  }

  performSearch() {
    const query = this.inputTarget.value.trim()
    const sort = this.hasSortTarget ? this.sortTarget.value : "trending"
    const params = new URLSearchParams()

    if (query) {
      params.set("q", query)
    } else {
      params.set("sort", sort)
    }

    const url = `/clawhub?${params.toString()}`

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }

    const frame = document.querySelector("turbo-frame#clawhub_results")
    if (frame) {
      frame.src = url
      frame.addEventListener("turbo:frame-load", () => {
        if (this.hasSpinnerTarget) {
          this.spinnerTarget.classList.add("hidden")
        }
      }, { once: true })
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
