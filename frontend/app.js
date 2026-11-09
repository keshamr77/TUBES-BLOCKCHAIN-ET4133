"use strict";

// Simulasi SAKSI: antarmuka untuk kontrak SaksiRegistry.
// Konfigurasi (alamat kontrak, RPC, akun uji, ABI) dibuat oleh scripts/deploy.sh di config.js.

const STATUS = ["–", "Disimpan", "Dalam serah-terima", "Ditutup"];
const STATUS_CLASS = ["badge-muted", "badge-ok", "badge-warn", "badge-muted"];
const ACTION = [
  "Bukti didaftarkan",
  "Serah-terima dimulai",
  "Serah-terima diterima",
  "Serah-terima ditolak",
  "Serah-terima dibatalkan",
  "Bukti ditutup",
];
const S_STORED = 1n;
const S_IN_TRANSFER = 2n;

const cfg = window.SAKSI_CONFIG;
const $ = (id) => document.getElementById(id);

const state = {
  provider: null,
  reader: null,
  wallets: {},
  current: "investigator",
  evidence: [],
  selectedId: null,
  paused: false,
  busy: false,
  roleNames: {},
  sample: null,
};

// ---------------------------------------------------------------------------
// Utilitas
// ---------------------------------------------------------------------------

function esc(value) {
  return String(value).replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

function short(addr) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "–";
}

function accountByAddress(addr) {
  if (!addr) return null;
  return cfg.accounts.find((a) => a.address.toLowerCase() === addr.toLowerCase()) || null;
}

function labelOf(addr) {
  if (!addr || addr === ethers.ZeroAddress) return "–";
  const acc = accountByAddress(addr);
  return acc ? acc.label : short(addr);
}

function currentAccount() {
  return cfg.accounts.find((a) => a.key === state.current);
}

function formatTime(ts) {
  return new Date(Number(ts) * 1000).toLocaleString("id-ID", {
    dateStyle: "medium",
    timeStyle: "medium",
  });
}

