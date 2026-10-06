"use strict";

// Every enhancement keeps a working HTML fallback: all modes, all documents,
// and direct full-size image links remain usable with JavaScript disabled.
const guideToggle = document.querySelector(".guide-menu-toggle");
if (guideToggle) {
  const sidebar = document.querySelector(".docs-sidebar");
  const navigation = document.getElementById("guide-navigation");
  const narrow = window.matchMedia("(max-width: 767px)");
  sidebar.classList.add("is-enhanced");
  function setGuideMenu(open) {
    navigation.hidden = !open;
    guideToggle.setAttribute("aria-expanded", String(open));
    guideToggle.querySelector("span").textContent = open ? "−" : "+";
  }
  function adaptGuideMenu() {
    guideToggle.hidden = !narrow.matches;
    setGuideMenu(!narrow.matches);
  }
  guideToggle.addEventListener("click", () => setGuideMenu(navigation.hidden));
  narrow.addEventListener("change", adaptGuideMenu);
  adaptGuideMenu();
}

const modes = document.querySelector("[data-modes]");
if (modes) {
  const tabs = [...modes.querySelectorAll("[data-mode]")];
  const bar = modes.querySelector(".mode-tabs");
  bar.hidden = false;
  bar.setAttribute("role", "tablist");
  modes.classList.add("is-enhanced");
  function selectMode(index, focus = false) {
    tabs.forEach((tab, i) => {
      const selected = i === index;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
      document.getElementById(`mode-${tab.dataset.mode}`).hidden = !selected;
    });
    if (focus) tabs[index].focus();
  }
  tabs.forEach((tab, i) => {
    const panel = document.getElementById(`mode-${tab.dataset.mode}`);
    tab.id = `tab-${tab.dataset.mode}`;
    tab.setAttribute("role", "tab");
    tab.setAttribute("aria-controls", panel.id);
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("aria-labelledby", tab.id);
    panel.tabIndex = 0;
    tab.addEventListener("click", () => selectMode(i));
    tab.addEventListener("keydown", (event) => {
      let next;
      if (event.key === "ArrowRight") next = (i + 1) % tabs.length;
      else if (event.key === "ArrowLeft") next = (i + tabs.length - 1) % tabs.length;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = tabs.length - 1;
      else return;
      event.preventDefault();
      selectMode(next, true);
    });
  });
  selectMode(0);
}

const search = document.getElementById("doc-search");
if (search) {
  document.querySelector(".doc-search").hidden = false;
  const cards = [...document.querySelectorAll(".doc-card")];
  const status = document.getElementById("search-status");
  const empty = document.querySelector(".search-empty");
  function filterGuides() {
    const terms = search.value.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
    let count = 0;
    cards.forEach((card) => {
      const text = (card.dataset.search || card.textContent).toLocaleLowerCase();
      const match = terms.every((term) => text.includes(term));
      card.hidden = !match;
      if (match) count += 1;
    });
    status.textContent = `${count} ${count === 1 ? "guide" : "guides"}${terms.length ? " found" : " to explore"}`;
    empty.hidden = count !== 0;
  }
  search.addEventListener("input", filterGuides);
  document.getElementById("clear-search").addEventListener("click", () => {
    search.value = "";
    filterGuides();
    search.focus();
  });
  filterGuides();
}

const viewer = document.getElementById("image-viewer");
if (viewer && typeof viewer.showModal === "function") {
  const links = [...document.querySelectorAll(".gallery-open")];
  const image = document.getElementById("viewer-image");
  let current = 0;
  let opener;
  function showImage(index) {
    current = (index + links.length) % links.length;
    const link = links[current];
    document.getElementById("viewer-error").hidden = true;
    document.getElementById("viewer-original").href = link.href;
    image.alt = link.querySelector("img").alt;
    image.src = link.href;
    document.getElementById("viewer-caption").textContent = link.dataset.caption;
    document.getElementById("viewer-position").textContent = `Screenshot ${current + 1} of ${links.length}`;
  }
  image.addEventListener("error", () => { document.getElementById("viewer-error").hidden = false; });
  links.forEach((link, i) => {
    link.addEventListener("click", (event) => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      opener = link;
      showImage(i);
      viewer.showModal();
    });
  });
  document.getElementById("viewer-close").addEventListener("click", () => viewer.close());
  document.getElementById("viewer-prev").addEventListener("click", () => showImage(current - 1));
  document.getElementById("viewer-next").addEventListener("click", () => showImage(current + 1));
  viewer.addEventListener("keydown", (event) => {
    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      event.preventDefault();
      showImage(current + (event.key === "ArrowRight" ? 1 : -1));
    }
  });
  viewer.addEventListener("click", (event) => {
    if (event.target !== viewer) return;
    const rect = viewer.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) viewer.close();
  });
  viewer.addEventListener("close", () => { if (opener) opener.focus(); });
}
