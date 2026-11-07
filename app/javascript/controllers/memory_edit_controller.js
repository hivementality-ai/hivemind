import { Controller } from "@hotwired/stimulus"

// Swaps a memory between its read-only text and an inline edit form.
export default class extends Controller {
  static targets = ["display", "form", "field"]

  edit() {
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.formTarget.classList.add("flex")
    this.fieldTarget.focus()
  }

  cancel() {
    this.formTarget.classList.add("hidden")
    this.formTarget.classList.remove("flex")
    this.displayTarget.classList.remove("hidden")
  }
}