async function sha256File(file) {
  if (!window.crypto || !crypto.subtle) {
    throw new Error("Browser tidak mengizinkan perhitungan hash. Buka halaman lewat http://localhost, bukan alamat lain.");
  }
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  return "0x" + [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function logItem(message, kind, time) {
  const li = document.createElement("li");
  if (kind) li.className = kind;
  li.innerHTML = `<span class="time">${time}</span>${message}`;
  return li;
}

function log(message, kind = "") {
  $("log").prepend(logItem(message, kind, new Date().toLocaleTimeString("id-ID")));
}

function showFatal(message) {
  const el = $("fatal");
  el.innerHTML = message;
  el.hidden = false;
}

// ---------------------------------------------------------------------------
// Terjemahan error kontrak
// ---------------------------------------------------------------------------

// ethers only decodes custom errors on read calls. When a transaction reverts during gas
// estimation the revert data is on err.data, so decode it with the contract ABI here.
function decodeRevert(err) {
  if (!err) return null;
  if (err.revert) return err.revert;
  const data = err.data || (err.info && err.info.error && err.info.error.data) || (err.error && err.error.data);
  if (typeof data === "string" && data.length >= 10 && state.reader) {
    try {
      const parsed = state.reader.interface.parseError(data);
      if (parsed) return { name: parsed.name, args: parsed.args };
    } catch {
      // not one of our errors
    }
  }
  return null;
}

function explainError(err) {
  const rev = decodeRevert(err);
  if (rev) {
    const a = rev.args || [];
    switch (rev.name) {
      case "HashMismatch":
        return `<strong>Hash berkas TIDAK COCOK.</strong> Terdaftar <code>${short(a[1])}</code>, diterima <code>${short(a[2])}</code>. ` +
          "Berkas kemungkinan telah diubah, sehingga serah-terima ditolak oleh smart contract.";
      case "NotHolder":
        return "Ditolak: akun ini bukan pemegang bukti tersebut.";
      case "NotPendingRecipient":
        return "Ditolak: akun ini bukan penerima serah-terima tersebut.";
      case "InvalidStatus":
        return `Ditolak: status bukti tidak sesuai untuk aksi ini (status sekarang: ${STATUS[Number(a[1])]}).`;
      case "InvalidRecipient":
        return "Ditolak: penerima harus personel lain (Penyidik atau Kustodian), bukan diri sendiri atau Admin.";
      case "DuplicateEvidence":
        return `Ditolak: berkas ini sudah terdaftar sebagai bukti #${a[1]}. Gunakan berkas lain (misalnya unduh berkas contoh baru).`;
      case "EmptyField":
        return "Ditolak: nomor perkara dan berkas wajib diisi.";
      case "FieldTooLong":
        return `Ditolak: teks terlalu panjang (${a[0]} byte, maksimal ${a[1]} byte).`;
      case "EvidenceNotFound":
        return `Ditolak: bukti #${a[0]} tidak ditemukan.`;
      case "NotPersonnel":
        return "Ditolak: akun ini bukan lagi personel aktif (peran telah dicabut).";
      case "AccessControlUnauthorizedAccount":
        return `Ditolak: akun ini tidak memiliki peran <strong>${esc(state.roleNames[a[1]] || a[1])}</strong> yang dibutuhkan.`;
      case "EnforcedPause":
        return "Ditolak: sistem sedang dijeda oleh Admin.";
      case "ExpectedPause":
        return "Ditolak: sistem tidak sedang dijeda.";
      default:
        return `Ditolak oleh kontrak: ${esc(rev.name)}`;
    }
  }
  if (err && (err.code === "NETWORK_ERROR" || err.code === "SERVER_ERROR" || /fetch|ECONNREFUSED/i.test(err.message || ""))) {
    return "Tidak bisa menghubungi node blockchain. Pastikan jaringan (anvil/Besu) sedang berjalan.";
  }
  // ethers reports node errors it cannot classify as "could not coalesce error"; the real
  // reason is on err.error.
  const rpcMessage = (err && err.code === "UNKNOWN_ERROR" && err.error && err.error.message) || "";
  if ((err && err.code === "NONCE_EXPIRED") || /underpriced|nonce/i.test(rpcMessage)) {
    return "Akun ini sedang dipakai mengirim transaksi lain (misalnya dari tab lain). Tunggu sebentar, lalu coba lagi.";
  }
  if (rpcMessage) return `Node menolak transaksi: ${esc(rpcMessage)}`;
  return esc((err && (err.shortMessage || err.message)) || String(err));
}

// ---------------------------------------------------------------------------
// Transaksi
// ---------------------------------------------------------------------------

// Dua sesi dengan akun yang sama bisa menandatangani transaksi identik (nonce dan data sama).
// Besu menolak salinan kedua dengan "Known transaction", padahal aksinya sedang diproses,
// jadi tunggu transaksi yang sudah ada di antrean itu.
async function submitTx(call, contract, nonce) {
  try {
    return await call(contract, { nonce });
  } catch (err) {
    const payload = err && err.payload;
    const isKnown = payload && payload.method === "eth_sendRawTransaction" &&
      err.error && /known transaction/i.test(err.error.message || "");
    if (!isKnown) throw err;
    const hash = ethers.keccak256(payload.params[0]);
    return {
      hash,
      wait: async () => {
        const receipt = await state.provider.waitForTransaction(hash);
        if (receipt.status !== 1) throw new Error("Transaksi gagal dieksekusi oleh smart contract.");
        return receipt;
      },
    };
  }
}

async function sendTx(description, call) {
  if (state.busy) {
    const message = "Tunggu transaksi sebelumnya selesai.";
    log(message, "err");
    return { ok: false, message };
  }
  state.busy = true;
  document.body.style.cursor = "progress";
  const acc = currentAccount();
  log(`<strong>${esc(acc.label)}</strong>: ${esc(description)}…`);
  try {
    const wallet = state.wallets[acc.key];
    const contract = state.reader.connect(wallet);
    // Raw RPC call bypasses ethers' short-lived request cache, which can return a stale
    // nonce when blocks are mined instantly (anvil).
    const nonce = Number(await state.provider.send("eth_getTransactionCount", [wallet.address, "pending"]));
    const tx = await submitTx(call, contract, nonce);
    log(`Transaksi dikirim <code>${short(tx.hash)}</code>, menunggu blok…`);
    const receipt = await tx.wait();
    log(`✔ ${esc(description)} berhasil (blok ${receipt.blockNumber}).`, "ok");
    return { ok: true, blockNumber: receipt.blockNumber };
  } catch (err) {
    const message = explainError(err);
    log(`✖ ${message}`, "err");
    console.error(err);
    return { ok: false, message };
  } finally {
    state.busy = false;
    document.body.style.cursor = "";
    await refresh();
  }
}

// ---------------------------------------------------------------------------
// Dialog aksi
// ---------------------------------------------------------------------------

let dialogResolve = null;

function openDialog({ title, desc, fields, submitLabel }) {
  $("action-title").textContent = title;
  $("action-desc").innerHTML = desc || "";
  $("action-submit").textContent = submitLabel || "Kirim";
  const box = $("action-fields");
  box.innerHTML = "";
  for (const f of fields) {
    const label = document.createElement("label");
    label.textContent = f.label;
    let input;
    if (f.type === "select") {
      input = document.createElement("select");
      for (const opt of f.options) {
        const o = document.createElement("option");
        o.value = opt.value;
        o.textContent = opt.label;
        input.append(o);
      }
    } else {
      input = document.createElement("input");
      input.type = f.type || "text";
      if (f.maxlength) input.maxLength = f.maxlength;
      if (f.placeholder) input.placeholder = f.placeholder;
    }
    input.name = f.name;
    if (f.required) input.required = true;
    label.append(input);
    if (f.type === "file") {
      const out = document.createElement("div");
      out.className = "hash-line";
      out.innerHTML = 'SHA-256: <code>–</code>';
      input.addEventListener("change", async () => {
        out.querySelector("code").textContent = input.files[0] ? await sha256File(input.files[0]) : "–";
      });
      label.append(out);
    }
    box.append(label);
  }
  $("action-dialog").showModal();
  return new Promise((resolve) => { dialogResolve = resolve; });
}

$("action-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const resolve = dialogResolve;
  dialogResolve = null;
  if (event.submitter && event.submitter.value === "cancel") {
    $("action-dialog").close();
    if (resolve) resolve(null);
    return;
  }
  const values = {};
  try {
    for (const el of $("action-fields").querySelectorAll("input, select")) {
      values[el.name] = el.type === "file" ? await sha256File(el.files[0]) : el.value.trim();
    }
  } catch (err) {
    log(`✖ ${esc(err.message)}`, "err");
    $("action-dialog").close();
    if (resolve) resolve(null);
    return;
  }
  $("action-dialog").close();
  if (resolve) resolve(values);
});

$("action-dialog").addEventListener("close", () => {
  if (dialogResolve) {
    dialogResolve(null);
    dialogResolve = null;
  }
});

// ---------------------------------------------------------------------------
// Aksi bukti
// ---------------------------------------------------------------------------

function personnelOptions(excludeAddr) {
  return cfg.accounts
    .filter((a) => a.key !== "admin" && a.address.toLowerCase() !== excludeAddr.toLowerCase())
    .map((a) => ({ value: a.address, label: `${a.label} (${short(a.address)})` }));
}

async function actionInitiate(e) {
  const v = await openDialog({
    title: `Serahkan bukti #${e.id}`,
    desc: "Bukti baru berpindah setelah penerima mengonfirmasi dengan berkas yang sama.",
    submitLabel: "Mulai serah-terima",
    fields: [
      { name: "to", label: "Penerima", type: "select", options: personnelOptions(state.wallets[state.current].address) },
      { name: "note", label: "Catatan (alasan, lokasi, nomor berita acara)", maxlength: 256, placeholder: "Dikirim ke lab forensik" },
    ],
  });
  if (v) await sendTx(`menyerahkan bukti #${e.id} ke ${labelOf(v.to)}`, (c, o) => c.initiateTransfer(e.id, v.to, v.note, o));
}

async function actionAccept(e) {
  const v = await openDialog({
    title: `Terima bukti #${e.id}`,
    desc: "Unggah berkas yang Anda terima. Hash-nya dihitung di browser dan dicocokkan oleh smart contract. " +
      "Untuk demo deteksi perubahan, unggah <strong>versi yang diubah</strong>.",
    submitLabel: "Terima bukti",
    fields: [{ name: "fileHash", label: "Berkas yang diterima", type: "file", required: true }],
  });
  if (v) await sendTx(`menerima bukti #${e.id}`, (c, o) => c.acceptTransfer(e.id, v.fileHash, o));
}

async function actionReject(e) {
  const v = await openDialog({
    title: `Tolak bukti #${e.id}`,
    desc: "Bukti tetap dipegang pengirim. Alasan penolakan tercatat permanen di riwayat.",
    submitLabel: "Tolak",
    fields: [{ name: "note", label: "Alasan penolakan", maxlength: 256, placeholder: "Segel kemasan rusak", required: true }],
  });
  if (v) await sendTx(`menolak bukti #${e.id}`, (c, o) => c.rejectTransfer(e.id, v.note, o));
}

async function actionCancel(e) {
  await sendTx(`membatalkan serah-terima bukti #${e.id}`, (c, o) => c.cancelTransfer(e.id, o));
}

async function actionClose(e) {
  const v = await openDialog({
    title: `Tutup bukti #${e.id}`,
    desc: "Status <strong>Ditutup</strong> bersifat final. Bukti tidak bisa diserahkan lagi.",
    submitLabel: "Tutup bukti",
    fields: [{ name: "note", label: "Catatan penutupan", maxlength: 256, placeholder: "Perkara telah berkekuatan hukum tetap" }],
  });
  if (v) await sendTx(`menutup bukti #${e.id}`, (c, o) => c.closeEvidence(e.id, v.note, o));
}

// ---------------------------------------------------------------------------
// Tampilan
// ---------------------------------------------------------------------------

function setRole(key) {
  if (key === state.current) return;
  state.current = key;
  renderRoles();
  renderEvidence();
  log(`Sekarang bertindak sebagai <strong>${esc(currentAccount().label)}</strong>.`);
}

function renderRoles() {
  const list = $("role-list");
  list.innerHTML = "";
  for (const acc of cfg.accounts) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "role" + (acc.key === state.current ? " active" : "");
    btn.setAttribute("aria-pressed", String(acc.key === state.current));
    btn.innerHTML = `<span><strong>${esc(acc.label)}</strong><span class="addr">${esc(acc.address)}</span></span>` +
      `<span class="badge">${esc(acc.role)}</span>`;
    btn.addEventListener("click", () => setRole(acc.key));
    list.append(btn);
  }
  // Pemilih ringkas di navigasi selalu mengikuti peran aktif.
  const select = $("role-select");
  if (select.options.length !== cfg.accounts.length) {
    select.innerHTML = "";
    for (const acc of cfg.accounts) {
      const o = document.createElement("option");
      o.value = acc.key;
      o.textContent = acc.label;
      select.append(o);
    }
  }
  select.value = state.current;
}

