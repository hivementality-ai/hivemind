import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { marked } from "marked"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "thinking", "thinkingContent", "tokenCount", "emptyState", "fileInput", "imagePreview", "imageThumbs", "attachPreview", "attachList", "hashtagDropdown", "toolCallsToggle", "working"]
  static values = { sessionId: Number, agentName: String, agentInitial: String, messageUrl: String, csrf: String }

  connect() {
    this.consumer = createConsumer()
    this.streaming = false
    this.streamBubble = null
    this.streamRawText = ""
    this.pendingImages = []
    this.pendingFiles = []
    this.hashtagActions = []
    this.hashtagDropdownVisible = false
    this.planningMode = false

    // Configure marked for safe, sane defaults
    marked.setOptions({
      breaks: true,
      gfm: true,
      silent: true
    })

    this.subscription = this.consumer.subscriptions.create(
      { channel: "SessionChannel", session_id: this.sessionIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )

    this.loadHashtagActions()
    this.initializeToolCallsToggle()
    this.renderExistingMarkdown()
    this.scrollToBottom()
    
    // Close hashtag dropdown when clicking outside
    this._boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener('click', this._boundOutsideClick)
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
    if (this.consumer) this.consumer.disconnect()
    document.removeEventListener('click', this._boundOutsideClick)
  }

  // ─── Hashtag Actions ───────────────────────────────────

  async loadHashtagActions() {
    try {
      const response = await fetch('/api/v1/hashtag_actions')
      this.hashtagActions = await response.json()
    } catch (e) {
      console.error('Failed to load hashtag actions:', e)
      this.hashtagActions = []
    }
  }

  toggleHashtagDropdown(event) {
    event.stopPropagation()
    this.hashtagDropdownVisible = !this.hashtagDropdownVisible
    if (this.hashtagDropdownVisible) {
      this.showHashtagDropdown()
    } else {
      this.hideHashtagDropdown()
    }
  }

  showHashtagDropdown(filter = '') {
    if (!this.hasHashtagDropdownTarget) return
    
    const filtered = filter 
      ? this.hashtagActions.filter(a => a.name.toLowerCase().startsWith(filter.toLowerCase()))
      : this.hashtagActions

    if (filtered.length === 0) {
      this.hideHashtagDropdown()
      return
    }

    this.hashtagDropdownTarget.innerHTML = filtered.map(action => `
      <div class="px-3 py-2 hover:bg-surface-raised cursor-pointer transition flex items-start gap-2"
           data-action="click->chat#insertHashtag"
           data-hashtag="${action.name}">
        <code class="text-purple-400 font-mono text-sm">#${this.escapeHtml(action.name)}</code>
        <span class="text-text-muted text-xs flex-1">${this.escapeHtml(action.description)}</span>
      </div>
    `).join('')

    this.hashtagDropdownTarget.classList.remove('hidden')
    this.hashtagDropdownVisible = true
  }

  hideHashtagDropdown() {
    if (!this.hasHashtagDropdownTarget) return
    this.hashtagDropdownTarget.classList.add('hidden')
    this.hashtagDropdownVisible = false
  }

  insertHashtag(event) {
    const hashtag = event.currentTarget.dataset.hashtag
    const input = this.inputTarget
    const cursorPos = input.selectionStart
    const textBefore = input.value.substring(0, cursorPos)
    const textAfter = input.value.substring(cursorPos)
    
    // If there's a # character just before cursor, replace it
    const beforeText = textBefore.endsWith('#') ? textBefore.slice(0, -1) : textBefore
    
    input.value = beforeText + `#${hashtag} ` + textAfter
    input.focus()
    
    // Move cursor after the inserted hashtag
    const newPos = beforeText.length + hashtag.length + 2
    input.setSelectionRange(newPos, newPos)
    
    this.hideHashtagDropdown()
    this.autoResize()
  }

  handleHashtagInput() {
    const input = this.inputTarget
    const cursorPos = input.selectionStart
    const textBefore = input.value.substring(0, cursorPos)
    
    // Check if user just typed # or is typing after #
    const hashtagMatch = textBefore.match(/#(\w*)$/)
    
    if (hashtagMatch) {
      const filter = hashtagMatch[1]
      this.showHashtagDropdown(filter)
    } else {
      this.hideHashtagDropdown()
    }
  }

  handleOutsideClick(event) {
    if (this.hashtagDropdownVisible && this.hasHashtagDropdownTarget && !this.hashtagDropdownTarget.contains(event.target)) {
      this.hideHashtagDropdown()
    }
  }

  handleEscape(event) {
    if (event.key === 'Escape' && this.hashtagDropdownVisible) {
      event.preventDefault()
      this.hideHashtagDropdown()
    }
  }

  // ─── Tool Calls Toggle ─────────────────────────────────

  initializeToolCallsToggle() {
    // Get session-specific storage key
    const storageKey = `toolCallsVisible_${this.sessionIdValue}`
    
    // Tool calls are hidden by default, load from session storage
    const isVisible = sessionStorage.getItem(storageKey) === 'true'
    
    // Set the checkbox state
    if (this.hasToolCallsToggleTarget) {
      this.toolCallsToggleTarget.checked = isVisible
    }
    
    // Store the current state
    this.toolCallsVisible = isVisible
    
    // Hide existing tool calls if visibility is off
    if (!this.toolCallsVisible) {
      this.hideExistingToolCalls()
    }
  }

  toggleToolCallsVisibility() {
    this.toolCallsVisible = this.toolCallsToggleTarget.checked
    
    // Store preference in session storage
    const storageKey = `toolCallsVisible_${this.sessionIdValue}`
    sessionStorage.setItem(storageKey, this.toolCallsVisible.toString())
    
    // Show or hide existing tool calls
    if (this.toolCallsVisible) {
      this.showExistingToolCalls()
      // Hide working indicator if tool calls are now visible
      this.hideWorking()
    } else {
      this.hideExistingToolCalls()
    }
  }

  hideExistingToolCalls() {
    // Hide tool calls that were added via JavaScript streaming
    this.messagesTarget.querySelectorAll('[data-tool-block]').forEach(el => {
      el.style.display = 'none'
    })
    
    // Also hide any tool calls that might be in the existing DOM 
    // (look for elements with yellow lightning icon - our tool call signature)
    this.messagesTarget.querySelectorAll('.bg-yellow-600').forEach(iconEl => {
      const messageDiv = iconEl.closest('.flex.justify-start')
      if (messageDiv) {
        messageDiv.style.display = 'none'
        // Mark it so we can show it later
        messageDiv.setAttribute('data-hidden-tool-call', 'true')
      }
    })
  }

  showExistingToolCalls() {
    // Show tool calls that were added via JavaScript streaming
    this.messagesTarget.querySelectorAll('[data-tool-block]').forEach(el => {
      el.style.display = 'block'
    })
    
    // Show tool calls that were hidden from existing DOM
    this.messagesTarget.querySelectorAll('[data-hidden-tool-call="true"]').forEach(el => {
      el.style.display = 'block'
    })
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
        this.finishStreamBubble()
        this.showToolStart(data.tool, data.input)
        break
      case "tool_result":
        this.showToolResult(data.tool, data.output, data.success)
        break
      case "file_attachment":
        this.appendFileAttachment(data.attachment)
        break
      case "coding_agent_message":
        this.appendCodingAgentMessage(data.message, data.cli, data.task_key)
        break
      case "coding_agent_progress":
        this.updateCodingAgentProgress(data.output, data.task_key)
        break
      case "coding_agent_complete":
        this.completeCodingAgent(data.message, data.output_summary, data.task_key, data.duration)
        break
      case "agent_question":
        this.showAgentQuestion(data.question, data.timestamp)
        break
      case "planning_mode":
        this.handlePlanningMode(data.planning, data.message, data.summary)
        break
      case "plan":
        this.handlePlanMessage(data)
        break
      case "done":
        this.finishStream()
        break
      case "error":
        this.hideThinking()
        this.hideWorking()
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
    
    // Hide any existing working indicator
    this.hideWorking()

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
    // Handle escape key for hashtag dropdown
    if (event.key === 'Escape') {
      this.handleEscape(event)
      return
    }
    
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  autoResize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 150) + "px"
    
    // Check for hashtag input
    this.handleHashtagInput()
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

    this.streamRawText += content
    this.streamBubble.textContent = this.streamRawText
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

  showWorking() {
    if (this.hasWorkingTarget) {
      this.workingTarget.classList.remove("hidden")
      this.scrollToBottom()
    }
  }

  hideWorking() {
    if (this.hasWorkingTarget) {
      this.workingTarget.classList.add("hidden")
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

    const displayStyle = this.toolCallsVisible ? 'block' : 'none'
    const html = `
      <div class="flex justify-start" data-tool-block="${toolName}" style="display: ${displayStyle}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-yellow-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">⚡</div>
            <div class="bg-surface-card border border-border-default rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-yellow-400 text-sm font-medium">
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 818-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                Running ${this.escapeHtml(toolName)}
              </div>
              <code class="text-text-muted text-xs mt-1 block">${this.escapeHtml(shortInput)}</code>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    
    // Show working indicator if tool calls are hidden
    if (!this.toolCallsVisible) {
      this.showWorking()
    }
    
    if (this.toolCallsVisible) {
      this.scrollToBottom()
    }
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
    if (this.toolCallsVisible) {
      this.scrollToBottom()
    }
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

  showAgentQuestion(question, timestamp) {
    // Hide any thinking indicators
    this.hideThinking()
    this.hideAgentThinking()
    this.finishStreamBubble()

    const html = `
      <div class="flex justify-start">
        <div class="max-w-2xl">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
              ${this.agentInitialValue}
            </div>
            <div class="bg-blue-900/30 border border-blue-600/50 rounded-2xl rounded-bl-md px-4 py-3">
              <div class="flex items-center gap-2 text-blue-400 text-sm font-medium mb-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Agent is asking:
              </div>
              <div class="text-white whitespace-pre-wrap">${this.escapeHtml(question)}</div>
            </div>
          </div>
        </div>
      </div>`

    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()

    // Focus the input for user response
    this.inputTarget.focus()
  }

  appendFileAttachment(attachment) {
    // Render agent-sent file attachment (from file_send or image_generate tools)
    const isImage = attachment.is_image || attachment.content_type?.startsWith('image/')
    
    let contentHtml = ""
    if (isImage) {
      // Render inline image
      contentHtml = `<img src="${attachment.url}" class="max-w-xs max-h-64 rounded-lg" loading="lazy" alt="${this.escapeHtml(attachment.filename)}">`
    } else {
      // Render document download pill
      const ext = attachment.filename.split(".").pop().toUpperCase()
      const size = this.formatFileSize(attachment.byte_size)
      contentHtml = `
        <a href="${attachment.url}" download="${this.escapeHtml(attachment.filename)}" 
           class="inline-flex items-center gap-2 bg-surface-raised rounded-lg px-3 py-2 hover:bg-surface-card transition border border-border-default">
          <span class="text-amber-400 font-mono text-xs">${this.escapeHtml(ext)}</span>
          <span class="text-text-primary text-sm">${this.escapeHtml(attachment.filename)}</span>
          <span class="text-text-faint text-xs">${size}</span>
          <svg class="w-4 h-4 text-text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
          </svg>
        </a>`
    }

    const html = `
      <div class="flex justify-start">
        <div class="max-w-2xl">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
              ${this.agentInitialValue}
            </div>
            <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3">
              ${contentHtml}
            </div>
          </div>
        </div>
      </div>`
    
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  appendCodingAgentMessage(message, cli, taskKey) {
    const html = `
      <div class="flex justify-start" id="coding-agent-${taskKey}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-amber-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">⚡</div>
            <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 w-full">
              <div class="text-text-primary text-sm font-medium mb-1">${this.escapeHtml(message)}</div>
              <pre class="coding-agent-output text-xs text-text-muted bg-surface-base rounded p-2 max-h-48 overflow-y-auto whitespace-pre-wrap hidden"></pre>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  updateCodingAgentProgress(output, taskKey) {
    const container = document.getElementById(`coding-agent-${taskKey}`)
    if (!container) return
    const pre = container.querySelector(".coding-agent-output")
    if (!pre) return
    pre.classList.remove("hidden")
    pre.textContent += output
    // Auto-scroll the output area
    pre.scrollTop = pre.scrollHeight
    this.scrollToBottom()
  }

  completeCodingAgent(message, outputSummary, taskKey, duration) {
    const container = document.getElementById(`coding-agent-${taskKey}`)
    if (!container) {
      // No existing container — render as a standalone message
      this.appendCodingAgentMessage(message, null, taskKey)
      return
    }
    const header = container.querySelector(".text-text-primary")
    if (header) {
      const durationText = duration ? ` (${duration}s)` : ""
      header.textContent = `${message}${durationText}`
    }
    const pre = container.querySelector(".coding-agent-output")
    if (pre && outputSummary) {
      pre.classList.remove("hidden")
      pre.textContent = outputSummary
      pre.scrollTop = pre.scrollHeight
    }
    this.scrollToBottom()
  }

  formatFileSize(bytes) {
    if (bytes < 1024) return `${bytes}B`
    if (bytes < 1048576) return `${(bytes/1024).toFixed(1)}KB`
    return `${(bytes/1048576).toFixed(1)}MB`
  }

  finishStreamBubble() {
    if (this.streamBubble && this.streamRawText) {
      this.streamBubble.innerHTML = this.renderMarkdown(this.streamRawText)
    }
    this.streamBubble = null
    this.streamRawText = ""
  }

  finishStream() {
    // Render final markdown from raw streamed text
    if (this.streamBubble && this.streamRawText) {
      this.streamBubble.innerHTML = this.renderMarkdown(this.streamRawText)
    }

    this.streaming = false
    this.streamBubble = null
    this.streamRawText = ""
    this.sendBtnTarget.disabled = false
    this.inputTarget.focus()
    
    // Hide working indicator when stream finishes
    this.hideWorking()

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

  // Render markdown for messages loaded from server (page load)
  renderExistingMarkdown() {
    this.messagesTarget.querySelectorAll(".chat-content").forEach(el => {
      const raw = el.textContent
      if (raw && raw.trim()) {
        el.innerHTML = this.renderMarkdown(raw)
      }
    })
  }

  renderMarkdown(text) {
    const raw = marked.parse(text)
    // Basic XSS sanitization — strip script tags and event handlers
    return raw
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "")
      .replace(/\son\w+\s*=/gi, " data-blocked=")
      .trim()
  }

  handlePlanningMode(isPlanning, message, summary) {
    // Find or create the planning mode indicator
    let planningIndicator = document.querySelector('[data-planning-indicator]')
    
    if (isPlanning) {
      // Show planning mode indicator
      if (!planningIndicator) {
        planningIndicator = this.createPlanningIndicator()
        // Insert after the header
        const header = this.element.querySelector('.border-b')
        header.insertAdjacentElement('afterend', planningIndicator)
      }
      planningIndicator.querySelector('[data-planning-message]').textContent = message
      planningIndicator.classList.remove('hidden')
      
      // Mark future tool calls as planning mode
      this.planningMode = true
    } else {
      // Hide planning mode indicator
      if (planningIndicator) {
        planningIndicator.classList.add('hidden')
      }
      
      // Show plan summary if provided
      if (summary && summary.trim()) {
        this.showPlanSummary(summary)
      }
      
      // Clear planning mode flag
      this.planningMode = false
    }
  }

  handlePlanMessage(data) {
    const { action, plan, current_phase, total_phases, phase_data, message, summary, markdown, learnings } = data

    switch (action) {
      case "display":
        this.displayPlan(plan)
        break
      case "start_execution":
        this.displayPlanExecution(plan, current_phase, total_phases)
        break
      case "phase_update":
        this.updatePhaseDisplay(current_phase, total_phases, phase_data)
        break
      case "exit":
        this.displayPlanSummary(summary, markdown, learnings)
        break
    }
  }

  displayPlan(plan) {
    const planDiv = document.createElement('div')
    planDiv.className = 'flex justify-start mb-4'
    planDiv.innerHTML = `
      <div class="max-w-4xl w-full">
        <div class="flex items-start gap-3">
          <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
            ${this.agentInitialValue}
          </div>
          <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100 w-full">
            <div class="text-blue-400 font-medium mb-3 flex items-center gap-2">
              <span>📋</span>
              <span>Work Plan</span>
              <button class="ml-auto text-xs px-2 py-1 bg-blue-600/20 hover:bg-blue-600/30 rounded border border-blue-500/30 text-blue-300" 
                      data-action="click->chat#togglePlanDetails">
                Show Details
              </button>
            </div>
            
            <div class="bg-surface-card px-3 py-2 rounded-lg border border-border-default">
              <div class="text-sm text-white font-semibold mb-2">${this.escapeHtml(plan.overview)}</div>
              <div class="text-xs text-text-muted mb-3">${this.escapeHtml(plan.context)}</div>
              
              <div class="space-y-2 mb-3">
                <div class="text-xs font-semibold text-text-muted">Phases:</div>
                <div class="space-y-1" data-plan-phases>
                  ${plan.phases.map((phase, idx) => `
                    <div class="flex items-center gap-2 text-xs">
                      <div class="w-6 h-6 rounded-full bg-blue-600/30 border border-blue-500/50 flex items-center justify-center text-blue-300 font-semibold">
                        ${phase.number}
                      </div>
                      <span class="text-gray-300">${this.escapeHtml(phase.name)}</span>
                    </div>
                  `).join('')}
                </div>
              </div>
              
              <div class="hidden space-y-3 text-xs" data-plan-details style="display: none;">
                ${plan.phases.map((phase, idx) => `
                  <div class="border-t border-border-default pt-2">
                    <div class="font-semibold text-blue-300 mb-1">Phase ${phase.number}: ${this.escapeHtml(phase.name)}</div>
                    <div class="text-gray-400 mb-1">
                      <strong>Objectives:</strong> ${phase.objectives.map(o => this.escapeHtml(o)).join('; ')}
                    </div>
                    <div class="text-gray-400 mb-1">
                      <strong>Approach:</strong> ${this.escapeHtml(phase.approach)}
                    </div>
                    <div class="text-gray-400">
                      <strong>Tools:</strong> ${phase.tools_needed.join(', ')}
                    </div>
                  </div>
                `).join('')}
              </div>
              
              <div class="border-t border-border-default pt-2 mt-3 text-xs text-text-muted">
                <strong>Success Criteria:</strong> ${plan.success_criteria.map(c => this.escapeHtml(c)).join('; ')}<br>
                <strong>Estimated Duration:</strong> ${this.escapeHtml(plan.estimated_duration)}
              </div>
            </div>
          </div>
        </div>
      </div>
    `

    this.messagesTarget.appendChild(planDiv)
    this.scrollToBottom()
  }

  togglePlanDetails(event) {
    const planDiv = event.target.closest('[data-plan-phases]')?.closest('.bg-surface-card')
    if (!planDiv) return

    const detailsDiv = planDiv.querySelector('[data-plan-details]')
    if (!detailsDiv) return

    const isHidden = detailsDiv.style.display === 'none'
    detailsDiv.style.display = isHidden ? 'block' : 'none'
    event.target.textContent = isHidden ? 'Hide Details' : 'Show Details'
  }

  displayPlanExecution(plan, currentPhase, totalPhases) {
    const executionDiv = document.createElement('div')
    executionDiv.className = 'flex justify-start mb-4'
    executionDiv.innerHTML = `
      <div class="max-w-2xl">
        <div class="flex items-start gap-3">
          <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
            ${this.agentInitialValue}
          </div>
          <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
            <div class="text-green-400 font-medium mb-2 flex items-center gap-2">
              <span>🚀</span>
              <span>Plan Execution Started</span>
            </div>
            <div class="text-xs text-text-muted">
              <div class="mb-2">Progress: <strong>${currentPhase}/${totalPhases}</strong></div>
              <div class="flex gap-1">
                ${plan.phases.map((_, idx) => `
                  <div class="h-1 flex-1 rounded-full ${(idx + 1) <= currentPhase ? 'bg-green-500' : 'bg-surface-card'}"></div>
                `).join('')}
              </div>
            </div>
          </div>
        </div>
      </div>
    `

    this.messagesTarget.appendChild(executionDiv)
    this.scrollToBottom()
  }

  updatePhaseDisplay(currentPhase, totalPhases, phaseData) {
    const phaseDiv = document.createElement('div')
    phaseDiv.className = 'flex justify-start mb-4'
    phaseDiv.innerHTML = `
      <div class="max-w-2xl">
        <div class="flex items-start gap-3">
          <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
            ${this.agentInitialValue}
          </div>
          <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
            <div class="text-cyan-400 font-medium mb-2 flex items-center gap-2">
              <span>📍</span>
              <span>Phase ${currentPhase}: ${this.escapeHtml(phaseData.name)}</span>
            </div>
            <div class="text-xs text-gray-400 space-y-1">
              <div><strong>Objectives:</strong> ${phaseData.objectives.map(o => this.escapeHtml(o)).join('; ')}</div>
              <div><strong>Approach:</strong> ${this.escapeHtml(phaseData.approach)}</div>
            </div>
          </div>
        </div>
      </div>
    `

    this.messagesTarget.appendChild(phaseDiv)
    this.scrollToBottom()
  }

  displayPlanSummary(summary, markdown, learnings) {
    const summaryDiv = document.createElement('div')
    summaryDiv.className = 'flex justify-start mb-4'
    
    const taskName = this.escapeHtml(summary.original_task)
    const completed = summary.phases_completed
    const total = summary.total_phases
    const duration = this.escapeHtml(summary.duration)
    
    const learningsHtml = learnings && learnings.length > 0
      ? learnings.map(l => `<li class="text-xs text-gray-400">- ${this.escapeHtml(l)}</li>`).join('')
      : '<li class="text-xs text-gray-400">- Plan executed successfully</li>'
    
    const resultsHtml = summary.key_results && summary.key_results.length > 0
      ? summary.key_results.map(r => `<li class="text-xs text-green-400">✓ ${this.escapeHtml(r)}</li>`).join('')
      : ''
    
    summaryDiv.innerHTML = `
      <div class="max-w-4xl w-full">
        <div class="flex items-start gap-3">
          <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
            ${this.agentInitialValue}
          </div>
          <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100 w-full">
            <div class="text-green-400 font-medium mb-3 flex items-center gap-2">
              <span>✅</span>
              <span>Plan Execution Complete</span>
            </div>
            
            <div class="bg-surface-card px-3 py-2 rounded-lg border border-border-default space-y-3 mb-3">
              <div class="text-sm">
                <strong class="text-white">Task:</strong>
                <div class="text-gray-300 ml-2">${taskName}</div>
              </div>
              
              <div class="text-sm">
                <strong class="text-white">Progress:</strong>
                <div class="text-gray-300 ml-2">${completed}/${total} phases completed in ${duration}</div>
                <div class="flex gap-1 mt-1">
                  ${Array.from({length: total}, (_, i) => `
                    <div class="h-1 flex-1 rounded-full ${(i + 1) <= completed ? 'bg-green-500' : 'bg-surface-card border border-border-default'}"></div>
                  `).join('')}
                </div>
              </div>
              
              ${resultsHtml ? `
                <div class="text-sm">
                  <strong class="text-white">Key Results:</strong>
                  <ul class="ml-2 space-y-1">
                    ${resultsHtml}
                  </ul>
                </div>
              ` : ''}
              
              <div class="text-sm">
                <strong class="text-white">Insights:</strong>
                <ul class="ml-2 space-y-1">
                  ${learningsHtml}
                </ul>
              </div>
            </div>
            
            <div class="space-y-2">
              <button class="w-full bg-blue-600 hover:bg-blue-700 text-white text-xs py-2 px-3 rounded font-medium transition"
                      data-action="click->chat#savePlanSummary"
                      data-markdown="${this.escapeHtml(markdown)}"
                      data-task="${this.escapeHtml(taskName)}">
                💾 Save Plan Summary
              </button>
              
              <div class="flex gap-2">
                <button class="flex-1 bg-gray-700 hover:bg-gray-600 text-white text-xs py-2 px-3 rounded font-medium transition"
                        data-action="click->chat#downloadPlanSummary"
                        data-markdown="${this.escapeHtml(markdown)}"
                        data-task="${this.escapeHtml(taskName)}">
                  📥 Download
                </button>
                <button class="flex-1 bg-gray-700 hover:bg-gray-600 text-white text-xs py-2 px-3 rounded font-medium transition"
                        data-action="click->chat#copyPlanSummary"
                        data-markdown="${this.escapeHtml(markdown)}">
                  📋 Copy
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    `

    this.messagesTarget.appendChild(summaryDiv)
    this.scrollToBottom()
  }

  savePlanSummary(event) {
    const markdown = event.target.dataset.markdown
    const taskName = event.target.dataset.task || 'plan-summary'
    
    if (!markdown) return
    
    const filename = `${taskName.toLowerCase().replace(/\s+/g, '-')}-summary.md`
    
    // Show save options
    this.showSaveOptions(markdown, filename)
  }

  downloadPlanSummary(event) {
    const markdown = event.target.dataset.markdown
    const taskName = event.target.dataset.task || 'plan-summary'
    
    if (!markdown) return
    
    const filename = `${taskName.toLowerCase().replace(/\s+/g, '-')}-summary.md`
    const blob = new Blob([markdown], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  copyPlanSummary(event) {
    const markdown = event.target.dataset.markdown
    if (!markdown) return
    
    navigator.clipboard.writeText(markdown).then(() => {
      // Show confirmation
      const originalText = event.target.textContent
      event.target.textContent = '✓ Copied!'
      setTimeout(() => {
        event.target.textContent = originalText
      }, 2000)
    }).catch(() => {
      alert('Failed to copy to clipboard')
    })
  }

  showSaveOptions(markdown, filename) {
    // Create modal for save options
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-50'
    modal.innerHTML = `
      <div class="bg-surface-raised rounded-lg p-6 max-w-md w-full mx-4 border border-border-default">
        <h2 class="text-white font-semibold mb-4 flex items-center gap-2">
          <span>💾</span>
          Save Plan Summary
        </h2>
        
        <p class="text-text-muted text-sm mb-4">
          Where would you like to save this plan summary?
        </p>
        
        <div class="space-y-2 mb-6">
          <button class="w-full text-left bg-surface-card hover:bg-surface-raised border border-border-default rounded p-3 text-sm text-white transition"
                  data-action="click->chat#workspaceSave"
                  data-markdown="${this.escapeHtml(markdown)}"
                  data-filename="${this.escapeHtml(filename)}">
            <div class="font-semibold">💾 Save to Workspace</div>
            <div class="text-xs text-text-muted">/workspace/plans/</div>
          </button>
          
          <button class="w-full text-left bg-surface-card hover:bg-surface-raised border border-border-default rounded p-3 text-sm text-white transition"
                  data-action="click->chat#downloadSave"
                  data-markdown="${this.escapeHtml(markdown)}"
                  data-filename="${this.escapeHtml(filename)}">
            <div class="font-semibold">📥 Download to Computer</div>
            <div class="text-xs text-text-muted">Save as markdown file</div>
          </button>
          
          <button class="w-full text-left bg-surface-card hover:bg-surface-raised border border-border-default rounded p-3 text-sm text-white transition"
                  data-action="click->chat#clipboardSave"
                  data-markdown="${this.escapeHtml(markdown)}">
            <div class="font-semibold">📋 Copy to Clipboard</div>
            <div class="text-xs text-text-muted">Ready to paste anywhere</div>
          </button>
        </div>
        
        <button class="w-full bg-gray-700 hover:bg-gray-600 text-white text-sm py-2 rounded font-medium transition"
                data-action="click->chat#closeModal">
          Close
        </button>
      </div>
    `
    
    document.body.appendChild(modal)
    modal.dataset.controller = 'chat'
    
    // Close on escape
    const closeHandler = (e) => {
      if (e.key === 'Escape') {
        modal.remove()
        document.removeEventListener('keydown', closeHandler)
      }
    }
    document.addEventListener('keydown', closeHandler)
  }

  workspaceSave(event) {
    const markdown = event.target.closest('button').dataset.markdown
    const filename = event.target.closest('button').dataset.filename
    
    if (!markdown || !filename) return
    
    // Send to backend to save to workspace
    fetch('/api/v1/plans/save', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfValue
      },
      body: JSON.stringify({
        filename: filename,
        content: markdown,
        location: 'workspace'
      })
    })
    .then(r => r.json())
    .then(data => {
      if (data.success) {
        this.showNotification('✓ Saved to /workspace/plans/' + filename)
        this.closeModal()
      } else {
        alert('Failed to save: ' + data.error)
      }
    })
    .catch(e => alert('Error saving: ' + e.message))
  }

  downloadSave(event) {
    const markdown = event.target.closest('button').dataset.markdown
    const filename = event.target.closest('button').dataset.filename
    
    if (!markdown || !filename) return
    
    const blob = new Blob([markdown], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    
    this.closeModal()
  }

  clipboardSave(event) {
    const markdown = event.target.closest('button').dataset.markdown
    
    if (!markdown) return
    
    navigator.clipboard.writeText(markdown).then(() => {
      this.showNotification('✓ Copied to clipboard!')
      this.closeModal()
    }).catch(() => {
      alert('Failed to copy to clipboard')
    })
  }

  closeModal(event) {
    const modal = document.querySelector('[data-controller="chat"] .fixed')
    if (modal) modal.remove()
  }

  showNotification(message) {
    const notification = document.createElement('div')
    notification.className = 'fixed bottom-4 right-4 bg-green-600 text-white px-4 py-2 rounded shadow-lg text-sm z-50'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  createPlanningIndicator() {
    const indicator = document.createElement('div')
    indicator.setAttribute('data-planning-indicator', '')
    indicator.className = 'bg-amber-900/30 border-b border-amber-600/30 px-6 py-3 flex items-center gap-3'
    indicator.innerHTML = `
      <div class="text-amber-400 animate-pulse">🧠</div>
      <span class="text-amber-200 text-sm font-medium" data-planning-message>Planning mode active...</span>
      <div class="ml-auto text-amber-400/60 text-xs">Tool calls shown for planning context</div>
    `
    return indicator
  }

  showPlanSummary(summary) {
    const summaryDiv = document.createElement('div')
    summaryDiv.className = 'flex justify-start mb-4'
    summaryDiv.innerHTML = `
      <div class="max-w-2xl">
        <div class="flex items-start gap-3">
          <div class="w-8 h-8 bg-surface-raised rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
            ${this.agentInitialValue}
          </div>
          <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
            <div class="text-amber-400 font-medium mb-2 flex items-center gap-2">
              <span>📋</span>
              <span>Plan Summary</span>
            </div>
            <div class="whitespace-pre-wrap text-sm bg-surface-card px-3 py-2 rounded-lg border border-border-default">
              ${this.escapeHtml(summary)}
            </div>
          </div>
        </div>
      </div>
    `
    
    this.messagesTarget.appendChild(summaryDiv)
    this.scrollToBottom()
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
