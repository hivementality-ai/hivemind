import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "thinking", "tokenCount", "emptyState"]
  static values = { sessionId: Number, agentName: String, agentInitial: String, messageUrl: String, csrf: String }

  connect() {
    this.consumer = createConsumer()
    this.streaming = false
    this.streamBubble = null

    this.subscription = this.consumer.subscriptions.create(
      { channel: "SessionChannel", session_id: this.sessionIdValue },
      {
        received: (data) => this.handleMessage(data),
        connected: () => console.log("Connected to session", this.sessionIdValue),
        disconnected: () => console.log("Disconnected from session", this.sessionIdValue)
      }
    )

    this.scrollToBottom()
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
    if (this.consumer) this.consumer.disconnect()
  }

  handleMessage(data) {
    switch (data.type) {
      case "user_message":
        this.appendUserMessage(data.content)
        this.showThinking()
        break
      case "token":
        this.hideThinking()
        this.appendToken(data.content)
        break
      case "tool_start":
        this.hideThinking()
        this.showToolStart(data.tool, data.input)
        break
      case "tool_result":
        this.showToolResult(data.tool, data.output, data.success)
        break
      case "done":
        this.finishStream()
        break
      case "error":
        this.hideThinking()
        this.showError(data.content)
        this.finishStream()
        break
    }
  }

  async send() {
    const message = this.inputTarget.value.trim()
    if (!message || this.streaming) return

    this.streaming = true
    this.sendBtnTarget.disabled = true
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"

    // Remove empty state
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.remove()
    }

    try {
      await fetch(this.messageUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfValue
        },
        body: `message=${encodeURIComponent(message)}`
      })
    } catch (e) {
      this.showError("Failed to send message")
      this.finishStream()
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  autoResize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 150) + "px"
  }

  appendUserMessage(content) {
    const html = `
      <div class="flex justify-end">
        <div class="max-w-2xl">
          <div class="bg-blue-600 rounded-2xl rounded-br-md px-4 py-3 text-white">
            <p class="whitespace-pre-wrap">${this.escapeHtml(content)}</p>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  appendToken(content) {
    if (!this.streamBubble) {
      this.streamId = (this.streamId || 0) + 1
      const id = `stream-${this.streamId}`
      const html = `
        <div class="flex justify-start">
          <div class="max-w-2xl">
            <div class="flex items-start gap-3">
              <div class="w-8 h-8 bg-gray-700 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
                ${this.agentInitialValue}
              </div>
              <div class="bg-gray-700 rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
                <div class="whitespace-pre-wrap" id="${id}"></div>
              </div>
            </div>
          </div>
        </div>`
      this.messagesTarget.insertAdjacentHTML("beforeend", html)
      this.streamBubble = document.getElementById(id)
    }

    this.streamBubble.textContent += content
    this.scrollToBottom()
  }

  showThinking() {
    if (this.hasThinkingTarget) {
      this.thinkingTarget.classList.remove("hidden")
      this.scrollToBottom()
    }
  }

  hideThinking() {
    if (this.hasThinkingTarget) {
      this.thinkingTarget.classList.add("hidden")
    }
  }

  showToolStart(toolName, input) {
    // End any current stream bubble so tool appears separately
    this.streamBubble = null
    this.hideThinking()

    const inputStr = typeof input === "object" ? JSON.stringify(input) : input
    const shortInput = inputStr.length > 100 ? inputStr.substring(0, 100) + "..." : inputStr

    const html = `
      <div class="flex justify-start" data-tool-block="${toolName}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-yellow-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">⚡</div>
            <div class="bg-gray-800 border border-gray-600 rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-yellow-400 text-sm font-medium">
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                Running ${this.escapeHtml(toolName)}
              </div>
              <code class="text-gray-400 text-xs mt-1 block">${this.escapeHtml(shortInput)}</code>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  showToolResult(toolName, output, success) {
    const block = this.messagesTarget.querySelector(`[data-tool-block="${toolName}"]:last-of-type`)
    if (block) {
      const statusEl = block.querySelector(".text-yellow-400")
      if (statusEl) {
        const color = success ? "text-green-400" : "text-red-400"
        const icon = success ? "✓" : "✗"
        statusEl.className = `flex items-center gap-2 ${color} text-sm font-medium`
        statusEl.innerHTML = `${icon} ${this.escapeHtml(toolName)} completed`
      }
      const codeEl = block.querySelector("code")
      if (codeEl && output) {
        const shortOutput = output.length > 300 ? output.substring(0, 300) + "..." : output
        codeEl.textContent = shortOutput
      }
    }
    this.scrollToBottom()
  }

  showError(message) {
    const html = `
      <div class="flex justify-center">
        <div class="bg-red-900/50 border border-red-600 text-red-200 px-4 py-2 rounded-lg text-sm">
          ${this.escapeHtml(message)}
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  finishStream() {
    this.streaming = false
    this.streamBubble = null
    this.sendBtnTarget.disabled = false
    this.inputTarget.focus()
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    })
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
