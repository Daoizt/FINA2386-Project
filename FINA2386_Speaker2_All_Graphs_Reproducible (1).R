# ============================================================================
# FINA2386 | Speaker 2: Spotify Artist Collaboration Network (2018–2020)
# FINAL REPRODUCIBLE R CODE -- ORIGINAL BLUE / ORANGE PALETTE
#
# INPUTS (put in one folder):
#   tracks_clean.csv
#   artists_clean.csv
#
# OUTPUTS (saved in speaker2_outputs/):
#   01_Full_Artist_Network.png
#   02_Local_Hub_Subnetwork.png
#   03_Top15_Degree_Ranking.png
#   04_Degree_Distribution.png
#   speaker2_network_summary.csv
#   speaker2_top15_artists.csv
#
# Note: 02 is a SELECTED SUBNETWORK with a new layout, not a literal zoom/crop.
#       It contains the highest-degree artist and 30 of their actual neighbors.
#       All nodes and edges are taken from the SAME full network as Figure 01.
# ============================================================================

# 0. Install packages (first use only) ----------------------------------------
packages <- c("readr", "dplyr", "stringr", "igraph", "ggraph",
              "ggplot2", "ggrepel", "scales", "tibble")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) install.packages(missing, repos = "https://cloud.r-project.org")

library(dplyr)
library(igraph)
library(ggplot2)
library(ggraph)

# 1. Folders and colors -------------------------------------------------------
# In RStudio: Session > Set Working Directory > Choose Directory ...
# Choose the folder containing both CSVs, OR edit DATA_DIR to its full path.
DATA_DIR <- "."
OUT_DIR <- file.path(DATA_DIR, "speaker2_outputs")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Original calm palette -- not the fluorescent green / purple version.
C_BG     <- "#F5F8FC"  # pale blue-grey background
C_LOW    <- "#91A2B8"  # low-degree nodes, 1–3 collaborators
C_MID    <- "#1D7792"  # medium-degree nodes, 4–20 collaborators
C_HIGH   <- "#E59A58"  # high-degree nodes, 21+ collaborators
C_EDGE   <- "#647894"  # subtle grey-blue edges
C_TEXT   <- "#19314A"
C_MUTED  <- "#526980"
C_GRID   <- "#D7E1EC"
node_palette <- c("1–3" = C_LOW, "4–20" = C_MID, "21+" = C_HIGH)

# 2. Read data ---------------------------------------------------------------
track_file <- file.path(DATA_DIR, "tracks_clean.csv")
artist_file <- file.path(DATA_DIR, "artists_clean.csv")
if (!file.exists(track_file) || !file.exists(artist_file)) {
  stop("Missing CSV. Please put tracks_clean.csv and artists_clean.csv in DATA_DIR.")
}

tracks <- readr::read_csv(track_file, show_col_types = FALSE)
artists <- readr::read_csv(artist_file, show_col_types = FALSE)
stopifnot(all(c("id_artists", "year") %in% names(tracks)))
stopifnot(all(c("id", "name") %in% names(artists)))

# Main sample: ALL cleaned tracks, 2018–2020, ALL popularity scores.
# DO NOT filter popularity >= 65 (that is a different sensitivity sample).
tracks <- tracks %>% filter(year >= 2018, year <= 2020)
cat("Tracks in main sample:", nrow(tracks), "\n")

# 3. Build undirected ID-based collaboration graph ---------------------------
# ID field looks like: "['22-character-Spotify-ID', '22-character-Spotify-ID']".
# Extract IDs (not names) to avoid accidentally merging same-name artists.
artist_lists <- stringr::str_extract_all(
  ifelse(is.na(tracks$id_artists), "", tracks$id_artists),
  "[A-Za-z0-9]{22}"
)
if (any(lengths(artist_lists) == 0)) {
  stop("Some rows have no readable artist IDs. Please check id_artists.")
}

# For one track with A, B, C: create A--B, A--C, B--C.
# Sorting IDs makes A--B and B--A the same undirected pair.
pair_tables <- lapply(artist_lists, function(ids) {
  ids <- sort(unique(ids))
  if (length(ids) < 2L) return(NULL)
  pair_mat <- utils::combn(ids, 2)
  tibble::tibble(from = pair_mat[1, ], to = pair_mat[2, ])
})
all_pairs <- dplyr::bind_rows(pair_tables)
edges <- all_pairs %>% count(from, to, name = "weight")

# Each unique pair = ONE edge. Edge weight = number of shared tracks.
g_all <- igraph::graph_from_data_frame(edges, directed = FALSE)
comp <- igraph::components(g_all)
g <- igraph::induced_subgraph(g_all, which(comp$membership == which.max(comp$csize)))

# Full-network degree (number of DISTINCT collaborators, not song count).
V(g)$degree <- igraph::degree(g)
V(g)$degree_band <- factor(
  ifelse(V(g)$degree <= 3, "1–3",
         ifelse(V(g)$degree <= 20, "4–20", "21+")),
  levels = c("1–3", "4–20", "21+")
)

