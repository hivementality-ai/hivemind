import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tabs"]

  connect() {
    this.highlightActiveTab()
    this.touchStartX = 0
    this.touchStartY = 0

    this.element.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: true })
    this.element.addEventListener("touchend", this.handleTouchEnd.bind(this), { passive: true })
  }

  highlightActiveTab() {
    const path = window.location.pathname
    const tabs = this.element.querySelectorAll("[data-tab-path]")

    tabs.forEach(tab => {
      const tabPath = tab.dataset.tabPath
      const isActive = path === tabPath || (tabPath !== "/m" && path.startsWith(tabPath))

      tab.classList.toggle("text-blue-400", isActive)
      tab.classList.toggle("text-text-muted", !isActive)
    })
  }

  handleTouchStart(event) {
    this.touchStartX = event.touches[0].clientX
    this.touchStartY = event.touches[0].clientY
  }

  handleTouchEnd(event) {
    const dx = event.changedTouches[0].clientX - this.touchStartX
    const dy = Math.abs(event.changedTouches[0].clientY - this.touchStartY)

    // Only handle horizontal swipes with minimal vertical movement
    if (Math.abs(dx) < 80 || dy > 40) return

    const tabs = Array.from(this.element.querySelectorAll("[data-tab-path]"))
    const activeIndex = tabs.findIndex(tab => tab.classList.contains("text-blue-400"))

    if (activeIndex === -1) return

    let nextIndex
    if (dx > 0) {
      // Swipe right -> previous tab
      nextIndex = Math.max(0, activeIndex - 1)
    } else {
      // Swipe left -> next tab
      nextIndex = Math.min(tabs.length - 1, activeIndex + 1)
    }

    if (nextIndex !== activeIndex) {
      const href = tabs[nextIndex].getAttribute("href") || tabs[nextIndex].dataset.tabPath
      if (href) window.location.href = href
    }
  }
}
