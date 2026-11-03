// Kopie aus forever-routen/scripts/lib/zip-reader.mjs (Stand 2026-11-03, unveraendert bis auf diese Zeile und den Verweis unten).
// Eigenstaendig kopiert, damit dieses Projekt nicht von forever-routen abhaengt. Genutzt von scripts/fetch-questiedb-release.mjs.
// Minimaler, grenzgepruefter Zip-Leser (Delta Datensammler, E2a): liest aus einem Zip-Archiv im Speicher genau die Eintraege mit den
// angefragten exakten Namen und entpackt sie in den Speicher. Genutzt von scripts/fetch-questiedb-release.mjs.
//
// Format: PKWARE APPNOTE 6.3.x (End of Central Directory, Central Directory, Local File Header). Unterstuetzt nur das, was ein
// GitHub-Release-Zip braucht: eine Platte, kein Zip64, keine Verschluesselung, Methode 0 (stored) und 8 (deflate).
//
// Sicherheit (das Archiv ist eine Fremd-Datei aus dem Netz):
//  - Nichts wird auf Platte geschrieben; kein Name aus dem Archiv wird je als Dateipfad benutzt. Gesucht wird nur per exaktem
//    Bytevergleich mit den vom Aufrufer festgelegten Namen (Zip-Slip-Namen wie "../x" koennen so nie "treffen").
//  - Jeder Lesezugriff ist gegen die Puffergrenzen geprueft (nie Out-of-bounds); Zaehler sind gedeckelt (keine Endlosschleife).
//  - Zip-Bombe: Limits fuer komprimierte und entpackte Groesse je Eintrag und gesamt; inflateRaw laeuft mit maxOutputLength =
//    angegebene Groesse, ein "luegender" Eintrag bricht also beim ersten Byte zu viel ab. Danach Laenge und CRC-32 gegengeprueft.
//  - Unklare Lage (doppelter Name, Name in Kopf und Verzeichnis verschieden, Daten ueberlappen das Verzeichnis) -> Abbruch.
//  - Jede Abweichung wirft ZipError mit deutscher Meldung; es gibt nie ein Teilergebnis.

import { crc32, inflateRawSync } from "node:zlib";

// ---------------------------------------------------------------- Konstanten

export const ZIP_LIMITS = Object.freeze({
  /** Groesstes Archiv, das ueberhaupt angesehen wird. */
  maxArchiveBytes: 64 * 1024 * 1024,
  /** Hoechste Zahl Eintraege im zentralen Verzeichnis. */
  maxEntries: 10_000,
  /** Groesste komprimierte Groesse eines angefragten Eintrags. */
  maxCompressedBytes: 32 * 1024 * 1024,
  /** Groesste entpackte Groesse eines angefragten Eintrags. */
  maxUncompressedBytes: 32 * 1024 * 1024,
  /** Groesste entpackte Gesamtgroesse aller angefragten Eintraege. */
  maxTotalUncompressedBytes: 64 * 1024 * 1024,
});

const SIG_EOCD = 0x06054b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_LOCAL = 0x04034b50;
const EOCD_BYTES = 22;
const CENTRAL_BYTES = 46;
const LOCAL_BYTES = 30;
const MAX_COMMENT = 0xffff;
const FLAG_ENCRYPTED = 0x0001;
const FLAG_STRONG_ENCRYPTION = 0x0040;
const METHOD_STORED = 0;
const METHOD_DEFLATE = 8;
/** Erlaubte Namen der Anfrage: ASCII ohne Steuerzeichen, kein fuehrender Schraegstrich, kein "..", hoechstens 255 Zeichen. */
const WANTED_NAME_RE = /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[\x21-\x7e](?:[\x20-\x7e]{0,254})$/;

// ---------------------------------------------------------------- Fehler

/** Fehler des Zip-Lesers (deutsche Meldung, ohne Archivinhalte ausser festen Kennwerten). */
export class ZipError extends Error {
  constructor(message) {
    super(message);
    this.name = "ZipError";
  }
}

// ---------------------------------------------------------------- Hilfen

