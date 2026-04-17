import { Controller } from "@hotwired/stimulus"

// Controls collapsible nav groups in the sidebar.
// Persists expanded/collapsed state in localStorage.
// Auto-expands a group when the current page is within it.
export default class extends Controller {
  static targets = ["content", "chevron"]
  static values = { name: String }

  connect() {
    if (this.hasActiveLink()) {
      this.expand()
    } else {
      const stored = localStorage.getItem(this.storageKey)
      if (stored === "expanded") {
        this.expand()
      } else {
        this.collapse()
      }
    }
  }

  toggle() {
    if (this.isExpanded()) {
      this.collapse()
      localStorage.setItem(this.storageKey, "collapsed")
    } else {
      this.expand()
      localStorage.setItem(this.storageKey, "expanded")
    }
  }

  expand() {
    this.contentTarget.style.maxHeight = this.contentTarget.scrollHeight + "px"
    this.contentTarget.style.opacity = "1"
    this.contentTarget.setAttribute("data-expanded", "true")
    this.chevronTarget.style.transform = "rotate(180deg)"
  }

  collapse() {
    this.contentTarget.style.maxHeight = "0"
    this.contentTarget.style.opacity = "0"
    this.contentTarget.removeAttribute("data-expanded")
    this.chevronTarget.style.transform = "rotate(0deg)"
  }

  isExpanded() {
    return this.contentTarget.hasAttribute("data-expanded")
  }

  hasActiveLink() {
    return this.contentTarget.querySelector(".nav-item-active") !== null
  }

  get storageKey() {
    return `nav-group-${this.nameValue}`
  }
}
