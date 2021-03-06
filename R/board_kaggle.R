kaggle_dependencies <- function() {

}

kaggle_auth_paths <- function() {
  normalizePath(
    "~/.kaggle/kaggle.json",
    mustWork = FALSE
  )
}

kaggle_authenticated <- function() {
  any(file.exists(kaggle_auth_paths()))
}

kaggle_auth_info <- function() {
  jsonlite::read_json(kaggle_auth_paths())
}


kaggle_auth <- function() {
  kaggle_keys <- kaggle_auth_info()

  httr::authenticate(
    kaggle_keys$username,
    kaggle_keys$key
  )
}

kaggle_qualify_name <- function(name) {
  qualified <- name
  if (!grepl("/", qualified)) qualified <- paste0(kaggle_auth_info()$username, "/", name)

  qualified
}

kaggle_upload_resource <- function(path) {
  path <- normalizePath(path)
  if (!file.exists(path)) stop("Invalid path: ", path)

  content_length <- file.info(path)$size
  modified <- as.integer(file.info(path)$mtime)

  url <- paste0("https://www.kaggle.com/api/v1/datasets/upload/file/", content_length, "/", modified)

  results <- httr::POST(url, body = list(fileName = basename(path)), config = kaggle_auth())

  if (httr::http_error(results)) stop("Upload registration failed with status ", httr::status_code(results))

  parsed <- httr::content(results)

  if (!identical(parsed$error, NULL)) stop("Upload registration failed: ", parsed$error)

  upload_url <- parsed$createUrl
  token <- parsed$token

  results <- httr::PUT(upload_url, body = httr::upload_file(normalizePath(path)), config = kaggle_auth())

  if (httr::http_error(results)) stop("Upload failed with status ", httr::status_code(results))

  parsed <- httr::content(results)

  if (!identical(parsed$error, NULL)) stop("Upload failed: ", parsed$error)

  token
}

kaggle_create_resource <- function(name, description, token, type) {
  url <- "https://www.kaggle.com/api/v1/datasets/create/new"

  body <- list(
    convertToCsv = jsonlite::unbox(FALSE),
    files = data.frame(
      token = token
    ),
    isPrivate = jsonlite::unbox(TRUE),
    licenseName = jsonlite::unbox("CC0-1.0"),
    ownerSlug = jsonlite::unbox(kaggle_auth_info()$username),
    slug = jsonlite::unbox(name),
    subtitle = jsonlite::unbox("none"),
    title = jsonlite::unbox(description),
    categories = list()
  )

  results <- httr::POST(url, body = body, config = kaggle_auth(), encode = "json")

  if (httr::http_error(results)) stop("Resource creation failed with status ", httr::status_code(results))

  parsed <- httr::content(results)

  if (!identical(parsed$error, NULL)) stop("Resource creation failed: ", parsed$error)

  parsed$url
}

kaggle_create_bundle <- function(path, type, description) {
  bundle_path <- tempfile()
  dir.create(bundle_path)
  on.exit(unlink(bundle_path, recursive = TRUE))

  if (identical(dir(path, "data\\.rds"), "data.rds")) {
    loaded <- readRDS(dir(path, "data\\.rds", full.names = TRUE))
  }

  if (dir.exists(path)) {
    file.copy(file.path(path, dir(path)), bundle_path, recursive = TRUE)
  }
  else {
    file.copy(path, bundle_path)
  }

  bundle_file <- tempfile(fileext = ".zip")
  withr::with_dir(
    bundle_path,
    zip::zip(bundle_file, dir(bundle_path))
  )

  bundle_file
}

board_initialize.kaggle <- function(board, token = NULL, overwrite = FALSE, ...) {
  if (!is.null(token)) {
    exists <- file.exists(kaggle_auth_paths())
    if (exists && !overwrite) stop("File already exists, use 'overwrite = TRUE' to overwrite.")

    if (!exists || identical(overwrite, TRUE)) {
      token_path <- dirname(kaggle_auth_paths())
      if (!dir.exists(token_path)) dir.create(token_path, recursive = TRUE)

      if (is.list(token)) {
         jsonlite::write_json(token, kaggle_auth_paths(), auto_unbox = TRUE)
      }
      else {
        file.copy(token, kaggle_auth_paths(), overwrite = TRUE)
      }
    }
  }

  if (!kaggle_authenticated()) {
    stop("Authentication to Kaggle failed. Was a token file specified when registering this board?")
  }

  board
}

