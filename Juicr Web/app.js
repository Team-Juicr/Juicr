const STORAGE_KEY = "juicr.web.app_state.v3";
const ROUTES = ["home", "discovery", "library", "settings"];
const SETTINGS_SECTIONS = ["general", "playback", "sources", "web", "about"];
const PERSISTED_KEYS = [
  "defaultCatalog",
  "defaultPlayback",
  "defaultSubtitles",
  "defaultTrailers",
  "addonCatalog",
  "addonStreams",
  "addonSubtitles",
  "addonTrailers",
  "tvSources",
  "reduceMotion",
  "compactLayout",
  "theme",
];

const DEFAULT_STATE = {
  defaultCatalog: false,
  defaultPlayback: false,
  defaultSubtitles: false,
  defaultTrailers: false,
  addonCatalog: false,
  addonStreams: false,
  addonSubtitles: false,
  addonTrailers: false,
  tvSources: false,
  reduceMotion: false,
  compactLayout: false,
  theme: "dark",
};

const WORKER_BASE_URL = "https://api.juicr.app";
const WORKER_CLIENT_HEADERS = {
  "x-juicr-client": "juicr-web",
  "x-juicr-client-version": "web-player-static",
};
const WORKER_FAILURE_BUCKETS = new Set([
  "worker temporarily unavailable",
  "worker route unavailable",
  "worker asked the shell to slow down",
  "worker rejected the request",
  "browser network unavailable",
  "worker response unavailable",
]);
const WORKER_CATALOG_REQUESTS = [
  ["movie", "Movie"],
  ["series", "Series"],
  ["animation", "Animation"],
];
const HOME_RAILS = [
  {
    sectionId: "trendingTodaySection",
    railId: "trendingTodayRail",
    empty: "Enable browsing in Settings to fill this shelf.",
    ranked: true,
  },
  {
    sectionId: "trendingWeekSection",
    railId: "trendingWeekRail",
    empty: "Weekly picks appear after browsing is enabled.",
    ranked: true,
  },
  {
    sectionId: "topTenSection",
    railId: "topTenRail",
    empty: "Top picks appear after browsing is enabled.",
    ranked: true,
  },
  {
    sectionId: "saveLaterSection",
    railId: "saveLaterRail",
    empty: "Saved ideas appear here once you keep a title for later.",
    ranked: false,
  },
  {
    sectionId: "upcomingYearSection",
    railId: "upcomingYearRail",
    empty: "Upcoming titles appear after browsing is enabled.",
    ranked: false,
  },
];
const catalogStore = {
  status: "idle",
  failureBucket: "none",
  items: [],
  metaStatus: "idle",
  metaFailureBucket: "none",
  metaCache: new Map(),
  requestKey: "",
};
const editorialStore = {
  status: "idle",
  failureBucket: "none",
  editionId: "",
  hero: null,
  heroItems: [],
  requestKey: "",
};

const media = [
  title("case-files", "Case Files", "Tense investigations with a quiet edge.", "Series", "2026", "Crime", "IMDb 7.8", ["linear-gradient(135deg,#31405b,#101116)", "radial-gradient(circle at 66% 24%,rgba(255,255,255,.28),transparent 120px)"]),
  title("night-run", "Night Run", "A city chase with no clean exits.", "Movie", "2025", "Action", "IMDb 7.3", ["linear-gradient(135deg,#4e3026,#101116)", "radial-gradient(circle at 24% 28%,rgba(255,142,73,.35),transparent 130px)"]),
  title("small-wonders", "Small Wonders", "Bright animation for a noisy afternoon.", "Animation", "2026", "Adventure", "IMDb 8.1", ["linear-gradient(135deg,#52622c,#11131a)", "radial-gradient(circle at 74% 18%,rgba(255,225,91,.4),transparent 130px)"]),
  title("harbor-line", "Harbor Line", "Cold weather, colder secrets.", "Series", "2024", "Mystery", "IMDb 7.5", ["linear-gradient(135deg,#29464b,#0d1116)", "radial-gradient(circle at 42% 20%,rgba(64,180,205,.26),transparent 150px)"]),
  title("orbit-house", "Orbit House", "A family drama under impossible skies.", "Movie", "2023", "Sci-Fi", "IMDb 7.9", ["linear-gradient(135deg,#263f67,#0b0d12)", "radial-gradient(circle at 70% 20%,rgba(97,171,255,.38),transparent 150px)"]),
  title("soft-signal", "Soft Signal", "A gentle story that still moves fast.", "Animation", "2025", "Family", "IMDb 7.6", ["linear-gradient(135deg,#664d2b,#101116)", "radial-gradient(circle at 30% 22%,rgba(255,197,84,.35),transparent 130px)"]),
  title("backroom-note", "Backroom Note", "One locked room, too many answers.", "Movie", "2026", "Thriller", "IMDb 6.9", ["linear-gradient(135deg,#6b5a2a,#101116)", "radial-gradient(circle at 75% 28%,rgba(255,242,113,.34),transparent 120px)"]),
  title("green-table", "Green Table", "Strange alliances and quiet betrayals.", "Series", "2022", "Drama", "IMDb 8.0", ["linear-gradient(135deg,#264d36,#101116)", "radial-gradient(circle at 46% 20%,rgba(63,220,132,.25),transparent 140px)"]),
];

const liveChannels = [
  title("live-world", "World Desk", "Live briefings and global updates.", "Live TV", "Live", "News", "Live", ["linear-gradient(135deg,#1e4032,#080b0f)", "radial-gradient(circle at 34% 18%,rgba(32,212,99,.28),transparent 130px)"]),
  title("live-arena", "Game Night", "Sports and event coverage.", "Live TV", "Live", "Sports", "Live", ["linear-gradient(135deg,#263f5e,#080b0f)", "radial-gradient(circle at 72% 22%,rgba(97,171,255,.3),transparent 130px)"]),
  title("live-cinema", "Cinema Loop", "A rotating channel for trailers and features.", "Live TV", "Live", "Movies", "Live", ["linear-gradient(135deg,#513128,#080b0f)", "radial-gradient(circle at 22% 26%,rgba(255,142,73,.3),transparent 130px)"]),
];

const settingsCards = [
  ["general", "General", "Theme and display preferences", "gear"],
  ["playback", "Playback", "Player and subtitle defaults", "play"],
  ["sources", "Sources", "Browsing, add-ons, and TV", "puzzle"],
  ["web", "Web experience", "Install, storage, and browser behavior", "shield"],
  ["about", "About & diagnostics", "Version, app status, and redacted support details", "info"],
];

