## edaphos gold-standard annotation reviewer (v1.8.1)
##
## Launched via `edaphos::llm_annotation_launch()`, which sets these
## options before calling `shiny::runApp()`:
##   - edaphos.annotation.draft     path to draft JSONL (read)
##   - edaphos.annotation.output    path to reviewed JSONL (write)
##   - edaphos.annotation.keyboard  logical, enable shortcuts
##
## The app is resume-safe: every "Save & Next" writes the entire
## reviewed JSONL to disk, so crashes / accidental browser closes
## never lose more than one abstract of work.

suppressPackageStartupMessages({
  library(shiny)
  library(DT)
  library(bslib)
  library(shinyjs)
  library(jsonlite)
})

# ─────────────────────────────────────────────────────────────────────────────
# Setup: read paths + inputs from options
# ─────────────────────────────────────────────────────────────────────────────
.draft_path    <- getOption("edaphos.annotation.draft")
.output_path   <- getOption("edaphos.annotation.output",  .draft_path)
.keyboard_on   <- getOption("edaphos.annotation.keyboard", TRUE)

if (is.null(.draft_path) || !file.exists(.draft_path)) {
  stop("No draft JSONL configured. Call edaphos::llm_annotation_launch().",
        call. = FALSE)
}

VOCAB <- c(
  "precipitation", "mean_annual_precipitation",
  "temperature",   "mean_annual_temperature",
  "elevation", "slope", "aspect", "twi",
  "clay", "sand", "silt", "bulk_density",
  "soc", "ph", "cec", "parent_material",
  "vegetation", "ndvi", "land_use", "fire_frequency",
  "erosion", "weathering"
)
POLARITY <- c("+", "-")
STATUS   <- c("draft", "accepted", "edited", "added", "rejected")

# Read JSONL
read_records <- function(path) {
  lns <- readLines(path, warn = FALSE)
  lns <- lns[nzchar(trimws(lns))]
  lapply(lns, jsonlite::fromJSON, simplifyVector = TRUE)
}
write_records <- function(records, path) {
  con <- file(path, "w"); on.exit(close(con))
  for (r in records) writeLines(
    jsonlite::toJSON(r, dataframe = "rows",
                      auto_unbox = TRUE, null = "null"), con)
}

# Coerce claims into a consistent data frame
coerce_claims <- function(cl) {
  if (is.null(cl) || length(cl) == 0L) {
    return(data.frame(cause = character(), effect = character(),
                       polarity = character(), confidence = numeric(),
                       rationale = character(), status = character(),
                       stringsAsFactors = FALSE))
  }
  if (is.data.frame(cl)) {
    df <- cl
  } else if (is.list(cl)) {
    df <- do.call(rbind, lapply(cl, as.data.frame,
                                  stringsAsFactors = FALSE))
  } else {
    return(data.frame(cause = character(), effect = character(),
                       polarity = character(), confidence = numeric(),
                       rationale = character(), status = character(),
                       stringsAsFactors = FALSE))
  }
  for (col in c("cause", "effect", "polarity", "rationale", "status"))
    if (!col %in% names(df)) df[[col]] <- NA_character_
  if (!"confidence" %in% names(df)) df$confidence <- 0.7
  df$status[is.na(df$status) | df$status == ""] <- "draft"
  df[, c("cause", "effect", "polarity", "confidence",
          "rationale", "status")]
}

# ─────────────────────────────────────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────────────────────────────────────

