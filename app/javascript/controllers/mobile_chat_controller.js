import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "messages", "input", "sendBtn", "stopBtn", "thinking", "working",
    "imagePreview", "imageThumbs", "attachPreview", "attachList",
    "fileInput", "emptyState"
  ]

  static values = {
    sessionId: Number,
    agentName: String,
    messageUrl: String,
    interruptUrl: String,
    csrf: String,
    processing: Boolean,
    teamChat: Boolean,
    agents: String
  }

  connect() {
    this.pendingImages = []
    this.pendingFiles = []
    this.currentStreamEl = null
    this.streamedContent = ""
    this.touchStartX = 0
    this.touchStartY = 0

    this.subscribeToChannel()
    this.scrollToBottom()

    if (this.processingValue) {
      this.showThinking()
    }

    // Keyboard awareness
    this.inputTarget.addEventListener("focus", () => {
      setTimeout(() => this.scrollToBottom(), 300)
    })

    // Touch gestures for swipe-back
    this.element.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: true })
    this.element.addEventListener("touchend", this.handleTouchEnd.bind(this), { passive: true })
  }

  subscribeToChannel() {
    this.consumer = createConsumer()
    const channelName = this.teamChatValue ? "TeamChatChannel" : "SessionChannel"
    const identifier = this.teamChatValue
      ? { channel: channelName, team_chat_id: this.sessionIdValue }
      : { channel: channelName, session_id: this.sessionIdValue }

    this.subscription = this.consumer.subscriptions.create(identifier, {
      received: this.received.bind(this)
    })
  }

  received(data) {
    switch (data.type) {
      case "token":
        this.appendToken(data.content)
        break
      case "thinking":
        this.showThinkingContent(data.content)
        break
      case "tool_start":
        this.showToolCall(data.name, data.id)
        break
      case "tool_result":
        this.updateToolResult(data.id, data.content)
        break
      case "done":
        this.finalizeMessage()
        break
      case "cancelled":
        this.handleCancelled()
        break
      case "error":
        this.handleError(data.content)
        break
      case "user_message":
        // Ignored — the send() method already appends the user bubble locally
        break
      case "processing":
        if (data.active) {
          this.showThinking()
        } else {
          this.hideThinking()
        }
        break
      case "interrupt_sent":
        this.showFlash("Interrupt sent")
        break
      case "agent_done":
        this.finalizeMessage(data.agent_name)
        break
    }
  }

  appendToken(token) {
    if (!this.currentStreamEl) {
      this.currentStreamEl = this.createAssistantBubble()
      this.streamedContent = ""
      this.hideEmptyState()
    }
    this.streamedContent += token
    this.currentStreamEl.querySelector(".message-content").textContent = this.streamedContent
    this.scrollToBottom()
  }

  showThinkingContent(content) {
    if (this.hasThinkingTarget) {
      this.thinkingTarget.querySelector(".thinking-text").textContent = content?.substring(0, 200) || ""
    }
  }

  showToolCall(name, id) {
    const el = document.createElement("div")
    el.className = "mx-4 my-1 px-3 py-1.5 bg-surface-card rounded text-xs text-text-muted border border-border-default"
    el.id = `tool-${id}`
    el.innerHTML = `<span class="font-mono">${this.escapeHtml(name)}</span> <span class="opacity-50">running...</span>`
    this.messagesTarget.appendChild(el)
    this.scrollToBottom()
  }

  updateToolResult(id, content) {
    const el = document.getElementById(`tool-${id}`)
    if (el) {
      const statusSpan = el.querySelector("span:last-child")
      if (statusSpan) statusSpan.textContent = "done"
    }
  }

  finalizeMessage(agentName) {
    if (this.currentStreamEl) {
      const contentEl = this.currentStreamEl.querySelector(".message-content")
      contentEl.innerHTML = this.renderMarkdown(this.streamedContent)
      if (agentName) {
        const badge = document.createElement("span")
        badge.className = "text-xs text-purple-400 font-medium mt-1 block"
        badge.textContent = `- ${agentName}`
        contentEl.appendChild(badge)
      }
      this.currentStreamEl = null
      this.streamedContent = ""
    }
    this.hideThinking()
    this.scrollToBottom()
  }

  handleCancelled() {
    if (this.currentStreamEl) {
      const el = document.createElement("span")
      el.className = "text-xs text-amber-400 italic block mt-1"
      el.textContent = "(cancelled)"
      this.currentStreamEl.querySelector(".message-content").appendChild(el)
      this.currentStreamEl = null
      this.streamedContent = ""
    }
    this.hideThinking()
  }

  handleError(content) {
    const el = document.createElement("div")
    el.className = "mx-4 my-2 px-3 py-2 bg-red-900/30 border border-red-700 rounded-lg text-sm text-red-300"
    el.textContent = content || "An error occurred"
    this.messagesTarget.appendChild(el)
    this.hideThinking()
    this.scrollToBottom()
  }

  appendUserBubble(content) {
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-end px-4 my-2"
    const bubble = document.createElement("div")
    bubble.className = "max-w-[80%] px-3 py-2 rounded-2xl rounded-br-sm bg-blue-600 text-white text-sm"
    bubble.textContent = content
    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    this.hideEmptyState()
    this.scrollToBottom()
  }

  createAssistantBubble() {
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-start px-4 my-2"
    const bubble = document.createElement("div")
    bubble.className = "max-w-[85%] px-3 py-2 rounded-2xl rounded-bl-sm bg-surface-card text-white text-sm border border-border-default"
    const content = document.createElement("div")
    content.className = "message-content prose prose-invert prose-sm max-w-none"
    bubble.appendChild(content)
    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    return wrapper
  }

  async send() {
    const message = this.inputTarget.value.trim()
    if (!message && this.pendingImages.length === 0 && this.pendingFiles.length === 0) return

    const formData = new FormData()
    formData.append("message", message)
    this.pendingImages.forEach(f => formData.append("images[]", f))
    this.pendingFiles.forEach(f => formData.append("files[]", f))

    // Append user bubble immediately
    if (message) {
      this.appendUserBubble(message)
    }

    // Clear input
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"
    this.clearImages()
    this.clearFiles()
    this.showThinking()

    try {
      await fetch(this.messageUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue },
        body: formData
      })
    } catch (err) {
      this.handleError("Failed to send message")
    }
  }

  async stopAgent() {
    try {
      await fetch(this.interruptUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfValue,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ type: "cancel" })
      })
    } catch (err) {
      // Silently handle interrupt failure
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  autoResize(event) {
    const textarea = event.target
    textarea.style.height = "auto"
    const maxHeight = parseInt(getComputedStyle(textarea).lineHeight) * 6
    textarea.style.height = Math.min(textarea.scrollHeight, maxHeight) + "px"
  }

  handleFiles(event) {
    const files = Array.from(event.target.files)
    files.forEach(file => {
      if (file.type.startsWith("image/")) {
        this.pendingImages.push(file)
        this.showImagePreview(file)
      } else {
        this.pendingFiles.push(file)
        this.showFilePill(file)
      }
    })
    // Reset input so the same file can be re-selected
    event.target.value = ""
  }

  showImagePreview(file) {
    if (!this.hasImagePreviewTarget) return
    this.imagePreviewTarget.classList.remove("hidden")
    const reader = new FileReader()
    reader.onload = (e) => {
      const thumb = document.createElement("div")
      thumb.className = "relative w-16 h-16 rounded-lg overflow-hidden border border-border-default"
      thumb.innerHTML = `
        <img src="${e.target.result}" class="w-full h-full object-cover" />
        <button class="absolute top-0 right-0 bg-black/60 rounded-bl px-1 text-xs" data-action="click->mobile-chat#removeImage" data-index="${this.pendingImages.length - 1}">&times;</button>
      `
      this.imageThumbsTarget.appendChild(thumb)
    }
    reader.readAsDataURL(file)
  }

  showFilePill(file) {
    if (!this.hasAttachPreviewTarget) return
    this.attachPreviewTarget.classList.remove("hidden")
    const pill = document.createElement("span")
    pill.className = "inline-flex items-center gap-1 px-2 py-1 bg-surface-card border border-border-default rounded text-xs text-text-muted"
    pill.innerHTML = `${this.escapeHtml(file.name)} <button data-action="click->mobile-chat#removeFile" data-index="${this.pendingFiles.length - 1}">&times;</button>`
    this.attachListTarget.appendChild(pill)
  }

  removeImage(event) {
    const idx = parseInt(event.currentTarget.dataset.index)
    this.pendingImages.splice(idx, 1)
    if (this.hasImageThumbsTarget) this.imageThumbsTarget.innerHTML = ""
    if (this.pendingImages.length === 0 && this.hasImagePreviewTarget) {
      this.imagePreviewTarget.classList.add("hidden")
    }
  }

  removeFile(event) {
    const idx = parseInt(event.currentTarget.dataset.index)
    this.pendingFiles.splice(idx, 1)
    if (this.hasAttachListTarget) this.attachListTarget.innerHTML = ""
    if (this.pendingFiles.length === 0 && this.hasAttachPreviewTarget) {
      this.attachPreviewTarget.classList.add("hidden")
    }
  }

  clearImages() {
    this.pendingImages = []
    if (this.hasImagePreviewTarget) {
      this.imagePreviewTarget.classList.add("hidden")
      this.imageThumbsTarget.innerHTML = ""
    }
  }

  clearFiles() {
    this.pendingFiles = []
    if (this.hasAttachPreviewTarget) {
      this.attachPreviewTarget.classList.add("hidden")
      this.attachListTarget.innerHTML = ""
    }
  }

  showThinking() {
    if (this.hasThinkingTarget) this.thinkingTarget.classList.remove("hidden")
    if (this.hasSendBtnTarget) this.sendBtnTarget.classList.add("hidden")
    if (this.hasStopBtnTarget) this.stopBtnTarget.classList.remove("hidden")
    this.scrollToBottom()
  }

  hideThinking() {
    if (this.hasThinkingTarget) this.thinkingTarget.classList.add("hidden")
    if (this.hasSendBtnTarget) this.sendBtnTarget.classList.remove("hidden")
    if (this.hasStopBtnTarget) this.stopBtnTarget.classList.add("hidden")
  }

  hideEmptyState() {
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
  }

  showFlash(message) {
    const flash = document.createElement("div")
    flash.className = "fixed top-4 left-1/2 -translate-x-1/2 px-4 py-2 bg-surface-card border border-border-default rounded-lg text-sm text-white shadow-lg z-50"
    flash.textContent = message
    document.body.appendChild(flash)
    setTimeout(() => flash.remove(), 2000)
  }

  handleTouchStart(event) {
    this.touchStartX = event.touches[0].clientX
    this.touchStartY = event.touches[0].clientY
  }

  handleTouchEnd(event) {
    const dx = event.changedTouches[0].clientX - this.touchStartX
    const dy = Math.abs(event.changedTouches[0].clientY - this.touchStartY)
    // Swipe right with minimal vertical movement
    if (dx > 100 && dy < 50) {
      history.back()
    }
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      requestAnimationFrame(() => {
        this.messagesTarget.scrollTo({
          top: this.messagesTarget.scrollHeight,
          behavior: "smooth"
        })
      })
    }
  }

  renderMarkdown(text) {
    if (!text) return ""
    if (typeof marked !== "undefined") {
      try {
        const html = marked.parse(text)
        return this.sanitize(html)
      } catch {
        return this.escapeHtml(text)
      }
    }
    return this.escapeHtml(text).replace(/\n/g, "<br>")
  }

  sanitize(html) {
    const tmp = document.createElement("div")
    tmp.innerHTML = html
    tmp.querySelectorAll("script, iframe, object, embed, form").forEach(el => el.remove())
    return tmp.innerHTML
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  disconnecting() {
    if (this.subscription) this.subscription.unsubscribe()
    if (this.consumer) this.consumer.disconnect()
  }
}