const iconPaths = {
  gear: "M10.8 2h2.4l.5 2.4c.6.2 1.1.4 1.6.7l2.1-1.3 1.7 1.7-1.3 2.1c.3.5.5 1 .7 1.6l2.4.5v2.4l-2.4.5c-.2.6-.4 1.1-.7 1.6l1.3 2.1-1.7 1.7-2.1-1.3c-.5.3-1 .5-1.6.7l-.5 2.4h-2.4l-.5-2.4c-.6-.2-1.1-.4-1.6-.7l-2.1 1.3-1.7-1.7 1.3-2.1c-.3-.5-.5-1-.7-1.6L2 12.1V9.7l2.4-.5c.2-.6.4-1.1.7-1.6L3.8 5.5l1.7-1.7 2.1 1.3c.5-.3 1-.5 1.6-.7L10.8 2ZM12 14.7a2.7 2.7 0 1 0 0-5.4 2.7 2.7 0 0 0 0 5.4Z",
  play: "M5 5h14v14H5V5Zm4 3v8l6-4-6-4Z",
  puzzle: "M9 3h4v3h2a2 2 0 1 1 0 4h-2v3h3v8H5v-8h3v-2a2 2 0 1 1 0-4V3h1Zm1.5 2v4.2l-1.4-.4a.7.7 0 1 0 0 1.4l1.4-.4V15H7v4h7v-4h-3.5V9.8l1.4.4a.7.7 0 1 0 0-1.4l-1.4.4V5Z",
  shield: "M12 2 20 5v6c0 5-3.3 9-8 11-4.7-2-8-6-8-11V5l8-3Zm0 2.2L6 6.5V11c0 3.8 2.3 6.8 6 8.6 3.7-1.8 6-4.8 6-8.6V6.5l-6-2.3Z",
  info: "M11 10h2v8h-2v-8Zm0-4h2v2h-2V6Zm1 16a10 10 0 1 1 0-20 10 10 0 0 1 0 20Zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z",
  heart: "M12 21s-7.5-4.6-9.6-9.3C.8 8.1 2.8 4 6.7 4c2.1 0 3.7 1.1 5.3 3 1.6-1.9 3.2-3 5.3-3 3.9 0 5.9 4.1 4.3 7.7C19.5 16.4 12 21 12 21Zm0-2.4c2.7-1.8 6.4-4.8 7.7-7.7 1-2.3-.1-4.9-2.4-4.9-1.6 0-2.8 1.1-4.4 3.2L12 10.4l-.9-1.2C9.5 7.1 8.3 6 6.7 6c-2.3 0-3.4 2.6-2.4 4.9 1.3 2.9 5 5.9 7.7 7.7Z",
  spark: "M12 2l1.5 5.2L19 9l-5.5 1.8L12 16l-1.5-5.2L5 9l5.5-1.8L12 2Zm6 10 1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3ZM5 13l.8 2.2L8 16l-2.2.8L5 19l-.8-2.2L2 16l2.2-.8L5 13Z",
};

const toggleRows = {
  general: [
    ["compactLayout", "Compact layout", "Reduce shelf height and card density for smaller windows."],
    ["reduceMotion", "Reduce motion", "Limit carousel and reveal motion."],
  ],
  playback: [
    ["defaultPlayback", "Playback option", "Show guarded playback availability for supported titles."],
    ["defaultSubtitles", "Subtitles", "Show subtitle availability markers."],
    ["defaultTrailers", "Trailers", "Enable trailer actions when available."],
  ],
  sources: [
    ["defaultCatalog", "Browsing source", "Movies, series, and animation shelves."],
    ["addonCatalog", "Add-on catalog", "Extra shelves from configured add-ons."],
    ["addonStreams", "Add-on streams", "Playback availability marker only."],
    ["addonSubtitles", "Add-on subtitles", "Subtitle availability from configured add-ons."],
    ["addonTrailers", "Add-on trailers", "Trailer availability from configured add-ons."],
    ["tvSources", "TV sources", "Live TV shelves and saved channels."],
  ],
};

let state = loadState();
let route = parseRoute();
let settingsSection = route.settings;
let selected = media[0];
let activeLibrary = "continue";
let activeFilter = "All";
let heroIndex = 0;
let heroTimer = null;
const activeEpisodeSeasons = new Map();
let recent = [];
let saved = [];
let lists = [];

document.addEventListener("DOMContentLoaded", boot);

function boot() {
  bindGlobalEvents();
  render();
  refreshWorkerData();
  refreshHomeEditorial();
  startHeroRotation();
  registerPwa();
}

function title(id, name, copy, type, year, genre, rating, artLayers) {
  return { id, name, copy, type, year, genre, rating, art: artLayers.join(",") };
}

