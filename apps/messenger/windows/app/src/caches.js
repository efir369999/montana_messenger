/** THE PICTURES KEPT IN MEMORY (iOS MontanaCaches): every map of pictures the window keeps -- a letter's file, a face, a wall's
 *  file -- is named here, and «Clear» in Data and Storage lets go of every one no page shows now; a picture standing on the screen
 *  stays until it leaves, and comes back from the store when it is wanted again. */
const CACHES = new Set();

/** A map of pictures (key -> object URL) the window keeps while it lives. */
export function keptPictures(map) {
  CACHES.add(map);
  return map;
}

/** Every kept picture no page shows now, let go: how many. */
export function dropPictures() {
  const shown = new Set([...document.querySelectorAll("[src^='blob:']")].map((e) => e.getAttribute("src")));
  let n = 0;
  for (const map of CACHES) {
    for (const [k, u] of [...map]) {
      if (typeof u !== "string" || !u.startsWith("blob:") || shown.has(u)) continue;
      URL.revokeObjectURL(u);
      map.delete(k);
      n++;
    }
  }
  return n;
}
