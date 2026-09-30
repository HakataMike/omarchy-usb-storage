.pragma library

// Decimal units, matching how drive capacity is printed on the packaging.
function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

function parseDrives(raw) {
  try {
    var parsed = JSON.parse(String(raw || "").trim() || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (e) {
    return []
  }
}

function primaryPartition(drive) {
  var parts = drive && drive.partitions ? drive.partitions : []
  for (var i = 0; i < parts.length; i++)
    if (parts[i].mountpoint) return parts[i]
  return parts.length > 0 ? parts[0] : null
}

function driveTitle(drive) {
  var part = primaryPartition(drive)
  if (part && part.label) return part.label
  return formatBytes(drive.size) + " USB Drive"
}

// Hardware identity from both the USB descriptor and the SCSI inquiry
// strings, skipping blanks and repeats so cheap sticks don't read "USB USB".
function driveSubtitle(drive) {
  var usb = drive.usb || {}
  var seen = {}
  var words = []
  var candidates = [usb.manufacturer, usb.product, drive.vendor, drive.model]
  for (var i = 0; i < candidates.length; i++) {
    var w = String(candidates[i] || "").trim()
    if (!w || seen[w.toLowerCase()]) continue
    seen[w.toLowerCase()] = true
    words.push(w)
  }
  return words.join(" ")
}

function speedLabel(mbps) {
  switch (Number(mbps)) {
  case 1.5: return "USB 1.0 · 1.5 Mbps"
  case 12: return "USB 1.1 · 12 Mbps"
  case 480: return "USB 2.0 · 480 Mbps"
  case 5000: return "USB 3.2 Gen 1 · 5 Gbps"
  case 10000: return "USB 3.2 Gen 2 · 10 Gbps"
  case 20000: return "USB 3.2 Gen 2x2 · 20 Gbps"
  default: return mbps ? mbps + " Mbps" : "Unknown"
  }
}

// A USB 3 device that negotiated a USB 2 link is almost always a half-seated
// plug, a USB 2 hub, or a USB 2 extension cable.
function runningSlow(drive) {
  var usb = drive.usb || {}
  return parseFloat(usb.version) >= 3 && Number(usb.speed) > 0 && Number(usb.speed) < 5000
}

function fsLabel(fstype) {
  var names = { vfat: "FAT32", exfat: "exFAT", ntfs: "NTFS", ext4: "ext4", btrfs: "Btrfs", xfs: "XFS", iso9660: "ISO 9660" }
  return names[fstype] || String(fstype || "—")
}

function usedFraction(part) {
  if (!part || !part.size || part.used === null || part.used === undefined) return 0
  return Math.max(0, Math.min(1, Number(part.used) / Number(part.size)))
}
