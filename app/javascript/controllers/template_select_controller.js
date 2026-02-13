import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["templateId", "nameSection", "selectedIcon", "selectedName", "nameInput"]

  pick(event) {
    const button = event.currentTarget
    const templateId = button.dataset.templateId
    const templateName = button.dataset.templateName

    // Update hidden field
    this.templateIdTarget.value = templateId

    // Highlight selected
    this.element.querySelectorAll("[data-template-id]").forEach(el => {
      el.classList.remove("border-blue-500", "bg-surface-raised")
      el.classList.add("border-border-default")
    })
    button.classList.remove("border-border-default")
    button.classList.add("border-blue-500", "bg-surface-raised")

    // Show name section
    this.nameSectionTarget.style.display = "block"
    this.selectedNameTarget.textContent = templateName
    this.nameInputTarget.placeholder = templateName

    // Scroll to name section
    this.nameSectionTarget.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
