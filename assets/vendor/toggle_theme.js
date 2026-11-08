const localStorageKey = "theme"
const themePreferences = ["system", "light", "dark"]
const systemTheme = window.matchMedia("(prefers-color-scheme: dark)")

const getThemePreference = () => {
  try {
    const preference = localStorage.getItem(localStorageKey)
    if (themePreferences.includes(preference)) return preference
  } catch (_error) {}

  return "system"
}

const resolvesToDark = preference =>
  preference === "dark" || (preference === "system" && systemTheme.matches)

const updateControl = (control, preference) => {
  if (!control) return

  control.dataset.themePreference = preference

  control.querySelectorAll("[data-theme-option]").forEach(option => {
    option.setAttribute("aria-pressed", String(option.dataset.themeOption === preference))
  })
}

const applyTheme = (preference, persist = false) => {
  const dark = resolvesToDark(preference)
  const theme = dark ? "dark" : "light"

  document.documentElement.classList.toggle("dark", dark)
  document.documentElement.dataset.theme = theme
  document.documentElement.dataset.themePreference = preference
  updateControl(document.getElementById("theme-toggle"), preference)

  if (persist) {
    try {
      if (preference === "system") {
        localStorage.removeItem(localStorageKey)
      } else {
        localStorage.setItem(localStorageKey, preference)
      }
    } catch (_error) {}
  }

  window.dispatchEvent(new CustomEvent("exdock:theme-changed", {detail: {preference, theme}}))
}

export const initializeTheme = () => {
  applyTheme(getThemePreference())

  systemTheme.addEventListener("change", () => {
    if (getThemePreference() === "system") applyTheme("system")
  })

  window.addEventListener("storage", event => {
    if (event.key === localStorageKey) applyTheme(getThemePreference())
  })
}

const toggleThemeHook = {
  mounted() {
    this.onSelect = event => {
      const option = event.target.closest("[data-theme-option]")
      if (option && this.el.contains(option)) applyTheme(option.dataset.themeOption, true)
    }

    this.onThemeChanged = event => updateControl(this.el, event.detail.preference)

    this.el.addEventListener("click", this.onSelect)
    window.addEventListener("exdock:theme-changed", this.onThemeChanged)
    updateControl(this.el, getThemePreference())
  },

  updated() {
    updateControl(this.el, getThemePreference())
  },

  destroyed() {
    this.el.removeEventListener("click", this.onSelect)
    window.removeEventListener("exdock:theme-changed", this.onThemeChanged)
  },
}

export default toggleThemeHook
