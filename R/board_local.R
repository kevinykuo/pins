board_initialize.local <- function(board, ...) {
  board
}

guess_extension_from_path <- function(path) {
  if (dir.exists(path)) {
    all_files <- dir(path, recursive = TRUE)
    all_files <- Filter(function(x) !grepl("data\\.txt", x), all_files)

    path <- all_files[[1]]
  }

  tools::file_ext(path)
}

board_pin_create.local <- function(board, path, name, ...) {
  description <- list(...)$description
  metadata <- list(...)$metadata
  type <- list(...)$type

  on.exit(board_connect(board$name))

  final_path <- pin_registry_update(name = name, component = "local")

  unlink(final_path, recursive = TRUE)
  dir.create(final_path)

  file.copy(dir(path, full.names = TRUE) , final_path, recursive = TRUE)

  # reduce index size
  metadata$columns <- NULL

  pin_registry_update(
    name = name,
    params = c(list(
      path = final_path,
      description = description,
      type = type
    ), metadata),
    component = "local")
}

board_pin_find.local <- function(board, text, ...) {
  results <- pin_registry_find(text, "local")

  if (nrow(results) == 1) {
    metadata <- jsonlite::fromJSON(results$metadata)
    extended <- pin_manifest_get(metadata$path)

    results$metadata <- as.character(jsonlite::toJSON(c(metadata, extended)))
  }

  results
}

board_pin_get.local <- function(board, name) {
  entry <- pin_registry_retrieve(name, "local")
  entry$path
}

board_pin_remove.local <- function(board, name) {
  pin_registry_remove(name, "local")
}
