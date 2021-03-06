rsconnect_token_dependencies <- function() {
  list(
    accounts = get0("accounts", envir = asNamespace("rsconnect")),
    account_info = get0("accountInfo", envir = asNamespace("rsconnect")),
    server_info = get0("serverInfo", envir = asNamespace("rsconnect")),
    signature_headers = get0("signatureHeaders", envir = asNamespace("rsconnect")),
    http_function = get0("httpFunction", envir = asNamespace("rsconnect"))
  )
}

rsconnect_token_parse_url <- function(urlText) {
  # see rsconnect::parseHttpUrl

  matches <- regexec("(http|https)://([^:/#?]+)(?::(\\d+))?(.*)", urlText)
  components <- regmatches(urlText, matches)[[1]]
  if (length(components) == 0)
    stop("Invalid url: ", urlText)

  url <- list()
  url$protocol <- components[[2]]
  url$host <- components[[3]]
  url$port <- components[[4]]
  url$path <- components[[5]]
  url
}

rsconnect_token_initialize <- function(board) {
  deps <- rsconnect_token_dependencies()

  if (is.null(deps$accounts)) stop("RStudio Connect is not registered, please install the 'rsconnect' package or specify an API key.")

  accounts <- deps$accounts()
  if (is.null(accounts)) stop("RStudio Connect is not registered, please add a publishing account or specify an API key.")

  if (is.null(board$server)) {
    board$server_name <- accounts$server[1]
    board$server <- gsub("/__api__", "", deps$server_info(board$server_name)$url)
  }

  if (is.null(board$account)) board$account <- accounts[accounts$server == board$server_name,]$name

  board
}

rsconnect_token_headers <- function(board, path, verb, content) {
  deps <- rsconnect_token_dependencies()

  server_info <- deps$server_info(board$server_name)
  service <- rsconnect_token_parse_url(server_info$url)

  account_info <- deps$account_info(board$account)

  content_file <- NULL
  if (identical(class(content), "form_file")) {
    content_file <- content$path
  }
  else if (!identical(content, NULL)){
    if (!is.character(content)) stop("Unsupported object of class", class(content)[[1]])
    content_file <- tempfile()
    on.exit(unlink(content_file))
    writeChar(content, content_file,  eos = NULL, useBytes = TRUE)
  }

  deps$signature_headers(account_info, verb, path, content_file)
}

rsconnect_token_post <- function(board, path, content, encode) {
  deps <- rsconnect_token_dependencies()

  server_info <- deps$server_info(board$server_name)
  parsed <- rsconnect_token_parse_url(server_info$url)

  if (identical(class(content), "form_file")) {
    content_file <- content$path
    content_type <- "application/x-gzip"
  }
  else {
    content_file <- tempfile()
    on.exit(unlink(content_file))
    writeChar(content, content_file, eos = NULL, useBytes = TRUE)
    content_type <- "application/json"
  }

  result <- deps$http_function()(parsed$protocol,
                                 parsed$host,
                                 parsed$port,
                                 "POST",
                                 path,
                                 rsconnect_token_headers(board, path, "POST", content),
                                 contentType = content_type,
                                 file = content_file)

  jsonlite::fromJSON(result$content)
}