board_pin_create.kaggle <- function(board, path, name, ...) {
  description <- list(...)$description
  if (is.null(description) || nchar(description) == 0) description <- paste("A pin for the", gsub("-pin$", "", name), "dataset")
  if (!file.exists(path)) stop("File does not exist: ", path)

  temp_bundle <- kaggle_create_bundle(path, type, description)
  on.exit(unlink(temp_bundle))

  token <- kaggle_upload_resource(temp_bundle)
  kaggle_create_resource(name, description, token, type)

  qualified_name <- paste0(kaggle_auth_info()$username, "/", name)

  retrieved <- NULL
  retries <- 10
  while (retries > 0 && is.null(retrieved)) {
    retrieved <- suppressWarnings(tryCatch({
      pin_get(qualified_name, board$name)
    }, error = function(e) NULL))

    Sys.sleep(1)
    retries <- retries - 1
  }
}

board_pin_search_kaggle <- function(text = NULL) {
  base_url <- "https://www.kaggle.com/api/v1/datasets/list?"
  if (identical(text, NULL) || length(text) == 0 || nchar(text) == 0) {
    params <- "group=my"
  }
  else {
    params <- paste0("search=", text)
  }

  url <- utils::URLencode(paste0(base_url, params))

  results <- httr::GET(url, config = kaggle_auth())
  if (httr::http_error(results)) stop("Finding pin failed with status ", httr::status_code(results))

  httr::content(results)
}

board_pin_find.kaggle <- function(board, text, ...) {
  if (!kaggle_authenticated()) return(data.frame(name = c(), description = c(), type = c(), metadata = c()))

  if (is.null(text)) text <- ""

  # clear name searches
  text <- gsub("^[^/]+/", "", text)

  # search private dataserts first sincee they won't search by default
  results <- board_pin_search_kaggle()
  reults <- Filter(function(e) grepl(text, e$ref), results)

  results <- c(results, board_pin_search_kaggle(text))

  results <- jsonlite::fromJSON(jsonlite::toJSON(results))

  if (identical(list(...)$extended, TRUE)) {
    results$name <- results$ref
    results$description <- results$title
    results$ref <- NULL
    results$title <- NULL
    return(results)
  }

  if (length(results) == 0) return(data.frame(name = c(), description = c(), type = c(), metadata = c()))

  data.frame(
    name = as.character(results$ref),
    description = as.character(results$title),
    type = "files",
    metadata = rep(as.character(jsonlite::toJSON(list(extension = "zip"), auto_unbox = TRUE)), length(results$ref)),
    stringsAsFactors = FALSE
  ) %>%
    unique()
}

board_pin_get.kaggle <- function(board, name) {
  if (!grepl("/", name)) name <- paste(kaggle_auth_info()$username, name, sep = "/")

  url <- paste0("https://www.kaggle.com/api/v1/datasets/download/", name)
  temp_zip <- tempfile(fileext = ".zip")

  extended <- pin_find(name, board = board$name, extended = TRUE)
  etag <- if (is.null(extended$lastUpdated)) "" else as.character(extended$lastUpdated)

  local_path <- pin_download(url,
                             name,
                             component = "kaggle",
                             config = kaggle_auth(),
                             custom_etag = etag)

  results <- httr::GET(url, config = kaggle_auth(), httr::write_disk(temp_zip))
  if (httr::http_error(results))
    stop("Failed to retrieve pin with status ", httr::status_code(results))

  local_path
}

board_pin_remove.kaggle <- function(board, name) {
  qualified <- kaggle_qualify_name(name)
  stop("Please remove dataset from: https://www.kaggle.com/", qualified, "/settings")
}

board_browse.kaggle <- function(board) {
  utils::browseURL("https://www.kaggle.com/datasets?tab=my")
}

