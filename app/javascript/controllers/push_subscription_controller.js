import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleBtn", "status"]
  static values = { vapidPublicKey: String }

  connect() {
    this.updateUI()
  }

  async updateUI() {
    if (!("Notification" in window) || !("serviceWorker" in navigator)) {
      this.setStatus("Push notifications are not supported in this browser.")
      this.disableToggle()
      return
    }

    const permission = Notification.permission

    if (permission === "granted") {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()
      if (subscription) {
        this.setToggleActive(true)
        this.setStatus("Notifications enabled.")
      } else {
        this.setToggleActive(false)
        this.setStatus("Tap to enable notifications.")
      }
    } else if (permission === "denied") {
      this.setStatus("Notifications are blocked. Please enable them in your browser settings.")
      this.disableToggle()
    } else {
      this.setToggleActive(false)
      this.setStatus("Tap to enable notifications.")
    }
  }

  async toggle() {
    if (!("Notification" in window)) return

    const permission = Notification.permission

    if (permission === "default") {
      const result = await Notification.requestPermission()
      if (result === "granted") {
        await this.subscribe()
      } else {
        this.setStatus("Notification permission denied.")
      }
    } else if (permission === "granted") {
      await this.subscribe()
    } else {
      this.setStatus("Notifications are blocked in browser settings.")
    }

    this.updateUI()
  }

  async subscribe() {
    try {
      const registration = await navigator.serviceWorker.ready
      const applicationServerKey = this.urlBase64ToUint8Array(this.vapidPublicKeyValue)

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey
      })

      const json = subscription.toJSON()
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch("/m/settings/push_subscription", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          subscription: {
            endpoint: json.endpoint,
            p256dh: json.keys.p256dh,
            auth: json.keys.auth
          }
        })
      })

      if (response.ok) {
        this.setStatus("Notifications enabled successfully.")
        this.setToggleActive(true)
      } else {
        this.setStatus("Failed to save subscription. Please try again.")
      }
    } catch (err) {
      this.setStatus("Failed to subscribe: " + err.message)
    }
  }

  setToggleActive(active) {
    if (!this.hasToggleBtnTarget) return
    const btn = this.toggleBtnTarget
    const knob = btn.querySelector("span")

    btn.setAttribute("aria-checked", active.toString())
    btn.classList.toggle("bg-blue-500", active)
    btn.classList.toggle("bg-gray-600", !active)
    if (knob) {
      knob.classList.toggle("translate-x-5", active)
      knob.classList.toggle("translate-x-0", !active)
    }
  }

  disableToggle() {
    if (this.hasToggleBtnTarget) {
      this.toggleBtnTarget.disabled = true
      this.toggleBtnTarget.classList.add("opacity-50", "cursor-not-allowed")
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
    }
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const rawData = atob(base64)
    const outputArray = new Uint8Array(rawData.length)
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i)
    }
    return outputArray
  }
}
