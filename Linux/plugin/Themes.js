.pragma library
// Pill styles. "omarchy" follows the desktop theme; the rest are fixed.
// The same table lives in Sources/Softly/Palette.swift and
// Windows/Softly/Palette.cs (where Midnight, the default, follows the
// system accent); keep the three in step.
var list = [
    { id: "omarchy", name: "Omarchy" },
    { id: "midnight", name: "Midnight", background: "#12151c", foreground: "#e6e8ee", accent: "#3b82f6" },
    { id: "graphite", name: "Graphite", background: "#1c1d20", foreground: "#ededed", accent: "#d9dce3" },
    { id: "ember", name: "Ember", background: "#1f1612", foreground: "#f5e7dd", accent: "#ff7a3d" },
    { id: "forest", name: "Forest", background: "#101a14", foreground: "#dcebe0", accent: "#4ade80" },
    { id: "lagoon", name: "Lagoon", background: "#0d1a20", foreground: "#dcf1f5", accent: "#2dd4bf" },
    { id: "rose", name: "Rose", background: "#1f1318", foreground: "#f7e4eb", accent: "#ff5c8a" },
    { id: "violet", name: "Violet", background: "#19112b", foreground: "#efe6ff", accent: "#b57bff" },
    { id: "brass", name: "Brass", background: "#18150e", foreground: "#f2ead5", accent: "#f2c14e" },
    { id: "paper", name: "Paper", background: "#f3efe6", foreground: "#2b2722", accent: "#e0703a" },
    { id: "frost", name: "Frost", background: "#edf1f6", foreground: "#1d2633", accent: "#2f7cf6" },
    { id: "blush", name: "Blush", background: "#f7eaec", foreground: "#3b242a", accent: "#e04f78" }
];

// The style for an id; unknown ids fall back to following Omarchy.
function named(id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return list[0];
}