function actionButtons(e) {
  const me = state.wallets[state.current].address.toLowerCase();
  const isHolder = e.holder.toLowerCase() === me;
  const isRecipient = e.pendingRecipient.toLowerCase() === me;
  const buttons = [];
  if (isHolder && e.status === S_STORED) {
    buttons.push(["Serahkan", actionInitiate, "btn-primary"], ["Tutup", actionClose, ""]);
  }
  if (isHolder && e.status === S_IN_TRANSFER) buttons.push(["Batalkan", actionCancel, "btn-danger"]);
  if (isRecipient && e.status === S_IN_TRANSFER) {
    buttons.push(["Terima", actionAccept, "btn-primary"], ["Tolak", actionReject, "btn-danger"]);
  }
  return buttons;
}

function renderEvidence() {
  const body = $("evidence-body");
  body.innerHTML = "";
  if (state.evidence.length === 0) {
    body.innerHTML = '<tr><td colspan="6" class="empty">Belum ada bukti. Daftarkan bukti pertama sebagai Penyidik.</td></tr>';
    return;
  }
  for (const e of state.evidence) {
    const tr = document.createElement("tr");
    if (e.id === state.selectedId) tr.className = "selected";
    const statusIdx = Number(e.status);
    const pending = e.status === S_IN_TRANSFER ? `<br><span class="hint">→ ${esc(labelOf(e.pendingRecipient))}</span>` : "";
    // data-label dipakai CSS untuk menampilkan tabel sebagai kartu di layar sempit.
    tr.innerHTML = `<td data-label="#">${e.id}</td>` +
      `<td data-label="Nomor perkara">${esc(e.caseNumber)}</td>` +
      `<td data-label="Deskripsi">${esc(e.description) || "–"}</td>` +
      `<td data-label="Pemegang">${esc(labelOf(e.holder))}</td>` +
      `<td data-label="Status"><span><span class="badge ${STATUS_CLASS[statusIdx]}">${STATUS[statusIdx]}</span>${pending}</span></td>` +
      `<td data-label="Aksi"></td>`;
    const cell = tr.lastElementChild;
    const wrap = document.createElement("div");
    wrap.className = "actions";
    for (const [label, handler, cls] of actionButtons(e)) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = `btn btn-small ${cls}`;
      b.textContent = label;
      b.addEventListener("click", () => handler(e));
      wrap.append(b);
    }
    const detail = document.createElement("button");
    detail.type = "button";
    detail.className = "btn btn-small";
    detail.textContent = "Riwayat";
    detail.addEventListener("click", () => {
      state.selectedId = e.id;
      renderEvidence();
      renderDetail();
    });
    wrap.append(detail);
    cell.append(wrap);
    body.append(tr);
  }
}