# Attach readable names for labeling the local network and ranking chart.
lookup <- artists %>% distinct(id, .keep_all = TRUE) %>% select(id, name)
artist_names <- lookup$name[match(V(g)$name, lookup$id)]
missing_names <- is.na(artist_names) | artist_names == ""
artist_names[missing_names] <- V(g)$name[missing_names]
V(g)$artist_name <- artist_names

# 4. Sanity check ------------------------------------------------------------
stats <- tibble::tibble(
  measure = c("Tracks", "Nodes in giant component", "Unique edges in giant component",
              "Density", "Global transitivity", "Median degree", "Maximum degree"),
  value = c(nrow(tracks), vcount(g), ecount(g),
            round(igraph::edge_density(g), 6),
            round(igraph::transitivity(g, type = "global"), 6),
            median(V(g)$degree), max(V(g)$degree))
)
print(stats, n = Inf)
readr::write_csv(stats, file.path(OUT_DIR, "speaker2_network_summary.csv"))

if (vcount(g) != 6368L || ecount(g) != 21573L) {
  warning("Unexpected network size: expected 6,368 nodes / 21,573 edges for the uploaded data. Check file versions and filters.")
}

# 5. FULL NETWORK: 6,368 artists & 21,573 edges -----------------------------
# This layout can take a little time on the first run.
set.seed(2386)
full_xy <- igraph::layout_with_drl(g, weights = NA)
full_layout <- ggraph::create_layout(g, layout = "manual",
                                     x = full_xy[, 1], y = full_xy[, 2])

p_full <- ggraph::ggraph(full_layout) +
  ggraph::geom_edge_link0(edge_colour = C_EDGE,
                          edge_alpha = 0.10,
                          edge_width = 0.13,
                          show.legend = FALSE) +
  ggraph::geom_node_point(aes(colour = degree_band, size = degree),
                          alpha = 0.84) +
  scale_colour_manual(values = node_palette, name = "Degree category") +
  scale_size_continuous(range = c(0.25, 4.8),
                        name = "Distinct collaborators") +
  coord_equal() +
  theme_void(base_size = 12) +
  theme(
    plot.background = element_rect(fill = C_BG, colour = NA),
    panel.background = element_rect(fill = C_BG, colour = NA),
    legend.position = "none",
    plot.margin = margin(5, 5, 5, 5, "mm")
  )

ggsave(file.path(OUT_DIR, "01_Full_Artist_Network.png"), p_full,
       width = 12.8, height = 7.2, dpi = 300, bg = C_BG)

# 6. LOCAL SUBNETWORK: the highest-degree artist and 30 real neighbors -------
# This is a graph-theoretic "detail view", not a pixel crop.
# We intentionally re-layout these nodes so individual ties can be seen.
hub_id <- V(g)$name[which.max(V(g)$degree)]
neighbor_ids <- igraph::as_ids(igraph::neighbors(g, hub_id))
neighbor_degrees <- igraph::degree(g, v = neighbor_ids)
ordered_neighbors <- neighbor_ids[order(neighbor_degrees, decreasing = TRUE)]

# Show both influential partners and less-connected partners.
# This makes the local picture more legible and less uniformly orange.
K <- length(ordered_neighbors)
mid_positions <- unique(round(seq(13, max(13, K - 12), length.out = 6)))
chosen_neighbors <- unique(c(
  head(ordered_neighbors, 12),
  ordered_neighbors[pmin(mid_positions, K)],
  tail(ordered_neighbors, 12)
))
local_ids <- unique(c(hub_id, chosen_neighbors))
g_local <- induced_subgraph(g, vids = local_ids)

set.seed(2386)
local_xy <- igraph::layout_with_fr(g_local, weights = E(g_local)$weight)
local_layout <- ggraph::create_layout(g_local, layout = "manual",
                                      x = local_xy[, 1], y = local_xy[, 2])

# Label the central hub and up to 11 other important selected artists.
label_df <- as.data.frame(local_layout) %>%
  arrange(desc(degree)) %>% slice_head(n = 12)

p_local <- ggraph::ggraph(local_layout) +
  ggraph::geom_edge_link0(edge_colour = C_EDGE,
                          edge_alpha = 0.23, edge_width = 0.4,
                          show.legend = FALSE) +
  ggraph::geom_node_point(aes(colour = degree_band, size = degree),
                          alpha = 0.97, show.legend = FALSE) +
  scale_colour_manual(values = node_palette) +
  scale_size_continuous(range = c(2.2, 10.5)) +
  ggrepel::geom_label_repel(
    data = label_df, inherit.aes = FALSE,
    aes(x = x, y = y, label = artist_name),
    size = 3.0, colour = C_TEXT, fill = "white",
    label.size = 0, alpha = 0.88,
    box.padding = 0.3, point.padding = 0.3,
    max.overlaps = Inf, seed = 2386
  ) +
  coord_equal() +
  labs(title = paste0("Local collaboration network: ", V(g_local)$artist_name[match(hub_id, V(g_local)$name)])) +
  theme_void(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 17,
                              colour = C_TEXT, margin = margin(b = 10)),
    plot.background = element_rect(fill = C_BG, colour = NA),
    panel.background = element_rect(fill = C_BG, colour = NA),
    plot.margin = margin(12, 10, 12, 10, "mm")
  )

