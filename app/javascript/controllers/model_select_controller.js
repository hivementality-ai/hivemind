import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["provider", "model"]
  static values = { url: String, current: String }

  connect() {
    // Load models for current provider on page load
    this.loadModels()
  }

  providerChanged() {
    this.loadModels()
  }

  async loadModels() {
    const provider = this.providerTarget.value
    if (!provider) return

    try {
      const response = await fetch(`${this.urlValue}?provider=${provider}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.updateModelSelect(data.models, provider)
    } catch (e) {
      console.error("Failed to fetch models:", e)
    }
  }

  updateModelSelect(models, provider) {
    const select = this.modelTarget
    const currentValue = this.currentValue || select.value

    select.innerHTML = ""

    if (models.length === 0) {
      const opt = document.createElement("option")
      opt.value = ""
      opt.textContent = provider === "ollama"
        ? "No models found — is Ollama running?"
        : "No models available"
      select.appendChild(opt)
      return
    }

    models.forEach(model => {
      const opt = document.createElement("option")
      opt.value = model.id
      opt.textContent = model.name
      if (model.id === currentValue) opt.selected = true
      select.appendChild(opt)
    })
  }
}