async function renderDetail() {
  const e = state.evidence.find((x) => x.id === state.selectedId);
  if (!e) {
    $("detail").hidden = true;
    return;
  }
  $("detail").hidden = false;
  $("detail-id").textContent = `#${e.id}`;
  $("detail-info").innerHTML =
    `<dt>Nomor perkara</dt><dd>${esc(e.caseNumber)}</dd>` +
    `<dt>Deskripsi</dt><dd>${esc(e.description) || "–"}</dd>` +
    `<dt>Hash SHA-256</dt><dd><code>${esc(e.fileHash)}</code></dd>` +
    `<dt>Pemegang</dt><dd>${esc(labelOf(e.holder))}</dd>` +
    `<dt>Status</dt><dd>${STATUS[Number(e.status)]}</dd>` +
    `<dt>Didaftarkan</dt><dd>${formatTime(e.registeredAt)}</dd>`;

  const history = await state.reader.getHistory(e.id);
  const ol = $("timeline");
  ol.innerHTML = "";
  for (const r of history) {
    const action = Number(r.action);
    let who = `<strong>${esc(labelOf(r.actor))}</strong>`;
    if (action === 1) who += ` → ${esc(labelOf(r.counterparty))}`;
    if (action === 2) who += ` (dari ${esc(labelOf(r.counterparty))})`;
    if (action === 3) who += ` (pengirim: ${esc(labelOf(r.counterparty))})`;
    if (action === 4) who += ` (calon penerima: ${esc(labelOf(r.counterparty))})`;
    const li = document.createElement("li");
    li.innerHTML = `<div><strong>${ACTION[action]}</strong> — ${who}</div>` +
      `<div class="when">${formatTime(r.timestamp)}</div>` +
      (r.note ? `<div class="note">“${esc(r.note)}”</div>` : "");
    ol.append(li);
  }
}