function loadState() {
  try {
    const savedState = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return PERSISTED_KEYS.reduce((next, key) => {
      next[key] = Object.prototype.hasOwnProperty.call(savedState, key)
        ? savedState[key]
        : DEFAULT_STATE[key];
      return next;
    }, {});
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function saveState() {
  const safe = PERSISTED_KEYS.reduce((next, key) => {
    next[key] = state[key];
    return next;
  }, {});
  localStorage.setItem(STORAGE_KEY, JSON.stringify(safe));
}

function parseRoute() {
  const raw = String(location.hash || "#home").replace(/^#\/?/, "");
  const [pageRaw, settingsRaw] = raw.split("/");
  const page = ROUTES.includes(pageRaw) ? pageRaw : "home";
  const settings = page === "settings" && SETTINGS_SECTIONS.includes(settingsRaw)
    ? settingsRaw
    : null;
  return { page, settings };
}

function navigate(page, settings = null) {
  const safePage = ROUTES.includes(page) ? page : "home";
  const safeSettings = safePage === "settings" && SETTINGS_SECTIONS.includes(settings)
    ? settings
    : null;
  const next = safeSettings ? `${safePage}/${safeSettings}` : safePage;
  if (location.hash.replace(/^#/, "") === next) {
    route = { page: safePage, settings: safeSettings };
    settingsSection = safeSettings;
    render();
    return;
  }
  location.hash = next;
}

function bindGlobalEvents() {
  addEventListener("hashchange", () => {
    route = parseRoute();
    settingsSection = route.settings;
    render();
  });
  document.addEventListener("click", (event) => {
    const routeButton = event.target.closest("[data-route]");
    if (routeButton) {
      event.preventDefault();
      navigate(routeButton.dataset.route);
      return;
    }
    const sheetButton = event.target.closest("[data-open-sheet]");
    if (sheetButton) {
      openSheet(sheetButton.dataset.openSheet);
      return;
    }
    if (event.target.closest("[data-close-sheet]")) {
      closeSheets();
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeSheets();
  });
  document.getElementById("globalSearch")?.addEventListener("input", (event) => {
    renderDiscovery(String(event.target.value || ""));
  });
  document.getElementById("randomDiscoveryPick")?.addEventListener("click", () => {
    const items = catalogItems();
    if (!items.length) {
      openSheet("sourceSheet");
      return;
    }
    showDetails(items[Math.floor(Math.random() * items.length)]);
  });
  document.getElementById("createListButton")?.addEventListener("click", createList);
  document.getElementById("closePlayer")?.addEventListener("click", () => {
    document.getElementById("playerDialog")?.close();
  });
  document.getElementById("closeDetails")?.addEventListener("click", () => {
    document.getElementById("detailsDialog")?.close();
  });
  document.getElementById("detailsWatch")?.addEventListener("click", () => {
    document.getElementById("detailsDialog")?.close();
    openPlayer(selected);
  });
  document.getElementById("detailsSave")?.addEventListener("click", saveSelected);
  document.getElementById("detailsTrailer")?.addEventListener("click", () => {
    document.getElementById("detailsDialog")?.close();
    openPlayer(selected, "Trailer preview");
  });
}

function startHeroRotation() {
  if (heroTimer || state.reduceMotion) return;
  heroTimer = setInterval(() => {
    const items = homeHeroItems();
    const count = items.length || 1;
    heroIndex = (heroIndex + 1) % count;
    if (route.page === "home") renderHomeFeatures();
  }, 4800);
}

function render() {
  renderRoutes();
  renderHome();
  renderDiscovery();
  renderLibrary();
  renderSettings();
  renderSourceSheet();
  renderFilterSheet();
  renderLibraryFilterSheet();
  applyPrefs();
}

function renderRoutes() {
  document.querySelectorAll("[data-route]").forEach((button) => {
    const active = button.dataset.route === route.page;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-current", active ? "page" : "false");
  });
  document.querySelectorAll("[data-page]").forEach((page) => {
    page.classList.toggle("is-active", page.dataset.page === route.page);
  });
}

function renderHome() {
  const page = document.getElementById("home");
  const empty = document.getElementById("homeEmpty");
  const sourceReady = hasCatalogData();
  page?.classList.toggle("is-source-empty", !sourceReady);
  if (empty) {
    empty.innerHTML = "";
    empty.hidden = sourceReady;
    if (!sourceReady) empty.append(emptyCard("No browsing enabled yet.", "setup"));
  }
  if (!sourceReady) {
    HOME_RAILS.forEach(({ sectionId, railId }) => {
      clearRail(railId);
      document.getElementById(sectionId)?.setAttribute("hidden", "");
    });
    return;
  }
  renderHomeHeader();
  renderHomeFeatures();
  renderContinue();
  renderHomeEditorialRails();
}

function renderHomeHeader() {
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  setText("homeGreeting", greeting);
}

function renderHomeFeatures() {
  const root = document.getElementById("homeFeatureGrid");
  if (!root) return;
  const items = homeHeroItems();
  if (!items.length) {
    root.innerHTML = "";
    setText("dailyCurationTitle", cleanValue(editorialStore.hero?.title) || "Picked for tonight");
    return;
  }
  heroIndex = heroIndex % items.length;
  const current = items[heroIndex];
  const previous = items[(heroIndex - 1 + items.length) % items.length];
  const next = items[(heroIndex + 1) % items.length];
  const heroTitle = cleanValue(editorialStore.hero?.title) || current.name;
  const cards = [
    ["Trailer", previous, "side"],
    ["Trailer", current, "main"],
    ["Trailer", next, "side"],
  ];
  setText("dailyCurationTitle", heroTitle);
  root.innerHTML = "";
  cards.forEach(([label, item, weight]) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = `poster-card home-feature-card is-${weight}`;
    card.style.setProperty("--art", item.heroArt || item.posterArt || item.art);
    card.innerHTML = `
      <span class="poster-badge">${escapeHtml(label)}</span>
      <strong>${escapeHtml(item.name)}</strong>
      <small>${escapeHtml(item.year)} - ${escapeHtml(item.rating)} - ${escapeHtml(item.genre)}</small>
    `;
    card.onclick = () => {
      const nextIndex = items.findIndex((entry) => entry.id === item.id);
      heroIndex = nextIndex >= 0 ? nextIndex : 0;
      if (weight === "main") {
        showDetails(item);
      } else {
        renderHomeFeatures();
      }
    };
    root.append(card);
  });
  root.append(heroDots());
}

function heroDots() {
  const dots = document.createElement("div");
  dots.className = "hero-dots";
  homeHeroItems().slice(0, 3).forEach((_, index) => {
    const dot = document.createElement("span");
    dot.className = index === 1 ? "is-active" : "";
    dots.append(dot);
  });
  return dots;
}

function renderContinue() {
  const latest = recent[0];
  setText("continueTitle", latest ? latest.name : "Nothing to continue yet");
  setText("continueSubtitle", latest ? `Resume ${latest.type.toLowerCase()} from this browser session.` : "Open a title in this browser and it will appear here.");
}

function renderHomeEditorialRails() {
  const rails = buildHomeEditorialRails(catalogItems());
  HOME_RAILS.forEach(({ sectionId, railId, empty, ranked }) => {
    const section = document.getElementById(sectionId);
    if (section) section.hidden = false;
    renderPosterRail(railId, rails[railId] || [], empty, { ranked });
  });
}

function buildHomeEditorialRails(items) {
  const ranked = rankHomeItems(items);
  const currentYear = new Date().getFullYear();
  const upcoming = ranked.filter((item) => toYearNumber(item) >= currentYear);
  const savedIdeas = ranked.filter((item) => item.saved || item.favorite || item.inLibrary || item.library);
  return {
    trendingTodayRail: ranked.slice(0, 20),
    trendingWeekRail: rotateItems(ranked, 3).slice(0, 20),
    topTenRail: ranked.slice(0, 10),
    saveLaterRail: (savedIdeas.length ? savedIdeas : rotateItems(ranked, 7)).slice(0, 20),
    upcomingYearRail: (upcoming.length ? upcoming : rotateItems(ranked, 11)).slice(0, 20),
  };
}

function rankHomeItems(items) {
  const seen = new Set();
  return [...items]
    .filter((item) => {
      const key = item.id || `${item.name}:${item.year}:${item.type}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((a, b) => {
      const ratingDelta = toRatingNumber(b) - toRatingNumber(a);
      if (Math.abs(ratingDelta) > 0.01) return ratingDelta;
      return toYearNumber(b) - toYearNumber(a);
    });
}

function rotateItems(items, offset) {
  if (!items.length) return [];
  const start = Math.abs(offset) % items.length;
  return [...items.slice(start), ...items.slice(0, start)];
}

function toRatingNumber(item) {
  const match = String(item?.rating || "").match(/(\d+(?:\.\d+)?)/);
  return match ? Number(match[1]) : 0;
}

function toYearNumber(item) {
  const year = Number.parseInt(String(item?.year || ""), 10);
  return Number.isFinite(year) ? year : 0;
}

function renderPosterRail(id, items, empty, options = {}) {
  const root = document.getElementById(id);
  if (!root) return;
  root.innerHTML = "";
  root.classList.toggle("is-empty", !items.length);
  if (!items.length) {
    root.append(emptyCard(empty, "setup"));
    return;
  }
  items.forEach((item, index) => root.append(posterCard(item, options.ranked ? index + 1 : 0)));
}

function clearRail(id) {
  const root = document.getElementById(id);
  if (!root) return;
  root.innerHTML = "";
  root.classList.remove("is-empty");
}

function renderDiscovery(search = document.getElementById("globalSearch")?.value || "") {
  const page = document.getElementById("discovery");
  const empty = document.getElementById("discoveryEmpty");
  const root = document.getElementById("discoveryGrid");
  if (!root) return;
  const sourceReady = hasCatalogData();
  page?.classList.toggle("is-source-empty", !sourceReady);
  if (empty) {
    empty.innerHTML = "";
    empty.hidden = sourceReady;
    if (!sourceReady) empty.append(emptyCard("No browsing enabled yet.", "setup"));
  }
  if (!sourceReady) {
    root.innerHTML = "";
    root.classList.remove("is-empty");
    return;
  }
  const query = search.trim().toLowerCase();
  const items = catalogItems().filter((item) => {
    const matchesFilter = itemMatchesFilter(item, activeFilter);
    const matchesQuery = !query || `${item.name} ${item.type} ${item.genre} ${(item.genres || []).join(" ")}`.toLowerCase().includes(query);
    return matchesFilter && matchesQuery;
  });
  root.innerHTML = "";
  root.classList.toggle("is-empty", !items.length);
  if (!items.length) {
    root.append(emptyCard("No matches for this filter.", "setup"));
  } else {
    items.forEach((item, index) => root.append(posterCard(item, index + 1)));
  }
}

function renderLibrary() {
  const page = document.getElementById("library");
  const content = document.getElementById("libraryContent");
  if (!content) return;
  const sourceReady = hasLibrarySource();
  page?.classList.toggle("is-source-empty", !sourceReady);
  if (!sourceReady) {
    content.innerHTML = "";
    content.classList.add("is-empty");
    content.append(emptyCard("No browsing enabled yet.", "setup"));
    return;
  }
  const items = libraryItems();
  content.innerHTML = "";
  content.classList.toggle("is-empty", !items.length);
  if (!items.length) {
    content.append(emptyCard(libraryEmptyCopy(), "library"));
    return;
  }
  items.forEach((item) => content.append(libraryRow(item)));
}

function renderSettings() {
  const hub = document.getElementById("settingsHub");
  const panel = document.getElementById("settingsPanel");
  if (!hub || !panel) return;
  hub.hidden = Boolean(settingsSection);
  panel.hidden = !settingsSection;
  hub.innerHTML = settingsCards.map(([key, titleText, copy, icon]) => `
    <button class="settings-card" type="button" data-settings="${key}">
      <span class="setting-icon">${iconSvg(icon)}</span>
      <span><strong>${titleText}</strong><small>${copy}</small></span>
    </button>
  `).join("");
  hub.querySelectorAll("[data-settings]").forEach((button) => {
    button.onclick = () => navigate("settings", button.dataset.settings);
  });
  if (!settingsSection) return;
  panel.innerHTML = settingsPanel(settingsSection);
  panel.querySelectorAll("[data-toggle]").forEach(bindToggle);
  panel.querySelector("[data-settings-back]")?.addEventListener("click", () => navigate("settings"));
  panel.querySelector("[data-copy-diagnostics]")?.addEventListener("click", copyDiagnostics);
  panel.querySelector("[data-reset-state]")?.addEventListener("click", resetState);
}

function renderSourceSheet() {
  const root = document.getElementById("sourceToggles");
  if (!root) return;
  root.innerHTML = toggleRows.sources.map(toggleMarkup).join("");
  root.querySelectorAll("[data-toggle]").forEach(bindToggle);
}

function renderFilterSheet() {
  const root = document.getElementById("filterChoices");
  if (!root) return;
  const activeKey = filterKey(activeFilter);
  root.innerHTML = filters().map((filter) => `
    <button class="toggle-row ${filterKey(filter) === activeKey ? "is-on" : ""}" type="button" data-sheet-filter="${escapeHtml(filter)}">
      <span><strong>${escapeHtml(filter)}</strong><small>${filter === "All" ? "Show everything available." : "Narrow Discovery to this lane."}</small></span>
      <span class="switch"></span>
    </button>
  `).join("");
  root.querySelectorAll("[data-sheet-filter]").forEach((button) => {
    button.onclick = () => {
      activeFilter = button.dataset.sheetFilter || "All";
      closeSheets();
      renderDiscovery();
    };
  });
}

function renderLibraryFilterSheet() {
  const root = document.getElementById("libraryFilterChoices");
  if (!root) return;
  root.innerHTML = librarySections().map(([key, label, copy]) => `
    <button class="toggle-row ${key === activeLibrary ? "is-on" : ""}" type="button" data-library-choice="${escapeHtml(key)}">
      <span><strong>${escapeHtml(label)}</strong><small>${escapeHtml(copy)}</small></span>
      <span class="switch"></span>
    </button>
  `).join("");
  root.querySelectorAll("[data-library-choice]").forEach((button) => {
    button.onclick = () => {
      activeLibrary = button.dataset.libraryChoice || "continue";
      closeSheets();
      renderLibrary();
    };
  });
}

function settingsPanel(key) {
  const meta = settingsCards.find((card) => card[0] === key) || settingsCards[0];
  if (key === "about") {
    return `
      <header class="settings-panel__header">
        <button class="icon-button" type="button" data-settings-back aria-label="Back">‹</button>
        <div><h2>${meta[1]}</h2><p>${meta[2]}</p></div>
      </header>
      <div class="settings-list">
        <article class="toggle-row"><span><strong>Juicr Web</strong><small>Product app shell for browsers and installed web app use.</small></span><span class="chip is-active">PWA</span></article>
        <button class="toggle-row" type="button" data-copy-diagnostics><span><strong>Copy diagnostics</strong><small>Copies redacted booleans and counts only.</small></span><span class="chip">Copy</span></button>
        <button class="toggle-row" type="button" data-reset-state><span><strong>Reset web state</strong><small>Clears only this browser's display and source switches.</small></span><span class="chip">Reset</span></button>
        <pre class="diagnostic-preview" id="diagnosticPreview">${escapeHtml(diagnosticsPacket())}</pre>
      </div>
    `;
  }
  if (key === "web") {
    return `
      <header class="settings-panel__header">
        <button class="icon-button" type="button" data-settings-back aria-label="Back">‹</button>
        <div><h2>${meta[1]}</h2><p>${meta[2]}</p></div>
      </header>
      <div class="settings-list">
        <article class="toggle-row"><span><strong>Installable app</strong><small>Browsers that support standalone apps can install Juicr Web.</small></span><span class="chip is-active">Ready</span></article>
        <article class="toggle-row"><span><strong>Offline shell</strong><small>Only safe shell assets are cached. Media and private details are not cached.</small></span><span class="chip">Shell</span></article>
        <article class="toggle-row"><span><strong>Storage</strong><small>Only allowlisted source and display preferences are saved.</small></span><span class="chip">Limited</span></article>
      </div>
    `;
  }
  return `
    <header class="settings-panel__header">
      <button class="icon-button" type="button" data-settings-back aria-label="Back">‹</button>
      <div><h2>${meta[1]}</h2><p>${meta[2]}</p></div>
    </header>
    <div class="settings-list">${(toggleRows[key] || []).map(toggleMarkup).join("")}</div>
  `;
}

function toggleMarkup([key, label, copy]) {
  return `
    <button class="toggle-row ${state[key] ? "is-on" : ""}" type="button" data-toggle="${key}" aria-pressed="${state[key] ? "true" : "false"}">
      <span><strong>${escapeHtml(label)}</strong><small>${escapeHtml(copy)}</small></span>
      <span class="switch"></span>
    </button>
  `;
}

function bindToggle(button) {
  button.onclick = () => {
    const key = button.dataset.toggle;
    if (!PERSISTED_KEYS.includes(key)) return;
    state[key] = !Boolean(state[key]);
    saveState();
    render();
    if (["defaultCatalog", "addonCatalog", "tvSources"].includes(key)) {
      refreshWorkerData();
      refreshHomeEditorial();
    }
  };
}

function posterCard(item, rank) {
  const card = document.createElement("button");
  card.type = "button";
  card.className = `poster-card ${item.id === selected.id ? "is-selected" : ""}`;
  card.style.setProperty("--art", item.posterArt || item.art);
  const badge = rank ? `Rank ${rank}` : item.rating;
  card.innerHTML = `
    <span class="poster-badge">${escapeHtml(badge)}</span>
    <strong>${escapeHtml(item.name)}</strong>
    <small>${escapeHtml(item.year)} - ${escapeHtml(item.genre)}</small>
  `;
  card.setAttribute("aria-label", `${item.name}, ${item.type}`);
  card.onclick = () => {
    selected = item;
    if (route.page === "home" || route.page === "discovery") {
      showDetails(item);
    } else {
      selectItem(item, true);
    }
  };
  return card;
}

function libraryRow(item) {
  const row = document.createElement("article");
  row.className = "library-row";
  row.style.setProperty("--art", item.posterArt || item.art);
  row.innerHTML = `
    <span class="library-thumb" aria-hidden="true"></span>
    <span><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.type)} - ${escapeHtml(item.year)}</small></span>
    <button class="pill-button" type="button">Open</button>
  `;
  row.querySelector("button").onclick = () => selectItem(item, true);
  return row;
}

function emptyCard(copy, variant = "setup") {
  const card = document.createElement("article");
  card.className = `empty-state empty-state--${variant}`;
  if (variant === "library") {
    card.innerHTML = `
      <span class="empty-icon empty-icon--heart" aria-hidden="true">${iconSvg("heart")}</span>
      <div><strong>Your library is empty</strong><p>Tap the heart on any movie or series to save it here.</p></div>
    `;
  } else {
    card.innerHTML = `
      <span class="empty-icon" aria-hidden="true">${iconSvg("puzzle")}</span>
      <div><strong>No browsing enabled yet.</strong><p>Fresh installs start empty until you choose what Juicr can show in this browser.</p></div>
      <button class="primary-button" type="button" data-route="settings">${iconSvg("puzzle")} Set up add-ons</button>
      <small>Juicr does not provide media. You choose what to connect.</small>
    `;
  }
  card.setAttribute("aria-label", copy);
  return card;
}

function selectItem(item, open = false) {
  selected = item;
  recent = [item, ...recent.filter((entry) => entry.id !== item.id)].slice(0, 8);
  if (open) openPlayer(item);
  render();
}

function showDetails(item) {
  selected = item;
  const dialog = document.getElementById("detailsDialog");
  const hero = document.getElementById("detailsHero");
  const poster = document.getElementById("detailsPoster");
  if (!dialog || !hero || !poster) return;
  hero.style.setProperty("--art", item.heroArt || item.posterArt || item.art);
  poster.style.setProperty("--art", item.posterArt || item.heroArt || item.art);
  setText("detailsType", item.type);
  setText("detailsTitle", item.name);
  setText("detailsCopy", item.copy);
  renderDetailsMeta(item);
  renderDetailsTags(item);
  renderDetailsEpisodes(item);
  renderDetailsRelated(item);
  renderDetailsPeople(item);
  dialog.showModal();
  refreshMeta(item);
}

function renderDetailsMeta(item) {
  const root = document.getElementById("detailsMeta");
  if (!root) return;
  const chips = [item.type, item.year, item.rating, item.type === "Series" ? "Season 1" : "1h 36m"];
  root.innerHTML = chips.map((chip) => `<span>${escapeHtml(chip)}</span>`).join("");
}

function renderDetailsTags(item) {
  const root = document.getElementById("detailsTags");
  if (!root) return;
  const tags = [item.genre, item.type === "Animation" ? "Family" : item.type === "Series" ? "Drama" : "Featured"];
  root.innerHTML = tags.map((tag) => `<span>${escapeHtml(tag)}</span>`).join("");
}

function renderDetailsEpisodes(item) {
  const section = document.getElementById("detailsEpisodesSection");
  const tabs = document.getElementById("detailsSeasons");
  const root = document.getElementById("detailsEpisodes");
  if (!section || !root) return;
  const isSeries = item.type === "Series";
  section.hidden = !isSeries;
  if (!isSeries) {
    root.innerHTML = "";
    if (tabs) tabs.innerHTML = "";
    return;
  }
  const seasons = seasonsForItem(item);
  const preferred = activeEpisodeSeasons.get(item.id);
  const selectedSeason = seasons.some((season) => season.season === preferred) ? preferred : seasons[0].season;
  activeEpisodeSeasons.set(item.id, selectedSeason);
  if (tabs) {
    tabs.hidden = seasons.length <= 1;
    tabs.innerHTML = seasons.map((season) => `
      <button class="season-tab ${season.season === selectedSeason ? "is-active" : ""}" type="button" data-season="${escapeHtml(season.season)}">
        ${escapeHtml(season.label)}
      </button>
    `).join("");
    tabs.querySelectorAll("[data-season]").forEach((button) => {
      button.onclick = () => {
        activeEpisodeSeasons.set(item.id, button.dataset.season || selectedSeason);
        renderDetailsEpisodes(item);
      };
    });
  }
  const episodes = (seasons.find((season) => season.season === selectedSeason) || seasons[0]).episodes;
  root.innerHTML = episodes.slice(0, 12).map((episode, index) => {
    const number = episode.number || `S${selectedSeason} E${index + 1}`;
    const titleText = episode.name || `Episode ${index + 1}`;
    const copy = episode.copy || "Episode details are available from metadata.";
    const thumbStyle = episode.thumbArt ? ` style="--art:${episode.thumbArt}"` : "";
    const thumb = episode.thumbArt
      ? `<span class="episode-thumb"${thumbStyle}></span>`
      : `<span class="episode-number">${escapeHtml(number)}</span>`;
    return `
      <button class="episode-card ${episode.thumbArt ? "has-thumb" : ""}" type="button">
        ${thumb}
        <span class="episode-copy"><strong>${escapeHtml(titleText)}</strong><small>${escapeHtml(copy)}</small></span>
        <span class="episode-pill">${escapeHtml(number)}</span>
      </button>
    `;
  }).join("");
}

function seasonsForItem(item) {
  const episodes = Array.isArray(item.episodes) && item.episodes.length
    ? item.episodes
    : fallbackSeriesEpisodes();
  const grouped = new Map();
  episodes.forEach((episode, index) => {
    const season = cleanValue(episode.season || "1") || "1";
    if (!grouped.has(season)) grouped.set(season, []);
    grouped.get(season).push({
      ...episode,
      episode: episode.episode || String(index + 1),
    });
  });
  return Array.from(grouped.entries())
    .sort(([a], [b]) => (Number(a) || 0) - (Number(b) || 0))
    .map(([season, entries]) => ({
      season,
      label: `Season ${season}`,
      episodes: entries,
    }));
}

function fallbackSeriesEpisodes() {
  return [
    { season: "1", episode: "1", number: "S1 E1", name: "First signal", copy: "A quiet lead starts moving." },
    { season: "1", episode: "2", number: "S1 E2", name: "False calm", copy: "The case widens after a second clue." },
    { season: "1", episode: "3", number: "S1 E3", name: "Pressure line", copy: "Old notes point to a new suspect." },
  ];
}

function renderDetailsRelated(item) {
  const root = document.getElementById("detailsRelated");
  if (!root) return;
  const related = catalogItems().filter((entry) => entry.id !== item.id).slice(0, 5);
  root.innerHTML = "";
  related.forEach((entry) => {
    const button = document.createElement("button");
    button.className = "mini-poster";
    button.type = "button";
    button.dataset.related = entry.id;
    button.style.setProperty("--art", entry.posterArt || entry.heroArt || entry.art);
    button.innerHTML = `<strong>${escapeHtml(entry.name)}</strong>`;
    root.append(button);
  });
  root.querySelectorAll("[data-related]").forEach((button) => {
    button.onclick = () => {
      const next = catalogItems().find((entry) => entry.id === button.dataset.related);
      if (next) showDetails(next);
    };
  });
}

function renderDetailsPeople(item) {
  renderPeopleGroup("detailsCastSection", "detailsCast", item.cast || []);
  renderPeopleGroup("detailsDirectorsSection", "detailsDirectors", item.directors || []);
}

function renderPeopleGroup(sectionId, rootId, people) {
  const section = document.getElementById(sectionId);
  const root = document.getElementById(rootId);
  if (!section || !root) return;
  const safePeople = Array.isArray(people)
    ? people.filter((person) => cleanValue(person?.name || person)).slice(0, 12)
    : [];
  section.hidden = !safePeople.length;
  root.innerHTML = safePeople.map((person) => {
    const entry = typeof person === "string" ? { name: person } : person;
    const art = entry.art ? ` style="--art:${entry.art}"` : "";
    return `
      <article class="person-card">
        <span class="person-avatar"${art}>${entry.art ? "" : escapeHtml(initials(entry.name))}</span>
        <strong>${escapeHtml(entry.name)}</strong>
        ${entry.role ? `<small>${escapeHtml(entry.role)}</small>` : ""}
      </article>
    `;
  }).join("");
}

function initials(name) {
  return cleanValue(name)
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || "")
    .join("");
}

function openPlayer(item, label = "Opening playback") {
  if (!state.defaultPlayback && !state.addonStreams && item.type !== "Live TV") {
    openSheet("sourceSheet");
    return;
  }
  const dialog = document.getElementById("playerDialog");
  const stage = document.getElementById("playerStage");
  if (!dialog || !stage) return;
  stage.style.setProperty("--art", item.heroArt || item.posterArt || item.art);
  stage.innerHTML = `<div><h2 id="playerTitle">${escapeHtml(item.name)}</h2><p class="player-note">${escapeHtml(label)} through Juicr's guarded web path.</p></div>`;
  dialog.showModal();
}

function saveSelected() {
  saved = [selected, ...saved.filter((item) => item.id !== selected.id)].slice(0, 30);
  renderLibrary();
}

function createList() {
  const input = document.getElementById("listNameInput");
  const name = String(input?.value || "").trim().slice(0, 48);
  if (!name) return;
  lists = [title(`list-${Date.now()}`, name, "Custom watchlist", "List", `${saved.length} saved`, "List", "List", ["linear-gradient(135deg,#1f3d2e,#101116)"]), ...lists];
  if (input) input.value = "";
  activeLibrary = "lists";
  closeSheets();
  navigate("library");
}

function resetState() {
  state = { ...DEFAULT_STATE };
  recent = [];
  saved = [];
  lists = [];
  saveState();
  navigate("home");
}

function openSheet(id) {
  closeSheets();
  const sheet = document.getElementById(id);
  if (!sheet) return;
  sheet.hidden = false;
  sheet.querySelector("button, input")?.focus();
}

function closeSheets() {
  document.querySelectorAll(".sheet").forEach((sheet) => {
    sheet.hidden = true;
  });
}

function catalogItems() {
  return hasCatalog() ? catalogStore.items : [];
}

function homeHeroItems() {
  if (editorialStore.heroItems.length) return editorialStore.heroItems;
  return catalogItems();
}

function hasCatalog() {
  return Boolean(state.defaultCatalog || state.addonCatalog);
}

function hasCatalogData() {
  return hasCatalog() && catalogStore.items.length > 0;
}

function hasLibrarySource() {
  return Boolean(state.defaultCatalog || state.addonCatalog || state.tvSources);
}

function filters() {
  return ["All", "Movie", "Series", "Animation", "Crime", "Action", "Drama", "Adventure"];
}

function librarySections() {
  return [
    ["continue", "Continue", "Recently played titles"],
    ["lists", "Lists", "Custom watchlists"],
    ["Movie", "Movies", "Saved movies"],
    ["Series", "Series", "Saved series"],
    ["Animation", "Animation", "Saved animation"],
    ["Live TV", "Live TV", "Saved channels"],
  ];
}

function libraryItems() {
  if (activeLibrary === "continue") return recent;
  if (activeLibrary === "lists") return lists;
  if (activeLibrary === "Live TV") return state.tvSources ? liveChannels : [];
  return saved.filter((item) => item.type === activeLibrary);
}

function libraryEmptyCopy() {
  if (activeLibrary === "continue") return "Nothing to continue yet.";
  if (activeLibrary === "lists") return "Create your first list.";
  if (activeLibrary === "Live TV") return "Saved channels appear when TV sources are enabled.";
  return "Saved titles will appear here.";
}

function diagnosticsPacket() {
  return [
    "Juicr web diagnostic report",
    "schema=juicr.web.diagnostic.v4",
    `route=${route.page}`,
    `settingsPanel=${settingsSection || "none"}`,
    `catalogEnabled=${Boolean(state.defaultCatalog)}`,
    `catalogRoute=worker-bound`,
    `catalogStatus=${catalogStore.status}`,
    `catalogFailureBucket=${catalogStore.failureBucket}`,
    `catalogItemCount=${catalogStore.items.length}`,
    `homeEditorialStatus=${editorialStore.status}`,
    `homeEditorialFailureBucket=${editorialStore.failureBucket}`,
    `homeEditorialHeroCount=${editorialStore.heroItems.length}`,
    `metadataRoute=worker-bound`,
    `metadataStatus=${catalogStore.metaStatus}`,
    `metadataFailureBucket=${catalogStore.metaFailureBucket}`,
    `playbackEnabled=${Boolean(state.defaultPlayback)}`,
    `addonsEnabled=${Boolean(state.addonCatalog || state.addonStreams)}`,
    `tvEnabled=${Boolean(state.tvSources)}`,
    `recentCount=${recent.length}`,
    `savedCount=${saved.length}`,
    `listCount=${lists.length}`,
    "browserPlayback=guarded_not_requested",
    "workerErrors=fixed_bucket_only",
    "privacy=redacted_counts_buckets_booleans_only",
  ].join("\n");
}

async function refreshWorkerData() {
  const key = sourceRequestKey();
  catalogStore.requestKey = key;
  if (!hasCatalog()) {
    catalogStore.status = "source_disabled";
    catalogStore.failureBucket = "none";
    catalogStore.items = [];
    render();
    return;
  }
  catalogStore.status = "loading";
  catalogStore.failureBucket = "none";
  render();
  try {
    const groups = await Promise.all(WORKER_CATALOG_REQUESTS.map(async ([type, label]) => {
      const payload = await workerJson("/catalog", { type, sort: "popular", page: "1" });
      return normalizeCatalogPayload(payload, label);
    }));
    if (catalogStore.requestKey !== key) return;
    catalogStore.items = dedupeCatalogItems(groups.flat());
    catalogStore.status = catalogStore.items.length ? "loaded" : "empty";
    catalogStore.failureBucket = "none";
  } catch (error) {
    if (catalogStore.requestKey !== key) return;
    catalogStore.items = [];
    catalogStore.status = "unavailable";
    catalogStore.failureBucket = safeWorkerBucket(error);
  }
  render();
}

async function refreshHomeEditorial() {
  const key = sourceRequestKey();
  editorialStore.requestKey = key;
  if (!hasCatalog()) {
    editorialStore.status = "source_disabled";
    editorialStore.failureBucket = "none";
    editorialStore.hero = null;
    editorialStore.heroItems = [];
    renderHomeFeatures();
    return;
  }
  editorialStore.status = "loading";
  editorialStore.failureBucket = "none";
  try {
    const payload = await workerJson("/home/editorial", { locale: "en" });
    const hero = normalizeEditorialHero(payload);
    const items = hero ? await hydrateEditorialHeroItems(hero) : [];
    if (editorialStore.requestKey !== key) return;
    editorialStore.hero = hero;
    editorialStore.heroItems = items;
    editorialStore.editionId = cleanValue(payload?.editionId || payload?.id);
    editorialStore.status = hero && items.length ? "loaded" : "empty";
    editorialStore.failureBucket = "none";
  } catch (error) {
    if (editorialStore.requestKey !== key) return;
    editorialStore.hero = null;
    editorialStore.heroItems = [];
    editorialStore.editionId = "";
    editorialStore.status = "unavailable";
    editorialStore.failureBucket = safeWorkerBucket(error);
  }
  renderHomeFeatures();
}

async function refreshMeta(item) {
  if (!item || !item.id || !hasCatalogData()) return;
  const cacheKey = `${item.type}:${item.id}`;
  if (catalogStore.metaCache.has(cacheKey)) {
    const cached = catalogStore.metaCache.get(cacheKey);
    if (selected.id === item.id) updateDetailsFromMeta(cached);
    return;
  }
  catalogStore.metaStatus = "loading";
  catalogStore.metaFailureBucket = "none";
  try {
    const payload = await workerJson("/meta", {
      type: workerType(item.type),
      id: item.sourceId || item.id,
    });
    const next = normalizeMediaItem(payload?.item || payload?.meta || {}, item.type);
    if (!next) {
      catalogStore.metaStatus = "empty";
      return;
    }
    const merged = { ...item, ...next, id: item.id, sourceId: item.sourceId || next.sourceId || item.id };
    catalogStore.metaCache.set(cacheKey, merged);
    catalogStore.metaStatus = "loaded";
    if (selected.id === item.id) updateDetailsFromMeta(merged);
  } catch (error) {
    catalogStore.metaStatus = "unavailable";
    catalogStore.metaFailureBucket = safeWorkerBucket(error);
  }
}

function normalizeEditorialHero(payload) {
  if (!payload || typeof payload !== "object") return null;
  if (payload.schema && payload.schema !== "juicr.home_editorial.v1") return null;
  const hero = payload.hero && typeof payload.hero === "object" ? payload.hero : null;
  if (!hero) return null;
  const types = normalizeEditorialTypes(hero.types);
  return {
    title: cleanValue(hero.title || hero.label || "Picked for tonight"),
    types,
    genres: cleanStringList(hero.genres || hero.genre ? hero.genres || [hero.genre] : []),
    sort: safeCatalogSort(hero.sort),
    query: cleanValue(hero.query),
    perType: cleanNumber(hero.perType || hero.limit, 8, 1, 24),
    pageOneOnly: Boolean(hero.pageOneOnly),
    requireGenreMatch: Boolean(hero.requireGenreMatch),
  };
}

async function hydrateEditorialHeroItems(hero) {
  const types = hero.types.length ? hero.types : ["movie", "series", "animation"];
  const groups = await Promise.all(types.map(async (type) => {
    const payload = await workerJson("/catalog", catalogParamsForEditorialHero(hero, type));
    return normalizeCatalogPayload(payload, displayType(type));
  }));
  const genreNeedles = hero.genres.map((genre) => genre.toLowerCase());
  const items = dedupeCatalogItems(groups.flat()).filter((item) => {
    if (!hero.requireGenreMatch || !genreNeedles.length) return true;
    return genreNeedles.some((genre) => item.genre.toLowerCase().includes(genre));
  });
  return items.slice(0, hero.perType);
}

function catalogParamsForEditorialHero(hero, type) {
  const params = {
    type,
    sort: safeCatalogSort(hero.sort),
    page: "1",
  };
  const genre = firstClean(hero.genres);
  if (genre) params.genre = genre;
  if (hero.query) params.search = hero.query;
  return params;
}

function updateDetailsFromMeta(item) {
  selected = { ...selected, ...item };
  const hero = document.getElementById("detailsHero");
  const poster = document.getElementById("detailsPoster");
  if (hero) hero.style.setProperty("--art", selected.heroArt || selected.posterArt || selected.art);
  if (poster) poster.style.setProperty("--art", selected.posterArt || selected.heroArt || selected.art);
  setText("detailsType", selected.type);
  setText("detailsTitle", selected.name);
  setText("detailsCopy", selected.copy);
  renderDetailsMeta(selected);
  renderDetailsTags(selected);
  renderDetailsEpisodes(selected);
  renderDetailsRelated(selected);
  renderDetailsPeople(selected);
}

async function workerJson(path, params = {}) {
  const url = new URL(path, WORKER_BASE_URL);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && String(value).trim()) {
      url.searchParams.set(key, String(value));
    }
  });
  let response;
  try {
    response = await fetch(url, {
      method: "GET",
      headers: WORKER_CLIENT_HEADERS,
      cache: "no-store",
    });
  } catch (error) {
    const safe = new Error("browser network unavailable");
    safe.bucket = "browser network unavailable";
    throw safe;
  }
  if (!response.ok) {
    const safe = new Error(bucketForStatus(response.status));
    safe.bucket = bucketForStatus(response.status);
    throw safe;
  }
  try {
    return await response.json();
  } catch {
    const safe = new Error("worker response unavailable");
    safe.bucket = "worker response unavailable";
    throw safe;
  }
}

function bucketForStatus(status) {
  if (status === 404) return "worker route unavailable";
  if (status === 429) return "worker asked the shell to slow down";
  if (status >= 400 && status < 500) return "worker rejected the request";
  if (status >= 500) return "worker temporarily unavailable";
  return "worker response unavailable";
}

function safeWorkerBucket(error) {
  const bucket = String(error?.bucket || error?.message || "").trim();
  return WORKER_FAILURE_BUCKETS.has(bucket) ? bucket : "worker response unavailable";
}

function sourceRequestKey() {
  return [
    state.defaultCatalog ? "catalog" : "no-catalog",
    state.addonCatalog ? "addon-catalog" : "no-addon-catalog",
    state.tvSources ? "tv" : "no-tv",
  ].join(":");
}

function normalizeCatalogPayload(payload, fallbackType) {
  const values = Array.isArray(payload?.items)
    ? payload.items
    : Array.isArray(payload?.metas)
      ? payload.metas
      : Array.isArray(payload)
        ? payload
        : [];
  return values
    .map((item) => normalizeMediaItem(item, fallbackType))
    .filter(Boolean);
}

function normalizeMediaItem(raw, fallbackType = "Movie") {
  if (!raw || typeof raw !== "object") return null;
  const sourceId = cleanValue(raw.id || raw.tmdb_id || raw.moviedb_id || raw.tmdbId || raw.imdb_id || raw.imdbId);
  const name = cleanValue(raw.name || raw.title);
  if (!sourceId || !name) return null;
  const type = displayType(raw.type || fallbackType);
  const year = cleanYear(raw.year || raw.releaseInfo || raw.releaseDate || raw.release_date || raw.firstAirDate || raw.first_air_date);
  const genres = cleanStringList(Array.isArray(raw.genres) ? raw.genres : raw.genre ? [raw.genre] : []);
  const genre = firstClean(genres) || type;
  const rating = cleanRating(raw.imdbRating || raw.imdb_rating || raw.rating);
  const copy = cleanValue(raw.description || raw.overview || raw.copy) || "Metadata is available from your enabled browsing options.";
  const episodeValues = Array.isArray(raw.videos)
    ? raw.videos
    : Array.isArray(raw.episodes)
      ? raw.episodes
      : flattenSeasonEpisodes(raw.seasons || raw.seasonData || raw.season_data);
  const episodes = episodeValues.map(normalizeEpisode).filter(Boolean);
  const cast = normalizePeople(raw.cast || raw.actors || raw.credits?.cast);
  const directors = normalizeDirectors(raw.directors || raw.director || raw.credits?.crew);
  const fallbackArt = artFor(sourceId, name);
  const posterArt = cssImageArt(firstClean([
    raw.poster,
    raw.posterUrl,
    raw.poster_url,
    raw.posterPath,
    raw.poster_path,
    raw.image,
    raw.thumbnail,
    raw.cover,
  ]));
  const heroArt = cssImageArt(firstClean([
    raw.background,
    raw.backdrop,
    raw.backdropUrl,
    raw.backdrop_url,
    raw.backdropPath,
    raw.backdrop_path,
    raw.fanart,
    raw.banner,
  ]));
  return {
    id: `${workerType(type)}:${sourceId}`,
    sourceId,
    name,
    copy,
    type,
    year,
    genre,
    genres,
    rating,
    art: posterArt || heroArt || fallbackArt,
    posterArt: posterArt || heroArt || fallbackArt,
    heroArt: heroArt || posterArt || fallbackArt,
    episodes,
    cast,
    directors,
  };
}

function flattenSeasonEpisodes(value) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((season, seasonIndex) => {
    const seasonNumber = season?.season || season?.number || season?.seasonNumber || seasonIndex + 1;
    const episodes = Array.isArray(season?.episodes)
      ? season.episodes
      : Array.isArray(season?.videos)
        ? season.videos
        : [];
    return episodes.map((episode, index) => ({
      ...episode,
      season: episode.season || seasonNumber,
      episode: episode.episode || episode.number || index + 1,
    }));
  });
}