css_rules <- "
  .claim-row            { border-bottom: 1px solid #eaeaea; padding: 8px 4px; }
  .claim-row.accepted   { background: #e6f7ea; }
  .claim-row.rejected   { background: #fdeaea; opacity: 0.6; }
  .claim-row.edited     { background: #e6f0ff; }
  .claim-row.added      { background: #fff4d6; }
  .claim-row.draft      { background: #fafafa; }
  .claim-buttons .btn   { margin-right: 4px; margin-bottom: 4px; }
  .progress-line        { font-size: 1.0em; margin-top: 4px; color: #444; }
  .abstract-box         { background: #f7f7f7; border-left: 4px solid #2ECC71;
                          padding: 10px 14px; font-size: 0.98em;
                          line-height: 1.45; }
  .meta-line            { color: #888; font-size: 0.88em; }
  .kbd                  { background: #eee; border: 1px solid #ccc;
                          border-radius: 3px; padding: 1px 5px;
                          font-family: monospace; font-size: 0.88em; }
"

ui <- bslib::page_navbar(
  title = "edaphos · gold-standard annotation (v1.8.1)",
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
  header = tagList(
    shinyjs::useShinyjs(),
    tags$style(HTML(css_rules))
  ),

  nav_panel(
    title = "Review",
    fluidRow(
      column(9,
        div(class = "progress-line",
             textOutput("progress_text", inline = TRUE)),
        tags$hr(),
        h4(textOutput("abstract_title")),
        div(class = "meta-line", textOutput("abstract_meta")),
        div(class = "abstract-box",
             textOutput("abstract_text")),
        tags$hr(),
        h5("Draft claims — accept, edit, or reject:"),
        uiOutput("claims_ui"),
        tags$hr(),
        fluidRow(
          column(4,
            actionButton("btn_add", "+ Add missed claim",
                          class = "btn-outline-primary")
          ),
          column(8, align = "right",
            actionButton("btn_prev", "← Previous",
                          class = "btn-outline-secondary"),
            actionButton("btn_accept_all", "Accept all",
                          class = "btn-success"),
            actionButton("btn_save_next", "Save & Next →",
                          class = "btn-primary")
          )
        )
      ),
      column(3,
        h5("Session"),
        textOutput("n_abstracts_done"),
        textOutput("n_claims_accepted"),
        tags$hr(),
        h6("Keyboard shortcuts"),
        HTML(paste0(
          '<p><span class="kbd">n</span> Save & Next  ',
          '<span class="kbd">p</span> Previous</p>',
          '<p><span class="kbd">a</span> Accept all  ',
          '<span class="kbd">+</span> Add claim</p>',
          '<p><span class="kbd">1</span>…<span class="kbd">9</span> Toggle accept on claim</p>'
        )),
        tags$hr(),
        h6("Output"),
        p(tags$code(.output_path),
           style = "font-size: 0.85em; word-break: break-all;")
      )
    )
  ),
  nav_panel(
    title = "Stats",
    fluidRow(
      column(12,
        h4("Progress summary"),
        DT::dataTableOutput("progress_table"),
        h4("Vocabulary coverage"),
        plotOutput("vocab_plot", height = "280px")
      )
    )
  ),
  nav_panel(
    title = "Export",
    fluidRow(
      column(12,
        h4("Final gold-standard"),
        p("Click below to validate and write the final gold-standard",
          "JSONL (draft / rejected claims removed)."),
        actionButton("btn_export", "Validate & export",
                      class = "btn-primary btn-lg"),
        tags$hr(),
        verbatimTextOutput("export_log")
      )
    )
  )
)

# ─────────────────────────────────────────────────────────────────────────────
# Server
# ─────────────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Reactive state ─────────────────────────────────────────────────────
  rv <- reactiveValues(
    records = NULL,   # full list of records with (possibly reviewed) claims
    idx     = 1L,     # current abstract index (1-based)
    current_claims = NULL  # data.frame for the current abstract (editable)
  )

  # Initial load — use output JSONL if it exists (resume), else draft
  isolate({
    path0 <- if (file.exists(.output_path)) .output_path else .draft_path
    rv$records <- read_records(path0)
    # Find first abstract with any "draft" claim (resume point)
    first_draft <- integer(0)
    for (i in seq_along(rv$records)) {
      cl <- coerce_claims(rv$records[[i]]$claims)
      if (any(cl$status == "draft"))
        first_draft <- c(first_draft, i)
    }
    rv$idx <- if (length(first_draft) > 0L) first_draft[1] else 1L
    rv$current_claims <- coerce_claims(rv$records[[rv$idx]]$claims)
  })

  # ── Navigation + load current abstract ──────────────────────────────────
  observe({
    i <- rv$idx
    rec <- rv$records[[i]]
    rv$current_claims <- coerce_claims(rec$claims)
  })

  # ── Render abstract header ──────────────────────────────────────────────
  output$abstract_title <- renderText({
    rec <- rv$records[[rv$idx]]
    paste0(rec$abstract_id, " — ", rec$title %||% "(no title)")
  })
  output$abstract_meta <- renderText({
    rec <- rv$records[[rv$idx]]
    parts <- c(
      if (!is.null(rec$year))  paste("Year:", rec$year) else NULL,
      if (!is.null(rec$topic)) paste("Topic:", rec$topic) else NULL,
      if (!is.null(rec$backend) && !is.null(rec$model))
        sprintf("Drafted by: %s / %s", rec$backend, rec$model) else NULL
    )
    paste(parts, collapse = " · ")
  })
  output$abstract_text <- renderText({
    rv$records[[rv$idx]]$abstract_text %||% "(no text)"
  })
  output$progress_text <- renderText({
    total <- length(rv$records)
    sprintf("Abstract %d of %d  —  %d claims total in current file",
             rv$idx, total,
             sum(vapply(rv$records, function(r)
               nrow(coerce_claims(r$claims)), integer(1L))))
  })

  # ── Render per-claim editor rows ────────────────────────────────────────
  output$claims_ui <- renderUI({
    cl <- rv$current_claims
    if (nrow(cl) == 0L)
      return(div(class = "meta-line",
                  em("No draft claims — add any claims the authors make.")))
    tagList(lapply(seq_len(nrow(cl)), function(i) {
      row_class <- paste("claim-row", cl$status[i])
      div(class = row_class,
        fluidRow(
          column(1, strong(i)),
          column(3, selectInput(
            paste0("cause_", i),
            label = NULL,
            choices = sort(unique(c(VOCAB, cl$cause[i]))),
            selected = cl$cause[i],
            width = "100%"
          )),
          column(3, selectInput(
            paste0("effect_", i),
            label = NULL,
            choices = sort(unique(c(VOCAB, cl$effect[i]))),
            selected = cl$effect[i],
            width = "100%"
          )),
          column(1, selectInput(
            paste0("polarity_", i),
            label = NULL,
            choices = POLARITY,
            selected = cl$polarity[i] %||% "+",
            width = "100%"
          )),
          column(2, sliderInput(
            paste0("confidence_", i),
            label = NULL,
            min = 0, max = 1, step = 0.05,
            value = as.numeric(cl$confidence[i] %||% 0.7),
            width = "100%"
          )),
          column(2, div(class = "claim-buttons",
            actionButton(paste0("btn_accept_", i),
                          label = "✓", class = "btn-success btn-sm"),
            actionButton(paste0("btn_reject_", i),
                          label = "✗", class = "btn-danger btn-sm")
          ))
        ),
        fluidRow(
          column(1),
          column(10, textInput(
            paste0("rationale_", i), label = NULL,
            value = cl$rationale[i] %||% "",
            placeholder = "Short rationale / quote from the abstract",
            width = "100%"
          )),
          column(1, span(class = "meta-line", cl$status[i]))
        )
      )
    }))
  })

  # ── Harvest UI inputs back into rv$current_claims ───────────────────────
  harvest_current <- function() {
    cl <- rv$current_claims
    if (nrow(cl) == 0L) return(cl)
    for (i in seq_len(nrow(cl))) {
      cl$cause[i]      <- input[[paste0("cause_", i)]]      %||% cl$cause[i]
      cl$effect[i]     <- input[[paste0("effect_", i)]]     %||% cl$effect[i]
      cl$polarity[i]   <- input[[paste0("polarity_", i)]]   %||% cl$polarity[i]
      cl$confidence[i] <- as.numeric(input[[paste0("confidence_", i)]] %||% cl$confidence[i])
      cl$rationale[i]  <- input[[paste0("rationale_", i)]]  %||% cl$rationale[i]
      # Promote to "edited" if still "draft" and content changed? Skip for now.
    }
    cl
  }

  # ── Per-claim accept/reject buttons (dynamic observers) ─────────────────
  observe({
    cl <- rv$current_claims
    for (i in seq_len(nrow(cl))) {
      local({
        my_i <- i
        observeEvent(input[[paste0("btn_accept_", my_i)]], {
          rv$current_claims <- harvest_current()
          rv$current_claims$status[my_i] <- "accepted"
        }, ignoreInit = TRUE)
        observeEvent(input[[paste0("btn_reject_", my_i)]], {
          rv$current_claims <- harvest_current()
          rv$current_claims$status[my_i] <- "rejected"
        }, ignoreInit = TRUE)
      })
    }
  })

  # ── "+ Add claim" ───────────────────────────────────────────────────────
  observeEvent(input$btn_add, {
    rv$current_claims <- harvest_current()
    rv$current_claims <- rbind(rv$current_claims, data.frame(
      cause = VOCAB[1], effect = VOCAB[2], polarity = "+",
      confidence = 0.75, rationale = "",
      status = "added", stringsAsFactors = FALSE
    ))
  })

  # ── Save & Next ─────────────────────────────────────────────────────────
  save_current_to_records <- function() {
    cl <- harvest_current()
    rv$records[[rv$idx]]$claims <- cl
    write_records(rv$records, .output_path)
  }

  observeEvent(input$btn_save_next, {
    save_current_to_records()
    rv$idx <- min(rv$idx + 1L, length(rv$records))
    showNotification("Saved ✓", duration = 1.5, type = "message")
  })
  observeEvent(input$btn_prev, {
    save_current_to_records()
    rv$idx <- max(rv$idx - 1L, 1L)
  })
  observeEvent(input$btn_accept_all, {
    rv$current_claims <- harvest_current()
    rv$current_claims$status[rv$current_claims$status == "draft"] <- "accepted"
    save_current_to_records()
    rv$idx <- min(rv$idx + 1L, length(rv$records))
    showNotification("Accepted all ✓", duration = 1.5, type = "message")
  })

  # ── Sidebar session stats ───────────────────────────────────────────────
  output$n_abstracts_done <- renderText({
    done <- sum(vapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      nrow(cl) == 0L || !any(cl$status == "draft")
    }, logical(1L)))
    sprintf("Abstracts reviewed: %d / %d", done, length(rv$records))
  })
  output$n_claims_accepted <- renderText({
    acc <- sum(vapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      sum(cl$status %in% c("accepted", "edited", "added"))
    }, integer(1L)))
    sprintf("Claims accepted: %d", acc)
  })

  # ── Stats tab ───────────────────────────────────────────────────────────
  output$progress_table <- DT::renderDataTable({
    df <- do.call(rbind, lapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      data.frame(
        abstract_id = r$abstract_id,
        n_draft     = sum(cl$status == "draft"),
        n_accepted  = sum(cl$status == "accepted"),
        n_edited    = sum(cl$status == "edited"),
        n_added     = sum(cl$status == "added"),
        n_rejected  = sum(cl$status == "rejected"),
        stringsAsFactors = FALSE
      )
    }))
    DT::datatable(df, options = list(pageLength = 15, dom = "tp"),
                   rownames = FALSE)
  })
  output$vocab_plot <- renderPlot({
    all_claims <- do.call(rbind, lapply(rv$records,
                                          function(r) coerce_claims(r$claims)))
    acc <- all_claims[all_claims$status %in%
                         c("accepted", "edited", "added"), ]
    if (nrow(acc) == 0L) {
      plot.new(); title("No accepted claims yet"); return()
    }
    vcoverage <- table(c(acc$cause, acc$effect))
    par(mar = c(4, 8, 2, 1))
    barplot(sort(vcoverage), horiz = TRUE, las = 1, col = "#2ECC71",
             main = "Canonical vocabulary coverage (accepted claims)")
  })

  # ── Export tab ──────────────────────────────────────────────────────────
  observeEvent(input$btn_export, {
    save_current_to_records()
    out_final <- sub("\\.jsonl$", "_final.jsonl", .output_path)
    # Mirror the logic in llm_annotation_export()
    records_out <- lapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      keep <- !(cl$status %in% c("rejected", "draft"))
      cl <- cl[keep, , drop = FALSE]
      cl$status <- NULL
      r$claims <- cl
      r
    })
    write_records(records_out, out_final)

    # Validate
    n_claims_total <- sum(vapply(records_out, function(x) nrow(x$claims),
                                  integer(1L)))
    n_vocab_ok <- sum(vapply(records_out, function(x) {
      if (nrow(x$claims) == 0L) return(0L)
      sum(x$claims$cause %in% VOCAB & x$claims$effect %in% VOCAB)
    }, integer(1L)))

    output$export_log <- renderText(paste(
      sprintf("=== Exported to %s ===", out_final),
      sprintf("  Abstracts : %d", length(records_out)),
      sprintf("  Claims    : %d", n_claims_total),
      sprintf("  In-vocabulary : %d / %d",
              n_vocab_ok, n_claims_total),
      "\nReady for benchmark ingestion:",
      sprintf("  Rscript data-raw/llm_benchmark_run.R  (point GOLD_PATH to the file above)"),
      sep = "\n"
    ))
    showNotification("Exported ✓", duration = 3, type = "message")
  })

  # ── Keyboard shortcuts ──────────────────────────────────────────────────
  if (isTRUE(.keyboard_on)) {
    shinyjs::runjs("
      $(document).on('keydown', function(e) {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA'
            || e.target.tagName === 'SELECT') return;
        if (e.key === 'n')  $('#btn_save_next').click();
        if (e.key === 'p')  $('#btn_prev').click();
        if (e.key === 'a')  $('#btn_accept_all').click();
        if (e.key === '+')  $('#btn_add').click();
        if (/^[1-9]$/.test(e.key)) $('#btn_accept_' + e.key).click();
      });
    ")
  }
}

shinyApp(ui, server)
