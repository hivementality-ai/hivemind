import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { marked } from "marked"

marked.setOptions({ breaks: true, gfm: true, silent: true })

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
    this.toolCallCount = 0       // counts tool calls fired during current stream
    this.touchStartX = 0
    this.touchStartY = 0

    this.subscribeToChannel()
    this.renderExistingMarkdown()
    this.scrollToBottom(true)

    if (this.processingValue) {
      this.showThinking()
    }

    // Keyboard awareness — iOS needs extra delay for keyboard animation
    this.inputTarget.addEventListener("focus", () => {
      setTimeout(() => this.scrollToBottom(), 350)
      setTimeout(() => this.scrollToBottom(), 600)
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
        this.handleToolStart(data.name, data.id)
        break
      case "tool_result":
        this.handleToolResult(data.id, data.content)
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
      this.toolCallCount = 0
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

  // Tool calls during streaming — update a single fixed-height indicator instead of
  // injecting new DOM elements, so the message content doesn't shift.
  handleToolStart(name, id) {
    this.toolCallCount++

    if (!this.currentStreamEl) {
      // Tool firing before any tokens — ensure we have a bubble
      this.currentStreamEl = this.createAssistantBubble()
      this.streamedContent = ""
      this.hideEmptyState()
    }

    // Update or create the in-bubble tool indicator (never appended to messages list)
    let indicator = this.currentStreamEl.querySelector(".tool-progress-indicator")
    if (!indicator) {
      indicator = document.createElement("div")
      indicator.className = "tool-progress-indicator mt-1.5 inline-flex items-center gap-1.5 px-2.5 py-1 bg-amber-500/10 border border-amber-500/25 rounded-full text-xs text-amber-400"
      // Insert inside the bubble wrapper, after the content div
      const bubble = this.currentStreamEl.querySelector(".assistant-bubble")
      if (bubble) bubble.appendChild(indicator)
    }

    indicator.innerHTML = `<span>⚡</span><span class="tool-progress-text">working…</span>`
  }

  handleToolResult(id, content) {
    // No-op during streaming — the indicator updates on tool_start are sufficient.
    // The final count is shown in finalizeMessage.
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

      // Replace the live "working…" indicator with a collapsed summary pill
      const indicator = this.currentStreamEl.querySelector(".tool-progress-indicator")
      if (indicator) {
        if (this.toolCallCount > 0) {
          const label = this.toolCallCount === 1 ? "1 tool used" : `${this.toolCallCount} tools used`
          indicator.outerHTML = `
            <details class="mt-1.5">
              <summary class="inline-flex items-center gap-1.5 px-2.5 py-1 bg-amber-500/10 border border-amber-500/25 rounded-full text-xs text-amber-400 cursor-pointer select-none list-none">
                <span>⚡</span><span>${label}</span>
                <svg class="w-3 h-3 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </summary>
            </details>`
        } else {
          indicator.remove()
        }
      }

      this.currentStreamEl = null
      this.streamedContent = ""
      this.toolCallCount = 0
    }
    this.hideThinking()
    this.scrollToBottom()
  }

  handleCancelled() {
    if (this.currentStreamEl) {
      // Remove any in-progress tool indicator
      const indicator = this.currentStreamEl.querySelector(".tool-progress-indicator")
      if (indicator) indicator.remove()

      const el = document.createElement("span")
      el.className = "text-xs text-amber-400 italic block mt-1"
      el.textContent = "(cancelled)"
      this.currentStreamEl.querySelector(".message-content").appendChild(el)
      this.currentStreamEl = null
      this.streamedContent = ""
      this.toolCallCount = 0
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
    wrapper.className = "flex justify-end"
    const bubble = document.createElement("div")
    bubble.className = "max-w-[85%] px-4 py-3 rounded-2xl rounded-br-md bg-brand text-white text-sm"
    bubble.textContent = content
    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    this.hideEmptyState()
    this.scrollToBottom()
  }

  createAssistantBubble() {
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-start"
    const inner = document.createElement("div")
    inner.className = "max-w-[85%]"
    const row = document.createElement("div")
    row.className = "flex items-start gap-3"
    const bubble = document.createElement("div")
    bubble.className = "assistant-bubble bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100"
    const content = document.createElement("div")
    content.className = "message-content chat-content text-sm"
    bubble.appendChild(content)
    row.appendChild(bubble)
    inner.appendChild(row)
    wrapper.appendChild(inner)
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

  scrollToBottom(instant = false) {
    if (!this.hasMessagesTarget) return

    const el = this.messagesTarget
    const behavior = instant ? "instant" : "smooth"

    // Double-rAF ensures the DOM has fully painted (images, markdown, etc.)
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.scrollTo({ top: el.scrollHeight, behavior })
      })
    })
  }

  renderExistingMarkdown() {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.querySelectorAll(".chat-content").forEach(el => {
      const raw = el.textContent
      if (raw && raw.trim()) {
        el.innerHTML = this.renderMarkdown(raw)
      }
    })
  }

  renderMarkdown(text) {
    if (!text) return ""
    try {
      const html = marked.parse(text)
      return this.sanitize(html)
    } catch {
      return this.escapeHtml(text).replace(/\n/g, "<br>")
    }
  }

  sanitize(html) {
    return html
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "")
      .replace(/<(iframe|object|embed|form)\b[^>]*>[\s\S]*?<\/\1>/gi, "")
      .replace(/\son\w+\s*=/gi, " data-blocked=")
      .trim()
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