function normalizeEpisode(raw, index) {
  if (!raw || typeof raw !== "object") return null;
  const season = cleanValue(raw.season || raw.seasonNumber || raw.season_number || "1");
  const episode = cleanValue(raw.episode || raw.episodeNumber || raw.episode_number || String(index + 1));
  const thumbArt = cssImageArt(firstClean([
    raw.thumbnail,
    raw.thumbnailUrl,
    raw.still,
    raw.stillUrl,
    raw.still_path,
    raw.stillPath,
    raw.image,
    raw.poster,
    raw.poster_path,
  ]));
  return {
    season,
    episode,
    number: `S${season} E${episode}`,
    name: cleanValue(raw.name || raw.title) || `Episode ${episode}`,
    copy: cleanValue(raw.description || raw.overview) || "Episode details are available from metadata.",
    thumbArt,
  };
}

function normalizePeople(value) {
  const values = Array.isArray(value)
    ? value
    : cleanValue(value)
      ? String(value).split(",")
      : [];
  return values.map((entry) => {
    if (typeof entry === "string") {
      const name = cleanValue(entry);
      return name ? { name } : null;
    }
    const name = cleanValue(entry.name || entry.original_name || entry.profileName || entry.actor);
    if (!name) return null;
    return {
      name,
      role: cleanValue(entry.character || entry.role || entry.job),
      art: cssImageArt(firstClean([
        entry.profile,
        entry.profilePath,
        entry.profile_path,
        entry.image,
      ])),
    };
  }).filter(Boolean).slice(0, 16);
}

