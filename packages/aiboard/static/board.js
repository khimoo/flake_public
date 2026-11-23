"use strict";

const byId = id => document.getElementById(id);
const page = document.body;
const postScroll = byId("post-scroll");
const panels = ["forums", "threads", "thread", "workers"];
const panelMarkup = new Map();
const busy = new WeakSet();
let lastPostNo = page.dataset.lastPostNo;
let refreshInFlight = false;
let openInFlight = false;

function feedback(message = "") {
  const area = byId("feedback");
  area.textContent = message;
  area.hidden = !message;
}

async function request(path, data) {
  const options = { mode: "same-origin" };
  if (data !== undefined) {
    options.method = "POST";
    options.headers = { "Content-Type": "application/json" };
    options.body = JSON.stringify(data);
  }
  const response = await fetch(path, options);
  if (!response.headers.get("Content-Type")?.startsWith("application/json")) {
    throw new Error(`HTTP ${response.status}`);
  }
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
  return result;
}

function setAvailable(form, allowed) {
  form.dataset.allowed = String(allowed);
  form.querySelector("button[type=submit]").setAttribute("aria-disabled", String(!allowed));
}

function apply(state, submittedForm) {
  const scroll = [...document.querySelectorAll(".pane"), postScroll]
    .map(node => [node, node.scrollLeft, node.scrollTop]);
  for (const key of panels) {
    const panel = byId(key);
    const focus = document.activeElement;
    // Revisit on the next poll rather than stealing focus or resetting a select.
    if (submittedForm?.contains(focus) || !panel.contains(focus)) {
      if (panelMarkup.get(key) !== state[key]) {
        // These are HTML fragments rendered and escaped by the local server.
        panel.innerHTML = state[key];
        panelMarkup.set(key, state[key]);
      }
    }
  }
  if (state.posts) {
    byId("posts").insertAdjacentHTML("beforeend", state.posts);
  }
  lastPostNo = String(state.last_post_no);
  const toggle = byId("archive-toggle");
  toggle.setAttribute("href", state.toggle_url);
  toggle.textContent = state.toggle_label;
  byId("forum-title").textContent = state.forum_title;
  byId("search-forum").value = state.forum_id;
  byId("new-thread").elements.forum_id.value = state.forum_id;
  setAvailable(byId("new-thread"), state.new_allowed);
  setAvailable(byId("reply"), state.reply_allowed);
  for (const [node, left, top] of scroll) {
    node.scrollLeft = left;
    node.scrollTop = top;
  }
}

function refreshPath(path) {
  const params = new URLSearchParams(location.search);
  params.set("since", lastPostNo);
  return `${path}?${params}`;
}

// Serialize view refreshes so an earlier poll cannot append duplicate posts
// after a later response. Mutations never change read state via the poll route.
let applying = Promise.resolve();
function update(open = false, submittedForm) {
  const run = async () => {
    const state = await request(refreshPath(open ? "/api/open" : "/api/poll"), open ? {} : undefined);
    apply(state, submittedForm);
  };
  const result = applying.then(run);
  applying = result.catch(() => {});
  return result;
}

async function openThread() {
  if (!page.dataset.threadId || openInFlight) return;
  openInFlight = true;
  try {
    await update(true);
  } catch (error) {
    feedback(`既読を更新できませんでした: ${error.message}`);
  } finally {
    openInFlight = false;
  }
}

function boardURL(forum, thread) {
  const query = new URLSearchParams();
  if (new URLSearchParams(location.search).get("archived") === "1") query.set("archived", "1");
  query.set("forum", forum);
  if (thread) query.set("thread", thread);
  return `/?${query}`;
}

document.addEventListener("submit", async event => {
  const form = event.target;
  if (!form.dataset.api) return;
  event.preventDefault();
  if (form.dataset.allowed === "false" || event.submitter?.disabled || busy.has(form)) return;
  const payload = Object.fromEntries(new FormData(form));
  busy.add(form);
  feedback();
  let result;
  try {
    result = await request(form.dataset.api, payload);
  } catch (error) {
    feedback(error.message);
    return;
  } finally {
    busy.delete(form);
  }
  if (form.id === "new-forum" || form.id === "new-thread") {
    location.assign(boardURL(result.forum_id, result.thread_id));
    return;
  }
  if (form.id === "reply" && form.elements.body.value === payload.body) form.reset();
  try {
    await update(false, form);
    if (form.id === "reply") {
      byId(`post-${result.post_no}`)?.scrollIntoView({ block: "nearest" });
    }
  } catch (error) {
    feedback(`操作は完了しましたが、画面を更新できませんでした: ${error.message}`);
  }
});

document.addEventListener("click", event => {
  const chip = event.target.closest("[data-mention]");
  if (!chip) return;
  const input = chip.closest("form").elements.body;
  const { selectionStart: start, selectionEnd: end, value } = input;
  const space = start && !/\s/u.test(value[start - 1]) ? " " : "";
  input.setRangeText(`${space}${chip.dataset.mention} `, start, end, "end");
  input.focus({ preventScroll: true });
});

// Keep panel hooks intact when comparing the first server-rendered response.
for (const key of panels) panelMarkup.set(key, byId(key).innerHTML);
for (const id of ["new-thread", "reply"]) setAvailable(byId(id), byId(id).dataset.allowed === "true");
openThread();
window.addEventListener("pageshow", event => { if (event.persisted) openThread(); });
window.setInterval(async () => {
  if (refreshInFlight || openInFlight) return;
  refreshInFlight = true;
  try {
    await update();
  } catch (error) {
    if (byId("feedback").hidden) feedback(`自動更新できませんでした: ${error.message}`);
  } finally {
    refreshInFlight = false;
  }
}, 5000);
