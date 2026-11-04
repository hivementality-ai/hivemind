import { Controller } from "@hotwired/stimulus"

// Chat-header dropdown: "Agent default" plus every enabled provider's models.
// Saves the choice to the session as { provider_config_id, llm_model }.
export default class extends Controller {
  static targets = ["select"]
  static values = {
    modelsUrl: String,
    saveUrl: String,
    providers: Array,
    provider: String,
    model: String,
    csrf: String
  }

  connect() {
    this.loadModels()
  }

  async loadModels() {
    for (const provider of this.providersValue) {
      try {
        const response = await fetch(`${this.modelsUrlValue}?provider_config_id=${provider.id}`, {
          headers: { "Accept": "application/json" }
        })
        const data = await response.json()
        this.appendGroup(provider, data.models || [])
      } catch (e) {
        console.error("Failed to fetch models:", e)
      }
    }
  }

  appendGroup(provider, models) {
    if (models.length === 0) return

    const group = document.createElement("optgroup")
    group.label = provider.name
    models.forEach(model => {
      const opt = document.createElement("option")
      opt.value = `${provider.id}|${model.id}`
      opt.textContent = model.name
      if (String(provider.id) === this.providerValue && model.id === this.modelValue) opt.selected = true
      group.appendChild(opt)
    })
    this.selectTarget.appendChild(group)
  }

  async save() {
    const [providerId, ...rest] = this.selectTarget.value.split("|")
    const body = this.selectTarget.value
      ? { provider_config_id: providerId, llm_model: rest.join("|") }
      : { provider_config_id: null, llm_model: null }

    try {
      await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
        body: JSON.stringify(body)
      })
    } catch (e) {
      console.error("Failed to save model:", e)
    }
  }
}