function normalizeDirectors(value) {
  const values = Array.isArray(value)
    ? value
    : cleanValue(value)
      ? String(value).split(",")
      : [];
  const directors = values.filter((entry) => {
    if (typeof entry === "string") return true;
    const job = cleanValue(entry.job || entry.known_for_department || entry.department || entry.role).toLowerCase();
    return !job || job.includes("director");
  });
  return normalizePeople(directors).slice(0, 8);
}

function dedupeCatalogItems(items) {
  const seen = new Set();
  return items.filter((item) => {
    if (seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
}

function displayType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "animation") return "Animation";
  if (normalized === "series" || normalized === "tv") return "Series";
  if (normalized === "live" || normalized === "live_tv" || normalized === "channel") return "Live TV";
  return "Movie";
}

function workerType(value) {
  const type = displayType(value);
  if (type === "Animation") return "animation";
  if (type === "Series") return "series";
  if (type === "Live TV") return "live_tv";
  return "movie";
}

function cleanValue(value) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 220);
}

function cleanYear(value) {
  const match = String(value || "").match(/\b(19|20)\d{2}\b/);
  return match ? match[0] : "";
}

function firstClean(values) {
  return Array.isArray(values) ? cleanValue(values.find((value) => cleanValue(value)) || "") : "";
}

