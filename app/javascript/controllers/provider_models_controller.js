import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="provider-models"
export default class extends Controller {
  static targets = ["keyInput", "modelList", "section"]

  connect() {
    // Show model lists for any pre-filled keys
    this.keyInputTargets.forEach((input) => this.updateVisibility(input))
  }

  toggleModels(event) {
    this.updateVisibility(event.currentTarget)
  }

  updateVisibility(input) {
    const section = input.closest("[data-provider]")
    const provider = section.dataset.provider
    const modelList = this.modelListTargets.find(
      (el) => el.dataset.provider === provider
    )

    if (modelList) {
      if (input.value.trim().length > 0) {
        modelList.classList.remove("hidden")
      } else {
        modelList.classList.add("hidden")
      }
    }
  }
}
