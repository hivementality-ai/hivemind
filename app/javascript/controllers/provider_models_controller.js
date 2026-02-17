import { Controller } from "@hotwired/stimulus"

const OLLAMA_DEFAULT_URL = "http://host.docker.internal:11434"

// Connects to data-controller="provider-models"
export default class extends Controller {
  static targets = ["keyInput", "modelList", "section", "ollamaToggle", "ollamaUrl", "ollamaEnabled", "ollamaCustomUrl"]

  connect() {
    // Show model lists for any pre-filled keys
    this.keyInputTargets.forEach((input) => this.updateVisibility(input))

    // Restore Ollama toggle state if URL was previously set
    if (this.hasOllamaUrlTarget && this.ollamaUrlTarget.value) {
      if (this.hasOllamaToggleTarget) {
        this.ollamaToggleTarget.checked = true
        this.showOllamaSettings()
      }
    }
  }

  toggleModels(event) {
    this.updateVisibility(event.currentTarget)
  }

  toggleOllama(event) {
    if (event.currentTarget.checked) {
      this.enableOllama()
    } else {
      this.disableOllama()
    }
  }

  enableOllama() {
    // Set the URL to default (Docker internal)
    if (this.hasOllamaUrlTarget) {
      this.ollamaUrlTarget.value = OLLAMA_DEFAULT_URL
    }
    if (this.hasOllamaCustomUrlTarget) {
      this.ollamaCustomUrlTarget.value = OLLAMA_DEFAULT_URL
    }
    this.showOllamaSettings()
  }

  disableOllama() {
    // Clear the URL
    if (this.hasOllamaUrlTarget) {
      this.ollamaUrlTarget.value = ""
    }
    this.hideOllamaSettings()
  }

  showOllamaSettings() {
    if (this.hasOllamaEnabledTarget) {
      this.ollamaEnabledTarget.classList.remove("hidden")
      // Auto-detect installed models
      if (typeof detectOllamaModels === "function") {
        detectOllamaModels()
      }
    }
  }

  hideOllamaSettings() {
    if (this.hasOllamaEnabledTarget) {
      this.ollamaEnabledTarget.classList.add("hidden")
    }
  }

  updateOllamaUrl(event) {
    // Sync the custom URL input to the hidden field
    const customUrl = event.currentTarget.value.trim()
    if (this.hasOllamaUrlTarget) {
      this.ollamaUrlTarget.value = customUrl || OLLAMA_DEFAULT_URL
    }
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
