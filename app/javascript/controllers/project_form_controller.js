import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["aiPanel", "manualPanel", "aiAssisted", "milestoneList", "milestoneEntry"]

  setMode({ params: { mode } }) {
    if (mode === "manual") {
      this.aiPanelTarget.classList.add("hidden")
      this.manualPanelTarget.classList.remove("hidden")
      this.aiAssistedTarget.value = "0"
    } else {
      this.aiPanelTarget.classList.remove("hidden")
      this.manualPanelTarget.classList.add("hidden")
      this.aiAssistedTarget.value = "1"
    }
  }

  addMilestone() {
    const entries = this.milestoneEntryTargets
    const template = entries[entries.length - 1]
    const clone = template.cloneNode(true)

    // Clear all inputs in the clone
    clone.querySelectorAll("input[type='text'], textarea").forEach(el => el.value = "")
    clone.querySelectorAll("select").forEach(el => el.selectedIndex = 0)
    clone.querySelectorAll("input[type='checkbox']").forEach(el => el.checked = true)

    // Update milestone number label
    const label = clone.querySelector("span")
    if (label) label.textContent = `Milestone ${entries.length + 1}`

    this.milestoneListTarget.appendChild(clone)
    this.renumberMilestones()
  }

  removeMilestone(event) {
    if (this.milestoneEntryTargets.length <= 1) return

    event.currentTarget.closest("[data-project-form-target='milestoneEntry']").remove()
    this.renumberMilestones()
  }

  renumberMilestones() {
    this.milestoneEntryTargets.forEach((entry, i) => {
      const label = entry.querySelector("span")
      if (label) label.textContent = `Milestone ${i + 1}`
    })
  }
}
