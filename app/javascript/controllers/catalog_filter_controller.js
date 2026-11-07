import { Controller } from "@hotwired/stimulus"

// Filters the grouped MCP shelf by name, summary and category as the user types.
// Groups with no match are hidden and an empty message shows when nothing matches.
export default class extends Controller {
  static targets = ["input", "group", "item", "empty"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach(item => {
      const hit = query === "" || item.dataset.searchText.includes(query)
      item.classList.toggle("hidden", !hit)
      if (hit) visible++
    })

    this.groupTargets.forEach(group => {
      const anyShown = Array.from(group.querySelectorAll("[data-catalog-filter-target='item']"))
        .some(item => !item.classList.contains("hidden"))
      group.classList.toggle("hidden", !anyShown)
    })

    this.emptyTarget.classList.toggle("hidden", visible > 0)
  }
}
