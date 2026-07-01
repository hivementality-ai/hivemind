import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { marked } from "marked"

export default class extends Controller {
  static targets = ["messages", "input", "sendBtn", "stopBtn", "thinkingArea", "emptyState", "mentionBar", "toolToggle", "fileInput", "imagePreview", "imageThumbs", "attachPreview", "attachList", "hashtagDropdown", "titleText", "titleInput"]
  static values = { sessionId: Number, messageUrl: String, updateUrl: String, interruptUrl: String, csrf: String, agents: Array }

  connect() {
    this.consumer = createConsumer()
    this.sending = false
    this.streamBubbles = {} // keyed by agent_id
    this.streamRawTexts = {} // raw text per agent for markdown rendering
    this.activeAgents = new Set() // agent IDs currently streaming

    marked.setOptions({ breaks: true, gfm: true, silent: true })
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
        received: (data) => this.handleMessage(data)
      }
    )

    this.loadHashtagActions()
    this.renderExistingMarkdown()
    this.scrollToBottom()
    
    // Close hashtag dropdown when clicking outside
    this._boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener('click', this._boundOutsideClick)

    // Request notification permission for background alerts
    if ("Notification" in window && Notification.permission === "default") {
      Notification.requestPermission()
    }
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
           data-action="click->team-chat#insertHashtag"
           data-hashtag="${action.name}">
        <code class="text-purple-400 font-mono text-sm">#${this.esc(action.name)}</code>
        <span class="text-text-muted text-xs flex-1">${this.esc(action.description)}</span>
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

  handleMessage(data) {
    switch (data.type) {
      case "user_message":
        this.appendUserMessage(data.content, data.target_agent_name, data.images, data.files)
        break
      case "thinking":
        this.activeAgents.add(data.agent_id)
        this.showStopBtn()
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
        this.notifyIfHidden(data.agent_name, this.streamRawTexts[data.agent_id] || data.content || "")
        this.activeAgents.delete(data.agent_id)
        if (this.activeAgents.size === 0) this.hideStopBtn()
        this.hideThinking(data.agent_id)
        this.finalizeAgentMessage(data.agent_id, data.content)
        break
      case "cancelled":
        this.activeAgents.delete(data.agent_id)
        if (this.activeAgents.size === 0) this.hideStopBtn()
        this.hideThinking(data.agent_id)
        this.finalizeAgentMessage(data.agent_id)
        this.appendSystemNotice(`⏹ ${data.agent_name} was stopped`)
        break
      case "redirected":
        this.activeAgents.delete(data.agent_id)
        if (this.activeAgents.size === 0) this.hideStopBtn()
        this.hideThinking(data.agent_id)
        this.finalizeAgentMessage(data.agent_id)
        this.appendSystemNotice("↪ Redirecting...")
        break
      case "inject":
        this.appendUserMessage(data.message, null, [], [])
        break
      case "interrupt_sent":
        // Visual feedback — briefly flash stop button
        if (this.hasStopBtnTarget) {
          this.stopBtnTarget.classList.add("opacity-50")
          setTimeout(() => this.stopBtnTarget.classList.remove("opacity-50"), 300)
        }
        break
      case "file_attachment":
        this.appendFileAttachment(data.agent_id, data.agent_name, data.attachment)
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
      case "sub_agent_started":
        this.showSubAgentWorking(data.child_agent, data.task, data.task_key)
        break
      case "sub_agent_complete":
        this.hideSubAgentWorking(data.task_key)
        break
      case "agent_to_agent":
        this.appendAgentToAgentMessage(data.from_agent_id, data.from_agent_name, data.to_agent_id, data.to_agent_name, data.content)
        break
      case "agent_to_agent_response":
        this.appendAgentToAgentMessage(data.from_agent_id, data.from_agent_name, data.to_agent_id, data.to_agent_name, data.content)
        break
      case "title_update":
        this.updateTitle(data.title)
        break
      case "agent_question":
        this.showAgentQuestion(data.agent_id, data.agent_name, data.questions, data.timestamp)
        break
      case "error":
        this.activeAgents.delete(data.agent_id)
        if (this.activeAgents.size === 0) this.hideStopBtn()
        this.hideThinking(data.agent_id)
        this.showError(data.content)
        break
    }
  }

  async send() {
    let message = this.inputTarget.value.trim()
    if (!message && this.pendingImages.length === 0 && this.pendingFiles.length === 0) return
    if (this.sending) return

    // If agents are actively streaming, treat this as a redirect
    if (this.activeAgents.size > 0 && message) {
      const prefix = this.pinnedAgents.map(n => `@${n}`).join(" ")
      this.inputTarget.value = prefix ? `${prefix} ` : ""
      this.inputTarget.style.height = "auto"
      await this.sendInterrupt("redirect", message)
      return
    }

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

    // Sync pinned agents with text — auto-pin typed @Names, unpin removed ones
    const val = input.value
    const agentNames = this.agentsValue.map(a => a.name)
    agentNames.forEach(name => {
      if (val.includes(`@${name}`) && !this.pinnedAgents.includes(name)) {
        this.pinnedAgents.push(name)
      }
    })
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

  createAgentBubble(agentId, agentName) {
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
                <div class="whitespace-pre-wrap chat-content" id="${bubbleId}"></div>
              </div>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.streamBubbles[agentId] = document.getElementById(bubbleId)
  }

  appendAgentToken(agentId, agentName, content) {
    if (!this.streamBubbles[agentId]) {
      this.createAgentBubble(agentId, agentName)
    }

    if (!this.streamRawTexts[agentId]) this.streamRawTexts[agentId] = ""
    this.streamRawTexts[agentId] += content
    this.streamBubbles[agentId].textContent = this.streamRawTexts[agentId]
    this.scrollToBottom()
  }

  finalizeAgentMessage(agentId, fallbackContent = null) {
    const text = this.streamRawTexts[agentId] || fallbackContent
    if (this.streamBubbles[agentId] && text) {
      this.streamBubbles[agentId].innerHTML = this.renderMarkdown(text)
    } else if (this.streamBubbles[agentId] && !text) {
      // Bubble exists but has no content — remove it so it doesn't show as blank
      const wrapper = this.streamBubbles[agentId].closest('[data-agent-bubble]')
      if (wrapper) wrapper.remove()
    } else if (!this.streamBubbles[agentId] && text) {
      // No bubble was created (tokens never streamed) — create one now
      const agent = this.agentsValue.find(a => a.id === agentId)
      const agentName = agent ? agent.name : "Agent"
      this.createAgentBubble(agentId, agentName)
      if (this.streamBubbles[agentId]) {
        this.streamBubbles[agentId].innerHTML = this.renderMarkdown(text)
      }
    }
    delete this.streamBubbles[agentId]
    delete this.streamRawTexts[agentId]
  }

  appendAgentToAgentMessage(fromId, fromName, toId, toName, content) {
    const fromColor = this.agentColors[fromId] || "gray"
    const fromInitial = fromName ? fromName[0].toUpperCase() : "?"

    const html = `
      <div class="flex justify-start" data-agent-bubble="${fromId}">
        <div class="max-w-2xl">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-${fromColor}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
              ${fromInitial}
            </div>
            <div>
              <div class="text-xs text-text-muted mb-1 flex items-center gap-1">
                <span>${this.esc(fromName)}</span>
                <svg class="w-3 h-3 text-text-faint" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"></path></svg>
                <span>${this.esc(toName)}</span>
              </div>
              <div class="bg-surface-card border border-border-default rounded-2xl rounded-bl-md px-4 py-3 text-gray-100">
                <div class="whitespace-pre-wrap chat-content">${this.renderMarkdown(content)}</div>
              </div>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  notifyIfHidden(agentName, responseText) {
    if (document.hidden && "Notification" in window && Notification.permission === "granted") {
      const body = responseText.length > 0
        ? responseText.replace(/[#*_`~\[\]]/g, "").substring(0, 120)
        : "Response ready"
      new Notification(agentName || "Team Chat", {
        body: body,
        tag: `hivemind-team-${this.sessionIdValue}`
      })
    }
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

  appendCodingAgentMessage(message, cli, taskKey) {
    const html = `
      <div class="flex justify-start" id="coding-agent-${taskKey}">
        <div class="max-w-2xl w-full">
          <div class="bg-surface-raised rounded-2xl px-4 py-3 w-full">
            <div class="text-text-primary text-sm font-medium mb-1">⚡ ${this.esc(message)}</div>
            <pre class="coding-agent-output text-xs text-text-muted bg-surface-base rounded p-2 max-h-48 overflow-y-auto whitespace-pre-wrap hidden"></pre>
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
    pre.scrollTop = pre.scrollHeight
    this.scrollToBottom()
  }

  completeCodingAgent(message, outputSummary, taskKey, duration) {
    const container = document.getElementById(`coding-agent-${taskKey}`)
    if (!container) {
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
    return raw
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "")
      .replace(/\son\w+\s*=/gi, " data-blocked=")
      .trim()
  }

  // ─── Inline Title Edit ─────────────────────────────────

  editTitle() {
    if (!this.hasTitleTextTarget || !this.hasTitleInputTarget) return
    this.titleInputTarget.value = this.titleTextTarget.textContent.trim()
    this.titleTextTarget.classList.add("hidden")
    this.titleInputTarget.classList.remove("hidden")
    this.titleInputTarget.focus()
    this.titleInputTarget.select()
  }

  handleTitleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.saveTitle()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.cancelTitleEdit()
    }
  }

  async saveTitle() {
    if (!this.hasTitleInputTarget || !this.hasTitleTextTarget) return
    const newTitle = this.titleInputTarget.value.trim()

    this.titleInputTarget.classList.add("hidden")
    this.titleTextTarget.classList.remove("hidden")

    if (!newTitle || newTitle.length > 100) return

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
        body: JSON.stringify({ title: newTitle })
      })
      if (response.ok) {
        this.titleTextTarget.textContent = newTitle
        document.title = newTitle
        // Update active sidebar entry
        const activeSidebarEntry = this.element.querySelector(".bg-surface-raised .text-sm.text-white.truncate")
        if (activeSidebarEntry) activeSidebarEntry.textContent = newTitle
      }
    } catch (e) {
      console.error("Failed to save title:", e)
    }
  }

  cancelTitleEdit() {
    if (!this.hasTitleInputTarget || !this.hasTitleTextTarget) return
    this.titleInputTarget.classList.add("hidden")
    this.titleTextTarget.classList.remove("hidden")
  }

  updateTitle(title) {
    if (!title) return
    document.title = title
    if (this.hasTitleTextTarget) {
      this.titleTextTarget.textContent = title
    }
    const activeSidebarEntry = this.element.querySelector(".bg-surface-raised .text-sm.text-white.truncate")
    if (activeSidebarEntry) activeSidebarEntry.textContent = title
  }

  // ─── Interrupt / Stop ───────────────────────────────────

  stopAll() {
    this.sendInterrupt("cancel")
  }

  async sendInterrupt(type, message = null) {
    if (!this.hasInterruptUrlValue) return
    try {
      const body = { type }
      if (message) body.message = message
      await fetch(this.interruptUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue, "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
    } catch (e) {
      console.error("Failed to send interrupt:", e)
    }
  }

  showStopBtn() {
    if (this.hasStopBtnTarget) this.stopBtnTarget.classList.remove("hidden")
  }

  hideStopBtn() {
    if (this.hasStopBtnTarget) this.stopBtnTarget.classList.add("hidden")
  }

  appendSystemNotice(text) {
    const html = `
      <div class="flex justify-center my-1">
        <span class="text-xs text-text-faint italic">${this.esc(text)}</span>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  showSubAgentWorking(agentName, task, taskKey) {
    const id = `sub-agent-${taskKey}`
    if (document.getElementById(id)) return
    const shortTask = task && task.length > 100 ? task.substring(0, 100) + "..." : (task || "")
    const html = `
      <div class="flex justify-start" id="${id}">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-purple-600/30 border border-purple-500/50 rounded-lg flex items-center justify-center text-purple-300 text-xs font-bold flex-shrink-0 mt-1">🔀</div>
            <div class="bg-purple-900/20 border border-purple-500/30 rounded-xl px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-purple-400 text-sm font-medium">
                <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                ${this.esc(agentName || "Sub-agent")} working...
              </div>
              <div class="text-purple-300/70 text-xs mt-1">${this.esc(shortTask)}</div>
            </div>
          </div>
        </div>
      </div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }

  hideSubAgentWorking(taskKey) {
    const el = document.getElementById(`sub-agent-${taskKey}`)
    if (el) el.remove()
  }

  showAgentQuestion(agentId, agentName, questions, timestamp) {
    // Stop any thinking indicators for this agent
    this.hideThinking(agentId)

    // Normalise: accept legacy plain-string or new questions array
    const questionList = Array.isArray(questions)
      ? questions
      : [ { question: String(questions || ""), options: [], multiSelect: false } ]

    const color = this.agentColors[agentId] || "blue"
    const widgetId = `tc-agent-question-${agentId}-${Date.now()}`

    const questionsHtml = questionList.map((q, qi) => {
      const hasOptions = Array.isArray(q.options) && q.options.length > 0
      const multi = q.multiSelect === true

      const optionsHtml = hasOptions ? q.options.map((opt, oi) => {
        const inputId = `${widgetId}-q${qi}-o${oi}`
        const descHtml = opt.description
          ? `<span class="text-blue-300/60 text-xs ml-1">${this.esc(opt.description)}</span>`
          : ""
        return `
          <label for="${inputId}" class="flex items-start gap-2 cursor-pointer hover:bg-blue-800/20 rounded-lg px-2 py-1.5 transition-colors">
            <input
              type="checkbox"
              id="${inputId}"
              data-widget="${widgetId}"
              data-qi="${qi}"
              data-oi="${oi}"
              class="mt-0.5 accent-blue-400 cursor-pointer flex-shrink-0"
            />
            <span class="text-white text-sm leading-snug">
              ${this.esc(opt.label)}${descHtml}
            </span>
          </label>`
      }).join("") : ""

      const otherId = `${widgetId}-q${qi}-other`
      const otherCheckId = `${widgetId}-q${qi}-other-check`
      const otherHtml = `
        <label for="${otherCheckId}" class="flex items-start gap-2 cursor-pointer hover:bg-blue-800/20 rounded-lg px-2 py-1.5 transition-colors">
          <input
            type="checkbox"
            id="${otherCheckId}"
            data-widget="${widgetId}"
            data-qi="${qi}"
            data-other="true"
            class="mt-0.5 accent-blue-400 cursor-pointer flex-shrink-0"
          />
          <span class="text-blue-300/70 text-sm italic leading-snug">Other / free text</span>
        </label>
        <div id="${otherId}-wrap" class="hidden pl-6 pt-1">
          <input
            type="text"
            id="${otherId}"
            placeholder="Type your answer…"
            class="w-full bg-blue-950/50 border border-blue-600/40 rounded-lg px-3 py-1.5 text-white text-sm placeholder-blue-400/50 focus:outline-none focus:border-blue-400"
          />
        </div>`

      const headerHtml = q.header
        ? `<span class="inline-block text-xs font-semibold bg-blue-700/40 text-blue-200 rounded px-2 py-0.5 mb-2">${this.esc(q.header)}</span>`
        : ""

      return `
        <div class="mb-4 last:mb-0" data-question-block="${qi}">
          ${headerHtml}
          <p class="text-white text-sm font-medium mb-2">${this.esc(q.question)}</p>
          <div class="space-y-0.5">
            ${optionsHtml}
            ${otherHtml}
          </div>
        </div>`
    }).join("")

    const nameLabel = agentName ? this.esc(agentName) : "Agent"

    const html = `
      <div class="flex justify-start mb-4" id="${widgetId}-wrap">
        <div class="max-w-2xl w-full">
          <div class="flex items-start gap-3">
            <div class="w-8 h-8 bg-${color}-600 rounded-lg flex items-center justify-center text-white font-bold text-xs flex-shrink-0 mt-1">
              ${nameLabel.charAt(0).toUpperCase()}
            </div>
            <div class="bg-blue-900/30 border border-blue-600/50 rounded-2xl rounded-bl-md px-4 py-3 w-full">
              <div class="flex items-center gap-2 text-blue-400 text-sm font-medium mb-3">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                ${nameLabel} is asking:
              </div>
              <div id="${widgetId}">
                ${questionsHtml}
              </div>
              <button
                data-action="click->team-chat#submitAgentQuestion"
                data-widget-id="${widgetId}"
                data-question-count="${questionList.length}"
                class="mt-4 w-full bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium rounded-xl px-4 py-2 transition-colors"
              >
                Submit
              </button>
            </div>
          </div>
        </div>
      </div>`

    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()

    // Wire "Other" checkbox to show/hide free-text input
    const wrapEl = document.getElementById(`${widgetId}-wrap`)
    if (wrapEl) {
      wrapEl.querySelectorAll(`input[data-other="true"]`).forEach(cb => {
        cb.addEventListener("change", () => {
          const qi = cb.dataset.qi
          const wrap = document.getElementById(`${widgetId}-q${qi}-other-wrap`)
          if (wrap) wrap.classList.toggle("hidden", !cb.checked)
        })
      })
    }
  }

  async submitAgentQuestion(event) {
    const btn = event.currentTarget
    const widgetId = btn.dataset.widgetId
    const questionCount = parseInt(btn.dataset.questionCount, 10)

    const answers = []
    for (let qi = 0; qi < questionCount; qi++) {
      const parts = []

      const checkedBoxes = document.querySelectorAll(
        `input[data-widget="${widgetId}"][data-qi="${qi}"]:not([data-other]):checked`
      )
      checkedBoxes.forEach(cb => {
        const label = cb.closest("label")?.querySelector("span")?.textContent?.trim()
        if (label) parts.push(label)
      })

      const otherCheck = document.querySelector(
        `input[data-widget="${widgetId}"][data-qi="${qi}"][data-other="true"]`
      )
      if (otherCheck?.checked) {
        const otherInput = document.getElementById(`${widgetId}-q${qi}-other`)
        const val = otherInput?.value?.trim()
        if (val) parts.push(val)
      }

      answers.push(parts.join(", ") || "(no selection)")
    }

    const responseText = answers.join(" | ")

    btn.disabled = true
    btn.textContent = "Sent ✓"

    try {
      const formData = new FormData()
      formData.append("message", responseText)
      await fetch(this.messageUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue },
        body: formData
      })
    } catch (e) {
      this.showError("Failed to submit answer")
      btn.disabled = false
      btn.textContent = "Submit"
    }
  }

  esc(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