/** Grenzgepruefter Zugriff; wirft ZipError statt still Unsinn zu lesen. */
function reader(buf) {
  const check = (o, n, what) => {
    if (!Number.isSafeInteger(o) || o < 0 || n < 0 || o + n > buf.length) throw new ZipError(`Zip-Archiv beschaedigt oder abgeschnitten (${what} ausserhalb der Datei).`);
  };
  return {
    u16(o, what) {
      check(o, 2, what);
      return buf.readUInt16LE(o);
    },
    u32(o, what) {
      check(o, 4, what);
      return buf.readUInt32LE(o);
    },
    slice(o, n, what) {
      check(o, n, what);
      return buf.subarray(o, o + n);
    },
  };
}

/** Sucht das End-of-Central-Directory von hinten (hoechstens 22 + 65535 Byte Kommentar). */
function findEocd(buf, r) {
  if (buf.length < EOCD_BYTES) throw new ZipError("Kein Zip-Archiv (Datei zu kurz).");
  const stop = Math.max(0, buf.length - EOCD_BYTES - MAX_COMMENT);
  for (let p = buf.length - EOCD_BYTES; p >= stop; p--) {
    if (buf[p] !== 0x50 || buf.readUInt32LE(p) !== SIG_EOCD) continue;
    const commentLen = r.u16(p + 20, "Archiv-Kommentar");
    // Der Kommentar muss genau bis zum Dateiende reichen, sonst ist das ein zufaelliges Signatur-Byte-Muster (weitersuchen).
    if (p + EOCD_BYTES + commentLen === buf.length) return p;
  }
  throw new ZipError("Kein Zip-Archiv oder abgeschnitten (Ende des Inhaltsverzeichnisses nicht gefunden).");
}

/** Prueft die angefragten Namen (vom Aufrufer, nicht aus dem Archiv) und liefert sie als Set. */
function checkWanted(names) {
  if (!Array.isArray(names) || names.length === 0 || names.length > 16) throw new ZipError("Ungueltige Anfrage: 1 bis 16 Eintragsnamen erwartet.");
  const set = new Set();
  for (const n of names) {
    if (typeof n !== "string" || !WANTED_NAME_RE.test(n)) throw new ZipError("Ungueltige Anfrage: Eintragsname nicht erlaubt.");
    set.add(n);
  }
  return set;
}

/** Name eines Eintrags fuer den exakten Vergleich (latin1 = Byte fuer Byte; angefragte Namen sind reines ASCII). */
const nameOf = (bytes) => bytes.toString("latin1");

// ---------------------------------------------------------------- Inhaltsverzeichnis

/**
 * Liest das zentrale Verzeichnis. Liefert [{ name, method, flags, crc, compressedSize, uncompressedSize, localOffset, modified }].
 * Nur fuer die Auswertung/Meldung; Namen sind Daten und werden nie als Pfad verwendet.
 */
