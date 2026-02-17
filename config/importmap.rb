# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "marked", to: "https://cdn.jsdelivr.net/npm/marked@15.0.7/lib/marked.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
