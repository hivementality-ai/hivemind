import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["statusBadge", "qrArea", "connectedArea", "userInfo", "instructions", "errorArea"]
  static values = { healthUrl: String, qrUrl: String, logoutUrl: String }

  connect() {
    this.polling = true
    this.poll()
  }

  disconnect() {
    this.polling = false
  }

  async poll() {
    if (!this.polling) return

    try {
      // Check connection status
      const healthRes = await fetch(this.healthUrlValue)
      const health = await healthRes.json()

      if (health.status === "connected") {
        this.showConnected(health)
        return // Stop polling
      }

      if (health.status === "qr_ready" || health.hasQR) {
        await this.showQR()
      } else {
        this.showWaiting(health.status)
      }

      this.hideError()
    } catch (err) {
      this.showError()
    }

    // Poll every 2 seconds
    setTimeout(() => this.poll(), 2000)
  }

  async showQR() {
    try {
      const qrRes = await fetch(this.qrUrlValue)
      const data = await qrRes.json()

      if (data.qr) {
        this.qrAreaTarget.innerHTML = `
          <img src="${data.qr}" alt="QR Code" class="w-[300px] h-[300px] rounded-xl" />
        `
        this.updateBadge("qr_ready", "Scan to connect", "yellow")
        this.instructionsTarget.classList.remove("hidden")
        this.connectedAreaTarget.classList.add("hidden")
      }
    } catch (err) {
      // Keep current state
    }
  }

  async reconnect() {
    try {
      const res = await fetch(this.logoutUrlValue, { method: "POST" })
      const data = await res.json()
      if (data.status === "logged_out") {
        // Reset UI and start polling for new QR
        this.connectedAreaTarget.classList.add("hidden")
        this.qrAreaTarget.classList.remove("hidden")
        this.qrAreaTarget.innerHTML = `
          <div class="w-[300px] h-[300px] bg-surface-base rounded-xl flex items-center justify-center">
            <div class="text-center">
              <div class="animate-spin w-8 h-8 border-2 border-brand border-t-transparent rounded-full mx-auto mb-3"></div>
              <p class="text-text-faint text-sm">Generating new QR code...</p>
            </div>
          </div>
        `
        this.instructionsTarget.classList.remove("hidden")
        this.polling = true
        setTimeout(() => this.poll(), 2000)
      }
    } catch (err) {
      console.error("Reconnect failed:", err)
    }
  }

  showConnected(health) {
    this.qrAreaTarget.classList.add("hidden")
    this.instructionsTarget.classList.add("hidden")
    this.connectedAreaTarget.classList.remove("hidden")
    this.errorAreaTarget.classList.add("hidden")

    const user = health.userName || health.user || "WhatsApp"
    this.userInfoTarget.textContent = `Linked as ${user}`
    this.updateBadge("connected", "Connected", "green")
  }

  showWaiting(status) {
    this.updateBadge(status, status === "connecting" ? "Reconnecting..." : "Waiting for QR...", "yellow")
  }

  showError() {
    this.errorAreaTarget.classList.remove("hidden")
    this.qrAreaTarget.innerHTML = `
      <div class="w-[300px] h-[300px] bg-surface-base rounded-xl flex items-center justify-center">
        <p class="text-text-faint text-sm">Connector offline</p>
      </div>
    `
    this.updateBadge("error", "Connector offline", "red")
  }

  hideError() {
    this.errorAreaTarget.classList.add("hidden")
  }

  updateBadge(status, text, color) {
    const colors = {
      green: "bg-green-500",
      yellow: "bg-yellow-500 animate-pulse",
      red: "bg-red-500",
    }

    this.statusBadgeTarget.innerHTML = `
      <span class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-surface-raised text-text-primary text-sm">
        <span class="w-2.5 h-2.5 rounded-full ${colors[color] || colors.yellow}"></span>
        ${text}
      </span>
    `
  }
}
