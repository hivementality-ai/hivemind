import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "thinking", "thinkingContent", "tokenCount", "emptyState", "fileInput", "imagePreview", "imageThumbs", "attachPreview", "attachList"]
  static values = { sessionId: Number, agentName: String, agentInitial: String, messageUrl: String, csrf: String }

  connect() {
    this.consumer = createConsumer()
    this.streaming = false
    this.streamBubble = null
    this.pendingImages = []
    this.pendingFiles = []

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
        this.appendUserMessage(data.content, data.images, data.files)
        this.showThinking()
        break
      case "thinking_start":
        this.showAgentThinking()
        break
      case "thinking":
        this.appendThinkingToken(data.content)
        break
      case "thinking_stop":
        this.hideAgentThinking()
        break
      case "token":
        this.hideThinking()
        this.hideAgentThinking()
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
    if (!message && this.pendingImages.length === 0 && this.pendingFiles.length === 0) return
    if (this.streaming) return

    this.streaming = true
    this.sendBtnTarget.disabled = true
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"

    if (this.hasEmptyStateTarget) this.emptyStateTarget.remove()

    try {
      const formData = new FormData()
      formData.append("message", message)
      this.pendingImages.forEach(file => formData.append("images[]", file))
      this.pendingFiles.forEach(file => formData.append("files[]", file))

      await fetch(this.messageUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue },
        body: formData
      })

      this.clearImages()
      this.clearFiles()
    } catch (e) {
      this.showError("Failed to send message")
      this.finishStream()
    }
  }

  // ─── Image Handling ────────────────────────────────────

  handleFiles() {
    const files = Array.from(this.fileInputTarget.files)
    files.forEach(f => this.addFile(f))
    this.fileInputTarget.value = ""
  }

  handlePaste(event) {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (item.type.startsWith("image/")) {
        event.preventDefault()
        const file = item.getAsFile()
        if (file) this.addFile(file)
      }
    }
  }

  dragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-brand")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-brand")
  }

  drop(event) {
    event.preventDefault()
    event.currentTarget.classList.remove("ring-2", "ring-brand")
    const files = Array.from(event.dataTransfer.files)
    files.forEach(f => this.addFile(f))
  }

  addFile(file) {
    const totalFiles = this.pendingImages.length + this.pendingFiles.length
    if (totalFiles >= 10) return // max 10 attachments

    if (file.type.startsWith("image/")) {
      this.pendingImages.push(file)
      this.updateImagePreview()
    } else {
      if (file.size > 10 * 1024 * 1024) return // max 10MB per file
      this.pendingFiles.push(file)
      this.updateFilePreview()
    }
  }

  addImage(file) {
    this.addFile(file)
  }

  clearImages() {
    this.pendingImages = []
    this.updateImagePreview()
  }

  updateImagePreview() {
    if (this.pendingImages.length === 0) {
      if (this.hasImagePreviewTarget) this.imagePreviewTarget.classList.add("hidden")
      return
    }

    if (this.hasImagePreviewTarget) this.imagePreviewTarget.classList.remove("hidden")
    if (!this.hasImageThumbsTarget) return

    this.imageThumbsTarget.innerHTML = ""
    this.pendingImages.forEach((file, idx) => {
      const url = URL.createObjectURL(file)
      const thumb = document.createElement("div")
      thumb.className = "relative group"
      thumb.innerHTML = `
        <img src="${url}" class="w-16 h-16 object-cover rounded-lg border border-border-default">
        <button class="absolute -top-1 -right-1 w-5 h-5 bg-red-600 rounded-full text-white text-xs flex items-center justify-center opacity-0 group-hover:opacity-100 transition" data-idx="${idx}">✕</button>
      `
      thumb.querySelector("button").addEventListener("click", () => {
        this.pendingImages.splice(idx, 1)
        this.updateImagePreview()
      })
      this.imageThumbsTarget.appendChild(thumb)
    })
  }

  clearFiles() {
    this.pendingFiles = []
    this.updateFilePreview()
  }

  updateFilePreview() {
    if (!this.hasAttachPreviewTarget) return

    if (this.pendingFiles.length === 0) {
      this.attachPreviewTarget.classList.add("hidden")
      return
    }

    this.attachPreviewTarget.classList.remove("hidden")
    if (!this.hasAttachListTarget) return

    this.attachListTarget.innerHTML = ""
    this.pendingFiles.forEach((file, idx) => {
      const ext = file.name.split(".").pop().toUpperCase()
      const size = file.size < 1024 ? `${file.size}B` : file.size < 1048576 ? `${(file.size/1024).toFixed(1)}KB` : `${(file.size/1048576).toFixed(1)}MB`
      const pill = document.createElement("div")
      pill.className = "flex items-center gap-2 bg-surface-raised rounded-lg px-3 py-2 text-sm group"
      pill.innerHTML = `
        <span class="text-amber-400 font-mono text-xs">${this.escapeHtml(ext)}</span>
        <span class="text-text-primary truncate max-w-[150px]">${this.escapeHtml(file.name)}</span>
        <span class="text-text-faint text-xs">${size}</span>
        <button class="text-text-faint hover:text-red-400 ml-1 opacity-0 group-hover:opacity-100 transition" data-idx="${idx}">✕</button>
      `
      pill.querySelector("button").addEventListener("click", () => {
        this.pendingFiles.splice(idx, 1)
        this.updateFilePreview()
      })
      this.attachListTarget.appendChild(pill)
    })
  }

  // ─── Key/Resize ────────────────────────────────────────

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

  // ─── Message Rendering ─────────────────────────────────

  appendUserMessage(content, images, files) {
    let imagesHtml = ""
    if (images && images.length > 0) {
      const thumbs = images.map(img =>
        `<img src="${img.url}" class="max-w-xs max-h-64 rounded-lg" loading="lazy">`
      ).join("")
      imagesHtml = `<div class="flex flex-wrap gap-2 mb-2">${thumbs}</div>`
    }

    let filesHtml = ""
    if (files && files.length > 0) {
      const pills = files.map(f => {
        const ext = f.filename.split(".").pop().toUpperCase()
        const size = f.byte_size < 1024 ? `${f.byte_size}B` : f.byte_size < 1048576 ? `${(f.byte_size/1024).toFixed(1)}KB` : `${(f.byte_size/1048576).toFixed(1)}MB`
        return `<span class="inline-flex items-center gap-1.5 bg-brand-dark/50 rounded-lg px-2.5 py-1 text-xs"><span class="font-mono text-brand-light">${this.escapeHtml(ext)}</span> ${this.escapeHtml(f.filename)} <span class="text-brand-light/60">${size}</span></span>`
      }).join("")
      filesHtml = `<div class="flex flex-wrap gap-1.5 mb-2">${pills}</div>`
    }

    const html = `
      <div class="flex justify-end">
        <div class="max-w-2xl">
          <div class="bg-brand rounded-2xl rounded-br-md px-4 py-3 text-white">
            ${imagesHtml}${filesHtml}
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
              <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
                ${this.agentInitialValue}
              </div>
              <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
                <div class="whitespace-pre-wrap chat-content" id="${id}"></div>
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

  showAgentThinking() {
    // Create a collapsible thinking bubble in the chat
    if (this.thinkingBubble) return
    const id = `thinking-${Date.now()}`
    const html = `
      <div class="flex justify-start" id="${id}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-purple-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">🧠</div>
            <div class="bg-purple-900/30 border border-purple-700/50 rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-purple-400 text-sm font-medium mb-1">
                <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                Thinking...
              </div>
              <div class="text-purple-300/70 text-xs font-mono whitespace-pre-wrap max-h-32 overflow-y-auto" data-chat-target="thinkingContent"></div>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.thinkingBubble = document.getElementById(id)
    this.scrollToBottom()
  }

  appendThinkingToken(content) {
    if (!this.hasThinkingContentTarget) return
    this.thinkingContentTarget.textContent += content
    this.scrollToBottom()
  }

  hideAgentThinking() {
    if (!this.thinkingBubble) return
    // Collapse the thinking bubble — keep it visible but mark as done
    const header = this.thinkingBubble.querySelector(".text-purple-400")
    if (header) {
      header.innerHTML = `<span class="cursor-pointer" onclick="this.closest('[id^=thinking-]').querySelector('[data-chat-target=thinkingContent]').classList.toggle('hidden')">🧠 Thought process (click to toggle)</span>`
    }
    const content = this.thinkingBubble.querySelector("[data-chat-target='thinkingContent']")
    if (content) content.classList.add("hidden")
    this.thinkingBubble = null
  }

  showToolStart(toolName, input) {
    this.streamBubble = null
    this.hideThinking()

    const inputStr = typeof input === "object" ? JSON.stringify(input) : input
    const shortInput = inputStr.length > 100 ? inputStr.substring(0, 100) + "..." : inputStr

    const html = `
      <div class="flex justify-start" data-tool-block="${toolName}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-yellow-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">⚡</div>
            <div class="bg-surface-card border border-border-default rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-yellow-400 text-sm font-medium">
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                Running ${this.escapeHtml(toolName)}
              </div>
              <code class="text-text-muted text-xs mt-1 block">${this.escapeHtml(shortInput)}</code>
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

    // Post-process: render images in agent responses
    this.renderAgentImages()
  }

  // Convert markdown image syntax and raw image URLs in agent messages to <img> tags
  renderAgentImages() {
    this.messagesTarget.querySelectorAll(".chat-content").forEach(el => {
      let html = el.innerHTML

      // Markdown images: ![alt](url)
      html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_, alt, url) => {
        return `<img src="${this.escapeHtml(url)}" alt="${this.escapeHtml(alt)}" class="max-w-full max-h-96 rounded-lg my-2" loading="lazy">`
      })

      // Standalone image URLs on their own line
      html = html.replace(/^(https?:\/\/\S+\.(?:png|jpg|jpeg|gif|webp|svg))$/gm, (url) => {
        return `<img src="${this.escapeHtml(url)}" class="max-w-full max-h-96 rounded-lg my-2" loading="lazy">`
      })

      // Workspace image paths (served via ActiveStorage or file_read)
      html = html.replace(/^(\/rails\/active_storage\/blobs\/\S+)$/gm, (url) => {
        return `<img src="${this.escapeHtml(url)}" class="max-w-full max-h-96 rounded-lg my-2" loading="lazy">`
      })

      if (html !== el.innerHTML) {
        el.innerHTML = html
      }
    })
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