// ---------------------------------------------------------------------------
// Sinkronisasi data
// ---------------------------------------------------------------------------

async function refresh() {
  try {
    const [count, paused] = await Promise.all([state.reader.evidenceCount(), state.reader.paused()]);
    // Konfirmasi lama tidak berlaku lagi kalau status berubah.
    if (paused !== state.paused) $("admin-result").hidden = true;
    state.paused = paused;
    $("pause-badge").hidden = !paused;
    $("system-status").textContent = paused ? "Dijeda" : "Aktif";
    $("system-status").className = `badge ${paused ? "badge-warn" : "badge-ok"}`;
    const ids = Array.from({ length: Number(count) }, (_, i) => i + 1);
    const items = await Promise.all(ids.map((id) => state.reader.getEvidence(id)));
    state.evidence = items.map((e, i) => ({
      id: ids[i],
      caseNumber: e.caseNumber,
      description: e.description,
      fileHash: e.fileHash,
      holder: e.holder,
      pendingRecipient: e.pendingRecipient,
      status: e.status,
      registeredAt: e.registeredAt,
    })).reverse();
    renderEvidence();
    if (state.selectedId) await renderDetail();
  } catch (err) {
    log(`✖ Gagal memuat data: ${explainError(err)}`, "err");
  }
}

