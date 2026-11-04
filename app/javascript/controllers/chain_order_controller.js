import { Controller } from "@hotwired/stimulus"

// Reorders the rows of the backup brain list; the form submits them in DOM order.
export default class extends Controller {
  up(event) {
    const row = event.currentTarget.closest("li")
    const previous = row.previousElementSibling
    if (previous) row.parentNode.insertBefore(row, previous)
  }

  down(event) {
    const row = event.currentTarget.closest("li")
    const next = row.nextElementSibling
    if (next) row.parentNode.insertBefore(next, row)
  }
}