export function listZipEntries(buf, limits = ZIP_LIMITS) {
  if (!Buffer.isBuffer(buf)) throw new ZipError("Kein Zip-Archiv (keine Bytes).");
  if (buf.length > limits.maxArchiveBytes) throw new ZipError(`Zip-Archiv zu gross (${buf.length} Byte, erlaubt bis ${limits.maxArchiveBytes}).`);
  const r = reader(buf);
  const eocd = findEocd(buf, r);
  const disk = r.u16(eocd + 4, "Kopf");
  const cdDisk = r.u16(eocd + 6, "Kopf");
  const entriesOnDisk = r.u16(eocd + 8, "Kopf");
  const entries = r.u16(eocd + 10, "Kopf");
  const cdSize = r.u32(eocd + 12, "Kopf");
  const cdOffset = r.u32(eocd + 16, "Kopf");
  if (entries === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) throw new ZipError("Zip64-Archive werden nicht unterstuetzt.");
  if (disk !== 0 || cdDisk !== 0 || entriesOnDisk !== entries) throw new ZipError("Mehrteilige Zip-Archive werden nicht unterstuetzt.");
  if (entries > limits.maxEntries) throw new ZipError(`Zip-Archiv hat zu viele Eintraege (${entries}, erlaubt bis ${limits.maxEntries}).`);
  if (cdOffset + cdSize > eocd) throw new ZipError("Zip-Archiv beschaedigt (Inhaltsverzeichnis ausserhalb der Datei).");

  const out = [];
  let p = cdOffset;
  const cdEnd = cdOffset + cdSize;
  for (let i = 0; i < entries; i++) {
    if (p + CENTRAL_BYTES > cdEnd) throw new ZipError("Zip-Archiv beschaedigt (Inhaltsverzeichnis kuerzer als angegeben).");
    if (r.u32(p, "Verzeichniseintrag") !== SIG_CENTRAL) throw new ZipError("Zip-Archiv beschaedigt (Verzeichniseintrag ohne Signatur).");
    const flags = r.u16(p + 8, "Verzeichniseintrag");
    const method = r.u16(p + 10, "Verzeichniseintrag");
    const time = r.u16(p + 12, "Verzeichniseintrag");
    const date = r.u16(p + 14, "Verzeichniseintrag");
    const crc = r.u32(p + 16, "Verzeichniseintrag");
    const compressedSize = r.u32(p + 20, "Verzeichniseintrag");
    const uncompressedSize = r.u32(p + 24, "Verzeichniseintrag");
    const nameLen = r.u16(p + 28, "Verzeichniseintrag");
    const extraLen = r.u16(p + 30, "Verzeichniseintrag");
    const commentLen = r.u16(p + 32, "Verzeichniseintrag");
    const diskStart = r.u16(p + 34, "Verzeichniseintrag");
    const localOffset = r.u32(p + 42, "Verzeichniseintrag");
    const next = p + CENTRAL_BYTES + nameLen + extraLen + commentLen;
    if (next > cdEnd) throw new ZipError("Zip-Archiv beschaedigt (Verzeichniseintrag laenger als das Verzeichnis).");
    if (diskStart !== 0) throw new ZipError("Mehrteilige Zip-Archive werden nicht unterstuetzt.");
    const name = nameOf(r.slice(p + CENTRAL_BYTES, nameLen, "Eintragsname"));
    out.push({ name, method, flags, crc, compressedSize, uncompressedSize, localOffset, modified: dosDateTime(date, time) });
    p = next;
  }
  if (p !== cdEnd) throw new ZipError("Zip-Archiv beschaedigt (Inhaltsverzeichnis laenger als seine Eintraege).");
  return out;
}

/** DOS-Datum/Zeit (Ortszeit des Packers, ohne Zeitzone) -> "JJJJ-MM-TTThh:mm:ss"; "" bei unmoeglichen Werten. */
export function dosDateTime(date, time) {
  const y = 1980 + (date >> 9);
  const mo = (date >> 5) & 0x0f;
  const d = date & 0x1f;
  const h = time >> 11;
  const mi = (time >> 5) & 0x3f;
  const s = (time & 0x1f) * 2;
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 59) return "";
  const p2 = (n) => String(n).padStart(2, "0");
  return `${y}-${p2(mo)}-${p2(d)}T${p2(h)}:${p2(mi)}:${p2(s)}`;
}

// ---------------------------------------------------------------- Entpacken

/**
 * Entpackt genau die Eintraege mit den angefragten exakten Namen in den Speicher.
 * Liefert Map<name, { data: Buffer, modified, compressedSize, uncompressedSize, crc }>. Fehlt ein angefragter Eintrag, ist er
 * doppelt vorhanden oder verletzt er eine Grenze, wirft die Funktion ZipError (kein Teilergebnis).
 */
