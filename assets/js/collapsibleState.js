const storageKey = (id) => `exdock:details:${id}`

export const CollapsibleState = {
  mounted() {
    this.restore()
    this.onToggle = () => {
      sessionStorage.setItem(storageKey(this.el.id), String(this.el.open))
    }
    this.el.addEventListener("toggle", this.onToggle)
  },

  updated() {
    this.restore()
  },

  destroyed() {
    this.el.removeEventListener("toggle", this.onToggle)
  },

  restore() {
    const stored = sessionStorage.getItem(storageKey(this.el.id))
    if (stored !== null) this.el.open = stored === "true"
  },
}