ggsave(file.path(OUT_DIR, "02_Local_Hub_Subnetwork.png"), p_local,
       width = 10.5, height = 7.0, dpi = 300, bg = C_BG)

# 7. TOP 15 DEGREE RANKING (horizontal list / bar chart) ---------------------
top15 <- tibble::tibble(
  artist_id = V(g)$name,
  artist = V(g)$artist_name,
  degree = V(g)$degree
) %>% arrange(desc(degree)) %>% slice_head(n = 15)
readr::write_csv(top15, file.path(OUT_DIR, "speaker2_top15_artists.csv"))

p_top <- ggplot(top15,
                aes(x = reorder(artist, degree), y = degree, fill = degree >= 120)) +
  geom_col(width = 0.68, show.legend = FALSE) +
  geom_text(aes(label = degree), hjust = -0.18,
            size = 4, fontface = "bold", colour = C_TEXT) +
  scale_fill_manual(values = c("FALSE" = "#55829A", "TRUE" = C_HIGH)) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Top 15 Artists by Number of Collaborators",
       x = NULL, y = "Distinct collaborators (Degree)") +
  theme_minimal(base_size = 14) +
  theme(
    plot.background = element_rect(fill = C_BG, colour = NA),
    panel.background = element_rect(fill = C_BG, colour = NA),
    plot.title = element_text(face = "bold", colour = C_TEXT, size = 17),
    axis.text = element_text(colour = C_MUTED),
    axis.title = element_text(colour = C_TEXT),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(colour = C_GRID, linewidth = 0.4),
    plot.margin = margin(10, 22, 8, 8, "mm")
  )

ggsave(file.path(OUT_DIR, "03_Top15_Degree_Ranking.png"), p_top,
       width = 10, height = 7.2, dpi = 300, bg = C_BG)

# 8. DEGREE DISTRIBUTION (the earlier 'list/bar chart') ----------------------
# This answers: how many artists have just 1, 2-3, 4-5, ... collaborators?
degree_table <- tibble::tibble(degree = V(g)$degree) %>%
  mutate(degree_bin = case_when(
    degree == 1 ~ "1",
    degree <= 3 ~ "2–3",
    degree <= 5 ~ "4–5",
    degree <= 10 ~ "6–10",
    degree <= 20 ~ "11–20",
    degree <= 50 ~ "21–50",
    TRUE ~ "51+"
  )) %>%
  mutate(degree_bin = factor(degree_bin,
                             levels = c("1", "2–3", "4–5", "6–10",
                                        "11–20", "21–50", "51+"))) %>%
  count(degree_bin, name = "n", .drop = FALSE)

p_dist <- ggplot(degree_table, aes(x = degree_bin, y = n, fill = degree_bin)) +
  geom_col(width = 0.67, show.legend = FALSE) +
  geom_text(aes(label = scales::comma(n)), vjust = -0.48,
            size = 4.4, fontface = "bold", colour = C_TEXT) +
  scale_fill_manual(values = c("1" = "#55829A", "2–3" = "#55829A",
                               "4–5" = "#55829A", "6–10" = "#55829A",
                               "11–20" = "#55829A", "21–50" = C_HIGH,
                               "51+" = C_HIGH)) +
  scale_y_continuous(labels = scales::comma,
                     expand = expansion(mult = c(0, 0.16))) +
  labs(title = "Degree Distribution",
       x = "Number of distinct collaborators (Degree)",
       y = "Number of artists") +
  theme_minimal(base_size = 14) +
  theme(
    plot.background = element_rect(fill = C_BG, colour = NA),
    panel.background = element_rect(fill = C_BG, colour = NA),
    plot.title = element_text(face = "bold", colour = C_TEXT, size = 17),
    axis.text = element_text(colour = C_MUTED),
    axis.title = element_text(colour = C_TEXT),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(colour = C_GRID, linewidth = 0.4),
    plot.margin = margin(10, 14, 8, 8, "mm")
  )

ggsave(file.path(OUT_DIR, "04_Degree_Distribution.png"), p_dist,
       width = 10.5, height = 6, dpi = 300, bg = C_BG)

cat("\nDONE: files saved in ", normalizePath(OUT_DIR), "\n", sep = "")
cat("01_Full_Artist_Network.png\n")
cat("02_Local_Hub_Subnetwork.png\n")
cat("03_Top15_Degree_Ranking.png\n")
cat("04_Degree_Distribution.png\n")
cat("speaker2_network_summary.csv\n")
cat("speaker2_top15_artists.csv\n")
cat("\nLegend: grey-blue = degree 1-3; blue = 4-20; orange = 21+.\n")
cat("Sizes AND colors encode degree measured in the FULL giant component.\n")
