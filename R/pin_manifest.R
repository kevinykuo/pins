pin_manifest_get <- function(path) {
  manifest <- list()

  data_txt <- file.path(path, "data.txt")
  if (file.exists(data_txt)) {
    manifest <- yaml::read_yaml(data_txt)
  }

  if (is.null(manifest$type)) manifest$type <- "files"

  manifest
}

pin_manifest_create <- function(path, type, description, metadata, files) {
  entries <- c(list(
    path = files,
    type = type,
    description = description
  ), metadata)

  entries[sapply(entries, is.null)] <- NULL

  yaml::write_yaml(entries, file.path(path, "data.txt"))
}
