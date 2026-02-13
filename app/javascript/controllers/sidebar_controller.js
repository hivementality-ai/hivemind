import { Controller } from "@hotwired/stimulus"

// Sidebar controller for mobile responsive navigation
export default class extends Controller {
  static targets = ["sidebar", "overlay"]
  
  connect() {
    // Close sidebar when clicking outside on mobile
    this.boundClose = this.close.bind(this)
  }
  
  disconnect() {
    this.boundClose = null
  }
  
  open() {
    this.sidebarTarget.classList.remove("-translate-x-full")
    this.overlayTarget.style.display = "block"
    
    // Prevent body scroll when sidebar is open
    document.body.style.overflow = "hidden"
  }
  
  close() {
    this.sidebarTarget.classList.add("-translate-x-full")
    this.overlayTarget.style.display = "none"
    
    // Restore body scroll
    document.body.style.overflow = ""
  }
  
  toggle() {
    if (this.sidebarTarget.classList.contains("-translate-x-full")) {
      this.open()
    } else {
      this.close()
    }
  }
}
