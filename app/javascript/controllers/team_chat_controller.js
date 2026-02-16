import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "thinkingArea", "emptyState", "mentionBar", "toolToggle", "fileInput", "imagePreview", "imageThumbs", "attachPreview", "attachList", "hashtagDropdown"]
  static values = { sessionId: Number, messageUrl: String, csrf: String, agents: Array }

  connect() {
    this.consumer = createConsumer()
    this.sending = false
    this.streamBubbles = {} // keyed by agent_id
    this.agentColors = {}
    this.pendingImages = []
    this.pendingFiles = []
    this.pinnedAgents = [] // sticky @mentions that persist across sends
    this.showTools = false // tool calls hidden by default
    this.hashtagActions = []
    this.hashtagDropdownVisible = false

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

    this.loadHashtagActions()
    this.scrollToBottom()
    
    // Close hashtag dropdown when clicking outside
    document.addEventListener('click', this.handleOutsideClick.bind(this))
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
    if (this.consumer) this.consumer.disconnect()
    document.removeEventListener('click', this.handleOutsideClick.bind(this))
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
           data-action="click->team-chat#insertHashtag"
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
    if (!this.element.contains(event.target)) {
      this.hideHashtagDropdown()
    }
  }

  handleEscape(event) {
    if (event.key === 'Escape' && this.hashtagDropdownVisible) {
      event.preventDefault()
      this.hideHashtagDropdown()
    }
  }

  handleMessage(data) {
    switch (data.type) {
      case "user_message":
        this.appendUserMessage(data.content, data.target_agent_name, data.images, data.files)
        break
      case "thinking":
        this.showThinking(data.agent_id, data.agent_name)
        break
      case "thinking_start":
        this.showAgentThinkingBubble(data.agent_id, data.agent_name)
        break
      case "thinking_stream":
        this.appendAgentThinkingToken(data.agent_id, data.content)
        break
      case "thinking_stop":
        this.collapseAgentThinking(data.agent_id)
        break
      case "tool_start":
        // Only hide thinking dots if tools are visible (otherwise keep the indicator)
        if (this.showTools) this.hideThinking(data.agent_id)
        // Finalize current bubble so tool narration doesn't merge with the response
        this.finalizeAgentMessage(data.agent_id)
        if (this.showTools) this.showTeamToolStart(data.agent_id, data.agent_name, data.tool, data.input)
        break
      case "tool_result":
        if (this.showTools) this.showTeamToolResult(data.agent_id, data.tool, data.output, data.success)
        break
      case "token":
        this.hideThinking(data.agent_id)
        this.appendAgentToken(data.agent_id, data.agent_name, data.content)
        break
      case "agent_done":
        this.hideThinking(data.agent_id)
        this.finalizeAgentMessage(data.agent_id)
        break
      case "file_attachment":
        this.appendFileAttachment(data.agent_id, data.agent_name, data.attachment)
        break
      case "error":
        this.hideThinking(data.agent_id)
        this.showError(data.content)
        break
    }
  }

  async send() {
    let message = this.inputTarget.value.trim()
    if (!message && this.pendingImages.length === 0 && this.pendingFiles.length === 0) return
    if (this.sending) return

    this.sending = true
    this.sendBtnTarget.disabled = true

    // Restore pinned prefix after clearing
    const prefix = this.pinnedAgents.map(n => `@${n}`).join(" ")
    this.inputTarget.value = prefix ? `${prefix} ` : ""
    this.inputTarget.style.height = "auto"

    if (this.hasEmptyStateTarget) this.emptyStateTarget.remove()
    if (this.hasMentionBarTarget) this.mentionBarTarget.classList.add("hidden")

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
      this.pendingFiles = []
      this.updateFilePreview()
    } catch (e) {
      this.showError("Failed to send message")
    }

    this.sending = false
    this.sendBtnTarget.disabled = false
    this.inputTarget.focus()
  }

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

    // Sync pinned agents — if user deletes an @Name from the text, unpin it
    const val = input.value
    this.pinnedAgents = this.pinnedAgents.filter(name => val.includes(`@${name}`))
    
    // Check for hashtag input
    this.handleHashtagInput()
  }

  autoResize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 150) + "px"
    
    // Check for hashtag input
    this.handleHashtagInput()
  }

  insertMention(event) {
    const name = event.currentTarget.dataset.agentName
    const input = this.inputTarget

    // Remove trailing @ from input
    const val = input.value
    const atPos = val.lastIndexOf("@")
    if (atPos >= 0 && atPos === val.length - 1) {
      input.value = val.substring(0, atPos)
    }

    // Pin the agent (adds @Name to start of input, persists across sends)
    this.pinAgent(name)

    if (this.hasMentionBarTarget) this.mentionBarTarget.classList.add("hidden")
    input.focus()
  }

  toggleToolCalls() {
    this.showTools = this.hasToolToggleTarget ? this.toolToggleTarget.checked : false
    // Show/hide existing tool blocks
    this.messagesTarget.querySelectorAll("[data-tool-block]").forEach(el => {
      el.style.display = this.showTools ? "" : "none"
    })
  }

  pinAgentFromSidebar(event) {
    const name = event.currentTarget.dataset.agentName
    this.pinAgent(name)
    this.inputTarget.focus()
  }

  pinAgent(name) {
    if (this.pinnedAgents.includes(name)) return
    this.pinnedAgents.push(name)
    this.rebuildInputPrefix()
  }

  // Rebuild the @mentions prefix in the textarea
  rebuildInputPrefix() {
    const input = this.inputTarget
    // Strip any existing @mentions from the start
    const userText = input.value.replace(/^(@\S+\s+)+/, "").trimStart()
    const prefix = this.pinnedAgents.map(n => `@${n}`).join(" ")
    input.value = prefix ? `${prefix} ${userText}` : userText
    // Place cursor at end
    input.selectionStart = input.selectionEnd = input.value.length
  }

  appendUserMessage(content, targetName, images, files) {
    const targetLabel = targetName ? `<div class="text-xs text-text-faint text-right mb-1">→ @${this.esc(targetName)}</div>` : ""
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
        return `<span class="inline-flex items-center gap-1.5 bg-brand-dark/50 rounded-lg px-2.5 py-1 text-xs"><span class="font-mono text-brand-light">${this.esc(ext)}</span> ${this.esc(f.filename)} <span class="text-brand-light/60">${size}</span></span>`
      }).join("")
      filesHtml = `<div class="flex flex-wrap gap-1.5 mb-2">${pills}</div>`
    }
    const html = `
      <div class="flex justify-end">
        <div class="max-w-2xl">
          ${targetLabel}
          <div class="bg-brand rounded-2xl rounded-br-md px-4 py-3 text-white">
            ${imagesHtml}${filesHtml}
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
        <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-text-muted">
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

  showAgentThinkingBubble(agentId, agentName) {
    const color = this.agentColors[agentId] || "gray"
    const initial = agentName ? agentName[0].toUpperCase() : "?"
    const id = `agent-thinking-${agentId}`
    if (document.getElementById(id)) return

    const html = `
      <div class="flex justify-start" id="${id}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-purple-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">${initial}</div>
            <div class="bg-purple-900/30 border border-purple-700/50 rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-purple-400 text-sm font-medium mb-1" data-thinking-header="${agentId}">
                <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                ${this.esc(agentName)} is thinking...
              </div>
              <div class="text-purple-300/70 text-xs font-mono whitespace-pre-wrap max-h-32 overflow-y-auto" data-thinking-content="${agentId}"></div>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  appendAgentThinkingToken(agentId, content) {
    const el = document.querySelector(`[data-thinking-content="${agentId}"]`)
    if (el && content) {
      el.textContent += content
      this.scrollToBottom()
    }
  }

  collapseAgentThinking(agentId) {
    const header = document.querySelector(`[data-thinking-header="${agentId}"]`)
    const content = document.querySelector(`[data-thinking-content="${agentId}"]`)
    if (header) {
      header.innerHTML = `<span class="cursor-pointer" onclick="this.closest('[id^=agent-thinking-]').querySelector('[data-thinking-content]').classList.toggle('hidden')">🧠 Thought process (click to toggle)</span>`
    }
    if (content) content.classList.add("hidden")
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
                <div class="text-xs text-text-muted mb-1">${this.esc(agentName)} <span class="text-gray-600">· ${this.esc(role)}</span></div>
                <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
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

  showTeamToolStart(agentId, agentName, toolName, input) {
    const color = this.agentColors[agentId] || "gray"
    const initial = agentName ? agentName[0].toUpperCase() : "?"
    const inputStr = typeof input === "object" ? JSON.stringify(input) : (input || "")
    const shortInput = inputStr.length > 80 ? inputStr.substring(0, 80) + "..." : inputStr
    const toolId = `team-tool-${agentId}-${Date.now()}`

    const html = `
      <div class="flex justify-start" data-tool-block="${toolId}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-${color}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">⚡</div>
            <div class="bg-surface-card border border-border-default rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-yellow-400 text-sm font-medium" data-tool-header="${toolId}">
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                ${this.esc(agentName)} running ${this.esc(toolName || "")}
              </div>
              <code class="text-text-muted text-xs mt-1 block">${this.esc(shortInput)}</code>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    // Hide if tools toggle is off
    if (!this.showTools) {
      const el = document.querySelector(`[data-tool-block="${toolId}"]`)
      if (el) el.style.display = "none"
    }
    this.lastToolId = { [agentId]: toolId }
    this.scrollToBottom()
  }

  showTeamToolResult(agentId, toolName, output, success) {
    const toolId = this.lastToolId?.[agentId]
    if (!toolId) return
    const header = document.querySelector(`[data-tool-header="${toolId}"]`)
    if (header) {
      const color = success ? "text-green-400" : "text-red-400"
      const icon = success ? "✓" : "✗"
      header.className = `flex items-center gap-2 ${color} text-sm font-medium`
      header.innerHTML = `${icon} ${this.esc(toolName || "")} completed`
    }
    const block = document.querySelector(`[data-tool-block="${toolId}"]`)
    if (block) {
      const codeEl = block.querySelector("code")
      if (codeEl && output) {
        const shortOutput = output.length > 200 ? output.substring(0, 200) + "..." : output
        codeEl.textContent = shortOutput
      }
    }
    this.scrollToBottom()
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

  appendFileAttachment(agentId, agentName, attachment) {
    // Render agent-sent file attachment (from file_send or image_generate tools)
    const color = this.agentColors[agentId] || "gray"
    const initial = agentName ? agentName[0].toUpperCase() : "?"
    const isImage = attachment.is_image || attachment.content_type?.startsWith('image/')
    
    let contentHtml = ""
    if (isImage) {
      // Render inline image
      contentHtml = `<img src="${attachment.url}" class="max-w-xs max-h-64 rounded-lg" loading="lazy" alt="${this.esc(attachment.filename)}">`
    } else {
      // Render document download pill
      const ext = attachment.filename.split(".").pop().toUpperCase()
      const size = this.formatFileSize(attachment.byte_size)
      contentHtml = `
        <a href="${attachment.url}" download="${this.esc(attachment.filename)}" 
           class="inline-flex items-center gap-2 bg-surface-card rounded-lg px-3 py-2 hover:bg-surface-raised transition border border-border-default">
          <span class="text-amber-400 font-mono text-xs">${this.esc(ext)}</span>
          <span class="text-text-primary text-sm">${this.esc(attachment.filename)}</span>
          <span class="text-text-faint text-xs">${size}</span>
          <svg class="w-4 h-4 text-text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
          </svg>
        </a>`
    }

    const agent = this.agentsValue.find(a => a.id === agentId)
    const role = agent ? agent.role : ""

    const html = `
      <div class="flex justify-start">
        <div class="max-w-2xl">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-${color}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
              ${initial}
            </div>
            <div>
              <div class="text-xs text-text-muted mb-1">${this.esc(agentName)} <span class="text-gray-600">· ${this.esc(role)}</span></div>
              <div class="bg-surface-raised rounded-2xl rounded-bl-md px-4 py-3">
                ${contentHtml}
              </div>
            </div>
          </div>
        </div>
      </div>`
    
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  formatFileSize(bytes) {
    if (bytes < 1024) return `${bytes}B`
    if (bytes < 1048576) return `${(bytes/1024).toFixed(1)}KB`
    return `${(bytes/1048576).toFixed(1)}MB`
  }

  // ─── File Handling ──────────────────────────────────────

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
    event.currentTarget.classList.add("ring-2", "ring-purple-500")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-purple-500")
  }

  drop(event) {
    event.preventDefault()
    event.currentTarget.classList.remove("ring-2", "ring-purple-500")
    const files = Array.from(event.dataTransfer.files)
    files.forEach(f => this.addFile(f))
  }

  addFile(file) {
    const totalFiles = this.pendingImages.length + this.pendingFiles.length
    if (totalFiles >= 10) return

    if (file.type.startsWith("image/")) {
      this.pendingImages.push(file)
      this.updateImagePreview()
    } else {
      if (file.size > 10 * 1024 * 1024) return
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

  clearFiles() {
    this.pendingFiles = []
    this.updateFilePreview()
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
        <span class="text-amber-400 font-mono text-xs">${this.esc(ext)}</span>
        <span class="text-text-primary truncate max-w-[150px]">${this.esc(file.name)}</span>
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
