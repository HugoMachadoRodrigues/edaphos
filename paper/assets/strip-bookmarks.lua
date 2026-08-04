-- Remove the anchor bookmarks pandoc emits for every heading/figure/table.
-- PLOS wants a clean manuscript body; the bookmarks show up as stray fields
-- in Word and serve no purpose in a submitted document.
function Header(el) el.identifier = ""; el.attributes = {}; return el end
function Div(el) if el.identifier and el.identifier ~= "" then el.identifier = "" end; return el end
function Span(el) if el.identifier and el.identifier ~= "" then el.identifier = "" end; return el end
function Table(el) el.identifier = ""; return el end
function Figure(el) el.identifier = ""; return el end
