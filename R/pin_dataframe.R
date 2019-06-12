pin.data.frame <- function(x, name = NULL, description = NULL, board = NULL, ...) {
  if (is.null(name)) stop("The 'name' parameter is required for '", class(x)[[1]], "' objects.")

  path <- tempfile(fileext = ".rds")
  saveRDS(x, path, version = 2)
  on.exit(unlink(path))

  metadata <- as.character(jsonlite::toJSON(list(
    rows = nrow(x),
    cols = ncol(x)
  )))

  board_pin_create(board_get(board), path, name, description, "table", metadata)
}

pin_load.table <- function(path, ...) {
  readRDS(path)
}

pin_preview.data.frame <- function(x) {
  head(x, n = getOption("pins.preview", 10^3))
}