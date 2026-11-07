import { Controller } from "@hotwired/stimulus"

// Sends a chosen or recorded audio file to the chat's audio-notes endpoint.
// Progress and the finished notes arrive in the chat over the session channel.
export default class extends Controller {
  static targets = ["file", "recordButton", "keep", "status"]
  static values = { url: String, csrf: String }

  upload() {
    const file = this.fileTarget.files[0]
    this.fileTarget.value = ""
    if (file) this.send(file, file.name)
  }

  async toggleRecording() {
    if (this.recorder) {
      this.recorder.stop()
      return
    }
    if (!navigator.mediaDevices || !window.MediaRecorder) {
      this.say("Recording is not available in this browser. Choose a file instead.")
      return
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      this.say("Could not use the microphone. Check that this site is allowed to use it.")
      return
    }
    this.chunks = []
    this.recorder = new MediaRecorder(this.stream)
    this.recorder.ondataavailable = (event) => this.chunks.push(event.data)
    this.recorder.onstop = () => this.finishRecording()
    this.recorder.start()
    this.recordButtonTarget.textContent = "Stop and make notes"
    this.say("Recording...")
  }

  finishRecording() {
    const type = this.recorder.mimeType || "audio/webm"
    const extension = type.includes("ogg") ? "ogg" : "webm"
    const blob = new Blob(this.chunks, { type })
    this.stream.getTracks().forEach((track) => track.stop())
    this.recorder = null
    this.recordButtonTarget.textContent = "Record"
    this.send(blob, `recording.${extension}`)
  }

  async send(file, name) {
    const body = new FormData()
    body.append("file", file, name)
    body.append("keep_recording", this.keepTarget.checked ? "true" : "false")
    this.say("Sending the recording...")
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue, Accept: "application/json" },
        body
      })
      const data = await response.json()
      if (response.ok) {
        this.say("")
      } else {
        this.say(data.error, data.settings_url)
      }
    } catch {
      this.say("Could not send the recording. Check your connection and try again.")
    }
  }

  say(message, settingsUrl = null) {
    this.statusTarget.textContent = message
    if (settingsUrl) {
      const link = document.createElement("a")
      link.href = settingsUrl
      link.textContent = " Open provider settings"
      link.className = "underline text-brand"
      this.statusTarget.appendChild(link)
    }
  }
}
