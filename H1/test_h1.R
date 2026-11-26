# From the repository root: Rscript H1/test_h1.R
# Base R only. Output goes to H1/Output.
read_data <- function(name) {
  read.csv(file.path("Prepared Data", name), stringsAsFactors = FALSE)
}
artists <- read_data("artists_clean.csv")
tracks <- read_data("tracks_clean.csv")
credits <- read_data("artist_track_credits.csv")
groups <- split(match(credits$artist_id, artists$id), credits$track_id)[tracks$id]
stopifnot(!anyDuplicated(artists$id), !anyDuplicated(tracks$id),
          !anyDuplicated(credits[c("track_id", "artist_id")]),
          !anyNA(unlist(groups)), all(lengths(groups) == tracks$artist_count))
status <- as.integer(artists$superstar)
stopifnot(is.logical(artists$superstar))

# One occurrence per pair per recording. Repeated rows represent shared-recording weights.
pairs <- do.call(rbind, lapply(groups[lengths(groups) >= 2], function(ids) {
  ids <- sort(ids[!is.na(status[ids])])
  if (length(ids) >= 2) t(combn(ids, 2))
}))
edges <- unique(pairs)
degree <- tabulate(as.vector(edges), nrow(artists))
active <- degree > 0
stars <- sum(status[active])
others <- sum(active) - stars
possible <- c(choose(others, 2), others * stars, choose(stars, 2))
counts <- tabulate(1L + status[edges[, 1]] + status[edges[, 2]], 3L)
density <- data.frame(pair = c("Other–other", "Mixed", "Star–star", "Total"),
                      edges = c(counts, sum(counts)), possible = c(possible, sum(possible)))
density$per_10000 <- 10000 * density$edges / density$possible
density$share_of_all_edges <- density$edges / sum(counts)

left <- pairs[, 1]
right <- pairs[, 2]
measure <- function(labels) {
  kind <- labels[edges[, 1]] + labels[edges[, 2]]
  rates <- tabulate(kind + 1L, 3L) / possible
  pair_sum <- labels[left] + labels[right]
  endpoint <- mean(pair_sum) / 2
  r <- (mean(pair_sum == 2L) - endpoint^2) / (endpoint * (1 - endpoint))
  c(rates[3] - rates[2], r)
}
bands <- cut(degree[active], c(0, 1, 2, 4, 8, 16, 32, 64, Inf))
strata <- split(which(active), bands, drop = TRUE)
observed <- measure(status)
set.seed(2386)
B <- 4999L
draws <- replicate(B, {
  shuffled <- status
  for (ids in strata) shuffled[ids] <- status[ids[sample.int(length(ids))]]
  measure(shuffled)
})
permutation <- data.frame(statistic = c("density difference", "weighted assortativity"),
                          observed = observed, null_mean = rowMeans(draws),
                          p = (1 + rowSums(draws >= observed)) / (B + 1))

fit_popularity <- function(label, min_score) {
  eligible <- tracks$collaboration_type %in% c("All superstar", "Mixed status") &
              tracks$popularity >= min_score
  t <- tracks[eligible, ]
  g <- groups[eligible]
  t$all_star <- as.integer(t$collaboration_type == "All superstar")
  fit <- lm(popularity ~ all_star + artist_count + factor(year), data = t)
  X <- model.matrix(fit)
  score <- drop(X %*% solve(crossprod(X))[, "all_star"]) * residuals(fit)
  # Add covariance once for each distinct pair of tracks sharing any artist.
  by_artist <- split(rep(seq_along(g), lengths(g)), unlist(g, use.names = FALSE))
  variance <- sum(score^2)
  for (i in seq_along(g)) {
    neighbors <- unique(unlist(by_artist[as.character(g[[i]])], use.names = FALSE))
    variance <- variance + 2 * score[i] * sum(score[neighbors[neighbors > i]])
  }
  se <- sqrt(variance)
  b <- unname(coef(fit)["all_star"])
  data.frame(sample = label, n = nrow(t), difference = b, low = b - 1.96 * se,
             high = b + 1.96 * se, p = 2 * pnorm(-abs(b / se)))
}
popularity <- rbind(fit_popularity("Full catalogue", 0), fit_popularity("Popularity ≥65", 65))
out <- file.path("H1", "Output")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
write_result <- function(table, file) {
  write.csv(table, file.path(out, file), row.names = FALSE, fileEncoding = "UTF-8")
}
write_result(density, "density.csv")
write_result(permutation, "permutation_results.csv")
write_result(popularity, "popularity_results.csv")
print(density)
print(permutation)
print(popularity)
