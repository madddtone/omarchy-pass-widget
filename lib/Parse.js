.pragma library

function str(v) {
  return v === undefined || v === null ? "" : String(v)
}

function normalize(o) {
  o = o || {}
  var service = str(o.Service !== undefined ? o.Service : o.service)
  return {
    service: service,
    username: str(o.Username !== undefined ? o.Username : o.username),
    category: str(o.Category !== undefined ? o.Category : o.category),
    url: str(o.URL !== undefined ? o.URL : o.url),
    notes: str(o.Notes !== undefined ? o.Notes : o.notes),
    createdAt: str(o.CreatedAt !== undefined ? o.CreatedAt : o.created_at),
    updatedAt: str(o.UpdatedAt !== undefined ? o.UpdatedAt : o.updated_at),
    modifiedCount: Number(o.ModifiedCount !== undefined ? o.ModifiedCount : o.modified_count) || 0,
    usageCount: Number(o.UsageCount !== undefined ? o.UsageCount : o.usage_count) || 0,
    lastAccessed: str(o.LastAccessed !== undefined ? o.LastAccessed : o.last_accessed),
    locations: o.Locations || o.locations || [],
    gitRepositories: o.GitRepositories || o.git_repositories || [],
    hasTotp: (o.HasTOTP !== undefined ? o.HasTOTP : o.has_totp) === true,
    totpIssuer: str(o.TOTPIssuer !== undefined ? o.TOTPIssuer : o.totp_issuer),
    domain: domainOf(str(o.URL !== undefined ? o.URL : o.url)),
    searchText: (service + " " + str(o.Username !== undefined ? o.Username : o.username)
      + " " + str(o.Category !== undefined ? o.Category : o.category)
      + " " + str(o.URL !== undefined ? o.URL : o.url)
      + " " + str(o.Notes !== undefined ? o.Notes : o.notes)).toLowerCase()
  }
}

function listFromJson(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data)) return []
    var out = []
    for (var i = 0; i < data.length; i++) out.push(normalize(data[i]))
    return out
  } catch (e) {
    return []
  }
}

function domainOf(url) {
  var u = str(url)
  if (!u) return ""
  u = u.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "")
  u = u.replace(/^[^@/]*@/, "")
  var slash = u.indexOf("/")
  if (slash !== -1) u = u.substring(0, slash)
  var colon = u.indexOf(":")
  if (colon !== -1) u = u.substring(0, colon)
  return u
}

function _rel(value) {
  var d = new Date(value)
  if (isNaN(d.getTime()) || d.getFullYear() < 2000) return ""
  var s = (Date.now() - d.getTime()) / 1000
  if (s < 0) s = 0
  if (s < 60) return "just now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m ago"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h ago"
  var days = Math.floor(h / 24)
  if (days < 30) return days + "d ago"
  var mo = Math.floor(days / 30)
  if (mo < 12) return mo + "mo ago"
  return Math.floor(mo / 12) + "y ago"
}

function relativeTime(value) {
  return _rel(value)
}

function categories(entries) {
  var seen = ({})
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var c = entries[i].category
    if (c && !seen[c]) { seen[c] = true; out.push(c) }
  }
  out.sort(function (a, b) { return a.localeCompare(b) })
  return out
}

function _fieldScore(value, q) {
  if (!value) return -1
  var v = value.toLowerCase()
  if (v === q) return 1000
  if (v.indexOf(q) === 0) return 800 - v.length
  var idx = v.indexOf(q)
  if (idx !== -1) return 500 - idx  - v.length * 0.01
  return -1
}

function matchScore(entry, query) {
  if (!query) return 0
  var q = query.toLowerCase()
  var best = _fieldScore(entry.service, q) * 1.5
  var u = _fieldScore(entry.username, q)
  if (u > best) best = u * 1.2
  var url = _fieldScore(entry.url, q)
  if (url > best) best = url
  var cat = _fieldScore(entry.category, q)
  if (cat > best) best = cat * 0.9
  var notes = _fieldScore(entry.notes, q)
  if (notes > best) best = notes * 0.6
  return best
}

function filter(entries, query, sortMode) {
  var list = entries || []
  var q = str(query).trim()
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var score = matchScore(e, q)
    if (q && score < 0) continue
    scored.push({ e: e, score: score })
  }
  scored.sort(function (a, b) {
    if (q && b.score !== a.score) return b.score - a.score
    if (sortMode === "alpha") return a.e.service.localeCompare(b.e.service)
    var at = Date.parse(a.e.lastAccessed) || 0
    var bt = Date.parse(b.e.lastAccessed) || 0
    if (bt !== at) return bt - at
    return a.e.service.localeCompare(b.e.service)
  })
  var out = []
  for (var j = 0; j < scored.length; j++) out.push(scored[j].e)
  return out
}

function shortError(raw) {
  var t = str(raw)
  t = t.replace(/\x1b\[[0-9;]*m/g, "")
  t = t.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, "")
  var lines = t.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line) return line.slice(0, 240)
  }
  return ""
}
