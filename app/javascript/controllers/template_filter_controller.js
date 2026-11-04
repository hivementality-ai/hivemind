import { Controller } from "@hotwired/stimulus"

// Filters grouped template cards by name and description as the user types.
// Groups with no match are hidden, matching groups open, and counts update.
export default class extends Controller {
  static targets = ["input", "group", "item", "count", "empty"]
  static values = { open: Boolean }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.groupTargets.forEach(group => {
      const items = Array.from(group.querySelectorAll("[data-template-filter-target='item']"))
      let matches = 0
      items.forEach(item => {
        const hit = query === "" || item.dataset.searchText.includes(query)
        item.classList.toggle("hidden", !hit)
        if (hit) matches++
      })

      group.classList.toggle("hidden", matches === 0)
      group.open = query === "" ? this.openValue : matches > 0
      const count = group.querySelector("[data-template-filter-target='count']")
      count.textContent = query === "" ? `(${items.length})` : `(${matches} of ${items.length})`
      visible += matches
    })

    this.emptyTarget.classList.toggle("hidden", visible > 0)
  }
}