async function updateBlock() {
  try {
    $("block-number").textContent = await state.provider.getBlockNumber();
    $("net-badge").className = "badge badge-ok";
  } catch {
    $("net-badge").className = "badge badge-err";
    $("block-number").textContent = "terputus";
  }
}

// ---------------------------------------------------------------------------
// Riwayat aktivitas dari blockchain
// ---------------------------------------------------------------------------

const LOG_HISTORY_LIMIT = 30;
// Besu membatasi rentang eth_getLogs (--rpc-max-logs-range, bawaan 5000 blok).
const LOG_RANGE_BLOCKS = 2000;

function describeEvent({ name, args: a }) {
  const who = (addr) => `<strong>${esc(labelOf(addr))}</strong>`;
  const note = a.note ? ` — “${esc(a.note)}”` : "";
  switch (name) {
    case "EvidenceRegistered":
      return `${who(a.holder)} mendaftarkan bukti #${a.id} (perkara ${esc(a.caseNumber)}).`;
    case "TransferInitiated":
      return `${who(a.from)} menyerahkan bukti #${a.id} ke ${who(a.to)}${note}.`;
    case "TransferAccepted":
      return `${who(a.to)} menerima bukti #${a.id} dari ${who(a.from)}.`;
    case "TransferRejected":
      return `${who(a.by)} menolak bukti #${a.id} dari ${who(a.from)}${note}.`;
    case "TransferCancelled":
      return `${who(a.by)} membatalkan serah-terima bukti #${a.id}.`;
    case "EvidenceClosed":
      return `${who(a.by)} menutup bukti #${a.id}${note}.`;
    case "Paused":
      return `${who(a.account)} menjeda sistem.`;
    case "Unpaused":
      return `${who(a.account)} melanjutkan sistem.`;
    default:
      return null; // misalnya RoleGranted saat deploy
  }
}

