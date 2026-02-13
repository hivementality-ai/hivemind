import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "backendSelect", "backendField", "authBackend",
    "oauthSection", "s3Section", "b2Section", "sftpSection"
  ]

  selectBackend() {
    const backend = this.backendSelectTarget.value
    const option = this.backendSelectTarget.selectedOptions[0]
    const needsToken = option?.dataset.needsToken === "true"

    // Hide all sections
    this.oauthSectionTarget.style.display = "none"
    this.s3SectionTarget.style.display = "none"
    this.b2SectionTarget.style.display = "none"
    this.sftpSectionTarget.style.display = "none"

    if (!backend) return

    if (backend === "s3") {
      this.s3SectionTarget.style.display = "block"
    } else if (backend === "b2") {
      this.b2SectionTarget.style.display = "block"
    } else if (backend === "sftp") {
      this.sftpSectionTarget.style.display = "block"
    } else if (needsToken) {
      this.oauthSectionTarget.style.display = "block"
      this.backendFieldTarget.value = backend
      this.authBackendTarget.textContent = backend
    }
  }
}
