## edaphos gold-standard annotation reviewer (v1.8.2)
##
## Launched via `edaphos::llm_annotation_launch()`, which sets these
## options before calling `shiny::runApp()`:
##   - edaphos.annotation.draft     path to draft JSONL (read)
##   - edaphos.annotation.output    path to reviewed JSONL (write)
##   - edaphos.annotation.keyboard  logical, enable shortcuts
##
## v1.8.2 adds: dark mode toggle, DAG preview tab, Zenodo bundle tab.

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

`%||%` <- function(a, b) if (is.null(a)) b else a

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
  [data-bs-theme='dark'] .claim-row.accepted { background: #1f3d2a; }
  [data-bs-theme='dark'] .claim-row.rejected { background: #3d1f1f; opacity: 0.5; }
  [data-bs-theme='dark'] .claim-row.edited   { background: #1f2d3d; }
  [data-bs-theme='dark'] .claim-row.added    { background: #3d341f; }
  [data-bs-theme='dark'] .claim-row.draft    { background: #2a2a2a; }
  .claim-buttons .btn   { margin-right: 4px; margin-bottom: 4px; }
  .progress-line        { font-size: 1.0em; margin-top: 4px; color: #444; }
  [data-bs-theme='dark'] .progress-line { color: #bbb; }
  .abstract-box         { background: #f7f7f7; border-left: 4px solid #2ECC71;
                          padding: 10px 14px; font-size: 0.98em;
                          line-height: 1.45; }
  [data-bs-theme='dark'] .abstract-box { background: #1e1e1e; color: #eee; }
  .meta-line            { color: #888; font-size: 0.88em; }
  [data-bs-theme='dark'] .meta-line { color: #aaa; }
  .kbd                  { background: #eee; border: 1px solid #ccc;
                          border-radius: 3px; padding: 1px 5px;
                          font-family: monospace; font-size: 0.88em; }
  [data-bs-theme='dark'] .kbd { background: #333; border-color: #555; color: #eee; }
  .theme-toggle-wrap    { position: relative; top: 2px; padding: 0 10px; }
"

ui <- bslib::page_navbar(
  id    = "nav",
  title = "edaphos · gold-standard annotation (v1.8.2)",
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
  header = tagList(
    shinyjs::useShinyjs(),
    tags$style(HTML(css_rules))
  ),

  ## ── Tab 1: Review ─────────────────────────────────────────────────
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
        h6("Theme"),
        input_dark_mode(id = "dark_mode", mode = "light"),
        tags$hr(),
        h6("Output"),
        p(tags$code(.output_path),
           style = "font-size: 0.85em; word-break: break-all;")
      )
    )
  ),

  ## ── Tab 2: Stats ───────────────────────────────────────────────────
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

  ## ── Tab 3: DAG preview ─────────────────────────────────────────────
  nav_panel(
    title = "DAG",
    fluidRow(
      column(12,
        h4("Aggregated DAG (accepted claims only)"),
        p("Each arrow is an edge that appears in at least",
          tags$code("min_support"), "accepted claims (across abstracts).",
          "Polarity is shown by edge colour: ",
          tags$span(style = "color:#27AE60;", "green"),
          " = positive, ",
          tags$span(style = "color:#C0392B;", "red"),
          " = negative.  Edge width encodes the mean confidence."),
        fluidRow(
          column(3, sliderInput("min_support",
                                  "min_support (occurrences)",
                                  min = 1, max = 10, value = 1, step = 1)),
          column(3, checkboxInput("show_labels",
                                    "Show vocabulary labels", TRUE)),
          column(6, verbatimTextOutput("dag_summary"))
        ),
        tags$div(style = "overflow-x: auto; text-align: center;",
                   DiagrammeR::grVizOutput("dag_plot", height = "680px"))
      )
    )
  ),

  ## ── Tab 4: Export ──────────────────────────────────────────────────
  nav_panel(
    title = "Export",
    fluidRow(
      column(12,
        h4("Validate and write the cleaned gold-standard"),
        p("Drops rejected / untouched-draft claims, strips the internal",
          tags$code("status"), "field, and validates against the",
          "canonical vocabulary."),
        actionButton("btn_export", "Validate & export",
                      class = "btn-primary btn-lg"),
        tags$hr(),
        verbatimTextOutput("export_log")
      )
    )
  ),

  ## ── Tab 5: Zenodo package ─────────────────────────────────────────
  nav_panel(
    title = "Publish",
    fluidRow(
      column(12,
        h4("Build a Zenodo-ready deposit bundle"),
        p("Packages the reviewed gold-standard into a directory ready",
          "to upload to",
          tags$a(href = "https://zenodo.org/deposit/new",
                   "zenodo.org/deposit/new", target = "_blank"),
          ". Contents: ",
          tags$code("gold_standard.jsonl"), ", ",
          tags$code("kg.ttl"), " (RDF 1.1 Turtle), ",
          tags$code("metadata.json"), " (DataCite), ",
          tags$code("README.md"), "."),
        fluidRow(
          column(6, textInput("z_title",
                                "Deposit title",
                                value = "Cerrado gold-standard KG (edaphos)",
                                width = "100%")),
          column(6, textInput("z_version",
                                "Version",
                                value = as.character(Sys.Date()),
                                width = "100%"))
        ),
        textAreaInput("z_description",
                       "Description (HTML allowed, auto-generated if empty)",
                       value = "", rows = 4, width = "100%"),
        textInput("z_output_dir",
                   "Output directory",
                   value = file.path(dirname(.output_path),
                                       "zenodo_package"),
                   width = "100%"),
        checkboxInput("z_zip", "Also create .zip archive", TRUE),
        actionButton("btn_publish", "Build Zenodo bundle",
                      class = "btn-primary btn-lg"),
        tags$hr(),
        verbatimTextOutput("publish_log")
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
    records = NULL,
    idx     = 1L,
    current_claims = NULL
  )

  # Initial load — use output JSONL if it exists (resume), else draft
  isolate({
    path0 <- if (file.exists(.output_path)) .output_path else .draft_path
    rv$records <- read_records(path0)
    first_draft <- integer(0)
    for (i in seq_along(rv$records)) {
      cl <- coerce_claims(rv$records[[i]]$claims)
      if (any(cl$status == "draft"))
        first_draft <- c(first_draft, i)
    }
    rv$idx <- if (length(first_draft) > 0L) first_draft[1] else 1L
    rv$current_claims <- coerce_claims(rv$records[[rv$idx]]$claims)
  })

  # ── Dark mode ─────────────────────────────────────────────────────────
  observe({
    new_theme <- if (isTRUE(input$dark_mode == "dark")) {
      bslib::bs_theme(version = 5, bootswatch = "darkly")
    } else {
      bslib::bs_theme(version = 5, bootswatch = "flatly")
    }
    session$setCurrentTheme(new_theme)
  })

  # ── Load current abstract ──────────────────────────────────────────────
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
      if (!is.null(rec$doi))   paste("DOI:", rec$doi) else NULL,
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

  # ── Claim editor rows ──────────────────────────────────────────────────
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

  # Harvest
  harvest_current <- function() {
    cl <- rv$current_claims
    if (nrow(cl) == 0L) return(cl)
    for (i in seq_len(nrow(cl))) {
      cl$cause[i]      <- input[[paste0("cause_", i)]]      %||% cl$cause[i]
      cl$effect[i]     <- input[[paste0("effect_", i)]]     %||% cl$effect[i]
      cl$polarity[i]   <- input[[paste0("polarity_", i)]]   %||% cl$polarity[i]
      cl$confidence[i] <- as.numeric(input[[paste0("confidence_", i)]] %||% cl$confidence[i])
      cl$rationale[i]  <- input[[paste0("rationale_", i)]]  %||% cl$rationale[i]
    }
    cl
  }

  # Per-claim buttons (dynamic)
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

  observeEvent(input$btn_add, {
    rv$current_claims <- harvest_current()
    rv$current_claims <- rbind(rv$current_claims, data.frame(
      cause = VOCAB[1], effect = VOCAB[2], polarity = "+",
      confidence = 0.75, rationale = "",
      status = "added", stringsAsFactors = FALSE
    ))
  })

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

  # ── Sidebar counters ───────────────────────────────────────────────────
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

  # ── Stats tab ──────────────────────────────────────────────────────────
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

  # ── DAG tab ────────────────────────────────────────────────────────────
  aggregate_claims <- reactive({
    all_claims <- do.call(rbind, lapply(rv$records,
                                          function(r) coerce_claims(r$claims)))
    acc <- all_claims[all_claims$status %in%
                         c("accepted", "edited", "added"), ]
    if (nrow(acc) == 0L) return(NULL)
    acc$edge <- paste(acc$cause, "->", acc$effect)
    stats::aggregate(
      cbind(support = 1L, confidence = acc$confidence) ~ edge + polarity,
      data = acc,
      FUN = function(x) if (length(x) == 0L) 0 else mean(x)
    ) -> agg_mean
    # aggregate support as sum (count of occurrences)
    sup <- stats::aggregate(
      support ~ edge, data = acc, FUN = length
    )
    agg_mean$support <- sup$support[match(agg_mean$edge, sup$edge)]
    agg_mean$cause   <- sub(" -> .*", "", agg_mean$edge)
    agg_mean$effect  <- sub(".* -> ", "", agg_mean$edge)
    agg_mean
  })

  output$dag_summary <- renderText({
    agg <- aggregate_claims()
    if (is.null(agg)) return("No accepted claims yet — accept some claims to see the DAG.")
    keep <- agg[agg$support >= (input$min_support %||% 1L), , drop = FALSE]
    nodes <- unique(c(keep$cause, keep$effect))
    sprintf(
      "Showing %d edges on %d nodes (min_support=%d).\nTotal accepted edges: %d.",
      nrow(keep), length(nodes),
      input$min_support %||% 1L,
      nrow(agg)
    )
  })

  output$dag_plot <- DiagrammeR::renderGrViz({
    agg <- aggregate_claims()
    if (is.null(agg)) {
      return(DiagrammeR::grViz("digraph empty { empty [label=\"No accepted claims yet\"] }"))
    }
    keep <- agg[agg$support >= (input$min_support %||% 1L), , drop = FALSE]
    if (nrow(keep) == 0L) {
      return(DiagrammeR::grViz("digraph empty { empty [label=\"No edges at this support threshold\"] }"))
    }
    show_lbl <- isTRUE(input$show_labels)
    nodes <- unique(c(keep$cause, keep$effect))
    node_defs <- vapply(nodes, function(n)
      sprintf("  \"%s\" [label=%s, shape=ellipse, style=filled, fillcolor=\"#E8F4FD\", color=\"#2980B9\"]",
              n, if (show_lbl) sprintf("\"%s\"", n) else "\"\""),
      character(1L))
    edge_defs <- vapply(seq_len(nrow(keep)), function(i) {
      col <- if (keep$polarity[i] == "+") "#27AE60" else "#C0392B"
      w <- 0.7 + 4 * (keep$confidence[i] %||% 0.5)
      lab <- sprintf("%.2f × %d", keep$confidence[i], keep$support[i])
      sprintf("  \"%s\" -> \"%s\" [color=\"%s\", penwidth=%.2f, label=\"%s\"]",
              keep$cause[i], keep$effect[i], col, w, lab)
    }, character(1L))
    dot <- paste0(
      "digraph dag {\n",
      "  graph [layout=dot, rankdir=LR, bgcolor=\"transparent\"]\n",
      "  node  [fontname=\"Helvetica\", fontsize=11]\n",
      "  edge  [fontname=\"Helvetica\", fontsize=9, arrowsize=0.8]\n",
      paste(node_defs, collapse = "\n"), "\n",
      paste(edge_defs, collapse = "\n"), "\n}"
    )
    DiagrammeR::grViz(dot)
  })

  # ── Export tab ─────────────────────────────────────────────────────────
  observeEvent(input$btn_export, {
    save_current_to_records()
    out_final <- sub("\\.jsonl$", "_final.jsonl", .output_path)
    records_out <- lapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      keep <- !(cl$status %in% c("rejected", "draft"))
      cl <- cl[keep, , drop = FALSE]
      cl$status <- NULL
      r$claims <- cl
      r
    })
    write_records(records_out, out_final)

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
      "  Rscript data-raw/llm_benchmark_run.R",
      sep = "\n"
    ))
    showNotification("Exported ✓", duration = 3, type = "message")
  })

  # ── Publish tab (Zenodo bundle) ────────────────────────────────────────
  observeEvent(input$btn_publish, {
    save_current_to_records()
    # First export a clean version alongside
    out_final <- sub("\\.jsonl$", "_final.jsonl", .output_path)
    records_out <- lapply(rv$records, function(r) {
      cl <- coerce_claims(r$claims)
      keep <- !(cl$status %in% c("rejected", "draft"))
      cl <- cl[keep, , drop = FALSE]
      cl$status <- NULL
      r$claims <- cl
      r
    })
    write_records(records_out, out_final)

    res <- tryCatch(
      edaphos::llm_annotation_to_zenodo(
        reviewed_path = out_final,
        output_dir    = input$z_output_dir,
        title         = input$z_title %||% "Cerrado gold-standard KG (edaphos)",
        description   = if (nzchar(input$z_description %||% "")) input$z_description else NULL,
        version       = input$z_version %||% as.character(Sys.Date()),
        zip           = isTRUE(input$z_zip)
      ),
      error = function(e) conditionMessage(e)
    )
    zip_path <- paste0(input$z_output_dir, ".zip")
    has_zip <- isTRUE(input$z_zip) && file.exists(zip_path)

    output$publish_log <- renderText(paste(
      sprintf("=== Bundle built at %s ===",
              if (is.character(res)) res else input$z_output_dir),
      "",
      "Files in the bundle:",
      paste(" -",
            list.files(input$z_output_dir, full.names = FALSE)),
      "",
      if (has_zip) sprintf("Zip archive: %s (%.1f KB)",
                            zip_path, file.size(zip_path) / 1024) else "",
      "",
      "Next steps:",
      "  1. Open https://zenodo.org/deposit/new in a browser.",
      "  2. Drag-and-drop the files (or the .zip) into the form.",
      "  3. Copy the metadata from metadata.json into the Zenodo form.",
      "  4. Publish; record the minted DOI in your paper.",
      sep = "\n"
    ))
    showNotification("Zenodo bundle ready ✓", duration = 4, type = "message")
  })

  # ── Keyboard shortcuts ─────────────────────────────────────────────────
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