// Isi log dengan aktivitas terbaru di rantai, karena pesan sesi hilang saat halaman dimuat ulang.
// Entri ditambahkan di bawah supaya tetap lebih lama daripada pesan sesi yang sudah tampil.
async function loadLogHistory() {
  const placeholder = logItem("Memuat aktivitas terbaru dari blockchain…", "", "");
  $("log").append(placeholder);
  try {
    const floor = cfg.deployBlock ?? 0;
    let to = await state.provider.getBlockNumber();
    const entries = [];
    while (to >= floor && entries.length < LOG_HISTORY_LIMIT) {
      const from = Math.max(floor, to - LOG_RANGE_BLOCKS + 1);
      const logs = await state.provider.getLogs({ address: cfg.contractAddress, fromBlock: from, toBlock: to });
      for (const entry of logs.reverse()) {
        const parsed = state.reader.interface.parseLog(entry);
        const message = parsed && describeEvent(parsed);
        if (message) entries.push({ message, blockNumber: entry.blockNumber, hash: entry.transactionHash });
      }
      to = from - 1;
    }
    const recent = entries.slice(0, LOG_HISTORY_LIMIT);
    const numbers = [...new Set(recent.map((e) => e.blockNumber))];
    const blocks = await Promise.all(numbers.map((n) => state.provider.getBlock(n)));
    const timeOf = new Map(blocks.map((b) => [b.number, b.timestamp]));
    placeholder.remove();
    for (const e of recent) {
      const detail = ` <span class="hint">blok ${e.blockNumber} · <code>${short(e.hash)}</code></span>`;
      $("log").append(logItem(e.message + detail, "", formatTime(timeOf.get(e.blockNumber))));
    }
    if (recent.length === 0) $("log").append(logItem("Belum ada aktivitas tercatat di blockchain.", "", ""));
  } catch (err) {
    placeholder.remove();
    $("log").append(logItem(`✖ Gagal memuat riwayat aktivitas: ${explainError(err)}`, "err", ""));
  }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

async function adminAction(description, call, successText) {
  const result = await sendTx(description, call);
  const box = $("admin-result");
  box.className = `admin-result ${result.ok ? "ok" : "err"}`;
  box.innerHTML = result.ok ? `✔ ${successText} (blok ${result.blockNumber}).` : `✖ ${result.message}`;
  box.hidden = false;
}

// ---------------------------------------------------------------------------
// Berkas contoh untuk demo
// ---------------------------------------------------------------------------

function download(name, text) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function makeSample() {
  const id = Math.random().toString(36).slice(2, 8).toUpperCase();
  const now = new Date().toLocaleString("id-ID");
  const text = [
    "BERITA ACARA PENYITAAN BUKTI DIGITAL (CONTOH SIMULASI)",
    `Nomor bukti   : BD-${id}`,
    `Waktu         : ${now}`,
    "Barang bukti  : 1 (satu) unit laptop, nomor seri SN-4471-0923",
    "Saldo transfer: Rp 25.000.000",
    "Petugas       : Penyidik (simulasi)",
  ].join("\n") + "\n";
  return { id, text, tampered: text.replace("Rp 25.000.000", "Rp 95.000.000") };
}

// ---------------------------------------------------------------------------
// Inisialisasi
// ---------------------------------------------------------------------------

async function init() {
  if (!window.ethers) {
    showFatal("Pustaka ethers.js gagal dimuat (frontend/vendor/ethers.umd.min.js).");
    return;
  }
  if (!cfg) {
    showFatal("Berkas <code>config.js</code> belum ada. Jalankan <code>scripts/deploy.sh anvil</code> atau <code>scripts/deploy.sh besu</code> terlebih dahulu.");
    return;
  }

  state.provider = new ethers.JsonRpcProvider(cfg.rpcUrl, cfg.chainId, { staticNetwork: true });
  state.provider.pollingInterval = 1000;
  state.reader = new ethers.Contract(cfg.contractAddress, cfg.abi, state.provider);
  for (const acc of cfg.accounts) state.wallets[acc.key] = new ethers.Wallet(acc.privateKey, state.provider);

  $("net-badge").textContent = `${cfg.network === "besu" ? "Besu QBFT" : "Anvil"} · chain ${cfg.chainId}`;
  // Info top bar mengikuti jaringan yang sebenarnya terhubung.
  if (cfg.network !== "besu") {
    $("topbar-network").textContent = "Jaringan Anvil (pengembangan)";
    $("topbar-validators").textContent = "1 Node lokal";
    $("topbar-blocktime").textContent = "Blok instan";
  }
  $("role-select").addEventListener("change", (event) => setRole(event.target.value));

  try {
    const code = await state.provider.getCode(cfg.contractAddress);
    if (code === "0x") {
      showFatal(`Kontrak tidak ditemukan di <code>${esc(cfg.contractAddress)}</code>. Jaringan mungkin di-reset; jalankan ulang <code>scripts/deploy.sh ${esc(cfg.network)}</code>.`);
      return;
    }
    const [inv, cus, adm] = await Promise.all([
      state.reader.INVESTIGATOR_ROLE(), state.reader.CUSTODIAN_ROLE(), state.reader.DEFAULT_ADMIN_ROLE(),
    ]);
    state.roleNames = { [inv]: "Penyidik", [cus]: "Kustodian", [adm]: "Admin" };
  } catch (err) {
    showFatal(`Tidak bisa terhubung ke ${esc(cfg.rpcUrl)}. Pastikan ${cfg.network === "besu" ? "<code>besu-network/start.sh</code>" : "<code>anvil</code>"} sudah berjalan, lalu muat ulang halaman.<br><small>${explainError(err)}</small>`);
    return;
  }

  renderRoles();
  await updateBlock();
  await refresh();
  setInterval(updateBlock, 2000);
  setInterval(() => { if (!state.busy) refresh(); }, 6000);

  $("refresh").addEventListener("click", refresh);
  $("detail-close").addEventListener("click", () => {
    state.selectedId = null;
    $("detail").hidden = true;
    renderEvidence();
  });

  const regForm = $("register-form");
  regForm.file.addEventListener("change", async () => {
    $("register-hash").textContent = regForm.file.files[0] ? await sha256File(regForm.file.files[0]) : "–";
  });
  regForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    let hash;
    try {
      hash = await sha256File(regForm.file.files[0]);
    } catch (err) {
      log(`✖ ${esc(err.message)}`, "err");
      return;
    }
    const result = await sendTx(
      `mendaftarkan bukti perkara ${regForm.caseNumber.value.trim()}`,
      (c, o) => c.registerEvidence(regForm.caseNumber.value.trim(), regForm.description.value.trim(), hash, o),
    );
    if (result.ok) {
      regForm.reset();
      $("register-hash").textContent = "–";
    }
  });

  $("verify-file").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    const out = $("verify-result");
    if (!file || !state.selectedId) return;
    try {
      const hash = await sha256File(file);
      const ok = await state.reader.verifyIntegrity(state.selectedId, hash);
      out.innerHTML = ok
        ? `<span class="badge badge-ok">COCOK</span> Berkas sama persis dengan yang terdaftar.`
        : `<span class="badge badge-err">TIDAK COCOK</span> Berkas berbeda dari yang terdaftar (hash <code>${short(hash)}</code>).`;
    } catch (err) {
      out.innerHTML = explainError(err);
    }
    event.target.value = "";
  });

  $("pause").addEventListener("click", () => adminAction("menjeda sistem", (c, o) => c.pause(o), "Sistem berhasil dijeda"));
  $("unpause").addEventListener("click", () => adminAction("melanjutkan sistem", (c, o) => c.unpause(o), "Sistem aktif kembali"));

  $("sample-original").addEventListener("click", () => {
    state.sample = makeSample();
    download(`bukti-${state.sample.id}.txt`, state.sample.text);
    $("sample-tampered").disabled = false;
    log(`Berkas contoh <code>bukti-${state.sample.id}.txt</code> diunduh.`);
  });
  $("sample-tampered").addEventListener("click", () => {
    if (!state.sample) return;
    download(`bukti-${state.sample.id}-DIUBAH.txt`, state.sample.tampered);
    log(`Versi yang diubah <code>bukti-${state.sample.id}-DIUBAH.txt</code> diunduh (nominal transfer diganti).`);
  });

  log(`Terhubung ke ${esc(cfg.network)} (${esc(cfg.rpcUrl)}), kontrak <code>${short(cfg.contractAddress)}</code>.`, "ok");
  loadLogHistory();
}

init();
