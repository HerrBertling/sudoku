// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/sudoku"
import topbar from "../vendor/topbar"

const STORAGE_KEY = "sudoku_board"
// Bumped when the saved shape changes; older payloads are discarded rather
// than migrated. v2 replaced auto-computed `excluded` candidates with
// player-authored `corner_marks` / `center_marks`.
const STORAGE_VERSION = 2

const DIGIT_CODE = /^(Digit|Numpad)[1-9]$/

const BoardPersistence = {
  mounted() {
    this.restore()

    this.handleEvent("save_board", (data) => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
    })

    this.handleEvent("clear_board", () => {
      localStorage.removeItem(STORAGE_KEY)
    })

    // The name field holds the same "" value before and after a save, so there
    // is no diff for LiveView to patch — clear it explicitly.
    this.handleEvent("reset_save_form", () => {
      const input = this.el.querySelector("#save-puzzle-form input[name='name']")
      if (input) { input.value = "" }
    })

    // Shift+digit (corner) and Ctrl+digit (centre) would otherwise trigger
    // browser shortcuts. Capture early so the page keeps the keystroke.
    this.onKeydown = (e) => {
      // Inside a text box these shortcuts belong to the box, not the board.
      if (["INPUT", "TEXTAREA", "SELECT"].includes(e.target?.tagName)) { return }

      const boardKey = DIGIT_CODE.test(e.code) || e.code === "Backspace" || e.code === "Delete" ||
        ["KeyA", "KeyZ", "KeyY"].includes(e.code)
      if (boardKey && (e.shiftKey || e.ctrlKey) && !e.metaKey && !e.altKey) {
        e.preventDefault()
      }
    }
    window.addEventListener("keydown", this.onKeydown, true)
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown, true)
  },

  restore() {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (!saved) { return }

    try {
      const data = JSON.parse(saved)
      if (data.version !== STORAGE_VERSION) {
        localStorage.removeItem(STORAGE_KEY)
        return
      }
      this.pushEvent("restore_board", data)
    } catch (_) {
      localStorage.removeItem(STORAGE_KEY)
    }
  }
}

// Pointer-driven cell selection: click to select, drag to sweep, and
// Ctrl/Cmd/Shift+click to add or remove a cell. Pointer events cover mouse
// and touch alike; the grid carries `touch-none` so a sweep doesn't scroll.
const BoardSelection = {
  mounted() {
    this.dragging = false
    this.last = null

    const cellAt = (x, y) => {
      const el = document.elementFromPoint(x, y)
      return el && el.closest("[data-cell]")
    }
    const coords = (cell) => {
      const [row, col] = cell.dataset.cell.split(",")
      return {row, col}
    }

    this.el.addEventListener("pointerdown", (e) => {
      const cell = e.target.closest("[data-cell]")
      if (!cell) { return }
      e.preventDefault()
      this.dragging = true
      this.last = cell.dataset.cell
      this.pushEvent("select_cell", {
        ...coords(cell),
        additive: e.ctrlKey || e.metaKey || e.shiftKey,
      })
    })

    this.el.addEventListener("pointermove", (e) => {
      if (!this.dragging) { return }
      const cell = cellAt(e.clientX, e.clientY)
      if (!cell || cell.dataset.cell === this.last) { return }
      this.last = cell.dataset.cell
      this.pushEvent("extend_selection", coords(cell))
    })

    this.stopDrag = () => { this.dragging = false; this.last = null }
    window.addEventListener("pointerup", this.stopDrag)
    window.addEventListener("pointercancel", this.stopDrag)
  },

  destroyed() {
    window.removeEventListener("pointerup", this.stopDrag)
    window.removeEventListener("pointercancel", this.stopDrag)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, BoardPersistence, BoardSelection},
  metadata: {
    // LiveView sends only `key` by default. The board needs the modifiers to
    // tell a normal digit from a corner (Shift) or centre (Ctrl) mark, and
    // `code` because Shift+1 arrives as "!".
    keydown: (e) => ({
      code: e.code,
      shiftKey: e.shiftKey,
      ctrlKey: e.ctrlKey,
      altKey: e.altKey,
      metaKey: e.metaKey,
      // Typing a puzzle name or a search term must not land on the board.
      inField: ["INPUT", "TEXTAREA", "SELECT"].includes(e.target?.tagName),
    }),
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