function cleanStringList(values) {
  if (!Array.isArray(values)) return [];
  return values.map(cleanValue).filter(Boolean).slice(0, 8);
}

function filterKey(value) {
  return cleanValue(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function itemMatchesFilter(item, filter) {
  const key = filterKey(filter);
  if (!key || key === "all") return true;
  const genres = [item.genre, ...(Array.isArray(item.genres) ? item.genres : [])].map(filterKey);
  return filterKey(item.type) === key || genres.includes(key);
}

function cleanNumber(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value || ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function normalizeEditorialTypes(values) {
  const raw = Array.isArray(values) ? values : [];
  const normalized = raw.map((value) => workerType(value)).filter((value) => (
    value === "movie" || value === "series" || value === "animation"
  ));
  return Array.from(new Set(normalized)).slice(0, 3);
}

function safeCatalogSort(value) {
  const normalized = cleanValue(value).toLowerCase();
  if (["popular", "top", "year", "upcoming", "nowplaying", "now_playing"].includes(normalized)) {
    return normalized === "nowplaying" ? "now_playing" : normalized;
  }
  return "popular";
}

function safeImageUrl(value) {
  const raw = cleanValue(value);
  if (!raw) return "";
  if (raw.startsWith("/t/p/")) return `https://image.tmdb.org${raw}`;
  if (raw.startsWith("/")) return `https://image.tmdb.org/t/p/w780${raw}`;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.origin !== "https://image.tmdb.org") return "";
    return url.toString();
  } catch {
    return "";
  }
}

function cssImageArt(value) {
  const url = safeImageUrl(value);
  if (!url) return "";
  const escaped = url.replace(/["\\]/g, "");
  return `url("${escaped}")`;
}

function cleanRating(value) {
  const text = cleanValue(value);
  const match = text.match(/\d+(?:\.\d+)?/);
  return match ? `IMDb ${match[0]}` : "IMDb";
}

function artFor(id, name) {
  const palettes = [
    ["#31405b", "#101116", "rgba(255,255,255,.24)"],
    ["#4e3026", "#101116", "rgba(255,142,73,.28)"],
    ["#52622c", "#11131a", "rgba(255,225,91,.28)"],
    ["#29464b", "#0d1116", "rgba(64,180,205,.22)"],
    ["#263f67", "#0b0d12", "rgba(97,171,255,.26)"],
    ["#264d36", "#101116", "rgba(63,220,132,.22)"],
  ];
  const seed = Array.from(`${id}:${name}`).reduce((sum, char) => sum + char.charCodeAt(0), 0);
  const [a, b, glow] = palettes[seed % palettes.length];
  return `linear-gradient(135deg,${a},${b}),radial-gradient(circle at 66% 24%,${glow},transparent 150px)`;
}

async function copyDiagnostics() {
  const packet = diagnosticsPacket();
  try {
    await navigator.clipboard.writeText(packet);
  } catch {
    const preview = document.getElementById("diagnosticPreview");
    if (preview) preview.textContent = packet;
  }
}

function applyPrefs() {
  document.documentElement.classList.toggle("reduce-motion", Boolean(state.reduceMotion));
  document.documentElement.classList.toggle("compact-layout", Boolean(state.compactLayout));
  if (state.reduceMotion && heroTimer) {
    clearInterval(heroTimer);
    heroTimer = null;
  } else if (!state.reduceMotion) {
    startHeroRotation();
  }
}

function registerPwa() {
  if (!("serviceWorker" in navigator)) return;
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  });
}

function setText(id, value) {
  const node = document.getElementById(id);
  if (node) node.textContent = value;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function iconSvg(name) {
  const path = iconPaths[name] || iconPaths.info;
  return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"/></svg>`;
}

window.JuicrWeb = {
  saveSelected,
  resetState,
  diagnosticsPacket,
};