export function readZipEntries(buf, names, limits = ZIP_LIMITS) {
  const wanted = checkWanted(names);
  const entries = listZipEntries(buf, limits);
  const r = reader(buf);
  const found = new Map();
  for (const e of entries) {
    if (!wanted.has(e.name)) continue;
    if (found.has(e.name)) throw new ZipError(`Zip-Archiv enthaelt den Eintrag "${e.name}" mehrfach; abgelehnt.`);
    found.set(e.name, e);
  }
  for (const n of wanted) if (!found.has(n)) throw new ZipError(`Eintrag "${n}" fehlt im Zip-Archiv.`);

  // Verzeichnisanfang = Ende des Datenbereichs (fuer die Ueberlappungspruefung)
  const eocd = findEocd(buf, r);
  const cdOffset = r.u32(eocd + 16, "Kopf");
  const out = new Map();
  let total = 0;
  for (const [name, e] of found) {
    if (e.flags & (FLAG_ENCRYPTED | FLAG_STRONG_ENCRYPTION)) throw new ZipError(`Eintrag "${name}" ist verschluesselt; abgelehnt.`);
    if (e.method !== METHOD_STORED && e.method !== METHOD_DEFLATE) throw new ZipError(`Eintrag "${name}" nutzt Kompressionsmethode ${e.method}; erlaubt sind nur 0 (ohne) und 8 (Deflate).`);
    if (e.compressedSize > limits.maxCompressedBytes) throw new ZipError(`Eintrag "${name}" ist komprimiert zu gross (${e.compressedSize} Byte, erlaubt bis ${limits.maxCompressedBytes}).`);
    if (e.uncompressedSize > limits.maxUncompressedBytes) throw new ZipError(`Eintrag "${name}" ist entpackt zu gross (${e.uncompressedSize} Byte, erlaubt bis ${limits.maxUncompressedBytes}).`);
    total += e.uncompressedSize;
    if (total > limits.maxTotalUncompressedBytes) throw new ZipError(`Angefragte Eintraege sind entpackt zusammen zu gross (erlaubt bis ${limits.maxTotalUncompressedBytes} Byte).`);
    if (e.method === METHOD_STORED && e.compressedSize !== e.uncompressedSize) throw new ZipError(`Eintrag "${name}" ist widerspruechlich (ungepackt, aber Groessen verschieden).`);

    // Lokaler Kopf: Signatur, gleicher Name, Daten liegen vollstaendig vor dem Inhaltsverzeichnis
    const lo = e.localOffset;
    if (r.u32(lo, "lokaler Kopf") !== SIG_LOCAL) throw new ZipError(`Eintrag "${name}": lokaler Kopf ohne Signatur (beschaedigt).`);
    const localFlags = r.u16(lo + 6, "lokaler Kopf");
    const localMethod = r.u16(lo + 8, "lokaler Kopf");
    const localNameLen = r.u16(lo + 26, "lokaler Kopf");
    const localExtraLen = r.u16(lo + 28, "lokaler Kopf");
    if (localMethod !== e.method || (localFlags & FLAG_ENCRYPTED) !== (e.flags & FLAG_ENCRYPTED)) throw new ZipError(`Eintrag "${name}": lokaler Kopf passt nicht zum Inhaltsverzeichnis.`);
    if (nameOf(r.slice(lo + LOCAL_BYTES, localNameLen, "lokaler Name")) !== name) throw new ZipError(`Eintrag "${name}": Name im lokalen Kopf weicht ab; abgelehnt.`);
    const dataStart = lo + LOCAL_BYTES + localNameLen + localExtraLen;
    if (dataStart + e.compressedSize > cdOffset) throw new ZipError(`Eintrag "${name}": Daten reichen ins Inhaltsverzeichnis oder ueber das Dateiende (beschaedigt).`);
    const raw = r.slice(dataStart, e.compressedSize, "Eintragsdaten");

    let data;
    if (e.method === METHOD_STORED) data = Buffer.from(raw);
    else {
      try {
        // maxOutputLength = angegebene Groesse: eine Bombe, die mehr liefert als sie angibt, bricht hier ab
        data = inflateRawSync(raw, { maxOutputLength: Math.max(1, e.uncompressedSize) });
      } catch {
        throw new ZipError(`Eintrag "${name}" laesst sich nicht entpacken (beschaedigt oder groesser als angegeben).`);
      }
    }
    if (data.length !== e.uncompressedSize) throw new ZipError(`Eintrag "${name}": entpackte Groesse ${data.length} statt ${e.uncompressedSize} Byte (beschaedigt).`);
    if (crc32(data) >>> 0 !== e.crc >>> 0) throw new ZipError(`Eintrag "${name}": Pruefsumme (CRC-32) stimmt nicht (beschaedigt).`);
    out.set(name, { data, modified: e.modified, compressedSize: e.compressedSize, uncompressedSize: e.uncompressedSize, crc: e.crc >>> 0 });
  }
  return out;
}
