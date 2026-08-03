var MeshCentralTheme = (function () {
  // MyCenter ships one local theme. This prevents a saved Bootswatch selection
  // from loading remote font imports and keeps the production UI deterministic.
  function normalizeTheme() {
    return "default";
  }

  function getThemeHref() {
    return "styles/bootstrap-min.css";
  }

  function isDarkBaseTheme() {
    return false;
  }

  // Apply the selected theme stylesheet to the active page.
  function applyTheme(theme) {
    var themeStylesheet = document.getElementById("theme-stylesheet");
    if (themeStylesheet) themeStylesheet.href = getThemeHref(theme);
  }

  return {
    normalizeTheme: normalizeTheme,
    getThemeHref: getThemeHref,
    isDarkBaseTheme: isDarkBaseTheme,
    applyTheme: applyTheme
  };
})();

document.addEventListener("DOMContentLoaded", function () {
  MeshCentralTheme.applyTheme("default");

  // Initialize Select2 on all select elements with the 'select2' class
  $(".select2").select2({
    theme: "bootstrap-5",
    width: $(this).data("width")
      ? $(this).data("width")
      : $(this).hasClass("w-100")
      ? "100%"
      : "style",
    placeholder: $(this).data("placeholder"),
  });
});
