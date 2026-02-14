import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "thinkingArea", "emptyState", "mentionBar"]
  static values = { sessionId: Number, messageUrl: String, csrf: String, agents: Array }

  connect() {
    this.consumer = createConsumer()
    this.sending = false
    this.streamBubbles = {} // keyed by agent_id
    this.agentColors = {}

    // Build color map from agents value
    const colors = ["blue", "green", "yellow", "pink", "cyan", "red", "indigo", "orange"]
    this.agentsValue.forEach((agent, i) => {
      this.agentColors[agent.id] = colors[i % colors.length]
    })

    this.subscription = this.consumer.subscriptions.create(
      { channel: "TeamChatChannel", team_chat_session_id: this.sessionIdValue },
      {
        received: (data) => this.handleMessage(data),
        connected: () => console.log("Connected to team chat", this.sessionIdValue),
        disconnected: () => console.log("Disconnected from team chat", this.sessionIdValue)
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
        this.appendUserMessage(data.content, data.target_agent_name)
        break
      case "thinking":
        this.showThinking(data.agent_id, data.agent_name)
        break
      case "token":
        this.hideThinking(data.agent_id)
        this.appendAgentToken(data.agent_id, data.agent_name, data.content)
        break
      case "agent_done":
        this.hideThinking(data.agent_id)
        this.finalizeAgentMessage(data.agent_id)
        break
      case "error":
        this.hideThinking(data.agent_id)
        this.showError(data.content)
        break
    }
  }

  async send() {
    const message = this.inputTarget.value.trim()
    if (!message || this.sending) return

    this.sending = true
    this.sendBtnTarget.disabled = true
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"

    if (this.hasEmptyStateTarget) this.emptyStateTarget.remove()
    if (this.hasMentionBarTarget) this.mentionBarTarget.classList.add("hidden")

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
    }

    this.sending = false
    this.sendBtnTarget.disabled = false
    this.inputTarget.focus()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  handleInput() {
    // Auto-resize
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 150) + "px"

    // Show mention bar when typing @
    if (this.hasMentionBarTarget) {
      const val = input.value
      const atPos = val.lastIndexOf("@")
      if (atPos >= 0 && atPos === val.length - 1) {
        this.mentionBarTarget.classList.remove("hidden")
      }
    }
  }

  insertMention(event) {
    const name = event.currentTarget.dataset.agentName
    const input = this.inputTarget
    const val = input.value

    // Replace trailing @ with @Name
    const atPos = val.lastIndexOf("@")
    if (atPos >= 0) {
      input.value = val.substring(0, atPos) + `@${name} `
    } else {
      input.value += `@${name} `
    }

    if (this.hasMentionBarTarget) this.mentionBarTarget.classList.add("hidden")
    input.focus()
  }

  appendUserMessage(content, targetName) {
    const targetLabel = targetName ? `<div class="text-xs text-gray-500 text-right mb-1">→ @${this.esc(targetName)}</div>` : ""
    const html = `
      <div class="flex justify-end">
        <div class="max-w-2xl">
          ${targetLabel}
          <div class="bg-blue-600 rounded-2xl rounded-br-md px-4 py-3 text-white">
            <p class="whitespace-pre-wrap">${this.esc(content)}</p>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  showThinking(agentId, agentName) {
    const color = this.agentColors[agentId] || "gray"
    const initial = agentName ? agentName[0].toUpperCase() : "?"
    const existing = this.thinkingAreaTarget.querySelector(`[data-thinking-agent="${agentId}"]`)
    if (existing) return

    const html = `
      <div class="flex items-start gap-3 mb-2" data-thinking-agent="${agentId}">
        <div class="w-8 h-8 bg-${color}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0">
          ${initial}
        </div>
        <div class="bg-gray-700 rounded-2xl rounded-bl-md px-4 py-3 text-gray-400">
          <div class="text-xs mb-1">${this.esc(agentName)} is thinking...</div>
          <div class="flex gap-1">
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0ms"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 150ms"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 300ms"></span>
          </div>
        </div>
      </div>`
    this.thinkingAreaTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  hideThinking(agentId) {
    const el = this.thinkingAreaTarget.querySelector(`[data-thinking-agent="${agentId}"]`)
    if (el) el.remove()
  }

  appendAgentToken(agentId, agentName, content) {
    if (!this.streamBubbles[agentId]) {
      const color = this.agentColors[agentId] || "gray"
      const initial = agentName ? agentName[0].toUpperCase() : "?"
      const bubbleId = `team-stream-${agentId}-${Date.now()}`

      const agent = this.agentsValue.find(a => a.id === agentId)
      const role = agent ? agent.role : ""

      const html = `
        <div class="flex justify-start" data-agent-bubble="${agentId}">
          <div class="max-w-2xl">
            <div class="flex items-start gap-3">
              <div class="w-8 h-8 bg-${color}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
                ${initial}
              </div>
              <div>
                <div class="text-xs text-gray-400 mb-1">${this.esc(agentName)} <span class="text-gray-600">· ${this.esc(role)}</span></div>
                <div class="bg-gray-700 rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
                  <div class="whitespace-pre-wrap" id="${bubbleId}"></div>
                </div>
              </div>
            </div>
          </div>
        </div>`
      this.messagesTarget.insertAdjacentHTML("beforeend", html)
      this.streamBubbles[agentId] = document.getElementById(bubbleId)
    }

    this.streamBubbles[agentId].textContent += content
    this.scrollToBottom()
  }

  finalizeAgentMessage(agentId) {
    delete this.streamBubbles[agentId]
  }

  showError(message) {
    const html = `
      <div class="flex justify-center">
        <div class="bg-red-900/50 border border-red-600 text-red-200 px-4 py-2 rounded-lg text-sm">
          ${this.esc(message)}
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    })
  }

  esc(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
