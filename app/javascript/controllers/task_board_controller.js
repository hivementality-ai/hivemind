import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["column"]
  static values = { teamId: Number }

  connect() {
    this.subscription = null
    this.sortables = []
    this._initSortable()
    this._subscribeToChannel()
  }

  disconnect() {
    this.sortables.forEach(s => s.destroy())
    this.sortables = []
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  // ── Sortable ──────────────────────────────────────────────────────────────

  _initSortable() {
    this.columnTargets.forEach(col => {
      const sortable = Sortable.create(col, {
        group: "tasks",
        animation: 150,
        ghostClass: "opacity-40",
        dragClass: "shadow-lg",
        filter: ".empty-state",
        onEnd: (evt) => this._onDrop(evt)
      })
      this.sortables.push(sortable)
    })
  }

  async _onDrop(evt) {
    const card = evt.item
    const newColumn = evt.to
    const oldColumn = evt.from
    const newStatus = newColumn.dataset.status
    const taskId = card.dataset.taskId

    if (!taskId || !newStatus) return

    // Optimistically remove empty-state if present
    const emptyState = newColumn.querySelector(".empty-state")
    if (emptyState) emptyState.remove()

    try {
      const response = await fetch(`/tasks/${taskId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ task: { status: newStatus } })
      })

      if (!response.ok) throw new Error(`Server responded ${response.status}`)

      // Update card's data attribute
      card.dataset.taskStatus = newStatus

      // Restore empty state in old column if now empty
      this._updateEmptyState(oldColumn)

    } catch (err) {
      console.error("[TaskBoard] PATCH failed:", err)
      // Revert — move card back to original column at original index
      oldColumn.insertBefore(card, oldColumn.children[evt.oldIndex] || null)
      this._updateEmptyState(newColumn)
      this._showToast("Failed to update task status. Please try again.")
    }
  }

  _updateEmptyState(column) {
    const cards = column.querySelectorAll(".task-card")
    const existing = column.querySelector(".empty-state")
    if (cards.length === 0 && !existing) {
      const msg = document.createElement("div")
      msg.className = "py-8 text-center text-text-faint text-xs empty-state"
      msg.textContent = "No tasks"
      column.appendChild(msg)
    } else if (cards.length > 0 && existing) {
      existing.remove()
    }
  }

  _showToast(message) {
    const toast = document.createElement("div")
    toast.className = "fixed bottom-6 right-6 z-50 bg-red-900/90 border border-red-700 text-red-200 text-sm px-4 py-3 rounded-lg shadow-lg"
    toast.textContent = message
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 4000)
  }

  // ── ActionCable ───────────────────────────────────────────────────────────

  _subscribeToChannel() {
    if (!this.teamIdValue) return

    const consumer = createConsumer()
    this.subscription = consumer.subscriptions.create(
      { channel: "TaskChannel", team_id: this.teamIdValue },
      {
        received: (data) => {
          if (data.type === "task_created") this._handleTaskCreated(data.task)
          if (data.type === "task_updated") this._handleTaskUpdated(data.task)
        }
      }
    )
  }

  _handleTaskCreated(task) {
    const column = this._columnForStatus(task.status)
    if (!column) return

    // Don't duplicate if already present (e.g. created by current user)
    if (column.querySelector(`[data-task-id="${task.id}"]`)) return

    column.querySelector(".empty-state")?.remove()
    const card = this._buildCardHtml(task)
    column.insertAdjacentHTML("afterbegin", card)
  }

  _handleTaskUpdated(task) {
    // Find the card anywhere on the board
    const existingCard = this.element.querySelector(`[data-task-id="${task.id}"]`)
    const targetColumn = this._columnForStatus(task.status)
    if (!targetColumn) return

    if (existingCard) {
      const currentColumn = existingCard.closest(".task-column")
      if (currentColumn !== targetColumn) {
        // Move card to new column
        existingCard.remove()
        this._updateEmptyState(currentColumn)
        targetColumn.querySelector(".empty-state")?.remove()
        targetColumn.insertAdjacentHTML("afterbegin", existingCard.outerHTML)
      }
      // Update agent name in card if needed
      const agentSpan = targetColumn.querySelector(`[data-task-id="${task.id}"] .task-agent-name`)
      if (agentSpan) agentSpan.textContent = task.agent_name || "Unassigned"
    } else {
      // Card not on board yet — treat as create
      this._handleTaskCreated(task)
    }
  }

  _columnForStatus(status) {
    return this.columnTargets.find(col => col.dataset.status === status) || null
  }

  _buildCardHtml(task) {
    const priorityClasses = {
      urgent: "bg-red-900/60 text-red-300 border-red-700/50",
      high:   "bg-orange-900/60 text-orange-300 border-orange-700/50",
      medium: "bg-blue-900/60 text-blue-300 border-blue-700/50",
      low:    "bg-surface-overlay text-text-muted border-border-default"
    }
    const badge = priorityClasses[task.priority] || priorityClasses.medium
    const agentLabel = task.agent_name
      ? `<span class="text-[10px] text-text-muted bg-surface-card px-1.5 py-0.5 rounded truncate max-w-[80px]">${task.agent_name}</span>`
      : `<span class="text-[10px] text-text-faint task-agent-name">Unassigned</span>`

    return `
      <div class="task-card bg-surface-raised border border-border-default rounded-lg p-3 hover:border-gray-500 transition cursor-pointer group"
           data-task-id="${task.id}" data-task-status="${task.status}" data-task-priority="${task.priority}">
        <a href="/tasks/${task.id}" class="block">
          <p class="text-text-primary text-sm font-medium line-clamp-2 mb-2 group-hover:text-white transition">${this._escapeHtml(task.title)}</p>
          <div class="flex items-center justify-between gap-2 flex-wrap">
            <span class="text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded border ${badge}">${task.priority}</span>
            <div class="flex items-center gap-2 ml-auto">${agentLabel}</div>
          </div>
        </a>
      </div>`
  }

  _escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
