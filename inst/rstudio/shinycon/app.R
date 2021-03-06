library(shiny)
library(pins)

rsApiUpdateDialog <- function(code) {
  if (exists(".rs.api.updateDialog")) {
    updateDialog <- get(".rs.api.updateDialog")
    updateDialog(code = code)
  }
}

rsConnectServers <- function() {
  as.character(rsconnect::accounts()$server)
}

#' @import rstudioapi
pins_connection_ui <- function() {
  elementSpacing <- if (.Platform$OS.type == "windows") 2 else 7

  tags$div(
    tags$head(
      tags$style(
        HTML(paste("
          body {
            background: none;

            font-family : \"Lucida Sans\", \"DejaVu Sans\", \"Lucida Grande\", \"Segoe UI\", Verdana, Helvetica, sans-serif;
            font-size : 12px;
            -ms-user-select : none;
            -moz-user-select : none;
            -webkit-user-select : none;
            user-select : none;

            margin: 0;
            margin-top: 7px;
          }

          select {
            background: #FFF;
          }

          .shiny-input-container {
            min-width: 100%;
            margin-bottom: ", elementSpacing, "px;
            display: table;
          }

          .shiny-input-container > .control-label,
          .shiny-input-container > label {
            display: table-cell;
            min-width: 195px;
          }

          .shiny-input-container > div {
            display: table-cell;
            width: 300px;
          }

          .shiny-input-container > .input-group {
            width: 100%;
          }

          .shiny-input-container > .input-group > input {
            border: solid 1px #A2A2A2;
            border-radius: 3px;
            padding: 2px;
          }

          .shiny-input-container > .input-group > .input-group-btn {
            margin-right: 6px;
            border: solid 1px #A2A2A2;
            border-radius: 3px;
            padding: 1px 6px 1px 6px;
          }

          .shiny-input-container > .input-group > input[type=\"text\"] {
            width: 218px;
          }

          .shiny-input-container .progress-bar { display: none; }

          #shiny-disconnected-overlay {
            display: none;
          }

          .token-label {
            text-align: right;
            margin-right: 14px;
          }

          .shiny-input-container > label {
            display: table-cell;
          }

          .shiny-input-container > input[type=\"text\"] {
            border: 1px solid rgba(0,0,0,0.3);
            border-radius: 4px;
            margin-left: 4px;
            width: 290px;
            padding: 2px 2px 2px 6px;
          }
        ", sep = ""))
      )
    ),
    tags$div(
      selectInput(
        "board",
        "Board:",
        choices = c(
          list(
            local = "local",
            github = "github",
            kaggle = "kaggle",
            rsconnect = "rsconnect"
          )
        ),
        selectize = FALSE,
        selected = "local"
      ),
      conditionalPanel(
        condition = "input.board == 'rsconnect'",
        selectInput(
          "server",
          "Server:",
          list(),
          selectize = FALSE
        )
      ),
      conditionalPanel(
        condition = "input.board == 'kaggle'",
        fileInput(
          "token",
          "Token:",
          placeholder = "Kaggle token file",
          accept = ".json"
        ),
        tags$div(
          "Dowload token file from",
          tags$a(
            "kaggle.com/me/account",
            href = "https://www.kaggle.com/me/account"
          ),
          class = "token-label"
        )
      ),
      conditionalPanel(
        condition = "input.board == 'github'",
        textInput(
          "repo",
          "Repository:",
          value = "owner/repo"
        ),
        textInput(
          "path",
          "Path/Branch:",
          value = "master/pins"
        ),
        textInput(
          "github",
          "Token:"
        ),
        tags$div(
          "Retrieve token from",
          tags$a(
            "github.com/settings/tokens",
            href = "https://github.com/settings/tokens"
          ),
          class = "token-label"
        )
      )
    ),
    tags$div(
      style = paste("display: table-row; height: 10px")
    )
  )
}

pins_connection_server <- function(input, output, session) {

  observe({
    if (identical(input$board, "rsconnect")) {
      updateSelectizeInput(
        session,
        "server",
        choices = rsConnectServers()
      )
    }
  })

  generateCode <- function(board) {
    parameters <- ""
    initializer <- ""

    if (identical(board, "rsconnect") && !is.null(input$server)) {
      initializer <- paste(
        "pins::board_register(\"rsconnect\", ",
        "server = \"", input$server, "\")\n", sep = "")
    }
    else if (identical(board, "kaggle") && !is.null(input$token)) {
      initializer <- tryCatch({
        contents <- jsonlite::read_json(input$token$datapath)

        paste(
          "pins::board_register(\"kaggle\", ",
          "token = list(",
          paste(names(contents), " = \"", contents, "\"", collapse = ", ", sep = ""),
          "), overwrite = TRUE)\n",
          sep = "")
      }, error = function(e) {
        rstudioapi::showDialog("Invalid Token", paste("Failed to parse the Kaggle token file:", e$message))
        ""
      })
    }
    else if (identical(board, "github") && !identical(input$repo, "owner/repo")) {
      path_parts <- strsplit(input$path, "/")[[1]]
      branch <- path_parts[1]
      path <- if (length(path_parts) > 1) paste(path_parts[2:length(path_parts)], sep = "/") else ""

      initializer <- paste0(
        "pins::board_register(\"github\", ",
        "repo = \"", input$repo, "\"",
        ifelse(identical(path, "pins"), "", paste0(", path = \"", path, "\"")),
        ifelse(identical(branch, "master"), "", paste0(", branch = \"", branch, "\"")),
        ifelse(nchar(input$github) == 0, "", paste0(", token = \"", input$github, "\")")),
        ")\n")
    }

    paste(
      initializer,
      "pins::board_connect(",
      "\"", board, "\"",
      parameters,
      ")",
      sep = ""
    )
  }

  codeReactive <- reactive({
    generateCode(input$board)
  })

  observe({
    rsApiUpdateDialog(codeReactive())
  })
}

shinyApp(pins_connection_ui, pins_connection_server)
