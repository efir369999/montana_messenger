/** A DOUBLE PRESS STAYS ON THE LAYER IT BEGAN ON (the review of 25.10.2026; iOS: a tap lands on what stood under the finger, and
 *  UIKit takes no touch while a page is pushed). The first press of a double click opens a layer -- a page, a sheet, an alert, a
 *  menu, the drawer -- or takes one away, and the second, a moment later at the same point, would press whatever the next layer
 *  wears there: the slot's page's cross under the slot, the content filter under «Privacy», the picture cache's «Clear» under
 *  «Data and Storage», the list's cross under «Back». A press that Windows counts as the second (or third) of a double click
 *  (`detail` over 1) is no press at all when it lands on another layer than the first press found. Keys and the reader's presses
 *  (UI Automation's Invoke and Toggle) are clicks of no count (`detail` 0): they are never stopped and never taken for a first
 *  press. The mouse's other buttons are left alone (leave.js hears its back button at every press). A Windows guard: the cursor's
 *  double click has no iOS counterpart. */
const LAYER = '.page-over, .crop, .drawer, .menu-shade, .sheet-shade, .alert-shade, [role="dialog"], [role="alertdialog"], [role="menu"]';
const layerOf = (t) => (t instanceof Element ? t.closest(LAYER) : null);   // null: the app itself
let first = null;   // the layer the last single press of the primary button found

function press(e) {
  if (e.button !== 0 || e.detail < 1) return;
  if (e.detail === 1) {
    // the press down and its click both (a page that keeps the press down from the mouse still has its click)
    if (e.type !== "dblclick") first = layerOf(e.target);
    return;
  }
  if (layerOf(e.target) === first) return;
  e.preventDefault();
  e.stopImmediatePropagation();
}

if (typeof window !== "undefined") {
  for (const kind of ["mousedown", "click", "dblclick"]) window.addEventListener(kind, press, true);
}
