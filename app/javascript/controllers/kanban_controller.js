import { Controller } from "@hotwired/stimulus"

// Kanban drag-and-drop controller.
// Enables dragging task cards between status columns.
// On drop, sends a PATCH /tasks/:id/move request to update the task status.
export default class extends Controller {
  static targets = ["column", "cards", "card"]

  connect() {
    this.draggedCard = null
    this.draggedFromColumn = null

    this.columnTargets.forEach(column => {
      column.addEventListener("dragover",  this.onDragOver.bind(this))
      column.addEventListener("drop",      this.onDrop.bind(this))
      column.addEventListener("dragenter", this.onDragEnter.bind(this))
      column.addEventListener("dragleave", this.onDragLeave.bind(this))
    })
  }

  disconnect() {
    this.columnTargets.forEach(column => {
      column.removeEventListener("dragover",  this.onDragOver.bind(this))
      column.removeEventListener("drop",      this.onDrop.bind(this))
      column.removeEventListener("dragenter", this.onDragEnter.bind(this))
      column.removeEventListener("dragleave", this.onDragLeave.bind(this))
    })
  }

  // ─── Card events (data-action on each card) ───────────────────

  dragStart(event) {
    this.draggedCard = event.currentTarget
    this.draggedFromColumn = this.draggedCard.closest("[data-status]")

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedCard.dataset.taskId)

    // Slight delay so the drag image renders before opacity change
    setTimeout(() => {
      this.draggedCard.classList.add("opacity-40")
    }, 0)
  }

  dragEnd(event) {
    if (this.draggedCard) {
      this.draggedCard.classList.remove("opacity-40")
    }
    this.clearDropTargets()
    this.draggedCard = null
    this.draggedFromColumn = null
  }

  // ─── Column events ─────────────────────────────────────────────

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  onDragEnter(event) {
    const column = event.currentTarget
    column.classList.add("ring-2", "ring-brand/50")
  }

  onDragLeave(event) {
    const column = event.currentTarget
    // Only clear if leaving the column entirely (not entering a child)
    if (!column.contains(event.relatedTarget)) {
      column.classList.remove("ring-2", "ring-brand/50")
    }
  }

  onDrop(event) {
    event.preventDefault()

    const targetColumn = event.currentTarget
    const newStatus = targetColumn.dataset.status
    const taskId = event.dataTransfer.getData("text/plain")

    targetColumn.classList.remove("ring-2", "ring-brand/50")

    if (!taskId || !newStatus) return

    const card = this.draggedCard || this.element.querySelector(`[data-task-id="${taskId}"]`)
    if (!card) return

    const currentStatus = card.dataset.currentStatus
    if (currentStatus === newStatus) return

    // Optimistically move the card in the DOM
    const cardsContainer = targetColumn.querySelector("[data-kanban-target='cards']")
    if (cardsContainer) {
      cardsContainer.appendChild(card)
      card.dataset.currentStatus = newStatus
      this.updateColumnCount(this.draggedFromColumn)
      this.updateColumnCount(targetColumn)
    }

    // Persist via PATCH
    this.persistMove(taskId, newStatus, card, currentStatus, this.draggedFromColumn)
  }

  // ─── Persistence ───────────────────────────────────────────────

  persistMove(taskId, newStatus, card, previousStatus, previousColumn) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const url = `/tasks/${taskId}/move`

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ status: newStatus })
    })
    .then(response => {
      if (!response.ok) {
        return response.json().then(data => { throw new Error(data.error || "Move failed") })
      }
      return response.json()
    })
    .catch(error => {
      console.error("[Kanban] Move failed:", error.message)
      // Roll back: move card back to previous column
      if (previousColumn) {
        const prevCards = previousColumn.querySelector("[data-kanban-target='cards']")
        if (prevCards) {
          prevCards.appendChild(card)
          card.dataset.currentStatus = previousStatus
          this.updateColumnCount(previousColumn)
          const targetColumn = this.element.querySelector(`[data-status="${newStatus}"]`)
          if (targetColumn) this.updateColumnCount(targetColumn)
        }
      }
    })
  }

  // ─── Helpers ───────────────────────────────────────────────────

  updateColumnCount(column) {
    if (!column) return
    const cards = column.querySelectorAll("[data-kanban-target='card']")
    const badge = column.querySelector(".rounded-full")
    if (badge) badge.textContent = cards.length
  }

  clearDropTargets() {
    this.columnTargets.forEach(col => {
      col.classList.remove("ring-2", "ring-brand/50")
    })
  }
}
